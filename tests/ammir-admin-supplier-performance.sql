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

INSERT INTO public.ammir_project_rfq_items(
 id,rfq_id,project_id,item_code,description,specification,unit,quantity,sort_order
) VALUES (
 'ffffffff-2511-4000-8000-000000000001',
 'cccccccc-2511-4000-8000-000000000001',
 'bbbbbbbb-2511-4000-8000-000000000001',
 'OPS-01','Cement supply','50kg bags','bag',10,1
) ON CONFLICT (id) DO NOTHING;

UPDATE public.ammir_project_rfqs
SET status='open',published_at=now()
WHERE id='cccccccc-2511-4000-8000-000000000001';

INSERT INTO public.ammar_market_suppliers(owner_id,business_name,status,is_verified)
VALUES('aaaaaaaa-2511-4000-8000-000000000003','Operational Alerts Test Supplier','active',true)
ON CONFLICT DO NOTHING;

INSERT INTO public.ammir_project_rfq_invites(
 rfq_id,project_id,provider_user_id,provider_type,provider_name_snapshot,status,invited_by,responded_at
) VALUES (
 'cccccccc-2511-4000-8000-000000000001',
 'bbbbbbbb-2511-4000-8000-000000000001',
 'aaaaaaaa-2511-4000-8000-000000000003',
 'supplier','Operational Alerts Test Supplier','invited',
 'aaaaaaaa-2511-4000-8000-000000000002',now()
) ON CONFLICT DO NOTHING;

UPDATE public.ammir_project_rfq_invites
SET status='accepted',responded_at=now()
WHERE rfq_id='cccccccc-2511-4000-8000-000000000001'
  AND provider_user_id='aaaaaaaa-2511-4000-8000-000000000003';

INSERT INTO public.ammir_project_rfq_quotes(
 id,rfq_id,project_id,provider_user_id,currency,total_cost,status,submitted_at
) VALUES (
 'ffffffff-2511-4000-8000-000000000002',
 'cccccccc-2511-4000-8000-000000000001',
 'bbbbbbbb-2511-4000-8000-000000000001',
 'aaaaaaaa-2511-4000-8000-000000000003','SDG',0,'draft',NULL
) ON CONFLICT (id) DO NOTHING;

INSERT INTO public.ammir_project_rfq_quote_items(
 id,quote_id,rfq_item_id,project_id,quoted_quantity,unit_rate
) VALUES (
 'ffffffff-2511-4000-8000-000000000003',
 'ffffffff-2511-4000-8000-000000000002',
 'ffffffff-2511-4000-8000-000000000001',
 'bbbbbbbb-2511-4000-8000-000000000001',10,100
) ON CONFLICT (id) DO NOTHING;

UPDATE public.ammir_project_rfq_quotes
SET status='submitted',submitted_at=now()
WHERE id='ffffffff-2511-4000-8000-000000000002';

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

INSERT INTO public.ammir_project_award_items(
 award_id,project_id,rfq_item_id,quote_item_id,awarded_quantity,unit_rate,currency
) VALUES (
 'dddddddd-2511-4000-8000-000000000001',
 'bbbbbbbb-2511-4000-8000-000000000001',
 'ffffffff-2511-4000-8000-000000000001',
 'ffffffff-2511-4000-8000-000000000003',10,100,'SDG'
) ON CONFLICT DO NOTHING;

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


-- Add one measurable delivery sample. It remains planned, so completion and
-- on-time rates must be unavailable/zero rather than fabricated.
INSERT INTO public.ammir_project_delivery_items(
 delivery_id,project_id,award_item_id,expected_quantity,received_quantity,damaged_quantity,missing_quantity
) VALUES (
 'eeeeeeee-2511-4000-8000-000000000001',
 'bbbbbbbb-2511-4000-8000-000000000001',
 (SELECT id FROM public.ammir_project_award_items
   WHERE award_id='dddddddd-2511-4000-8000-000000000001' LIMIT 1),
 10,0,0,0
) ON CONFLICT DO NOTHING;

-- A signed-in non-admin must be denied by the RPC itself.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','aaaaaaaa-2511-4000-8000-000000000002',true);
DO $nonadmin$
DECLARE v_denied boolean := false;
BEGIN
  BEGIN
    PERFORM * FROM public.ammar_admin_supplier_performance(now() - interval '90 days');
  EXCEPTION WHEN SQLSTATE '42501' THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'non-admin unexpectedly received supplier performance';
  END IF;
END
$nonadmin$;

-- An administrator receives provider-level aggregates only, not project details.
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','aaaaaaaa-2511-4000-8000-000000000001',true);
DO $admin$
DECLARE
  v_row record;
BEGIN
  SELECT * INTO v_row
  FROM public.ammar_admin_supplier_performance(now() - interval '90 days')
  WHERE provider_id='aaaaaaaa-2511-4000-8000-000000000003';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'expected supplier performance aggregate was not returned';
  END IF;
  IF v_row.provider_name <> 'Operational Alerts Test Supplier'
     OR v_row.rfq_invitation_count <> 1
     OR v_row.rfq_response_count <> 1
     OR v_row.rfq_response_rate <> 100 THEN
    RAISE EXCEPTION 'unexpected RFQ response metrics: %', row_to_json(v_row);
  END IF;
  IF v_row.delivery_count <> 1 OR v_row.completed_delivery_count <> 0
     OR v_row.delivery_completion_rate <> 0
     OR v_row.on_time_delivery_rate IS NOT NULL THEN
    RAISE EXCEPTION 'incomplete delivery must not count as completed or on-time: %', row_to_json(v_row);
  END IF;
END
$admin$;

RESET ROLE;
ROLLBACK;

SELECT 'AMMIR ADMIN SUPPLIER PERFORMANCE TESTS PASSED' AS result;
