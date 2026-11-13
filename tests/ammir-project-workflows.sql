BEGIN;

DO $ammir_workflow_tests$
DECLARE
  v_owner uuid := gen_random_uuid();
  v_supplier_a uuid := gen_random_uuid();
  v_supplier_b uuid := gen_random_uuid();
  v_project uuid := gen_random_uuid();
  v_boq uuid;
  v_boq_item uuid;
  v_rfq uuid;
  v_rfq_item uuid;
  v_invite_a uuid;
  v_invite_b uuid;
  v_quote_a uuid;
  v_quote_b uuid;
  v_quote_item_a uuid;
  v_quote_item_b uuid;
  v_award_a uuid;
  v_award_b uuid;
  v_award_c uuid;
  v_delivery_a uuid;
  v_delivery_b uuid;
  v_delivery_item_a uuid;
  v_delivery_item_b uuid;
  v_evidence uuid;
  v_total numeric(20,2);
  v_failed boolean;
  v_count integer;
BEGIN
  INSERT INTO auth.users(id,email) VALUES
    (v_owner,'workflow-owner@example.test'),
    (v_supplier_a,'workflow-supplier-a@example.test'),
    (v_supplier_b,'workflow-supplier-b@example.test');
  INSERT INTO public.profiles(id,role) VALUES
    (v_owner,'client'),(v_supplier_a,'client'),(v_supplier_b,'client');

  INSERT INTO public.projects(id,client_id,title)
  VALUES(v_project,v_owner,'AMMIR workflow regression project');

  INSERT INTO public.ammar_market_suppliers(owner_id,business_name,status,is_verified)
  VALUES(v_supplier_a,'Verified Materials Supplier','active',true);
  INSERT INTO public.ammar_service_providers(owner_id,business_name,provider_type,status,is_verified)
  VALUES(v_supplier_b,'Verified Engineering Provider','engineering','active',true);

  INSERT INTO public.ammir_project_boq_versions(project_id,version_no,title,status,created_by)
  VALUES(v_project,1,'Core construction scope','draft',v_owner)
  RETURNING id INTO v_boq;

  INSERT INTO public.ammir_project_boq_items(
    project_id,boq_version_id,item_code,category,description,specification,unit,quantity,unit_rate,currency,created_by
  ) VALUES (
    v_project,v_boq,'01.01','Concrete','Supply and place concrete','Grade C30','m3',10,100,'SDG',v_owner
  ) RETURNING id INTO v_boq_item;

  UPDATE public.ammir_project_boq_versions
    SET status='published',published_by=v_owner,published_at=now()
    WHERE id=v_boq;

  v_failed := false;
  BEGIN
    UPDATE public.ammir_project_boq_items SET quantity=11 WHERE id=v_boq_item;
  EXCEPTION WHEN OTHERS THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'Published BOQ item was unexpectedly editable'; END IF;

  INSERT INTO public.ammir_project_rfqs(
    project_id,boq_version_id,reference_code,title,scope_description,delivery_location,currency,status,created_by,published_at
  ) VALUES (
    v_project,v_boq,'AMMIR-RFQ-TEST-001','Concrete supply request','Supply 10 cubic metres of C30 concrete',
    'Khartoum test location','SDG','open',v_owner,now()
  ) RETURNING id INTO v_rfq;

  INSERT INTO public.ammir_project_rfq_items(
    rfq_id,project_id,boq_item_id,item_code,description,specification,unit,quantity,sort_order
  ) VALUES (
    v_rfq,v_project,v_boq_item,'01.01','Supply and place concrete','Grade C30','m3',10,1
  ) RETURNING id INTO v_rfq_item;

  v_failed := false;
  BEGIN
    UPDATE public.ammir_project_rfq_items SET description='Altered after publication'
      WHERE id=v_rfq_item;
  EXCEPTION WHEN OTHERS THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'Published RFQ item was unexpectedly editable'; END IF;

  INSERT INTO public.ammir_project_rfq_invites(
    rfq_id,project_id,provider_user_id,provider_type,provider_name_snapshot,invited_by,status
  ) VALUES
    (v_rfq,v_project,v_supplier_a,'supplier','Verified Materials Supplier',v_owner,'accepted'),
    (v_rfq,v_project,v_supplier_b,'service_provider','Verified Engineering Provider',v_owner,'accepted');

  SELECT id INTO v_invite_a FROM public.ammir_project_rfq_invites
   WHERE rfq_id=v_rfq AND provider_user_id=v_supplier_a;
  SELECT id INTO v_invite_b FROM public.ammir_project_rfq_invites
   WHERE rfq_id=v_rfq AND provider_user_id=v_supplier_b;
  IF v_invite_a IS NULL OR v_invite_b IS NULL THEN RAISE EXCEPTION 'Multi-provider invitations were not recorded'; END IF;

  INSERT INTO public.ammir_project_rfq_quotes(
    rfq_id,project_id,provider_user_id,currency,transport_cost,loading_cost,taxes,other_costs,status
  ) VALUES(v_rfq,v_project,v_supplier_a,'SDG',50,0,0,0,'draft')
  RETURNING id INTO v_quote_a;

  INSERT INTO public.ammir_project_rfq_quote_items(
    quote_id,rfq_item_id,project_id,quoted_quantity,unit_rate,availability_status
  ) VALUES(v_quote_a,v_rfq_item,v_project,10,110,'confirmed')
  RETURNING id INTO v_quote_item_a;

  UPDATE public.ammir_project_rfq_quotes
    SET status='submitted',submitted_at=now()
    WHERE id=v_quote_a;

  SELECT total_cost INTO v_total FROM public.ammir_project_rfq_quotes WHERE id=v_quote_a;
  IF v_total <> 1150 THEN RAISE EXCEPTION 'Submitted quote total should be 1150, got %',v_total; END IF;

  INSERT INTO public.ammir_project_rfq_quotes(
    rfq_id,project_id,provider_user_id,currency,transport_cost,loading_cost,taxes,other_costs,status
  ) VALUES(v_rfq,v_project,v_supplier_b,'SDG',0,0,100,0,'draft')
  RETURNING id INTO v_quote_b;

  INSERT INTO public.ammir_project_rfq_quote_items(
    quote_id,rfq_item_id,project_id,quoted_quantity,unit_rate,availability_status
  ) VALUES(v_quote_b,v_rfq_item,v_project,10,120,'partial')
  RETURNING id INTO v_quote_item_b;

  UPDATE public.ammir_project_rfq_quotes
    SET status='submitted',submitted_at=now()
    WHERE id=v_quote_b;

  SELECT total_cost INTO v_total FROM public.ammir_project_rfq_quotes WHERE id=v_quote_b;
  IF v_total <> 1300 THEN RAISE EXCEPTION 'Second submitted quote total should be 1300, got %',v_total; END IF;

  INSERT INTO public.ammir_project_awards(
    rfq_id,project_id,supplier_user_id,award_reference,status,terms,created_by,issued_at
  ) VALUES(v_rfq,v_project,v_supplier_a,'AWD-TEST-A','draft','First partial award',v_owner,NULL)
  RETURNING id INTO v_award_a;

  INSERT INTO public.ammir_project_award_items(
    award_id,project_id,rfq_item_id,quote_item_id,awarded_quantity,unit_rate,currency
  ) VALUES(v_award_a,v_project,v_rfq_item,v_quote_item_a,4,110,'SDG');
  UPDATE public.ammir_project_awards SET status='issued',issued_at=now() WHERE id=v_award_a;

  INSERT INTO public.ammir_project_awards(
    rfq_id,project_id,supplier_user_id,award_reference,status,terms,created_by
  ) VALUES(v_rfq,v_project,v_supplier_a,'AWD-TEST-C','draft','Price mismatch guard test',v_owner)
  RETURNING id INTO v_award_c;

  v_failed := false;
  BEGIN
    INSERT INTO public.ammir_project_award_items(
      award_id,project_id,rfq_item_id,quote_item_id,awarded_quantity,unit_rate,currency
    ) VALUES(v_award_c,v_project,v_rfq_item,v_quote_item_a,0.5,111,'SDG');
  EXCEPTION WHEN OTHERS THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'Award price differing from submitted quote was unexpectedly accepted'; END IF;

  INSERT INTO public.ammir_project_awards(
    rfq_id,project_id,supplier_user_id,award_reference,status,terms,created_by,issued_at
  ) VALUES(v_rfq,v_project,v_supplier_b,'AWD-TEST-B','draft','Second split award',v_owner,NULL)
  RETURNING id INTO v_award_b;

  INSERT INTO public.ammir_project_award_items(
    award_id,project_id,rfq_item_id,quote_item_id,awarded_quantity,unit_rate,currency
  ) VALUES(v_award_b,v_project,v_rfq_item,v_quote_item_b,6,120,'SDG');
  UPDATE public.ammir_project_awards SET status='issued',issued_at=now() WHERE id=v_award_b;

  v_failed := false;
  BEGIN
    DELETE FROM public.ammir_project_award_items WHERE award_id=v_award_a;
  EXCEPTION WHEN OTHERS THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'Issued award line items were unexpectedly deletable'; END IF;

  v_failed := false;
  BEGIN
    INSERT INTO public.ammir_project_award_items(
      award_id,project_id,rfq_item_id,quote_item_id,awarded_quantity,unit_rate,currency
    ) VALUES(v_award_c,v_project,v_rfq_item,v_quote_item_a,0.001,110,'SDG');
  EXCEPTION WHEN OTHERS THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'Split awards exceeding requested quantity were unexpectedly accepted'; END IF;


  v_failed := false;
  BEGIN
    INSERT INTO public.ammir_project_deliveries(
      award_id,project_id,supplier_user_id,delivery_reference,status,created_by
    ) VALUES(v_award_a,v_project,v_supplier_b,'DEL-TEST-WRONG-SUPPLIER','planned',v_owner);
  EXCEPTION WHEN OTHERS THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'Delivery with a supplier different from the award was accepted'; END IF;

  INSERT INTO public.ammir_project_deliveries(
    award_id,project_id,supplier_user_id,delivery_reference,status,created_by
  ) VALUES(v_award_a,v_project,v_supplier_a,'DEL-TEST-PARTIAL','planned',v_owner)
  RETURNING id INTO v_delivery_a;

  INSERT INTO public.ammir_project_delivery_items(delivery_id,project_id,award_item_id,expected_quantity)
  SELECT v_delivery_a,v_project,id,4
  FROM public.ammir_project_award_items WHERE award_id=v_award_a
  RETURNING id INTO v_delivery_item_a;

  UPDATE public.ammir_project_delivery_items
    SET received_quantity=3
    WHERE id=v_delivery_item_a;

  v_failed := false;
  BEGIN
    UPDATE public.ammir_project_deliveries SET status='received' WHERE id=v_delivery_a;
  EXCEPTION WHEN OTHERS THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'Incomplete receipt was unexpectedly marked fully received'; END IF;

  UPDATE public.ammir_project_delivery_items
    SET received_quantity=3,missing_quantity=1
    WHERE id=v_delivery_item_a;
  UPDATE public.ammir_project_deliveries SET status='exception' WHERE id=v_delivery_a;

  INSERT INTO public.ammir_project_deliveries(
    award_id,project_id,supplier_user_id,delivery_reference,status,created_by
  ) VALUES(v_award_b,v_project,v_supplier_b,'DEL-TEST-COMPLETE','planned',v_owner)
  RETURNING id INTO v_delivery_b;

  INSERT INTO public.ammir_project_delivery_items(delivery_id,project_id,award_item_id,expected_quantity,received_quantity)
  SELECT v_delivery_b,v_project,id,6,6
  FROM public.ammir_project_award_items WHERE award_id=v_award_b
  RETURNING id INTO v_delivery_item_b;

  UPDATE public.ammir_project_deliveries
    SET status='received',received_at=now(),received_by=v_owner
    WHERE id=v_delivery_b;

  v_failed := false;
  BEGIN
    INSERT INTO public.ammir_project_delivery_items(delivery_id,project_id,award_item_id,expected_quantity)
    SELECT v_delivery_a,v_project,id,0.1
    FROM public.ammir_project_award_items WHERE award_id=v_award_a;
  EXCEPTION WHEN OTHERS THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'Cumulative dispatched quantity exceeding award was unexpectedly accepted'; END IF;

  v_failed := false;
  BEGIN
    DELETE FROM public.ammir_project_deliveries WHERE id=v_delivery_b;
  EXCEPTION WHEN OTHERS THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'A fully received delivery was unexpectedly deletable'; END IF;

  INSERT INTO storage.objects(bucket_id,name,owner_id)
  VALUES('ammir-delivery-evidence',v_project::text||'/'||v_delivery_a::text||'/proof.png',v_owner::text);
  INSERT INTO public.ammir_project_delivery_evidence(
    delivery_id,project_id,object_path,file_name,mime_type,caption,uploaded_by
  ) VALUES(
    v_delivery_a,v_project,v_project::text||'/'||v_delivery_a::text||'/proof.png',
    'proof.png','image/png','Test delivery evidence',v_owner
  ) RETURNING id INTO v_evidence;

  IF v_evidence IS NULL THEN RAISE EXCEPTION 'Delivery evidence metadata was not recorded'; END IF;

  SELECT count(*) INTO v_count FROM pg_policies
  WHERE schemaname='public' AND tablename='ammir_project_rfq_quotes'
    AND policyname='ammir_rfq_quotes_select';
  IF v_count<>1 THEN RAISE EXCEPTION 'Provider quote visibility policy is missing'; END IF;

  SELECT count(*) INTO v_count FROM pg_policies
  WHERE schemaname='public' AND tablename='ammir_project_rfq_quotes'
    AND policyname='ammir_rfq_quotes_update_provider';
  IF v_count<>1 THEN RAISE EXCEPTION 'Provider draft quote policy is missing'; END IF;

  RAISE NOTICE 'AMMIR PROJECT BOQ/RFQ/AWARD/DELIVERY TESTS PASSED';
END
$ammir_workflow_tests$;

ROLLBACK;
