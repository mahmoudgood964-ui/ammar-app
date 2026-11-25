BEGIN;

INSERT INTO auth.users(id,email) VALUES
 ('aaaaaaaa-2511-4000-8000-000000000001','ops-admin@ammir.test'),
 ('aaaaaaaa-2511-4000-8000-000000000002','ops-unrelated@ammir.test'),
 ('aaaaaaaa-2511-4000-8000-000000000003','ops-supplier@ammir.test')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles(id,role) VALUES
 ('aaaaaaaa-2511-4000-8000-000000000001','admin'),
 ('aaaaaaaa-2511-4000-8000-000000000002','client'),
 ('aaaaaaaa-2511-4000-8000-000000000003','client')
ON CONFLICT (id) DO UPDATE SET role=EXCLUDED.role;

INSERT INTO public.projects(id,client_id,title) VALUES
 ('bbbbbbbb-2511-4000-8000-000000000001','aaaaaaaa-2511-4000-8000-000000000002','Operational alerts regression project')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.ammir_project_rfqs(
 id,project_id,reference_code,title,delivery_location,deadline_at,currency,status,created_by,published_at
) VALUES (
 'cccccccc-2511-4000-8000-000000000001',
 'bbbbbbbb-2511-4000-8000-000000000001',
 'AMMIR-OPS-RFQ-001','Overdue test RFQ','CI test location',
 now()-interval '2 days','SDG','draft',
 'aaaaaaaa-2511-4000-8000-000000000002',NULL
) ON CONFLICT (id) DO NOTHING;

UPDATE public.ammir_project_rfqs
SET status='open',published_at=now()
WHERE id='cccccccc-2511-4000-8000-000000000001';

INSERT INTO public.ammir_project_awards(
 id,rfq_id,project_id,supplier_user_id,award_reference,status,created_by,issued_at,accepted_at
) VALUES (
 'dddddddd-2511-4000-8000-000000000001',
 'cccccccc-2511-4000-8000-000000000001',
 'bbbbbbbb-2511-4000-8000-000000000001',
 'aaaaaaaa-2511-4000-8000-000000000003',
 'AMMIR-OPS-AWARD-001','draft',
 'aaaaaaaa-2511-4000-8000-000000000002',NULL,NULL
) ON CONFLICT (id) DO NOTHING;

UPDATE public.ammir_project_awards
SET status='issued',issued_at=now()
WHERE id='dddddddd-2511-4000-8000-000000000001';
UPDATE public.ammir_project_awards
SET status='accepted',accepted_at=now()
WHERE id='dddddddd-2511-4000-8000-000000000001';

INSERT INTO public.ammir_project_deliveries(
 id,award_id,project_id,supplier_user_id,delivery_reference,status,scheduled_at,created_by
) VALUES (
 'eeeeeeee-2511-4000-8000-000000000001',
 'dddddddd-2511-4000-8000-000000000001',
 'bbbbbbbb-2511-4000-8000-000000000001',
 'aaaaaaaa-2511-4000-8000-000000000003',
 'AMMIR-OPS-DEL-001','planned',CURRENT_DATE-2,
 'aaaaaaaa-2511-4000-8000-000000000002'
) ON CONFLICT (id) DO NOTHING;

-- An unrelated authenticated account must not be able to call the RPC.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','aaaaaaaa-2511-4000-8000-000000000002',true);
DO $test$
DECLARE v_denied boolean := false;
BEGIN
  BEGIN
    PERFORM * FROM public.ammar_admin_list_operational_alerts(100);
  EXCEPTION WHEN SQLSTATE '42501' THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'An unrelated authenticated account executed the admin alerts RPC';
  END IF;
END
$test$;

-- The administrator receives only the two expected overdue operational alerts.
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','aaaaaaaa-2511-4000-8000-000000000001',true);
DO $test$
DECLARE
  v_count integer;
  v_rfq integer;
  v_delivery integer;
BEGIN
  SELECT count(*) INTO v_count
  FROM public.ammar_admin_list_operational_alerts(100);
  SELECT count(*) INTO v_rfq
  FROM public.ammar_admin_list_operational_alerts(100)
  WHERE alert_kind='rfq' AND alert_id='cccccccc-2511-4000-8000-000000000001';
  SELECT count(*) INTO v_delivery
  FROM public.ammar_admin_list_operational_alerts(100)
  WHERE alert_kind='delivery' AND alert_id='eeeeeeee-2511-4000-8000-000000000001';

  IF v_count <> 2 OR v_rfq <> 1 OR v_delivery <> 1 THEN
    RAISE EXCEPTION 'Admin alerts expected 2 rows (1 RFQ, 1 delivery), found total %, RFQ %, delivery %',
      v_count,v_rfq,v_delivery;
  END IF;
END
$test$;

RESET ROLE;
ROLLBACK;

SELECT 'AMMIR ADMIN OPERATIONAL ALERTS TESTS PASSED' AS result;
