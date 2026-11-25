-- AMMIR Revenue Engine: append-only commission adjustments.
-- Additive only: does not rewrite the existing commission ledger or payment tables.

create table if not exists public.ammar_commission_adjustments (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references public.ammar_commission_ledger(id) on delete restrict,
  adjustment_kind text not null
    check (adjustment_kind in ('partial_refund','full_reversal','fee_increase','fee_decrease')),
  amount_delta numeric(14,2) not null check (amount_delta <> 0),
  currency text not null check (currency = btrim(currency) and char_length(currency) between 1 and 12),
  reason text not null check (char_length(btrim(reason)) between 10 and 1000),
  idempotency_key text not null unique
    check (idempotency_key = btrim(idempotency_key) and char_length(idempotency_key) between 12 and 128),
  source_reference text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint ammar_commission_adjustments_kind_sign_check check (
    (adjustment_kind in ('partial_refund','full_reversal','fee_decrease') and amount_delta < 0)
    or (adjustment_kind = 'fee_increase' and amount_delta > 0)
  )
);

create index if not exists ammar_commission_adjustments_ledger_created_idx
  on public.ammar_commission_adjustments (ledger_id, created_at desc);

alter table public.ammar_commission_adjustments enable row level security;

drop policy if exists ammar_commission_adjustments_select on public.ammar_commission_adjustments;
create policy ammar_commission_adjustments_select
  on public.ammar_commission_adjustments
  for select to authenticated
  using (
    (select app_private.is_admin())
    or exists (
      select 1
      from public.ammar_commission_ledger l
      where l.id = ammar_commission_adjustments.ledger_id
        and l.payer_id = (select auth.uid())
    )
  );

revoke all on table public.ammar_commission_adjustments from anon, authenticated;
grant select on table public.ammar_commission_adjustments to authenticated;

create or replace function app_private.prevent_commission_adjustment_mutation()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  raise exception 'Commission adjustments are append-only; create a compensating adjustment instead';
end;
$function$;

revoke all on function app_private.prevent_commission_adjustment_mutation() from public, anon, authenticated;

drop trigger if exists ammar_commission_adjustments_immutable on public.ammar_commission_adjustments;
create trigger ammar_commission_adjustments_immutable
before update or delete on public.ammar_commission_adjustments
for each row execute function app_private.prevent_commission_adjustment_mutation();

create or replace function public.ammar_record_commission_adjustment(
  p_ledger_id uuid,
  p_adjustment_kind text,
  p_amount numeric,
  p_currency text,
  p_reason text,
  p_idempotency_key text,
  p_source_reference text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_ledger public.ammar_commission_ledger%rowtype;
  v_existing public.ammar_commission_adjustments%rowtype;
  v_id uuid;
  v_delta numeric(14,2);
  v_current_adjustments numeric(14,2);
  v_remaining numeric(14,2);
begin
  if auth.uid() is null or not app_private.is_admin() then
    raise exception 'Administrator permission required';
  end if;

  if p_adjustment_kind is null or p_adjustment_kind not in ('partial_refund','full_reversal','fee_increase','fee_decrease') then
    raise exception 'Unsupported commission adjustment kind';
  end if;

  if p_amount is null or p_amount <= 0 or p_amount <> round(p_amount, 2) then
    raise exception 'Adjustment amount must be positive and have at most two decimal places';
  end if;

  if p_currency is null or p_currency <> btrim(p_currency) or char_length(p_currency) not between 1 and 12 then
    raise exception 'A valid currency is required';
  end if;

  if p_reason is null or char_length(btrim(p_reason)) not between 10 and 1000 then
    raise exception 'A reason between 10 and 1000 characters is required';
  end if;

  if p_idempotency_key is null or p_idempotency_key <> btrim(p_idempotency_key) or char_length(p_idempotency_key) not between 12 and 128 then
    raise exception 'An idempotency key between 12 and 128 characters is required';
  end if;

  select *
    into v_existing
  from public.ammar_commission_adjustments
  where idempotency_key = p_idempotency_key;

  if found then
    if v_existing.ledger_id <> p_ledger_id
       or v_existing.adjustment_kind <> p_adjustment_kind
       or abs(v_existing.amount_delta) <> p_amount
       or v_existing.currency <> p_currency
       or v_existing.reason <> btrim(p_reason)
       or coalesce(v_existing.source_reference, '') <> coalesce(nullif(btrim(p_source_reference), ''), '') then
      raise exception 'Idempotency key was already used with a different adjustment payload';
    end if;
    return v_existing.id;
  end if;

  select *
    into v_ledger
  from public.ammar_commission_ledger
  where id = p_ledger_id
  for update;

  if not found then
    raise exception 'Commission ledger row not found';
  end if;

  if v_ledger.currency <> p_currency then
    raise exception 'Adjustment currency must match the original ledger currency';
  end if;

  v_delta := case
    when p_adjustment_kind in ('partial_refund','full_reversal','fee_decrease') then -p_amount
    else p_amount
  end;

  select coalesce(sum(a.amount_delta), 0)::numeric(14,2)
    into v_current_adjustments
  from public.ammar_commission_adjustments a
  where a.ledger_id = p_ledger_id;

  v_remaining := round(v_ledger.commission_amount + v_current_adjustments, 2);

  if p_adjustment_kind = 'full_reversal' and p_amount <> v_remaining then
    raise exception 'A full reversal must equal the remaining commission balance';
  end if;

  if v_delta < 0 and p_amount > v_remaining then
    raise exception 'Adjustment exceeds the remaining commission balance';
  end if;

  insert into public.ammar_commission_adjustments (
    ledger_id, adjustment_kind, amount_delta, currency, reason,
    idempotency_key, source_reference, created_by
  )
  values (
    p_ledger_id, p_adjustment_kind, v_delta, p_currency, btrim(p_reason),
    p_idempotency_key, nullif(btrim(p_source_reference), ''), auth.uid()
  )
  on conflict (idempotency_key) do nothing
  returning id into v_id;

  if v_id is not null then
    return v_id;
  end if;

  select *
    into v_existing
  from public.ammar_commission_adjustments
  where idempotency_key = p_idempotency_key;

  if not found
     or v_existing.ledger_id <> p_ledger_id
     or v_existing.adjustment_kind <> p_adjustment_kind
     or v_existing.amount_delta <> v_delta
     or v_existing.currency <> p_currency
     or v_existing.reason <> btrim(p_reason)
     or coalesce(v_existing.source_reference, '') <> coalesce(nullif(btrim(p_source_reference), ''), '') then
    raise exception 'Idempotency key was already used with a different adjustment payload';
  end if;

  return v_existing.id;
end;
$function$;

revoke all on function public.ammar_record_commission_adjustment(uuid,text,numeric,text,text,text,text) from public, anon;
grant execute on function public.ammar_record_commission_adjustment(uuid,text,numeric,text,text,text,text) to authenticated;
