-- Add the remaining single-column FK indexes flagged by Supabase Advisor.
-- These columns were present in composite/secondary indexes but not as leading keys.
CREATE INDEX IF NOT EXISTS idx_ammar_agreements_provider_id
  ON public.ammar_agreements(provider_id);
CREATE INDEX IF NOT EXISTS idx_ammar_conversation_preferences_user_id
  ON public.ammar_conversation_preferences(user_id);
CREATE INDEX IF NOT EXISTS idx_ammar_message_reports_reporter_id
  ON public.ammar_message_reports(reporter_id);
CREATE INDEX IF NOT EXISTS idx_ammar_pinned_messages_message_id
  ON public.ammar_pinned_messages(message_id);
CREATE INDEX IF NOT EXISTS idx_ammar_reviews_reviewer_id
  ON public.ammar_reviews(reviewer_id);
CREATE INDEX IF NOT EXISTS idx_ammar_user_blocks_blocked_id
  ON public.ammar_user_blocks(blocked_id);
