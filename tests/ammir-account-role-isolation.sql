\set ON_ERROR_STOP on

BEGIN;

INSERT INTO auth.users(id,email) VALUES
('cccccccc-1000-4000-8000-000000000001','rls-owner@ammir.test'),
('cccccccc-1000-4000-8000-000000000002','rls-admin@ammir.test')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles(id,role) VALUES
('cccccccc-1000-4000-8000-000000000001','client'),
('cccccccc-1000-4000-8000-000000000002','admin')
ON CONFLICT (id) DO UPDATE SET role=EXCLUDED.role;

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','cccccccc-1000-4000-8000-000000000001',false);

DO $profile_role_guard_test$
BEGIN
  IF public.is_admin() THEN
    RAISE EXCEPTION 'Non-admin fixture unexpectedly resolves as administrator';
  END IF;

  BEGIN
    UPDATE public.profiles SET role='admin'
    WHERE id=auth.uid();
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    UPDATE public.profiles SET role='client'
    WHERE id='cccccccc-1000-4000-8000-000000000002';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END
$profile_role_guard_test$;

RESET ROLE;

DO $profile_role_guard_test$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id='cccccccc-1000-4000-8000-000000000001' AND role='client'
  ) THEN
    RAISE EXCEPTION 'Ordinary account promoted its own profile to admin';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id='cccccccc-1000-4000-8000-000000000002' AND role='admin'
  ) THEN
    RAISE EXCEPTION 'Ordinary account changed another profile role';
  END IF;
END
$profile_role_guard_test$;

ROLLBACK;

SELECT 'AMMIR ACCOUNT ROLE ISOLATION TESTS PASSED' AS result;
