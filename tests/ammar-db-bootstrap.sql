-- Minimal Supabase-compatible PostgreSQL fixtures for the AMMAR ecosystem migration tests.
CREATE EXTENSION IF NOT EXISTS pgcrypto;
DO $$ BEGIN CREATE ROLE authenticated NOLOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE anon NOLOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS storage;
CREATE TABLE auth.users (id uuid PRIMARY KEY,email text UNIQUE);
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
 SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
$$;
CREATE TABLE public.profiles (
 id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
 role text NOT NULL DEFAULT 'client'
);
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
 SELECT EXISTS (
   SELECT 1 FROM public.profiles
   WHERE id = (SELECT auth.uid()) AND role = 'admin'
 )
$$;
CREATE TABLE public.projects (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 client_id uuid NOT NULL REFERENCES auth.users(id),
 title text NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.project_members (
 project_id uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 member_role text NOT NULL DEFAULT 'manager',
 PRIMARY KEY(project_id,user_id)
);
CREATE TABLE public.project_expenses (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 project_id uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
 description text NOT NULL, amount numeric(14,2) NOT NULL CHECK(amount>=0),
 currency text, spent_on date NOT NULL DEFAULT CURRENT_DATE, notes text,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.project_tasks (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 project_id uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
 title text NOT NULL, details text, status text NOT NULL DEFAULT 'todo',
 due_date date, assigned_to text, created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.project_change_orders (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 project_id uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
 title text NOT NULL, reason text NOT NULL, cost_impact numeric(14,2) NOT NULL DEFAULT 0,
 currency text, days_impact integer NOT NULL DEFAULT 0, status text NOT NULL DEFAULT 'submitted',
 decision_note text, requested_by uuid, decided_by uuid, decided_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE OR REPLACE FUNCTION public.ammar_project_role(p_project_id text)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT CASE WHEN p.client_id=auth.uid() THEN 'owner' ELSE pm.member_role END
 FROM public.projects p LEFT JOIN public.project_members pm
 ON pm.project_id=p.id AND pm.user_id=auth.uid()
 WHERE p.id::text=p_project_id AND (p.client_id=auth.uid() OR pm.user_id=auth.uid())
 LIMIT 1
$$;
CREATE TABLE storage.buckets (
 id text PRIMARY KEY,name text NOT NULL,public boolean NOT NULL DEFAULT false,
 file_size_limit bigint,allowed_mime_types text[]
);
CREATE TABLE storage.objects (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 bucket_id text NOT NULL REFERENCES storage.buckets(id),name text NOT NULL,owner_id text,
 created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(bucket_id,name)
);
CREATE OR REPLACE FUNCTION storage.foldername(name text)
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$ SELECT string_to_array(name,'/') $$;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_publication WHERE pubname='supabase_realtime') THEN
  EXECUTE 'CREATE PUBLICATION supabase_realtime';
 END IF;
END $$;
GRANT USAGE ON SCHEMA public,auth,storage TO authenticated,anon;
GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT,INSERT,UPDATE,DELETE ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE,SELECT ON SEQUENCES TO authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON storage.objects TO authenticated;
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON storage.buckets TO authenticated,anon;
