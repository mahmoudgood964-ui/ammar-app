#!/usr/bin/env bash
set -euo pipefail

export PGPASSWORD=postgres
DB=(psql -h 127.0.0.1 -U postgres -d ammar_test -v ON_ERROR_STOP=1 -X -q)

run_reduction() {
  local key="$1"
  "${DB[@]}" -c "
    SET ROLE authenticated;
    SELECT set_config('request.jwt.claim.sub','aaaaaaaa-2424-4000-8000-000000000003',false);
    SELECT public.ammar_record_commission_adjustment(
      'aaaaaaaa-2424-4000-8000-000000000098'::uuid,
      'partial_refund',
      30.00,
      'SDG',
      'Concurrent reduction serialization test',
      '${key}',
      NULL
    );
  "
}

set +e
run_reduction "ci-concurrent-reduction-0001" >/tmp/ammir-concurrent-1.log 2>&1 &
pid1=$!
run_reduction "ci-concurrent-reduction-0002" >/tmp/ammir-concurrent-2.log 2>&1 &
pid2=$!
wait "$pid1"; status1=$?
wait "$pid2"; status2=$?
set -e

if [[ "$status1" -eq 0 && "$status2" -eq 0 ]]; then
  echo "Both concurrent reductions succeeded; remaining balance protection failed."
  cat /tmp/ammir-concurrent-1.log /tmp/ammir-concurrent-2.log
  exit 1
fi

if [[ "$status1" -ne 0 && "$status2" -ne 0 ]]; then
  echo "Both concurrent reductions failed unexpectedly."
  cat /tmp/ammir-concurrent-1.log /tmp/ammir-concurrent-2.log
  exit 1
fi

result=$("${DB[@]}" -At -c "
  SELECT count(*) || ':' || coalesce(sum(amount_delta),0)
  FROM public.ammar_commission_adjustments
  WHERE ledger_id='aaaaaaaa-2424-4000-8000-000000000098'::uuid;
")

if [[ "$result" != "1:-30.00" && "$result" != "1:-30" ]]; then
  echo "Unexpected concurrent adjustment state: $result"
  cat /tmp/ammir-concurrent-1.log /tmp/ammir-concurrent-2.log
  exit 1
fi

echo "AMMIR concurrent commission reductions serialized correctly."

run_idempotent_replay() {
  "${DB[@]}" -c "
    SET ROLE authenticated;
    SELECT set_config('request.jwt.claim.sub','aaaaaaaa-2424-4000-8000-000000000003',false);
    SELECT public.ammar_record_commission_adjustment(
      'aaaaaaaa-2424-4000-8000-000000000098'::uuid,
      'partial_refund',
      10.00,
      'SDG',
      'Concurrent same-key idempotency replay',
      'ci-concurrent-same-key-0001',
      NULL
    );
  "
}

run_idempotent_replay >/tmp/ammir-idempotent-1.log 2>&1 &
replay1=$!
run_idempotent_replay >/tmp/ammir-idempotent-2.log 2>&1 &
replay2=$!
wait "$replay1"
wait "$replay2"

replay_result=$("${DB[@]}" -At -c "
  SELECT count(*) || ':' || coalesce(sum(amount_delta),0)
  FROM public.ammar_commission_adjustments
  WHERE ledger_id='aaaaaaaa-2424-4000-8000-000000000098'::uuid;
")
if [[ "$replay_result" != "2:-40.00" && "$replay_result" != "2:-40" ]]; then
  echo "Concurrent same-key replay produced unexpected ledger adjustments: $replay_result"
  cat /tmp/ammir-idempotent-1.log /tmp/ammir-idempotent-2.log
  exit 1
fi

same_key_count=$("${DB[@]}" -At -c "
  SELECT count(*) FROM public.ammar_commission_adjustments
  WHERE idempotency_key='ci-concurrent-same-key-0001'
    AND ledger_id='aaaaaaaa-2424-4000-8000-000000000098'::uuid
    AND amount_delta=-10.00;
")
if [[ "$same_key_count" != "1" ]]; then
  echo "Concurrent same-key retry created $same_key_count rows instead of one."
  cat /tmp/ammir-idempotent-1.log /tmp/ammir-idempotent-2.log
  exit 1
fi

echo "AMMIR concurrent same-key idempotent retries returned one logical adjustment."
