-- AMMAR bank-referenced milestone payment workflow.
-- This is an audit/workflow feature only. It does not receive, hold, or transfer funds.
-- Any safeguarded funds, escrow, or bank-initiated payouts require a written bank/licensed-provider agreement.

DO $$
DECLARE
  project_id_type text;
BEGIN
  SELECT format_type(a.atttypid, a.atttypmod)
    INTO project_id_type
  FROM pg_attribute a
  WHERE a.attrelid = 'public.projects'::regclass
    AND a.attname = 'id'
    AND NOT a.attisdropped;

  IF project_id_type IS NULL THEN
    RAISE EXCEPTION 'Could not determine public.projects.id type';
  END IF;

  EXECUTE format($ddl$
    CREATE TABLE IF NOT EXISTS public.project_payment_milestones (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      project_id %s NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
      title text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 200),
      contractor_name text NOT NULL CHECK (char_length(contractor_name) BETWEEN 1 AND 200),
      amount numeric(14,2) NOT NULL CHECK (amount > 0),
      currency text NOT NULL CHECK (char_length(btrim(currency)) BETWEEN 3 AND 12),
      due_date date,
      status text NOT NULL DEFAULT 'awaiting_deposit'
        CHECK (status IN (
          'awaiting_deposit','deposit_reported','bank_confirmed','in_progress',
          'completion_submitted','client_approved','payout_recorded',
          'disputed','refunded','cancelled'
        )),
      status_before_dispute text
        CHECK (status_before_dispute IS NULL OR status_before_dispute IN (
          'awaiting_deposit','deposit_reported','bank_confirmed',
          'in_progress','completion_submitted','client_approved'
        )),
      bank_name text,
      deposit_reference text,
      deposit_reported_by uuid,
      deposit_reported_at timestamptz,
      bank_confirmed_by uuid,
      bank_confirmed_at timestamptz,
      bank_confirmation_note text,
      completion_note text,
      completion_submitted_by uuid,
      completion_submitted_at timestamptz,
      client_approved_by uuid,
      client_approved_at timestamptz,
      payout_reference text,
      payout_recorded_by uuid,
      payout_recorded_at timestamptz,
      dispute_reason text,
      dispute_opened_by uuid,
      dispute_opened_at timestamptz,
      refund_reference text,
      refund_recorded_by uuid,
      refund_recorded_at timestamptz,
      created_by uuid NOT NULL DEFAULT auth.uid(),
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now()
    )
  $ddl$, project_id_type);

  EXECUTE format($ddl$
    CREATE TABLE IF NOT EXISTS public.project_payment_events (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      project_id %s NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
      milestone_id uuid NOT NULL
        REFERENCES public.project_payment_milestones(id) ON DELETE CASCADE,
      event_type text NOT NULL,
      from_status text,
      to_status text,
      note text,
      actor_id uuid NOT NULL DEFAULT auth.uid(),
      created_at timestamptz NOT NULL DEFAULT now()
    )
  $ddl$, project_id_type);
END $$;

CREATE INDEX IF NOT EXISTS project_payment_milestones_project_status_idx
  ON public.project_payment_milestones(project_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS project_payment_events_milestone_created_idx
  ON public.project_payment_events(milestone_id, created_at DESC);
CREATE INDEX IF NOT EXISTS project_payment_events_project_created_idx
  ON public.project_payment_events(project_id, created_at DESC);

ALTER TABLE public.project_payment_milestones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_payment_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS project_payment_milestones_member_select
  ON public.project_payment_milestones;
CREATE POLICY project_payment_milestones_member_select
  ON public.project_payment_milestones
  FOR SELECT TO authenticated
  USING (public.ammar_project_role(project_id::text) IS NOT NULL);

DROP POLICY IF EXISTS project_payment_events_member_select
  ON public.project_payment_events;
CREATE POLICY project_payment_events_member_select
  ON public.project_payment_events
  FOR SELECT TO authenticated
  USING (public.ammar_project_role(project_id::text) IS NOT NULL);

-- Authenticated users may read project records but must use validated RPCs for all writes.
REVOKE ALL ON public.project_payment_milestones,
  public.project_payment_events FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.project_payment_milestones,
  public.project_payment_events TO authenticated;

DROP TRIGGER IF EXISTS ammar_payment_milestones_touch_updated_at
  ON public.project_payment_milestones;
CREATE TRIGGER ammar_payment_milestones_touch_updated_at
BEFORE UPDATE ON public.project_payment_milestones
FOR EACH ROW EXECUTE FUNCTION public.ammar_touch_updated_at();

CREATE OR REPLACE FUNCTION public.ammar_create_payment_milestone(
  p_project_id text,
  p_title text,
  p_contractor_name text,
  p_amount numeric,
  p_currency text,
  p_due_date date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_project_id public.projects.id%TYPE;
  v_item public.project_payment_milestones%ROWTYPE;
  v_role text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT p.id INTO v_project_id
  FROM public.projects p
  WHERE p.id::text = p_project_id;

  IF v_project_id IS NULL THEN
    RAISE EXCEPTION 'Project not found';
  END IF;

  v_role := public.ammar_project_role(p_project_id);
  IF v_role IS NULL OR v_role NOT IN ('owner','manager','accountant') THEN
    RAISE EXCEPTION 'Not allowed to create payment milestones';
  END IF;

  IF p_title IS NULL OR char_length(btrim(p_title)) NOT BETWEEN 1 AND 200
     OR p_contractor_name IS NULL
     OR char_length(btrim(p_contractor_name)) NOT BETWEEN 1 AND 200
     OR p_amount IS NULL OR p_amount <= 0
     OR p_currency IS NULL
     OR char_length(btrim(p_currency)) NOT BETWEEN 3 AND 12 THEN
    RAISE EXCEPTION 'Invalid milestone details';
  END IF;

  INSERT INTO public.project_payment_milestones(
    project_id, title, contractor_name, amount, currency, due_date, created_by
  )
  VALUES (
    v_project_id, btrim(p_title), btrim(p_contractor_name), p_amount,
    upper(btrim(p_currency)), p_due_date, auth.uid()
  )
  RETURNING * INTO v_item;

  INSERT INTO public.project_payment_events(
    project_id, milestone_id, event_type, from_status, to_status, note, actor_id
  )
  VALUES (
    v_item.project_id, v_item.id, 'milestone_created', NULL,
    v_item.status, 'تم إنشاء مستحق مرحلي جديد.', auth.uid()
  );

  RETURN to_jsonb(v_item);
END;
$$;

CREATE OR REPLACE FUNCTION public.ammar_transition_payment_milestone(
  p_milestone_id uuid,
  p_action text,
  p_note text DEFAULT NULL,
  p_bank_name text DEFAULT NULL,
  p_transfer_reference text DEFAULT NULL,
  p_payout_reference text DEFAULT NULL,
  p_refund_reference text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_item public.project_payment_milestones%ROWTYPE;
  v_old_status text;
  v_role text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT * INTO v_item
  FROM public.project_payment_milestones
  WHERE id = p_milestone_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment milestone not found';
  END IF;

  v_role := public.ammar_project_role(v_item.project_id::text);
  IF v_role IS NULL THEN
    RAISE EXCEPTION 'Project membership required';
  END IF;

  v_old_status := v_item.status;

  IF p_action = 'report_deposit' THEN
    IF v_role <> 'owner' THEN
      RAISE EXCEPTION 'Only the project owner can report the customer deposit';
    END IF;
    IF v_item.status <> 'awaiting_deposit' THEN
      RAISE EXCEPTION 'Deposit can only be reported before bank confirmation';
    END IF;
    IF p_bank_name IS NULL OR char_length(btrim(p_bank_name)) NOT BETWEEN 2 AND 120
       OR p_transfer_reference IS NULL
       OR char_length(btrim(p_transfer_reference)) NOT BETWEEN 3 AND 120 THEN
      RAISE EXCEPTION 'Bank name and transfer reference are required';
    END IF;
    UPDATE public.project_payment_milestones
    SET status = 'deposit_reported',
        bank_name = btrim(p_bank_name),
        deposit_reference = btrim(p_transfer_reference),
        deposit_reported_by = auth.uid(),
        deposit_reported_at = now()
    WHERE id = v_item.id
    RETURNING * INTO v_item;

  ELSIF p_action = 'confirm_bank_receipt' THEN
    IF v_role NOT IN ('owner','manager','accountant') THEN
      RAISE EXCEPTION 'Finance permission required to reconcile the bank receipt';
    END IF;
    IF v_item.status <> 'deposit_reported' THEN
      RAISE EXCEPTION 'A customer deposit report is required first';
    END IF;
    IF p_note IS NULL OR char_length(btrim(p_note)) < 8 THEN
      RAISE EXCEPTION 'Record how the transaction was matched against the bank records';
    END IF;
    UPDATE public.project_payment_milestones
    SET status = 'bank_confirmed',
        bank_confirmed_by = auth.uid(),
        bank_confirmed_at = now(),
        bank_confirmation_note = btrim(p_note)
    WHERE id = v_item.id
    RETURNING * INTO v_item;

  ELSIF p_action = 'start_work' THEN
    IF v_role NOT IN ('owner','manager','supervisor','engineer','worker') THEN
      RAISE EXCEPTION 'Not allowed to start this work';
    END IF;
    IF v_item.status <> 'bank_confirmed' THEN
      RAISE EXCEPTION 'Work can start only after the bank receipt is reconciled';
    END IF;
    UPDATE public.project_payment_milestones
    SET status = 'in_progress'
    WHERE id = v_item.id
    RETURNING * INTO v_item;

  ELSIF p_action = 'submit_completion' THEN
    IF v_role NOT IN ('owner','manager','supervisor','engineer','worker') THEN
      RAISE EXCEPTION 'Not allowed to submit completion';
    END IF;
    IF v_item.status <> 'in_progress' THEN
      RAISE EXCEPTION 'The milestone must be in progress first';
    END IF;
    IF p_note IS NULL OR char_length(btrim(p_note)) < 8 THEN
      RAISE EXCEPTION 'Completion details are required';
    END IF;
    UPDATE public.project_payment_milestones
    SET status = 'completion_submitted',
        completion_note = btrim(p_note),
        completion_submitted_by = auth.uid(),
        completion_submitted_at = now()
    WHERE id = v_item.id
    RETURNING * INTO v_item;

  ELSIF p_action = 'approve_completion' THEN
    IF v_role <> 'owner' THEN
      RAISE EXCEPTION 'Only the customer/project owner can approve completion';
    END IF;
    IF v_item.status <> 'completion_submitted' THEN
      RAISE EXCEPTION 'The contractor must submit completion first';
    END IF;
    UPDATE public.project_payment_milestones
    SET status = 'client_approved',
        client_approved_by = auth.uid(),
        client_approved_at = now()
    WHERE id = v_item.id
    RETURNING * INTO v_item;

  ELSIF p_action = 'record_payout' THEN
    IF v_role NOT IN ('owner','manager','accountant') THEN
      RAISE EXCEPTION 'Finance permission required to record the contractor payout';
    END IF;
    IF v_item.status <> 'client_approved' THEN
      RAISE EXCEPTION 'Client approval is required before recording a payout';
    END IF;
    IF p_payout_reference IS NULL
       OR char_length(btrim(p_payout_reference)) NOT BETWEEN 3 AND 120 THEN
      RAISE EXCEPTION 'Bank payout reference is required';
    END IF;
    UPDATE public.project_payment_milestones
    SET status = 'payout_recorded',
        payout_reference = btrim(p_payout_reference),
        payout_recorded_by = auth.uid(),
        payout_recorded_at = now()
    WHERE id = v_item.id
    RETURNING * INTO v_item;

  ELSIF p_action = 'open_dispute' THEN
    IF v_role NOT IN ('owner','manager','supervisor','engineer','accountant','worker') THEN
      RAISE EXCEPTION 'Project role cannot open a payment dispute';
    END IF;
    IF v_item.status NOT IN ('bank_confirmed','in_progress','completion_submitted','client_approved') THEN
      RAISE EXCEPTION 'A dispute can only pause a milestone after bank receipt is confirmed';
    END IF;
    IF p_note IS NULL OR char_length(btrim(p_note)) < 8 THEN
      RAISE EXCEPTION 'A dispute reason is required';
    END IF;
    UPDATE public.project_payment_milestones
    SET status_before_dispute = status,
        status = 'disputed',
        dispute_reason = btrim(p_note),
        dispute_opened_by = auth.uid(),
        dispute_opened_at = now()
    WHERE id = v_item.id
    RETURNING * INTO v_item;

  ELSIF p_action = 'resolve_dispute_continue' THEN
    IF v_role NOT IN ('owner','manager') THEN
      RAISE EXCEPTION 'Only the project owner or manager can resume a disputed milestone';
    END IF;
    IF v_item.status <> 'disputed' OR v_item.status_before_dispute IS NULL THEN
      RAISE EXCEPTION 'No resumable payment dispute exists';
    END IF;
    IF p_note IS NULL OR char_length(btrim(p_note)) < 8 THEN
      RAISE EXCEPTION 'Record the dispute resolution decision';
    END IF;
    UPDATE public.project_payment_milestones
    SET status = status_before_dispute,
        status_before_dispute = NULL
    WHERE id = v_item.id
    RETURNING * INTO v_item;

  ELSIF p_action = 'record_refund' THEN
    IF v_role NOT IN ('owner','manager','accountant') THEN
      RAISE EXCEPTION 'Finance permission required to record a refund';
    END IF;
    IF v_item.status <> 'disputed'
       OR v_item.status_before_dispute NOT IN ('bank_confirmed','in_progress','completion_submitted','client_approved') THEN
      RAISE EXCEPTION 'A confirmed bank receipt and an open dispute are required before recording a refund';
    END IF;
    IF p_refund_reference IS NULL
       OR char_length(btrim(p_refund_reference)) NOT BETWEEN 3 AND 120
       OR p_note IS NULL OR char_length(btrim(p_note)) < 8 THEN
      RAISE EXCEPTION 'Actual bank refund reference and resolution note are required';
    END IF;
    UPDATE public.project_payment_milestones
    SET status = 'refunded',
        refund_reference = btrim(p_refund_reference),
        refund_recorded_by = auth.uid(),
        refund_recorded_at = now()
    WHERE id = v_item.id
    RETURNING * INTO v_item;

  ELSIF p_action = 'cancel' THEN
    IF v_role NOT IN ('owner','manager') THEN
      RAISE EXCEPTION 'Only the project owner or manager can cancel this milestone';
    END IF;
    IF v_item.status <> 'awaiting_deposit' THEN
      RAISE EXCEPTION 'A milestone can only be cancelled before a deposit is reported';
    END IF;
    UPDATE public.project_payment_milestones
    SET status = 'cancelled'
    WHERE id = v_item.id
    RETURNING * INTO v_item;

  ELSE
    RAISE EXCEPTION 'Unsupported payment milestone action';
  END IF;

  INSERT INTO public.project_payment_events(
    project_id, milestone_id, event_type, from_status, to_status, note, actor_id
  )
  VALUES (
    v_item.project_id, v_item.id, p_action, v_old_status, v_item.status,
    nullif(btrim(coalesce(p_note, '')), ''), auth.uid()
  );

  RETURN to_jsonb(v_item);
END;
$$;

REVOKE ALL ON FUNCTION public.ammar_create_payment_milestone(
  text, text, text, numeric, text, date
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ammar_create_payment_milestone(
  text, text, text, numeric, text, date
) TO authenticated;

REVOKE ALL ON FUNCTION public.ammar_transition_payment_milestone(
  uuid, text, text, text, text, text, text
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ammar_transition_payment_milestone(
  uuid, text, text, text, text, text, text
) TO authenticated;
