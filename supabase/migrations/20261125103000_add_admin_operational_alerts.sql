BEGIN;

-- A narrow, read-only operational alert feed. It does not grant administrators
-- broad SELECT access to project, supplier, quote, award, or delivery tables.
CREATE OR REPLACE FUNCTION public.ammar_admin_list_operational_alerts(
  p_limit integer DEFAULT 100
)
RETURNS TABLE (
  alert_kind text,
  alert_id uuid,
  project_id uuid,
  project_title text,
  reference_code text,
  subject text,
  status text,
  due_at timestamptz,
  created_at timestamptz,
  related_count bigint,
  attention_reason text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'administrator access required'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    'rfq'::text,
    r.id,
    r.project_id,
    p.title,
    r.reference_code,
    r.title,
    r.status,
    r.deadline_at,
    r.created_at,
    (SELECT count(*)::bigint
       FROM public.ammir_project_rfq_quotes q
      WHERE q.rfq_id = r.id
        AND q.project_id = r.project_id
        AND q.status = 'submitted'),
    'انتهى موعد استقبال العروض ولم يُغلق طلب الأسعار'::text
  FROM public.ammir_project_rfqs r
  JOIN public.projects p ON p.id = r.project_id
  WHERE r.status IN ('open','closing')
    AND r.deadline_at IS NOT NULL
    AND r.deadline_at < now()

  UNION ALL

  SELECT
    'delivery'::text,
    d.id,
    d.project_id,
    p.title,
    d.delivery_reference,
    'متابعة التسليم'::text,
    d.status,
    d.scheduled_at::timestamp AT TIME ZONE 'UTC',
    d.created_at,
    (SELECT count(*)::bigint
       FROM public.ammir_project_delivery_items di
      WHERE di.delivery_id = d.id
        AND di.project_id = d.project_id
        AND (di.received_quantity < di.expected_quantity
             OR di.damaged_quantity > 0
             OR di.missing_quantity > 0)),
    CASE
      WHEN d.status = 'exception' THEN 'التسليم مسجل بحالة استثناء'
      ELSE 'تجاوز موعد التسليم المجدول'
    END
  FROM public.ammir_project_deliveries d
  JOIN public.projects p ON p.id = d.project_id
  WHERE d.status IN ('planned','dispatched','partially_received','exception')
    AND (
      d.status = 'exception'
      OR (d.scheduled_at IS NOT NULL AND d.scheduled_at < CURRENT_DATE)
    )

  ORDER BY due_at ASC NULLS LAST, created_at ASC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 100), 1), 200);
END;
$function$;

REVOKE ALL ON FUNCTION public.ammar_admin_list_operational_alerts(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ammar_admin_list_operational_alerts(integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.ammar_admin_list_operational_alerts(integer) TO authenticated;

COMMENT ON FUNCTION public.ammar_admin_list_operational_alerts(integer)
IS 'Read-only, bounded overdue RFQ and delivery alerts for AMMIR administrators; does not grant broad project or supplier data access';

COMMIT;
