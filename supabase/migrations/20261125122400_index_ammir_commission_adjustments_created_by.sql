-- Cover created_by foreign key lookups for append-only commission adjustments.
CREATE INDEX IF NOT EXISTS ammar_commission_adjustments_created_by_idx
  ON public.ammar_commission_adjustments (created_by)
  WHERE created_by IS NOT NULL;