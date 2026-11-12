\set ON_ERROR_STOP on
DO $test$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ammar_commission_rules WHERE is_active = true) THEN
    RAISE EXCEPTION 'Unapproved commission defaults remain active';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.ammar_commission_ledger
    WHERE commission_amount < 0 OR gross_amount < 0 OR rate_percent < 0
  ) THEN
    RAISE EXCEPTION 'Commission ledger contains invalid negative values';
  END IF;
END
$test$;
SELECT 'AMMIR UNAPPROVED COMMISSION DEFAULTS ARE INACTIVE' AS result;
