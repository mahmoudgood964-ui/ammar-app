-- Disable placeholder commission defaults until a commercial rate is approved in writing
-- No transaction or existing ledger row is altered
BEGIN;
UPDATE public.ammar_commission_rules
SET is_active = false
WHERE is_active = true;
COMMENT ON TABLE public.ammar_commission_rules
IS 'Commission rules remain inactive until an approved commercial schedule is authorized and explicitly activated by an administrator';
COMMIT;