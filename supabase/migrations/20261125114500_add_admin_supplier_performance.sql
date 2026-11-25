BEGIN;

-- Aggregate-only supplier/contractor performance. No project identifiers or
-- project-specific facts are returned to the administrator dashboard.
CREATE OR REPLACE FUNCTION app_private.ammar_admin_supplier_performance(
  p_since timestamptz DEFAULT now() - interval '90 days'
)
RETURNS TABLE (
  provider_id uuid,
  provider_name text,
  provider_kind text,
  rfq_invitation_count bigint,
  rfq_response_count bigint,
  rfq_response_rate numeric,
  average_response_hours numeric,
  delivery_count bigint,
  completed_delivery_count bigint,
  delivery_completion_rate numeric,
  on_time_delivery_count bigint,
  on_time_delivery_rate numeric,
  sample_since timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_since timestamptz := COALESCE(p_since, now() - interval '90 days');
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'administrator access required' USING ERRCODE = '42501';
  END IF;
  IF v_since < now() - interval '24 months' THEN
    v_since := now() - interval '24 months';
  ELSIF v_since > now() THEN
    v_since := now();
  END IF;

  RETURN QUERY
  WITH invite_stats AS (
    SELECT
      i.provider_user_id,
      max(i.provider_name_snapshot) AS snapshot_name,
      max(i.provider_type) AS provider_type,
      count(*)::bigint AS invitation_count,
      count(*) FILTER (WHERE i.responded_at IS NOT NULL)::bigint AS response_count,
      avg(extract(epoch FROM (i.responded_at - i.invited_at)) / 3600.0)
        FILTER (WHERE i.responded_at IS NOT NULL AND i.responded_at >= i.invited_at) AS avg_response_hours
    FROM public.ammir_project_rfq_invites i
    JOIN public.ammir_project_rfqs r
      ON r.id = i.rfq_id AND r.project_id = i.project_id
    WHERE i.invited_at >= v_since
      AND i.provider_user_id IS NOT NULL
      AND i.status <> 'withdrawn'
      -- Do not penalize suppliers for invitations whose response window is still open.
      AND (
        i.responded_at IS NOT NULL
        OR (r.deadline_at IS NOT NULL AND r.deadline_at <= now())
        OR r.status IN ('awarded','cancelled','closed')
      )
    GROUP BY i.provider_user_id
  ),
  delivery_rows AS (
    SELECT
      d.supplier_user_id AS provider_user_id,
      d.id AS delivery_id,
      d.scheduled_at,
      d.received_at,
      d.status,
      COALESCE(sum(di.expected_quantity), 0) AS expected_quantity,
      COALESCE(sum(di.received_quantity), 0) AS received_quantity,
      COALESCE(sum(di.damaged_quantity), 0) AS damaged_quantity,
      COALESCE(sum(di.missing_quantity), 0) AS missing_quantity,
      count(di.id) AS item_count
    FROM public.ammir_project_deliveries d
    LEFT JOIN public.ammir_project_delivery_items di
      ON di.delivery_id = d.id AND di.project_id = d.project_id
    WHERE d.created_at >= v_since
      AND d.supplier_user_id IS NOT NULL
      AND d.status <> 'cancelled'
    GROUP BY d.supplier_user_id, d.id, d.scheduled_at, d.received_at, d.status
  ),
  delivery_stats AS (
    SELECT
      dr.provider_user_id,
      count(*) FILTER (WHERE dr.item_count > 0)::bigint AS delivery_count,
      count(*) FILTER (
        WHERE dr.item_count > 0
          AND dr.status = 'received'
          AND dr.received_at IS NOT NULL
          AND dr.expected_quantity > 0
          AND dr.received_quantity >= dr.expected_quantity
          AND dr.damaged_quantity = 0
          AND dr.missing_quantity = 0
      )::bigint AS completed_count,
      count(*) FILTER (
        WHERE dr.item_count > 0
          AND dr.status = 'received'
          AND dr.received_at IS NOT NULL
          AND dr.scheduled_at IS NOT NULL
          AND dr.expected_quantity > 0
          AND dr.received_quantity >= dr.expected_quantity
          AND dr.damaged_quantity = 0
          AND dr.missing_quantity = 0
          AND dr.received_at::date <= dr.scheduled_at
      )::bigint AS on_time_count,
      count(*) FILTER (
        WHERE dr.item_count > 0
          AND dr.status = 'received'
          AND dr.received_at IS NOT NULL
          AND dr.scheduled_at IS NOT NULL
          AND dr.expected_quantity > 0
          AND dr.received_quantity >= dr.expected_quantity
          AND dr.damaged_quantity = 0
          AND dr.missing_quantity = 0
      )::bigint AS on_time_denominator
    FROM delivery_rows dr
    GROUP BY dr.provider_user_id
  ),
  provider_ids AS (
    SELECT provider_user_id FROM invite_stats
    UNION
    SELECT provider_user_id FROM delivery_stats
  ),
  names AS (
    SELECT
      ids.provider_user_id,
      COALESCE(
        NULLIF(max(ins.snapshot_name), ''),
        NULLIF(max(ms.business_name), ''),
        NULLIF(max(sp.business_name), ''),
        'مقدم خدمة بدون اسم مسجل'
      ) AS provider_name,
      COALESCE(
        max(ins.provider_type),
        CASE WHEN bool_or(sp.owner_id IS NOT NULL) THEN 'service_provider' ELSE 'supplier' END
      ) AS provider_kind
    FROM provider_ids ids
    LEFT JOIN invite_stats ins ON ins.provider_user_id = ids.provider_user_id
    LEFT JOIN public.ammar_market_suppliers ms ON ms.owner_id = ids.provider_user_id
    LEFT JOIN public.ammar_service_providers sp ON sp.owner_id = ids.provider_user_id
    GROUP BY ids.provider_user_id
  )
  SELECT
    n.provider_user_id,
    n.provider_name,
    n.provider_kind,
    COALESCE(i.invitation_count, 0),
    COALESCE(i.response_count, 0),
    CASE WHEN COALESCE(i.invitation_count, 0) = 0 THEN NULL
         ELSE round(i.response_count::numeric * 100 / i.invitation_count, 2) END,
    CASE WHEN i.avg_response_hours IS NULL THEN NULL ELSE round(i.avg_response_hours::numeric, 2) END,
    COALESCE(d.delivery_count, 0),
    COALESCE(d.completed_count, 0),
    CASE WHEN COALESCE(d.delivery_count, 0) = 0 THEN NULL
         ELSE round(d.completed_count::numeric * 100 / d.delivery_count, 2) END,
    COALESCE(d.on_time_count, 0),
    CASE WHEN COALESCE(d.on_time_denominator, 0) = 0 THEN NULL
         ELSE round(d.on_time_count::numeric * 100 / d.on_time_denominator, 2) END,
    v_since
  FROM names n
  LEFT JOIN invite_stats i ON i.provider_user_id = n.provider_user_id
  LEFT JOIN delivery_stats d ON d.provider_user_id = n.provider_user_id
  ORDER BY COALESCE(d.delivery_count,0) DESC, COALESCE(i.invitation_count,0) DESC, n.provider_name
  LIMIT 500;
END;
$function$;

REVOKE ALL ON FUNCTION app_private.ammar_admin_supplier_performance(timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION app_private.ammar_admin_supplier_performance(timestamptz) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.ammar_admin_supplier_performance(
  p_since timestamptz DEFAULT now() - interval '90 days'
)
RETURNS TABLE (
  provider_id uuid,
  provider_name text,
  provider_kind text,
  rfq_invitation_count bigint,
  rfq_response_count bigint,
  rfq_response_rate numeric,
  average_response_hours numeric,
  delivery_count bigint,
  completed_delivery_count bigint,
  delivery_completion_rate numeric,
  on_time_delivery_count bigint,
  on_time_delivery_rate numeric,
  sample_since timestamptz
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $wrapper$
  SELECT * FROM app_private.ammar_admin_supplier_performance(p_since)
$wrapper$;

REVOKE ALL ON FUNCTION public.ammar_admin_supplier_performance(timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ammar_admin_supplier_performance(timestamptz) TO authenticated, service_role;

COMMENT ON FUNCTION public.ammar_admin_supplier_performance(timestamptz)
IS 'Admin-only aggregate supplier/contractor performance; returns no project identifiers or project-specific details';

COMMIT;
