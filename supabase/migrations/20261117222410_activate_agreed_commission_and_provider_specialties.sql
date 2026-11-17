BEGIN;

ALTER TABLE public.ammar_service_providers
  ADD COLUMN IF NOT EXISTS specialties text[] NOT NULL DEFAULT '{}'::text[];

ALTER TABLE public.ammar_service_providers
  DROP CONSTRAINT IF EXISTS ammar_service_provider_specialties_limit_check;

ALTER TABLE public.ammar_service_providers
  ADD CONSTRAINT ammar_service_provider_specialties_limit_check
  CHECK (cardinality(specialties) <= 20);

CREATE INDEX IF NOT EXISTS ammar_service_providers_specialties_gin_idx
  ON public.ammar_service_providers USING gin (specialties);

DO $commission_activation$
DECLARE
  v_count integer;
BEGIN
  SELECT count(*)
    INTO v_count
  FROM public.ammar_commission_rules
  WHERE activity_type IN ('market_materials','contracting','maintenance','engineering','other')
    AND rate_percent = 5.00
    AND payer_side = 'provider';

  IF v_count <> 5 THEN
    RAISE EXCEPTION 'Expected five existing agreed 5%% provider-side commission rules; found %', v_count;
  END IF;

  UPDATE public.ammar_commission_rules
  SET is_active = true,
      effective_from = now()
  WHERE activity_type IN ('market_materials','contracting','maintenance','engineering','other')
    AND rate_percent = 5.00
    AND payer_side = 'provider';
END
$commission_activation$;

COMMIT;