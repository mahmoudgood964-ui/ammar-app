-- AMMAR project management modules
-- Run once in Supabase SQL Editor. Uses the existing projects.id and projects.client_id types.
DO $$
DECLARE
  project_id_type text;
BEGIN
  SELECT format_type(a.atttypid, a.atttypmod)
    INTO project_id_type
  FROM pg_attribute a
  WHERE a.attrelid = 'public.projects'::regclass
    AND a.attname = 'id' AND NOT a.attisdropped;

  IF project_id_type IS NULL THEN
    RAISE EXCEPTION 'Could not determine public.projects.id type';
  END IF;

  EXECUTE format('CREATE TABLE IF NOT EXISTS public.project_tasks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id %s NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    title text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 180),
    details text,
    status text NOT NULL DEFAULT ''todo'' CHECK (status IN (''todo'',''doing'',''done'')),
    due_date date,
    assigned_to text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
  )', project_id_type);

  EXECUTE format('CREATE TABLE IF NOT EXISTS public.project_expenses (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id %s NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    description text NOT NULL CHECK (char_length(description) BETWEEN 1 AND 240),
    amount numeric(14,2) NOT NULL CHECK (amount >= 0),
    currency text,
    spent_on date NOT NULL DEFAULT CURRENT_DATE,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
  )', project_id_type);

  EXECUTE format('CREATE TABLE IF NOT EXISTS public.project_quotes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id %s NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    supplier_name text NOT NULL CHECK (char_length(supplier_name) BETWEEN 1 AND 180),
    title text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 180),
    amount numeric(14,2),
    currency text,
    details text,
    status text NOT NULL DEFAULT ''pending'' CHECK (status IN (''pending'',''accepted'',''rejected'')),
    created_at timestamptz NOT NULL DEFAULT now()
  )', project_id_type);

  EXECUTE format('CREATE TABLE IF NOT EXISTS public.project_updates (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id %s NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    progress integer NOT NULL CHECK (progress BETWEEN 0 AND 100),
    note text,
    created_by uuid DEFAULT auth.uid(),
    created_at timestamptz NOT NULL DEFAULT now()
  )', project_id_type);

  EXECUTE format('CREATE TABLE IF NOT EXISTS public.project_documents (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id %s NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    title text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 180),
    file_path text NOT NULL,
    mime_type text,
    file_size bigint,
    notes text,
    created_by uuid DEFAULT auth.uid(),
    created_at timestamptz NOT NULL DEFAULT now()
  )', project_id_type);
END $$;

CREATE INDEX IF NOT EXISTS project_tasks_project_idx ON public.project_tasks(project_id, created_at DESC);
CREATE INDEX IF NOT EXISTS project_expenses_project_idx ON public.project_expenses(project_id, spent_on DESC);
CREATE INDEX IF NOT EXISTS project_quotes_project_idx ON public.project_quotes(project_id, created_at DESC);
CREATE INDEX IF NOT EXISTS project_updates_project_idx ON public.project_updates(project_id, created_at DESC);
CREATE INDEX IF NOT EXISTS project_documents_project_idx ON public.project_documents(project_id, created_at DESC);

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['project_tasks','project_expenses','project_quotes','project_updates','project_documents']
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_owner_all', t);
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.projects p WHERE p.id = project_id AND p.client_id = auth.uid())
      ) WITH CHECK (
        EXISTS (SELECT 1 FROM public.projects p WHERE p.id = project_id AND p.client_id = auth.uid())
      )', t || '_owner_all', t
    );
  END LOOP;
END $;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.project_tasks, public.project_expenses, public.project_quotes, public.project_updates, public.project_documents TO authenticated;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'ammar-project-files', 'ammar-project-files', false, 15728640,
  ARRAY['image/jpeg','image/png','image/webp','application/pdf','application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']
)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS ammar_project_files_owner_select ON storage.objects;
CREATE POLICY ammar_project_files_owner_select ON storage.objects
FOR SELECT TO authenticated USING (
  bucket_id = 'ammar-project-files'
  AND (storage.foldername(name))[1] = auth.uid()::text
);
DROP POLICY IF EXISTS ammar_project_files_owner_insert ON storage.objects;
CREATE POLICY ammar_project_files_owner_insert ON storage.objects
FOR INSERT TO authenticated WITH CHECK (
  bucket_id = 'ammar-project-files'
  AND (storage.foldername(name))[1] = auth.uid()::text
);
DROP POLICY IF EXISTS ammar_project_files_owner_delete ON storage.objects;
CREATE POLICY ammar_project_files_owner_delete ON storage.objects
FOR DELETE TO authenticated USING (
  bucket_id = 'ammar-project-files'
  AND (storage.foldername(name))[1] = auth.uid()::text
);
