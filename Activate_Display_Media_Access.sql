-- Authorize only media in this paired device's saved playlist.
-- No tables, records or storage files are deleted.
BEGIN;
CREATE OR REPLACE FUNCTION public.rr_display_media_path(p_secret text,p_path text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE d public.rr_display_devices%ROWTYPE; snap jsonb;
BEGIN
 IF p_secret IS NULL OR p_secret !~ '^[a-f0-9]{64}$' OR p_path IS NULL OR length(p_path)>250 THEN RETURN NULL; END IF;
 SELECT * INTO d FROM public.rr_display_devices WHERE secret_hash=public.rr_display_hash(p_secret);
 IF NOT FOUND OR d.organization_id IS NULL THEN RETURN NULL; END IF;
 snap:=public.rr_display_snapshot(d.id);
 IF NOT coalesce((snap->>'enabled')::boolean,false) THEN RETURN NULL; END IF;
 IF p_path NOT LIKE d.organization_id::text||'/display/'||d.id::text||'/%' OR position('..' in p_path)>0 THEN RETURN NULL; END IF;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(d.config->'playlist','[]'::jsonb)) AS x WHERE x->>'path'=p_path AND x->>'type' IN ('image','video')) THEN RETURN NULL; END IF;
 RETURN p_path;
END $$;
REVOKE ALL ON FUNCTION public.rr_display_media_path(text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rr_display_media_path(text,text) TO anon;
COMMIT;
SELECT 'DISPLAY_MEDIA_ACCESS_READY' AS result;
