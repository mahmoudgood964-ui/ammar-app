-- Reconcile legacy project tables with the current AMMIR client contract.
-- Additive/non-destructive: preserves existing columns and records.
-- Deliberately does not modify bank milestone/payment-event tables or workflows.

ALTER TABLE public.project_updates
  ADD COLUMN IF NOT EXISTS progress integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS note text,
  ADD COLUMN IF NOT EXISTS created_by uuid DEFAULT auth.uid();

DO $ammar_progress_check$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.project_updates'::regclass
      AND conname='project_updates_progress_range_check'
  ) THEN
    ALTER TABLE public.project_updates
      ADD CONSTRAINT project_updates_progress_range_check
      CHECK (progress BETWEEN 0 AND 100) NOT VALID;
  END IF;
END
$ammar_progress_check$;

ALTER TABLE public.project_members
  DROP CONSTRAINT IF EXISTS project_members_member_role_check;

ALTER TABLE public.project_members
  ADD CONSTRAINT project_members_member_role_check
  CHECK (member_role IN (
    'manager','supervisor','engineer','accountant','worker','viewer',
    'contractor','admin','project_manager','owner','member','technician'
  ));

ALTER TABLE public.projects
  ALTER COLUMN status SET DEFAULT 'planning';

-- The legacy default 'new' is not part of the current status domain.
-- Normalize only rows carrying that legacy default to the equivalent planning state.
UPDATE public.projects
SET status='planning'
WHERE status='new';
