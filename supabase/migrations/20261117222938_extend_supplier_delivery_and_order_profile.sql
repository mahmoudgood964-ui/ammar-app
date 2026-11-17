BEGIN;

ALTER TABLE public.ammar_market_suppliers
  ADD COLUMN IF NOT EXISTS brands text[] NOT NULL DEFAULT '{}'::text[],
  ADD COLUMN IF NOT EXISTS delivery_mode text NOT NULL DEFAULT 'unknown',
  ADD COLUMN IF NOT EXISTS delivery_coverage text,
  ADD COLUMN IF NOT EXISTS minimum_order_amount numeric(14,2),
  ADD COLUMN IF NOT EXISTS minimum_order_currency text NOT NULL DEFAULT 'SDG',
  ADD COLUMN IF NOT EXISTS typical_lead_time_days integer,
  ADD COLUMN IF NOT EXISTS delivery_terms text;

ALTER TABLE public.ammar_market_suppliers
  DROP CONSTRAINT IF EXISTS ammar_market_suppliers_delivery_mode_check;
ALTER TABLE public.ammar_market_suppliers
  ADD CONSTRAINT ammar_market_suppliers_delivery_mode_check
  CHECK (delivery_mode IN ('delivery','pickup','on_request','unknown'));

ALTER TABLE public.ammar_market_suppliers
  DROP CONSTRAINT IF EXISTS ammar_market_suppliers_brands_limit_check;
ALTER TABLE public.ammar_market_suppliers
  ADD CONSTRAINT ammar_market_suppliers_brands_limit_check
  CHECK (cardinality(brands) <= 30);

ALTER TABLE public.ammar_market_suppliers
  DROP CONSTRAINT IF EXISTS ammar_market_suppliers_minimum_order_check;
ALTER TABLE public.ammar_market_suppliers
  ADD CONSTRAINT ammar_market_suppliers_minimum_order_check
  CHECK (minimum_order_amount IS NULL OR minimum_order_amount >= 0);

ALTER TABLE public.ammar_market_suppliers
  DROP CONSTRAINT IF EXISTS ammar_market_suppliers_lead_time_check;
ALTER TABLE public.ammar_market_suppliers
  ADD CONSTRAINT ammar_market_suppliers_lead_time_check
  CHECK (typical_lead_time_days IS NULL OR typical_lead_time_days BETWEEN 0 AND 3650);

COMMIT;