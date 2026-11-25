BEGIN;

DO $ammir_adjustment_schema_contract$
DECLARE
  v_canonical_policy text;
  v_proposal_policy text;
BEGIN
  IF to_regclass('public.ammar_commission_adjustments') IS NULL THEN
    RAISE EXCEPTION 'Canonical commission adjustment ledger is missing';
  END IF;
  IF to_regclass('public.ammir_commission_adjustment_proposals') IS NULL THEN
    RAISE EXCEPTION 'AMMIR return proposal table is missing';
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='ammar_commission_adjustments'
      AND column_name IN ('original_ledger_id','return_id','adjustment_amount','status')
  ) THEN
    RAISE EXCEPTION 'Return proposal columns leaked into the canonical adjustment ledger';
  END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='ammir_commission_adjustment_proposals'
      AND column_name IN ('ledger_id','adjustment_kind','amount_delta','idempotency_key')
  ) THEN
    RAISE EXCEPTION 'Canonical financial-ledger columns leaked into the proposal table';
  END IF;

  SELECT qual INTO v_canonical_policy
  FROM pg_policies
  WHERE schemaname='public' AND tablename='ammar_commission_adjustments'
    AND policyname='ammar_commission_adjustments_select';
  IF v_canonical_policy IS NULL
     OR position('payer_id' IN v_canonical_policy)=0
     OR position('is_admin' IN v_canonical_policy)=0 THEN
    RAISE EXCEPTION 'Canonical ledger must retain payer/admin read policy';
  END IF;

  SELECT qual INTO v_proposal_policy
  FROM pg_policies
  WHERE schemaname='public' AND tablename='ammir_commission_adjustment_proposals'
    AND policyname='ammir_commission_adjustment_proposals_select';
  IF v_proposal_policy IS NULL
     OR position('is_admin' IN v_proposal_policy)=0
     OR position('payer_id' IN v_proposal_policy)>0 THEN
    RAISE EXCEPTION 'Return proposals must remain admin-only';
  END IF;
END
$ammir_adjustment_schema_contract$;

ROLLBACK;
