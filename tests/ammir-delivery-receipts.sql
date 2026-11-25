BEGIN;

DO $delivery_receipt_tests$
DECLARE
  v_owner uuid := gen_random_uuid();
  v_supplier uuid := gen_random_uuid();
  v_unrelated uuid := gen_random_uuid();
  v_project uuid := gen_random_uuid();
  v_rfq uuid;
  v_rfq_item uuid;
  v_quote uuid;
  v_quote_item uuid;
  v_award uuid;
  v_award_item uuid;
  v_delivery_a uuid;
  v_delivery_b uuid;
  v_item_a uuid;
  v_item_b uuid;
  v_key_a uuid := gen_random_uuid();
  v_key_b uuid := gen_random_uuid();
  v_key_c uuid := gen_random_uuid();
  v_receipt_a uuid;
  v_receipt_b uuid;
  v_receipt_replay uuid;
  v_count integer;
  v_gross numeric(20,2);
  v_commission numeric(20,2);
  v_paid_gross numeric(20,2);
  v_paid_commission numeric(20,2);
  v_failed boolean;
  v_error text;
BEGIN
  INSERT INTO auth.users(id,email) VALUES
    (v_owner,'delivery-receipt-owner@example.test'),
    (v_supplier,'delivery-receipt-supplier@example.test'),
    (v_unrelated,'delivery-receipt-unrelated@example.test');
  INSERT INTO public.profiles(id,role) VALUES
    (v_owner,'client'),(v_supplier,'client');
  INSERT INTO public.projects(id,client_id,title)
  VALUES(v_project,v_owner,'AMMIR incremental receipt regression');

  INSERT INTO public.ammar_market_suppliers(owner_id,business_name,status,is_verified)
  VALUES(v_supplier,'Verified Receipt Test Supplier','active',true);

  INSERT INTO public.ammar_commission_rules(activity_type,rate_percent,payer_side,is_active,effective_from)
  VALUES('market_materials',5,'provider',true,now())
  ON CONFLICT(activity_type) DO UPDATE
    SET rate_percent=5,payer_side='provider',is_active=true,effective_from=now();

  INSERT INTO public.ammir_project_rfqs(
    project_id,reference_code,title,currency,status,created_by,published_at
  ) VALUES(v_project,'RCPT-RFQ-01','Receipt regression request','SDG','draft',v_owner,now())
  RETURNING id INTO v_rfq;

  INSERT INTO public.ammir_project_rfq_items(
    rfq_id,project_id,description,unit,quantity,sort_order
  ) VALUES(v_rfq,v_project,'Test aggregate','unit',10,1)
  RETURNING id INTO v_rfq_item;

  UPDATE public.ammir_project_rfqs SET status='open',published_at=now() WHERE id=v_rfq;

  INSERT INTO public.ammir_project_rfq_invites(
    rfq_id,project_id,provider_user_id,provider_type,provider_name_snapshot,invited_by,status
  ) VALUES(v_rfq,v_project,v_supplier,'supplier','Verified Receipt Test Supplier',v_owner,'invited');

  INSERT INTO public.ammir_project_rfq_quotes(
    rfq_id,project_id,provider_user_id,currency,status
  ) VALUES(v_rfq,v_project,v_supplier,'SDG','draft')
  RETURNING id INTO v_quote;

  INSERT INTO public.ammir_project_rfq_quote_items(
    quote_id,rfq_item_id,project_id,quoted_quantity,unit_rate,availability_status
  ) VALUES(v_quote,v_rfq_item,v_project,10,110,'confirmed')
  RETURNING id INTO v_quote_item;

  UPDATE public.ammir_project_rfq_quotes
  SET status='submitted',submitted_at=now()
  WHERE id=v_quote;

  INSERT INTO public.ammir_project_awards(
    rfq_id,project_id,supplier_user_id,award_reference,status,created_by
  ) VALUES(v_rfq,v_project,v_supplier,'RCPT-AWARD-01','draft',v_owner)
  RETURNING id INTO v_award;

  INSERT INTO public.ammir_project_award_items(
    award_id,project_id,rfq_item_id,quote_item_id,awarded_quantity,unit_rate,currency
  ) VALUES(v_award,v_project,v_rfq_item,v_quote_item,10,110,'SDG')
  RETURNING id INTO v_award_item;

  UPDATE public.ammir_project_awards
  SET status='issued',issued_at=now()
  WHERE id=v_award;

  PERFORM set_config('request.jwt.claim.sub',v_supplier::text,true);
  UPDATE public.ammir_project_awards
  SET status='accepted',accepted_at=now()
  WHERE id=v_award AND supplier_user_id=v_supplier;

  PERFORM set_config('request.jwt.claim.sub',v_owner::text,true);
  INSERT INTO public.ammir_project_deliveries(
    award_id,project_id,supplier_user_id,delivery_reference,status,created_by
  ) VALUES(v_award,v_project,v_supplier,'RCPT-DELIVERY-A','planned',v_owner)
  RETURNING id INTO v_delivery_a;

  INSERT INTO public.ammir_project_delivery_items(
    delivery_id,project_id,award_item_id,expected_quantity
  ) VALUES(v_delivery_a,v_project,v_award_item,4)
  RETURNING id INTO v_item_a;

  PERFORM set_config('request.jwt.claim.sub',v_supplier::text,true);
  UPDATE public.ammir_project_deliveries
  SET status='dispatched',dispatched_at=now()
  WHERE id=v_delivery_a AND supplier_user_id=v_supplier;

  PERFORM set_config('request.jwt.claim.sub',v_owner::text,true);

  -- An authenticated but unrelated user must not reconcile another project's delivery.
  PERFORM set_config('request.jwt.claim.sub',v_unrelated::text,true);
  v_failed := false;
  v_error := null;
  BEGIN
    PERFORM public.ammir_record_delivery_receipt(
      v_delivery_a,
      jsonb_build_array(jsonb_build_object(
        'delivery_item_id',v_item_a,'received_quantity',1,'damaged_quantity',0,
        'missing_quantity',0,'rejected_quantity',0,'condition_notes',null
      )),
      'partially_received',gen_random_uuid(),null
    );
  EXCEPTION WHEN OTHERS THEN
    v_failed := true;
    GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;
  END;
  IF NOT v_failed OR v_error NOT LIKE '%Project manager permission required%' THEN
    RAISE EXCEPTION 'Unrelated authenticated user was not rejected by project authorization: %',coalesce(v_error,'no error');
  END IF;
  PERFORM set_config('request.jwt.claim.sub',v_owner::text,true);

  -- A premature full-receipt claim must fail without creating an event or ledger row.
  v_failed := false;
  BEGIN
    PERFORM public.ammir_record_delivery_receipt(
      v_delivery_a,
      jsonb_build_array(jsonb_build_object(
        'delivery_item_id',v_item_a,'received_quantity',2,'damaged_quantity',0,
        'missing_quantity',0,'rejected_quantity',0,'condition_notes',null
      )),
      'received',gen_random_uuid(),null
    );
  EXCEPTION WHEN OTHERS THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'Incomplete receipt was accepted as fully received'; END IF;

  -- First batch: two good units. One immutable commission entry is created.
  v_receipt_a := public.ammir_record_delivery_receipt(
    v_delivery_a,
    jsonb_build_array(jsonb_build_object(
      'delivery_item_id',v_item_a,'received_quantity',2,'damaged_quantity',0,
      'missing_quantity',0,'rejected_quantity',0,'condition_notes',null
    )),
    'partially_received',v_key_a,null
  );

  SELECT count(*),coalesce(sum(gross_amount),0),coalesce(sum(commission_amount),0)
  INTO v_count,v_gross,v_commission
  FROM public.ammar_commission_ledger
  WHERE source_type='project_delivery' AND source_id LIKE v_delivery_a::text||':%';
  IF v_count<>1 OR v_gross<>220 OR v_commission<>11 THEN
    RAISE EXCEPTION 'First receipt commission mismatch: rows %, gross %, commission %',v_count,v_gross,v_commission;
  END IF;

  -- Reusing an idempotency key with a different payload must be rejected.
  v_failed := false;
  v_error := null;
  BEGIN
    PERFORM public.ammir_record_delivery_receipt(
      v_delivery_a,
      jsonb_build_array(jsonb_build_object(
        'delivery_item_id',v_item_a,'received_quantity',1,'damaged_quantity',0,
        'missing_quantity',0,'rejected_quantity',0,'condition_notes',null
      )),
      'partially_received',v_key_a,null
    );
  EXCEPTION WHEN OTHERS THEN
    v_failed := true;
    GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;
  END;
  IF NOT v_failed OR v_error NOT LIKE '%idempotency key was already used with a different payload%' THEN
    RAISE EXCEPTION 'Reusing an idempotency key with a changed payload was not rejected: %',coalesce(v_error,'no error');
  END IF;

  -- A batch may not account for more than the outstanding delivery quantity.
  v_failed := false;
  v_error := null;
  BEGIN
    PERFORM public.ammir_record_delivery_receipt(
      v_delivery_a,
      jsonb_build_array(jsonb_build_object(
        'delivery_item_id',v_item_a,'received_quantity',3,'damaged_quantity',0,
        'missing_quantity',0,'rejected_quantity',0,'condition_notes',null
      )),
      'received',gen_random_uuid(),null
    );
  EXCEPTION WHEN OTHERS THEN
    v_failed := true;
    GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;
  END;
  IF NOT v_failed OR v_error NOT LIKE '%Invalid receipt quantities%' THEN
    RAISE EXCEPTION 'Receipt quantity beyond outstanding balance was not rejected: %',coalesce(v_error,'no error');
  END IF;

  UPDATE public.ammar_commission_ledger
  SET status='paid',settled_at=now()
  WHERE source_type='project_delivery' AND source_id LIKE v_delivery_a::text||':%';

  SELECT gross_amount,commission_amount INTO v_paid_gross,v_paid_commission
  FROM public.ammar_commission_ledger
  WHERE source_type='project_delivery' AND source_id LIKE v_delivery_a::text||':%';

  -- Replaying the same idempotency key and payload must not add quantities or commission.
  v_receipt_replay := public.ammir_record_delivery_receipt(
    v_delivery_a,
    jsonb_build_array(jsonb_build_object(
      'delivery_item_id',v_item_a,'received_quantity',1,'damaged_quantity',0,
      'missing_quantity',0,'rejected_quantity',0,'condition_notes',null
    )),
    'partially_received',v_key_b,null
  );
  v_receipt_b := public.ammir_record_delivery_receipt(
    v_delivery_a,
    jsonb_build_array(jsonb_build_object(
      'delivery_item_id',v_item_a,'received_quantity',1,'damaged_quantity',0,
      'missing_quantity',0,'rejected_quantity',0,'condition_notes',null
    )),
    'partially_received',v_key_b,null
  );
  IF v_receipt_replay<>v_receipt_b THEN RAISE EXCEPTION 'Idempotent replay did not return the original receipt id'; END IF;

  SELECT count(*),coalesce(sum(gross_amount),0),coalesce(sum(commission_amount),0)
  INTO v_count,v_gross,v_commission
  FROM public.ammar_commission_ledger
  WHERE source_type='project_delivery' AND source_id LIKE v_delivery_a::text||':%';
  IF v_count<>2 OR v_gross<>330 OR v_commission<>16.5 THEN
    RAISE EXCEPTION 'Second receipt should create only one incremental ledger row; rows %, gross %, commission %',v_count,v_gross,v_commission;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.ammar_commission_ledger
    WHERE source_type='project_delivery' AND source_id LIKE v_delivery_a::text||':%'
      AND status='paid' AND gross_amount=v_paid_gross AND commission_amount=v_paid_commission
  ) THEN RAISE EXCEPTION 'A paid commission row was changed by a later partial receipt'; END IF;

  -- Final good unit completes the delivery with a third separate ledger entry.
  PERFORM public.ammir_record_delivery_receipt(
    v_delivery_a,
    jsonb_build_array(jsonb_build_object(
      'delivery_item_id',v_item_a,'received_quantity',1,'damaged_quantity',0,
      'missing_quantity',0,'rejected_quantity',0,'condition_notes',null
    )),
    'received',v_key_c,null
  );

  SELECT count(*),coalesce(sum(gross_amount),0),coalesce(sum(commission_amount),0)
  INTO v_count,v_gross,v_commission
  FROM public.ammar_commission_ledger
  WHERE source_type='project_delivery' AND source_id LIKE v_delivery_a::text||':%';
  IF v_count<>3 OR v_gross<>440 OR v_commission<>22 THEN
    RAISE EXCEPTION 'Final receipt totals mismatch: rows %, gross %, commission %',v_count,v_gross,v_commission;
  END IF;

  v_failed := false;
  BEGIN
    UPDATE public.ammir_project_deliveries SET status='cancelled' WHERE id=v_delivery_a;
  EXCEPTION WHEN OTHERS THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'A delivery with receipt history was unexpectedly cancelled'; END IF;

  v_failed := false;
  BEGIN
    UPDATE public.ammir_project_delivery_items SET received_quantity=0 WHERE id=v_item_a;
  EXCEPTION WHEN OTHERS THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'Direct delivery quantity mutation bypassed receipt history'; END IF;

  -- Second delivery: rejected units are accounted for but excluded from commission.
  INSERT INTO public.ammir_project_deliveries(
    award_id,project_id,supplier_user_id,delivery_reference,status,created_by
  ) VALUES(v_award,v_project,v_supplier,'RCPT-DELIVERY-B','planned',v_owner)
  RETURNING id INTO v_delivery_b;

  INSERT INTO public.ammir_project_delivery_items(
    delivery_id,project_id,award_item_id,expected_quantity
  ) VALUES(v_delivery_b,v_project,v_award_item,6)
  RETURNING id INTO v_item_b;

  PERFORM set_config('request.jwt.claim.sub',v_supplier::text,true);
  UPDATE public.ammir_project_deliveries
  SET status='dispatched',dispatched_at=now()
  WHERE id=v_delivery_b AND supplier_user_id=v_supplier;

  PERFORM set_config('request.jwt.claim.sub',v_owner::text,true);

  -- A rejected quantity without a recorded reason must be rejected.
  v_failed := false;
  v_error := null;
  BEGIN
    PERFORM public.ammir_record_delivery_receipt(
      v_delivery_b,
      jsonb_build_array(jsonb_build_object(
        'delivery_item_id',v_item_b,'received_quantity',4,'damaged_quantity',0,
        'missing_quantity',0,'rejected_quantity',2,'condition_notes',null
      )),
      'exception',gen_random_uuid(),null
    );
  EXCEPTION WHEN OTHERS THEN
    v_failed := true;
    GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;
  END;
  IF NOT v_failed OR v_error NOT LIKE '%Invalid receipt quantities, reason%' THEN
    RAISE EXCEPTION 'Rejected quantity without a reason was not rejected: %',coalesce(v_error,'no error');
  END IF;

  PERFORM public.ammir_record_delivery_receipt(
    v_delivery_b,
    jsonb_build_array(jsonb_build_object(
      'delivery_item_id',v_item_b,'received_quantity',4,'damaged_quantity',0,
      'missing_quantity',0,'rejected_quantity',2,'condition_notes','Rejected by buyer: specification mismatch'
    )),
    'exception',gen_random_uuid(),null
  );

  SELECT count(*),coalesce(sum(gross_amount),0),coalesce(sum(commission_amount),0)
  INTO v_count,v_gross,v_commission
  FROM public.ammar_commission_ledger
  WHERE source_type='project_delivery' AND source_id LIKE v_delivery_b::text||':%';
  IF v_count<>1 OR v_gross<>440 OR v_commission<>22 THEN
    RAISE EXCEPTION 'Rejected quantities must be excluded from commission; rows %, gross %, commission %',v_count,v_gross,v_commission;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.ammir_project_delivery_receipt_items
    WHERE delivery_id=v_delivery_b AND rejected_quantity=2
      AND condition_notes='Rejected by buyer: specification mismatch'
  ) THEN RAISE EXCEPTION 'Rejected quantity and reason were not preserved in receipt history'; END IF;

  -- Delivery claims create an auditable dispute trail without changing receipt or commission data.
  DECLARE
    v_claim_id uuid;
    v_claim_event_count integer;
    v_ledger_count_before integer;
    v_ledger_gross_before numeric(20,2);
    v_ledger_commission_before numeric(20,2);
  BEGIN
    SELECT count(*),coalesce(sum(gross_amount),0),coalesce(sum(commission_amount),0)
      INTO v_ledger_count_before,v_ledger_gross_before,v_ledger_commission_before
    FROM public.ammar_commission_ledger
    WHERE source_type='project_delivery' AND source_id LIKE v_delivery_b::text||':%';

    PERFORM set_config('request.jwt.claim.sub',v_owner::text,true);
    v_claim_id := public.ammir_submit_delivery_claim(
      v_delivery_b,
      (SELECT id FROM public.ammir_project_delivery_receipt_items
       WHERE delivery_id=v_delivery_b AND delivery_item_id=v_item_b LIMIT 1),
      'rejected_goods',2,
      'The supplier delivered rejected goods that do not match the agreed specification.'
    );

    -- A user unrelated to the project or assigned supplier cannot add claim messages.
    PERFORM set_config('request.jwt.claim.sub',v_unrelated::text,true);
    v_failed := false;
    BEGIN
      PERFORM public.ammir_add_delivery_claim_message(v_claim_id,'I am not a party to this delivery claim.');
    EXCEPTION WHEN OTHERS THEN
      v_failed := true;
    END;
    IF NOT v_failed THEN RAISE EXCEPTION 'Unrelated user unexpectedly added a claim message'; END IF;

    -- The assigned supplier can respond; project managers control resolution.
    PERFORM set_config('request.jwt.claim.sub',v_supplier::text,true);
    PERFORM public.ammir_add_delivery_claim_message(
      v_claim_id,'We acknowledge the rejection and will review the supplied batch documentation.'
    );

    PERFORM set_config('request.jwt.claim.sub',v_owner::text,true);
    PERFORM public.ammir_transition_delivery_claim(v_claim_id,'under_review',null);
    PERFORM public.ammir_transition_delivery_claim(v_claim_id,'response_requested',null);
    PERFORM public.ammir_transition_delivery_claim(
      v_claim_id,'accepted','Claim accepted for operational follow-up; no automatic financial adjustment.'
    );

    SELECT count(*) INTO v_claim_event_count
    FROM public.ammir_project_delivery_claim_events
    WHERE claim_id=v_claim_id;
    IF v_claim_event_count<>5 THEN
      RAISE EXCEPTION 'Expected opening, supplier response and three status events; found %',v_claim_event_count;
    END IF;

    v_failed := false;
    BEGIN
      UPDATE public.ammir_project_delivery_claim_events
      SET body='tampered'
      WHERE claim_id=v_claim_id;
    EXCEPTION WHEN OTHERS THEN
      v_failed := true;
    END;
    IF NOT v_failed THEN RAISE EXCEPTION 'Claim event history was unexpectedly mutable'; END IF;

    v_failed := false;
    BEGIN
      PERFORM public.ammir_add_delivery_claim_message(v_claim_id,'This message must be blocked after resolution.');
    EXCEPTION WHEN OTHERS THEN
      v_failed := true;
    END;
    IF NOT v_failed THEN RAISE EXCEPTION 'Resolved claim unexpectedly accepted a new message'; END IF;

    IF NOT EXISTS (
      SELECT 1 FROM public.ammir_project_delivery_claims
      WHERE id=v_claim_id AND status='accepted'
        AND resolved_by=v_owner AND resolved_at IS NOT NULL
        AND resolution_note='Claim accepted for operational follow-up; no automatic financial adjustment.'
    ) THEN RAISE EXCEPTION 'Claim resolution details were not persisted'; END IF;

    IF (
      SELECT count(*) FROM public.ammar_commission_ledger
      WHERE source_type='project_delivery' AND source_id LIKE v_delivery_b::text||':%'
    )<>v_ledger_count_before OR (
      SELECT coalesce(sum(gross_amount),0) FROM public.ammar_commission_ledger
      WHERE source_type='project_delivery' AND source_id LIKE v_delivery_b::text||':%'
    )<>v_ledger_gross_before OR (
      SELECT coalesce(sum(commission_amount),0) FROM public.ammar_commission_ledger
      WHERE source_type='project_delivery' AND source_id LIKE v_delivery_b::text||':%'
    )<>v_ledger_commission_before THEN
      RAISE EXCEPTION 'Claim resolution unexpectedly changed delivery commission ledger';
    END IF;
  END;

  RAISE NOTICE 'AMMIR INCREMENTAL DELIVERY RECEIPT AND CLAIM TESTS PASSED';
END
$delivery_receipt_tests$;

ROLLBACK;
