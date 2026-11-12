-- AMMAR collaboration, workflow, finance, audit and notification layer
-- Apply once in Supabase SQL Editor after the existing project_management migration.
-- Existing project and module records are preserved.

ALTER TABLE public.projects
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'planning',
  ADD COLUMN IF NOT EXISTS start_date date,
  ADD COLUMN IF NOT EXISTS target_end_date date,
  ADD COLUMN IF NOT EXISTS completed_at timestamptz,
  ADD COLUMN IF NOT EXISTS budget_amount numeric(14,2),
  ADD COLUMN IF NOT EXISTS budget_currency text,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.projects'::regclass
      AND conname = 'projects_ammar_status_check'
  ) THEN
    ALTER TABLE public.projects
      ADD CONSTRAINT projects_ammar_status_check
      CHECK (status IN ('planning','approved','in_progress','on_hold','completed','cancelled')) NOT VALID;
  END IF;
END $$;

DO $$
DECLARE project_id_type text;
BEGIN
  SELECT format_type(a.atttypid, a.atttypmod)
    INTO project_id_type
  FROM pg_attribute a
  WHERE a.attrelid = 'public.projects'::regclass
    AND a.attname = 'id' AND NOT a.attisdropped;

  IF project_id_type IS NULL THEN
    RAISE EXCEPTION 'Could not determine public.projects.id type';
  END IF;

  EXECUTE format('CREATE TABLE IF NOT EXISTS public.project_invitations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id %s NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    email text NOT NULL,
    member_role text NOT NULL CHECK (member_role IN (''manager'',''supervisor'',''engineer'',''accountant'',''worker'',''viewer'')),
    invite_token text NOT NULL UNIQUE,
    status text NOT NULL DEFAULT ''pending'' CHECK (status IN (''pending'',''accepted'',''revoked'',''expired'')),
    expires_at timestamptz NOT NULL,
    created_by uuid NOT NULL DEFAULT auth.uid(),
    created_at timestamptz NOT NULL DEFAULT now(),
    accepted_by uuid,
    accepted_at timestamptz
  )', project_id_type);

  EXECUTE format('CREATE TABLE IF NOT EXISTS public.project_activity (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id %s NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    actor_id uuid DEFAULT auth.uid(),
    event_type text NOT NULL,
    summary text NOT NULL CHECK (char_length(summary) BETWEEN 1 AND 500),
    entity_type text,
    entity_id text,
    metadata jsonb NOT NULL DEFAULT ''{}''::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
  )', project_id_type);

  EXECUTE format('CREATE TABLE IF NOT EXISTS public.project_comments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id %s NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    author_id uuid NOT NULL DEFAULT auth.uid(),
    message text NOT NULL CHECK (char_length(message) BETWEEN 1 AND 4000),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
  )', project_id_type);

  EXECUTE format('CREATE TABLE IF NOT EXISTS public.project_payments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id %s NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    description text NOT NULL CHECK (char_length(description) BETWEEN 1 AND 240),
    amount numeric(14,2) NOT NULL CHECK (amount >= 0),
    currency text,
    due_date date,
    paid_on date,
    status text NOT NULL DEFAULT ''planned'' CHECK (status IN (''planned'',''paid'',''cancelled'')),
    payment_method text,
    reference text,
    notes text,
    created_by uuid DEFAULT auth.uid(),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
  )', project_id_type);

  EXECUTE format('CREATE TABLE IF NOT EXISTS public.project_notifications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id %s NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    user_id uuid NOT NULL,
    actor_id uuid,
    title text NOT NULL,
    body text,
    read_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
  )', project_id_type);
END $$;

CREATE INDEX IF NOT EXISTS project_invitations_project_idx ON public.project_invitations(project_id, created_at DESC);
CREATE INDEX IF NOT EXISTS project_activity_project_idx ON public.project_activity(project_id, created_at DESC);
CREATE INDEX IF NOT EXISTS project_comments_project_idx ON public.project_comments(project_id, created_at DESC);
CREATE INDEX IF NOT EXISTS project_payments_project_idx ON public.project_payments(project_id, due_date DESC);
CREATE INDEX IF NOT EXISTS project_notifications_user_idx ON public.project_notifications(user_id, created_at DESC);

-- Store the invited email on the membership record so the roster is usable without exposing auth.users.
ALTER TABLE public.project_members ADD COLUMN IF NOT EXISTS member_email text;
