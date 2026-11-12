-- Restore the private project attachment bucket expected by the AMMIR client.
-- Additive and idempotent; does not modify existing objects or legacy bucket data.
INSERT INTO storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
VALUES (
  'ammar-project-files',
  'ammar-project-files',
  false,
  15728640,
  ARRAY[
    'image/jpeg','image/png','image/webp','application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  ]
)
ON CONFLICT (id) DO UPDATE
SET public=false,
    file_size_limit=EXCLUDED.file_size_limit,
    allowed_mime_types=EXCLUDED.allowed_mime_types;
