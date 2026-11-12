-- Add covering indexes for public foreign keys introduced by the marketplace
-- and messaging schema. Safe additive performance migration.
-- The deferred bank milestone/event tables remain excluded.
DO $ammar_fk_indexes$
DECLARE
  f record;
  cols text;
  idx_name text;
BEGIN
  FOR f IN
    SELECT c.oid,c.conrelid,c.conname,n.nspname,t.relname,c.conkey
    FROM pg_constraint c
    JOIN pg_class t ON t.oid=c.conrelid
    JOIN pg_namespace n ON n.oid=t.relnamespace
    WHERE c.contype='f'
      AND n.nspname='public'
      AND t.relname NOT IN ('project_payment_milestones','project_payment_events')
      AND NOT EXISTS (
        SELECT 1
        FROM pg_index i
        WHERE i.indrelid=c.conrelid
          AND i.indisvalid
          AND NOT EXISTS (
            SELECT 1
            FROM unnest(c.conkey) AS fk(attnum)
            WHERE NOT (fk.attnum = ANY(i.indkey))
          )
      )
  LOOP
    SELECT string_agg(format('%I',a.attname),',' ORDER BY k.ordinality)
      INTO cols
    FROM unnest(f.conkey) WITH ORDINALITY AS k(attnum,ordinality)
    JOIN pg_attribute a ON a.attrelid=f.conrelid AND a.attnum=k.attnum;

    idx_name := left('idx_fk_' || f.relname || '_' || substr(md5(f.conname),1,8),63);
    EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON %I.%I (%s)',
      idx_name,f.nspname,f.relname,cols);
  END LOOP;
END
$ammar_fk_indexes$;
