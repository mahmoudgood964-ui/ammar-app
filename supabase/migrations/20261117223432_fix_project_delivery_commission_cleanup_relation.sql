BEGIN;

CREATE OR REPLACE FUNCTION app_private.ammir_sync_project_delivery_commission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_delivery_id uuid;
  v_award_id uuid;
  v_project_id uuid;
  v_supplier_user_id uuid;
  v_status text;
  v_provider_type text;
  v_is_supplier boolean := false;
  v_activity_type text;
  v_currency text;
  v_gross numeric(14,2);
  v_rate numeric(5,2);
  v_payer_side text;
  v_payer_id uuid;
  v_project_client_id uuid;
BEGIN
  IF TG_TABLE_NAME = 'ammir_project_deliveries' THEN
    IF TG_OP = 'DELETE' THEN
      v_delivery_id := OLD.id;
    ELSE
      v_delivery_id := NEW.id;
    END IF;
  ELSE
    IF TG_OP = 'DELETE' THEN
      v_delivery_id := OLD.delivery_id;
    ELSE
      v_delivery_id := NEW.delivery_id;
    END IF;
  END IF;

  SELECT d.award_id, d.project_id, d.supplier_user_id, d.status
    INTO v_award_id, v_project_id, v_supplier_user_id, v_status
  FROM public.ammir_project_deliveries AS d
  WHERE d.id = v_delivery_id;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  IF v_status NOT IN ('received','partially_received','exception') THEN
    UPDATE public.ammar_commission_ledger AS l
    SET status = CASE WHEN l.status = 'paid' THEN 'paid' ELSE 'void' END
    WHERE l.source_type = 'project_delivery'
      AND l.source_id LIKE v_delivery_id::text || ':%';
    RETURN NULL;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.ammar_market_suppliers AS s
    WHERE s.owner_id = v_supplier_user_id
  ) INTO v_is_supplier;

  IF v_is_supplier THEN
    v_activity_type := 'market_materials';
  ELSE
    SELECT p.provider_type
      INTO v_provider_type
    FROM public.ammar_service_providers AS p
    WHERE p.owner_id = v_supplier_user_id
    LIMIT 1;

    v_activity_type := CASE
      WHEN v_provider_type = 'contractor' THEN 'contracting'
      WHEN v_provider_type = 'maintenance' THEN 'maintenance'
      WHEN v_provider_type = 'engineering' THEN 'engineering'
      ELSE 'other'
    END;
  END IF;

  SELECT pr.client_id
    INTO v_project_client_id
  FROM public.projects AS pr
  WHERE pr.id = v_project_id;

  FOR v_currency, v_gross IN
    SELECT
      COALESCE(NULLIF(ai.currency,''),'SDG') AS currency,
      ROUND(SUM(di.received_quantity * ai.unit_rate),2) AS gross_amount
    FROM public.ammir_project_delivery_items AS di
    JOIN public.ammir_project_award_items AS ai
      ON ai.id = di.award_item_id
     AND ai.project_id = di.project_id
    WHERE di.delivery_id = v_delivery_id
      AND di.project_id = v_project_id
    GROUP BY COALESCE(NULLIF(ai.currency,''),'SDG')
    HAVING SUM(di.received_quantity * ai.unit_rate) > 0
  LOOP
    SELECT r.rate_percent, r.payer_side
      INTO v_rate, v_payer_side
    FROM public.ammar_commission_rules AS r
    WHERE r.activity_type = v_activity_type
      AND r.is_active = true
    ORDER BY r.effective_from DESC NULLS LAST
    LIMIT 1;

    IF NOT FOUND THEN
      CONTINUE;
    END IF;

    v_payer_id := CASE
      WHEN v_payer_side = 'customer' THEN v_project_client_id
      ELSE v_supplier_user_id
    END;

    IF v_payer_id IS NULL THEN
      RAISE EXCEPTION 'Cannot determine the payer for AMMIR project delivery commission';
    END IF;

    INSERT INTO public.ammar_commission_ledger (
      request_id,
      activity_type,
      source_type,
      source_id,
      gross_amount,
      currency,
      rate_percent,
      commission_amount,
      payer_id,
      status
    )
    VALUES (
      NULL,
      v_activity_type,
      'project_delivery',
      v_delivery_id::text || ':' || v_currency,
      v_gross,
      v_currency,
      v_rate,
      ROUND(v_gross * v_rate / 100, 2),
      v_payer_id,
      'due'
    )
    ON CONFLICT (source_type, source_id)
    DO UPDATE SET
      activity_type = EXCLUDED.activity_type,
      gross_amount = EXCLUDED.gross_amount,
      currency = EXCLUDED.currency,
      rate_percent = EXCLUDED.rate_percent,
      commission_amount = EXCLUDED.commission_amount,
      payer_id = EXCLUDED.payer_id,
      status = CASE
        WHEN public.ammar_commission_ledger.status = 'paid' THEN 'paid'
        ELSE 'due'
      END;
  END LOOP;

  UPDATE public.ammar_commission_ledger AS l
  SET status = CASE WHEN l.status = 'paid' THEN 'paid' ELSE 'void' END
  WHERE l.source_type = 'project_delivery'
    AND l.source_id LIKE v_delivery_id::text || ':%'
    AND NOT EXISTS (
      SELECT 1
      FROM public.ammar_commission_ledger AS keep
      WHERE keep.id = l.id
        AND EXISTS (
          SELECT 1
          FROM public.ammir_project_delivery_items AS di
          JOIN public.ammar_project_award_items AS ai
            ON ai.id = di.award_item_id
           AND ai.project_id = di.project_id
          WHERE di.delivery_id = v_delivery_id
          GROUP BY COALESCE(NULLIF(ai.currency,''),'SDG')
          HAVING SUM(di.received_quantity * ai.unit_rate) > 0
             AND keep.source_id = v_delivery_id::text || ':' || COALESCE(NULLIF(ai.currency,''),'SDG')
        )
    );

  RETURN NULL;
END;
$function$
;

COMMIT;
