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
