-- Run after Activate_Display_Devices.sql. No school records are reset.
BEGIN;
CREATE OR REPLACE FUNCTION public.rr_display_enroll(p_secret text,p_rotate boolean DEFAULT false) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE d public.rr_display_devices%ROWTYPE;h text;code text;i int;BEGIN
 h:=public.rr_display_hash(p_secret);SELECT * INTO d FROM public.rr_display_devices WHERE secret_hash=h FOR UPDATE;
 IF NOT FOUND THEN
  -- Global admission cap bounds anonymous database growth. Existing devices are unaffected.
  PERFORM pg_advisory_xact_lock(880025);
  IF (SELECT count(*) FROM public.rr_display_devices WHERE created_at>now()-interval '1 hour')>=200 THEN RAISE EXCEPTION 'Device setup busy. Try later.';END IF;
  INSERT INTO public.rr_display_devices(secret_hash) VALUES(h) RETURNING * INTO d;
 END IF;
 IF p_rotate THEN
  DELETE FROM public.rr_display_scan_requests WHERE device_id=d.id;
  UPDATE public.rr_display_devices SET organization_id=NULL,program_id=NULL,paired_by=NULL,label='',enabled=false,config='{}',design='{}',active_student=NULL,session_expires=NULL,revision=revision+1 WHERE id=d.id RETURNING * INTO d;
 END IF;
 IF p_rotate OR d.pair_code IS NULL THEN
  FOR i IN 1..12 LOOP
   code:=(100000000+(('x'||substr(replace(gen_random_uuid()::text,'-',''),1,12))::bit(48)::bigint%900000000))::text;
   IF code=d.pair_code THEN CONTINUE;END IF;
   BEGIN UPDATE public.rr_display_devices SET pair_code=code,pair_expires=NULL WHERE id=d.id RETURNING * INTO d;EXIT;EXCEPTION WHEN unique_violation THEN IF i=12 THEN RAISE;END IF;END;
  END LOOP;
 END IF;
 RETURN jsonb_build_object('paired',d.organization_id IS NOT NULL,'id',d.id,'label',d.label,'code',d.pair_code);
END $$;
CREATE OR REPLACE FUNCTION public.rr_display_claim(p_org uuid,p_program uuid,p_code text,p_label text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE d public.rr_display_devices%ROWTYPE;BEGIN
 PERFORM public.rr_motivation_require_access(p_org);
 IF NOT EXISTS(SELECT 1 FROM public.rr_motivation_programs WHERE id=p_program AND organization_id=p_org) OR length(btrim(p_label)) NOT BETWEEN 1 AND 80 OR p_code !~ '^[0-9]{9}$' THEN RAISE EXCEPTION 'Choose a program, name and nine-digit code.' USING ERRCODE='22023';END IF;
 SELECT * INTO d FROM public.rr_display_devices WHERE pair_code=p_code AND organization_id IS NULL FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Code already paired or not found.' USING ERRCODE='22023';END IF;
 UPDATE public.rr_display_devices SET organization_id=p_org,program_id=p_program,paired_by=auth.uid(),label=btrim(p_label),pair_expires=NULL,revision=revision+1 WHERE id=d.id;
 INSERT INTO public.rr_motivation_events(organization_id,program_id,actor_id,kind,detail) VALUES(p_org,p_program,auth.uid(),'display_paired',jsonb_build_object('device',d.id,'label',btrim(p_label)));
 RETURN jsonb_build_object('id',d.id);
END $$;
CREATE OR REPLACE FUNCTION public.rr_display_unpair(p_org uuid,p_id uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$BEGIN
 PERFORM public.rr_motivation_require_access(p_org);
 UPDATE public.rr_display_devices SET organization_id=NULL,program_id=NULL,paired_by=NULL,label='',config='{}',design='{}',enabled=false,pair_expires=NULL,active_student=NULL,session_expires=NULL,revision=revision+1 WHERE id=p_id AND organization_id=p_org;
 IF NOT FOUND THEN RAISE EXCEPTION 'Display not found' USING ERRCODE='42501';END IF;
 DELETE FROM public.rr_display_scan_requests WHERE device_id=p_id;
 INSERT INTO public.rr_motivation_events(organization_id,actor_id,kind,detail) VALUES(p_org,auth.uid(),'display_unpaired',jsonb_build_object('device',p_id));END $$;

CREATE OR REPLACE FUNCTION public.rr_display_media_path(p_secret text,p_path text) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE d public.rr_display_devices%ROWTYPE;snap jsonb;BEGIN
 SELECT * INTO d FROM public.rr_display_devices WHERE secret_hash=public.rr_display_hash(p_secret);
 snap:=public.rr_display_snapshot(d.id);
 IF NOT coalesce((snap->>'enabled')::boolean,false) OR p_path NOT LIKE d.organization_id::text||'/display/'||d.id::text||'/%' OR p_path LIKE '%..%' OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(d.config->'playlist','[]')) x WHERE x->>'path'=p_path AND x->>'type' IN ('image','video')) THEN RAISE EXCEPTION 'Media unavailable' USING ERRCODE='42501';END IF;
 RETURN p_path;
END $$;
REVOKE ALL ON FUNCTION public.rr_display_media_path(text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rr_display_media_path(text,text) TO anon;
NOTIFY pgrst,'reload schema';
COMMIT;
SELECT 'DISPLAY_UPGRADE_READY' AS result;
