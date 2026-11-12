-- Isolated AMMIR staging baseline: schema only, no production data copied.
-- Mirrors the legacy project tables required before ordered migrations 001–004.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name text,
  phone text,
  role text NOT NULL DEFAULT 'client'
    CHECK (role IN ('client','engineer','contractor','admin')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.projects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id uuid NOT NULL REFERENCES public.profiles(id),
  title text NOT NULL,
  description text,
  property_location text,
  property_type text,
  budget numeric,
  status text NOT NULL DEFAULT 'planning',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.project_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  member_role text NOT NULL CHECK (member_role IN (
    'manager','supervisor','engineer','accountant','worker','viewer',
    'contractor','admin','project_manager','owner','member','technician'
  )),
  created_at timestamptz NOT NULL DEFAULT now(),
  member_email text,
  UNIQUE(project_id,user_id)
);

CREATE TABLE public.quotes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  contractor_id uuid NOT NULL REFERENCES public.profiles(id),
  amount numeric NOT NULL CHECK (amount >= 0),
  description text,
  estimated_days integer,
  status text NOT NULL DEFAULT 'pending',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.project_updates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  author_id uuid REFERENCES public.profiles(id),
  title text NOT NULL DEFAULT 'تحديث',
  details text,
  progress integer NOT NULL DEFAULT 0 CHECK (progress BETWEEN 0 AND 100),
  note text,
  created_by uuid DEFAULT auth.uid(),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.project_files (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  uploaded_by uuid NOT NULL REFERENCES public.profiles(id),
  file_name text NOT NULL,
  file_path text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX projects_client_id_idx ON public.projects(client_id);
CREATE INDEX project_members_user_id_idx ON public.project_members(user_id);
CREATE INDEX quotes_project_id_idx ON public.quotes(project_id);
CREATE INDEX project_updates_project_id_idx ON public.project_updates(project_id);
CREATE INDEX project_files_project_id_idx ON public.project_files(project_id);

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id=(SELECT auth.uid()) AND role='admin'
  );
$$;

CREATE OR REPLACE FUNCTION public.is_project_member(pid uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.project_members
    WHERE project_id=pid AND user_id=(SELECT auth.uid())
  );
$$;

REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_project_member(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_project_member(uuid) TO authenticated;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quotes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_updates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_files ENABLE ROW LEVEL SECURITY;

CREATE POLICY profiles_insert ON public.profiles
FOR INSERT TO authenticated WITH CHECK (id=(SELECT auth.uid()) AND role='client');
CREATE POLICY profiles_read ON public.profiles
FOR SELECT TO authenticated USING (id=(SELECT auth.uid()) OR (SELECT public.is_admin()));
CREATE POLICY profiles_update ON public.profiles
FOR UPDATE TO authenticated USING (id=(SELECT auth.uid()) OR (SELECT public.is_admin()))
WITH CHECK ((id=(SELECT auth.uid()) AND role='client') OR (SELECT public.is_admin()));

CREATE POLICY projects_insert ON public.projects
FOR INSERT TO authenticated WITH CHECK (client_id=(SELECT auth.uid()));
CREATE POLICY projects_read ON public.projects
FOR SELECT TO authenticated USING (
  client_id=(SELECT auth.uid()) OR (SELECT public.is_project_member(id)) OR (SELECT public.is_admin())
);
CREATE POLICY projects_update ON public.projects
FOR UPDATE TO authenticated USING (client_id=(SELECT auth.uid()) OR (SELECT public.is_admin()))
WITH CHECK (client_id=(SELECT auth.uid()) OR (SELECT public.is_admin()));

CREATE POLICY project_members_owner_or_self_select ON public.project_members
FOR SELECT TO authenticated USING (
  user_id=(SELECT auth.uid())
  OR EXISTS (SELECT 1 FROM public.projects p WHERE p.id=project_id AND p.client_id=(SELECT auth.uid()))
);

CREATE POLICY quotes_read ON public.quotes
FOR SELECT TO authenticated USING (
  contractor_id=(SELECT auth.uid())
  OR (SELECT public.is_project_member(project_id))
  OR EXISTS (SELECT 1 FROM public.projects p WHERE p.id=project_id AND p.client_id=(SELECT auth.uid()))
  OR (SELECT public.is_admin())
);
CREATE POLICY quotes_insert ON public.quotes
FOR INSERT TO authenticated WITH CHECK (
  contractor_id=(SELECT auth.uid())
  AND EXISTS (SELECT 1 FROM public.project_members m
    WHERE m.project_id=project_id AND m.user_id=(SELECT auth.uid()) AND m.member_role='contractor')
);

CREATE POLICY project_updates_read ON public.project_updates
FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM public.projects p WHERE p.id=project_id AND p.client_id=(SELECT auth.uid()))
  OR (SELECT public.is_project_member(project_id))
);
CREATE POLICY project_files_read ON public.project_files
FOR SELECT TO authenticated USING (
  uploaded_by=(SELECT auth.uid())
  OR (SELECT public.is_project_member(project_id))
  OR EXISTS (SELECT 1 FROM public.projects p WHERE p.id=project_id AND p.client_id=(SELECT auth.uid()))
  OR (SELECT public.is_admin())
);
CREATE POLICY project_files_insert ON public.project_files
FOR INSERT TO authenticated WITH CHECK (
  uploaded_by=(SELECT auth.uid())
  AND (
    (SELECT public.is_project_member(project_id))
    OR EXISTS (SELECT 1 FROM public.projects p WHERE p.id=project_id AND p.client_id=(SELECT auth.uid()))
    OR (SELECT public.is_admin())
  )
);

GRANT SELECT,INSERT,UPDATE,DELETE ON public.profiles,public.projects,public.project_members,
  public.quotes,public.project_updates,public.project_files TO authenticated;
