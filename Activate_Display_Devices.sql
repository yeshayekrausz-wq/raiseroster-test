-- Requires the automatic planner, random cards and shared student activation.
-- Adds private display tables and narrowly scoped RPCs. Does not reset school data.
BEGIN;
CREATE TABLE IF NOT EXISTS public.rr_display_devices(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), secret_hash text NOT NULL UNIQUE,
 pair_code text UNIQUE, pair_expires timestamptz, created_at timestamptz NOT NULL DEFAULT now(),
 organization_id uuid REFERENCES public.organizations(id),program_id uuid REFERENCES public.rr_motivation_programs(id),
 paired_by uuid,label text NOT NULL DEFAULT '',enabled boolean NOT NULL DEFAULT false,
 config jsonb NOT NULL DEFAULT '{}',design jsonb NOT NULL DEFAULT '{}',revision bigint NOT NULL DEFAULT 0,
 last_seen timestamptz,active_student uuid,session_expires timestamptz);
ALTER TABLE public.rr_display_devices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rr_display_devices FROM PUBLIC,anon,authenticated;
CREATE INDEX IF NOT EXISTS rr_display_org ON public.rr_display_devices(organization_id);
CREATE TABLE IF NOT EXISTS public.rr_display_scan_requests(device_id uuid REFERENCES public.rr_display_devices(id) ON DELETE CASCADE,request_id uuid,code text NOT NULL,result jsonb NOT NULL,PRIMARY KEY(device_id,request_id));
ALTER TABLE public.rr_display_scan_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rr_display_scan_requests FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.rr_display_hash(p_secret text) RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$BEGIN
 IF p_secret IS NULL OR p_secret !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'Invalid device credential' USING ERRCODE='42501';END IF;
 RETURN encode(sha256(convert_to(p_secret,'UTF8')),'hex');END $$;
CREATE OR REPLACE FUNCTION public.rr_display_enroll(p_secret text,p_rotate boolean DEFAULT false) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE d public.rr_display_devices%ROWTYPE;h text;code text;i int;BEGIN
 h:=public.rr_display_hash(p_secret);SELECT * INTO d FROM public.rr_display_devices WHERE secret_hash=h FOR UPDATE;
 IF NOT FOUND THEN
  -- Global admission cap bounds anonymous database growth. Existing devices are unaffected.
  PERFORM pg_advisory_xact_lock(880025);
  IF (SELECT count(*) FROM public.rr_display_devices WHERE created_at>now()-interval '1 hour')>=200 THEN RAISE EXCEPTION 'Device setup busy. Try later.';END IF;
  INSERT INTO public.rr_display_devices(secret_hash) VALUES(h) RETURNING * INTO d;
 END IF;
 IF d.organization_id IS NOT NULL THEN
  IF p_rotate THEN RAISE EXCEPTION 'Unpair this computer in Admin before changing its code.';END IF;
  RETURN jsonb_build_object('paired',true,'id',d.id,'label',d.label);
 END IF;
 IF p_rotate OR d.pair_expires IS NULL OR d.pair_expires<=now() THEN
  FOR i IN 1..12 LOOP
   code:=(100000000+(('x'||substr(replace(gen_random_uuid()::text,'-',''),1,12))::bit(48)::bigint%900000000))::text;
   BEGIN UPDATE public.rr_display_devices SET pair_code=code,pair_expires=now()+interval '15 minutes' WHERE id=d.id RETURNING * INTO d;EXIT;EXCEPTION WHEN unique_violation THEN IF i=12 THEN RAISE;END IF;END;
  END LOOP;
 END IF;
 RETURN jsonb_build_object('paired',false,'id',d.id,'code',d.pair_code,'expires',d.pair_expires);
END $$;
CREATE OR REPLACE FUNCTION public.rr_display_claim(p_org uuid,p_program uuid,p_code text,p_label text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE d public.rr_display_devices%ROWTYPE;BEGIN
 PERFORM public.rr_motivation_require_access(p_org);
 IF NOT EXISTS(SELECT 1 FROM public.rr_motivation_programs WHERE id=p_program AND organization_id=p_org) OR length(btrim(p_label)) NOT BETWEEN 1 AND 80 OR p_code !~ '^[0-9]{9}$' THEN RAISE EXCEPTION 'Choose a program, name and nine-digit code.' USING ERRCODE='22023';END IF;
 SELECT * INTO d FROM public.rr_display_devices WHERE pair_code=p_code AND organization_id IS NULL AND pair_expires>now() FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Code expired, already paired, or not found.' USING ERRCODE='22023';END IF;
 UPDATE public.rr_display_devices SET organization_id=p_org,program_id=p_program,paired_by=auth.uid(),label=btrim(p_label),pair_code=NULL,pair_expires=NULL,revision=revision+1 WHERE id=d.id;
 INSERT INTO public.rr_motivation_events(organization_id,program_id,actor_id,kind,detail) VALUES(p_org,p_program,auth.uid(),'display_paired',jsonb_build_object('device',d.id,'label',btrim(p_label)));
 RETURN jsonb_build_object('id',d.id);
END $$;
CREATE OR REPLACE FUNCTION public.rr_display_list(p_org uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$BEGIN
 PERFORM public.rr_motivation_require_access(p_org);RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id',id,'program_id',program_id,'label',label,'enabled',enabled,'config',config,'design',design,'revision',revision,'last_seen',last_seen) ORDER BY label) FROM public.rr_display_devices WHERE organization_id=p_org),'[]');END $$;
CREATE OR REPLACE FUNCTION public.rr_display_save(p_org uuid,p_id uuid,p_revision bigint,p_label text,p_enabled boolean,p_config jsonb,p_design jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE d public.rr_display_devices%ROWTYPE;cl text;v jsonb;t text;BEGIN
 PERFORM public.rr_motivation_require_access(p_org);SELECT * INTO d FROM public.rr_display_devices WHERE id=p_id AND organization_id=p_org FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Display not found' USING ERRCODE='42501';END IF;
 IF d.revision<>p_revision THEN RAISE EXCEPTION 'Display changed. Reload before saving.' USING ERRCODE='40001';END IF;
 IF length(btrim(p_label)) NOT BETWEEN 1 AND 80 OR p_enabled IS NULL OR jsonb_typeof(p_config) IS DISTINCT FROM 'object' OR jsonb_typeof(p_design) IS DISTINCT FROM 'object' OR octet_length(p_design::text)>200000 THEN RAISE EXCEPTION 'Invalid display settings' USING ERRCODE='22023';END IF;
 IF coalesce(p_config->>'mode','') NOT IN ('all','single') OR coalesce(p_config->>'rotation','') !~ '^\d+$' OR (p_config->>'rotation')::int NOT BETWEEN 3 AND 3600 OR coalesce(p_config->>'idle','') !~ '^\d+$' OR (p_config->>'idle')::int NOT BETWEEN 5 AND 300 OR coalesce(p_config->>'minimum','') !~ '^\d+(\.\d+)?$' OR (p_config->>'minimum')::numeric NOT BETWEEN 0 AND 100 THEN RAISE EXCEPTION 'Check rotation, inactivity and minimum percentage.' USING ERRCODE='22023';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.rr_planner_plans WHERE id=(p_config->>'plan')::uuid AND organization_id=p_org AND program_id=d.program_id) THEN RAISE EXCEPTION 'Choose an existing weekly plan.' USING ERRCODE='22023';END IF;
 IF jsonb_typeof(p_config->'classes') IS DISTINCT FROM 'array' OR jsonb_array_length(p_config->'classes') NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'Choose classes.' USING ERRCODE='22023';END IF;
 FOR cl IN SELECT jsonb_array_elements_text(p_config->'classes') LOOP
  IF NOT EXISTS(SELECT 1 FROM public.classes c JOIN public.school_years y ON y.id=c.school_year_id AND y.is_current WHERE c.id=cl::uuid AND c.organization_id=p_org AND c.is_active) THEN RAISE EXCEPTION 'Invalid class.' USING ERRCODE='22023';END IF;
 END LOOP;
 IF NOT (p_config->'classes' ? (p_config->>'selectedClass')) THEN RAISE EXCEPTION 'Choose a selected class.' USING ERRCODE='22023';END IF;
 IF jsonb_typeof(p_config->'days') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Select schedule days.';END IF;
 FOR v IN SELECT value FROM jsonb_array_elements(p_config->'days') LOOP IF v::text !~ '^[0-6]$' THEN RAISE EXCEPTION 'Invalid schedule day';END IF;END LOOP;
 FOR t IN SELECT unnest(ARRAY[p_config->>'start',p_config->>'end']) LOOP IF t IS NULL OR t !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN RAISE EXCEPTION 'Enter schedule times.';END IF;END LOOP;
 IF jsonb_typeof(coalesce(p_config->'classTimes','{}')) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Invalid class hours';END IF;
 FOR v IN SELECT value FROM jsonb_each(coalesce(p_config->'classTimes','{}')) LOOP FOR t IN SELECT unnest(ARRAY[v->>'start',v->>'end']) LOOP IF t IS NULL OR t !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN RAISE EXCEPTION 'Invalid class hours';END IF;END LOOP;END LOOP;
 IF jsonb_typeof(coalesce(p_config->'overrides','{}')) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Invalid display overrides';END IF;
 FOR v IN SELECT value FROM jsonb_each(coalesce(p_config->'overrides','{}')) LOOP IF v#>>'{}' NOT IN ('auto','show','hide') THEN RAISE EXCEPTION 'Invalid visibility override';END IF;END LOOP;
 UPDATE public.rr_display_devices SET label=btrim(p_label),enabled=p_enabled,config=p_config,design=p_design,revision=revision+1,active_student=NULL,session_expires=NULL WHERE id=p_id RETURNING * INTO d;
 INSERT INTO public.rr_motivation_events(organization_id,program_id,actor_id,kind,detail) VALUES(p_org,d.program_id,auth.uid(),'display_updated',jsonb_build_object('device',d.id,'enabled',p_enabled,'revision',d.revision));
 RETURN jsonb_build_object('revision',d.revision);END $$;
CREATE OR REPLACE FUNCTION public.rr_display_unpair(p_org uuid,p_id uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$BEGIN
 PERFORM public.rr_motivation_require_access(p_org);
 UPDATE public.rr_display_devices SET organization_id=NULL,program_id=NULL,paired_by=NULL,label='',config='{}',design='{}',enabled=false,pair_code=NULL,pair_expires=NULL,active_student=NULL,session_expires=NULL,revision=revision+1 WHERE id=p_id AND organization_id=p_org;
 IF NOT FOUND THEN RAISE EXCEPTION 'Display not found' USING ERRCODE='42501';END IF;
 DELETE FROM public.rr_display_scan_requests WHERE device_id=p_id;
 INSERT INTO public.rr_motivation_events(organization_id,actor_id,kind,detail) VALUES(p_org,auth.uid(),'display_unpaired',jsonb_build_object('device',p_id));END $$;
CREATE OR REPLACE FUNCTION public.rr_display_window(p_cfg jsonb,p_zone text,p_class text DEFAULT NULL) RETURNS boolean LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $$
DECLARE dt timestamp:=now() AT TIME ZONE p_zone;d int:=extract(dow FROM dt);tm text:=to_char(dt,'HH24:MI');a text;b text;w jsonb;BEGIN
 IF p_class IS NULL THEN IF NOT coalesce((p_cfg->>'scheduleEnabled')::boolean,false) THEN RETURN true;END IF;w:=jsonb_build_object('start',p_cfg->>'start','end',p_cfg->>'end');
 ELSE IF NOT coalesce((p_cfg->>'scanEnabled')::boolean,false) THEN RETURN false;END IF;IF NOT coalesce((p_cfg->>'classSchedule')::boolean,false) THEN RETURN true;END IF;w:=p_cfg->'classTimes'->p_class;IF w IS NULL THEN RETURN false;END IF;END IF;
 a:=w->>'start';b:=w->>'end';IF a=b THEN RETURN p_cfg->'days' @> to_jsonb(ARRAY[d]);ELSIF a<b THEN RETURN p_cfg->'days' @> to_jsonb(ARRAY[d]) AND tm>=a AND tm<b;ELSE RETURN (tm>=a AND p_cfg->'days' @> to_jsonb(ARRAY[d])) OR (tm<b AND p_cfg->'days' @> to_jsonb(ARRAY[(d+6)%7]));END IF;END $$;
CREATE OR REPLACE FUNCTION public.rr_display_snapshot(p_id uuid,p_preview boolean DEFAULT false) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE d public.rr_display_devices%ROWTYPE;plan public.rr_planner_plans%ROWTYPE;zone text;current_period uuid;due_periods uuid[];due_end timestamptz;due_target numeric;week_num int;student_rows jsonb;BEGIN
 SELECT * INTO d FROM public.rr_display_devices WHERE id=p_id;
 IF d.organization_id IS NULL THEN RETURN jsonb_build_object('paired',false);END IF;
 IF NOT EXISTS(SELECT 1 FROM public.organization_members WHERE organization_id=d.organization_id AND user_id=d.paired_by AND role::text IN ('admin','super_admin')) THEN RETURN jsonb_build_object('paired',true,'enabled',false,'label',d.label);END IF;
 SELECT * INTO plan FROM public.rr_planner_plans WHERE id=(d.config->>'plan')::uuid AND organization_id=d.organization_id AND program_id=d.program_id;
 IF NOT FOUND OR (NOT d.enabled AND NOT p_preview) THEN RETURN jsonb_build_object('paired',true,'enabled',false,'label',d.label,'revision',d.revision);END IF;
 zone:=plan.preview->>'timezone';
 IF NOT p_preview AND NOT public.rr_display_window(d.config,zone) THEN RETURN jsonb_build_object('paired',true,'enabled',false,'label',d.label,'revision',d.revision);END IF;
 SELECT array_agg(w.period_id),max((plan.preview->'weeks'->(w.ordinal-1)->>'end_at')::timestamptz) INTO due_periods,due_end FROM public.rr_planner_weeks w WHERE w.plan_id=plan.id AND (plan.preview->'weeks'->(w.ordinal-1)->>'end_at')::timestamptz<=now();
 due_target:=floor((plan.preview->>'target')::numeric*coalesce(cardinality(due_periods),0)/jsonb_array_length(plan.preview->'weeks'));
 SELECT period_id,ordinal INTO current_period,week_num FROM public.rr_planner_weeks WHERE plan_id=plan.id AND (plan.preview->'weeks'->(ordinal-1)->>'start_at')::timestamptz<=now() ORDER BY ordinal DESC LIMIT 1;
 WITH totals AS(SELECT student_id,sum(points) n FROM public.rr_motivation_points WHERE organization_id=d.organization_id AND program_id=d.program_id AND available_at<=now() GROUP BY student_id),
 points AS(SELECT r.student_id,sum(CASE WHEN r.period_id=ANY(due_periods) THEN round(r.base_points*r.pct/100,4) ELSE 0 END) due,sum(CASE WHEN r.period_id=current_period THEN r.base_points-round(r.base_points*r.pct/100,4) ELSE 0 END) held FROM public.rr_reward_redemptions r JOIN public.rr_motivation_cards c ON c.id=r.card_id WHERE r.organization_id=d.organization_id AND c.program_id=d.program_id GROUP BY r.student_id),
 manual AS(SELECT p.student_id,sum(p.points) n FROM public.rr_motivation_points p WHERE p.organization_id=d.organization_id AND p.program_id=d.program_id AND p.available_at<=due_end AND NOT EXISTS(SELECT 1 FROM public.rr_reward_redemptions r WHERE r.point_id=p.id) GROUP BY p.student_id)
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'class_id',a.class_id,'approved',coalesce(t.n,0),'due',coalesce(p.due,0)+coalesce(m.n,0),'held',coalesce(p.held,0),'photo',CASE WHEN coalesce((d.config->>'photos')::boolean,false) THEN s.photo_url ELSE NULL END,'override',coalesce(d.config->'overrides'->>s.id::text,'auto')) ORDER BY s.name),'[]') INTO student_rows FROM public.students s JOIN public.student_class_assignments a ON a.student_id=s.id AND a.organization_id=d.organization_id AND a.is_current JOIN public.classes c ON c.id=a.class_id JOIN public.school_years y ON y.id=c.school_year_id AND y.is_current LEFT JOIN totals t ON t.student_id=s.id LEFT JOIN points p ON p.student_id=s.id LEFT JOIN manual m ON m.student_id=s.id WHERE s.organization_id=d.organization_id AND NOT s.is_archived AND d.config->'classes' ? a.class_id::text;
 RETURN jsonb_build_object('paired',true,'enabled',true,'label',d.label,'revision',d.revision,'config',d.config,'design',d.design,'timezone',zone,'week',coalesce(week_num,1),'dueTarget',due_target,'goal',plan.preview->'target','students',student_rows,'classes',coalesce((SELECT jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) ORDER BY c.sort_order,c.name) FROM public.classes c WHERE c.organization_id=d.organization_id AND d.config->'classes' ? c.id::text),'[]'));
END $$;
CREATE OR REPLACE FUNCTION public.rr_display_poll(p_secret text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$DECLARE d public.rr_display_devices%ROWTYPE;BEGIN
 SELECT * INTO d FROM public.rr_display_devices WHERE secret_hash=public.rr_display_hash(p_secret);
 IF NOT FOUND THEN RAISE EXCEPTION 'Device not found' USING ERRCODE='42501';END IF;
 UPDATE public.rr_display_devices SET last_seen=now() WHERE id=d.id AND (last_seen IS NULL OR last_seen<now()-interval '30 seconds');
 RETURN public.rr_display_snapshot(d.id);END $$;
CREATE OR REPLACE FUNCTION public.rr_display_scan(p_secret text,p_request uuid,p_code text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE d public.rr_display_devices%ROWTYPE;snap jsonb;sid uuid;cl uuid;c public.rr_motivation_cards%ROWTYPE;old public.rr_display_scan_requests%ROWTYPE;result jsonb;oldsub text;student jsonb;BEGIN
 IF p_request IS NULL OR p_code IS NULL OR p_code !~ '^[0-9]{4,13}$' THEN RAISE EXCEPTION 'Invalid scan' USING ERRCODE='22023';END IF;
 SELECT * INTO d FROM public.rr_display_devices WHERE secret_hash=public.rr_display_hash(p_secret) FOR UPDATE;
 IF NOT FOUND OR d.organization_id IS NULL THEN RAISE EXCEPTION 'Device not paired' USING ERRCODE='42501';END IF;
 snap:=public.rr_display_snapshot(d.id);IF NOT coalesce((snap->>'enabled')::boolean,false) OR NOT coalesce((d.config->>'scanEnabled')::boolean,false) THEN RAISE EXCEPTION 'Scanning is closed' USING ERRCODE='42501';END IF;
 SELECT * INTO old FROM public.rr_display_scan_requests WHERE device_id=d.id AND request_id=p_request;IF FOUND THEN IF old.code<>p_code THEN RAISE EXCEPTION 'Request already used';END IF;RETURN old.result;END IF;
 SELECT s.id,a.class_id INTO sid,cl FROM public.students s JOIN public.rr_student_aliases ids ON ids.student_id=s.id JOIN public.student_class_assignments a ON a.student_id=s.id AND a.is_current AND a.organization_id=d.organization_id WHERE s.organization_id=d.organization_id AND NOT s.is_archived AND (ids.short_id::text=p_code OR ids.barcode=p_code) LIMIT 1;
 IF d.session_expires<=now() THEN d.active_student:=NULL;END IF;
 IF sid IS NOT NULL THEN
  IF d.active_student=sid THEN result:=jsonb_build_object('kind','closed');UPDATE public.rr_display_devices SET active_student=NULL,session_expires=NULL WHERE id=d.id;
  ELSIF d.active_student IS NOT NULL THEN result:=jsonb_build_object('kind','denied','message','Scan the same ID to finish first.');
  ELSIF NOT d.config->'classes' ? cl::text OR NOT public.rr_display_window(d.config,snap->>'timezone',cl::text) THEN result:=jsonb_build_object('kind','denied','message','Scanning is not open for this class.');
  ELSE SELECT value INTO student FROM jsonb_array_elements(snap->'students') WHERE value->>'id'=sid::text;IF student IS NULL THEN RAISE EXCEPTION 'Student unavailable';END IF;
   UPDATE public.rr_display_devices SET active_student=sid,session_expires=now()+make_interval(secs=>(d.config->>'idle')::int) WHERE id=d.id;
   result:=jsonb_build_object('kind','opened','student',student);END IF;
 ELSE
  IF d.active_student IS NULL THEN result:=jsonb_build_object('kind','denied','message','Scan your ID first.');
  ELSE
   SELECT class_id INTO cl FROM public.student_class_assignments WHERE student_id=d.active_student AND organization_id=d.organization_id AND is_current;
   IF NOT (d.config->'classes' ? cl::text) OR NOT public.rr_display_window(d.config,snap->>'timezone',cl::text) THEN RAISE EXCEPTION 'Scanning is closed for this class';END IF;
   SELECT * INTO c FROM public.rr_motivation_cards WHERE organization_id=d.organization_id AND program_id=d.program_id AND (code=p_code OR barcode=p_code) LIMIT 1;
   IF NOT FOUND OR c.class_id<>cl OR c.status<>'available' THEN result:=jsonb_build_object('kind','denied','message','Card not accepted. It may belong to another class or already be entered.');
   ELSE
    oldsub:=current_setting('request.jwt.claim.sub',true);PERFORM set_config('request.jwt.claim.sub',d.paired_by::text,true);
    BEGIN result:=public.rr_motivation_command(d.organization_id,p_request,'redeem',jsonb_build_object('program',d.program_id,'student',d.active_student,'code',c.code));EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claim.sub',coalesce(oldsub,''),true);RAISE;END;
    PERFORM set_config('request.jwt.claim.sub',coalesce(oldsub,''),true);
    result:=jsonb_build_object('kind',CASE WHEN result->>'outcome'='accepted' THEN 'accepted' ELSE 'denied' END,'message',coalesce(result->>'message','Card entered.'),'points',c.points,'held',coalesce(result->'held','false'));
    INSERT INTO public.rr_motivation_events(organization_id,program_id,student_id,actor_id,kind,detail) VALUES(d.organization_id,d.program_id,d.active_student,d.paired_by,'display_scan',jsonb_build_object('device',d.id,'request',p_request));
   END IF;
   UPDATE public.rr_display_devices SET session_expires=now()+make_interval(secs=>(d.config->>'idle')::int) WHERE id=d.id;
  END IF;
 END IF;
 INSERT INTO public.rr_display_scan_requests VALUES(d.id,p_request,p_code,result);RETURN result;
END $$;
CREATE OR REPLACE FUNCTION public.rr_display_photo_path(p_secret text,p_student uuid) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$DECLARE snap jsonb;path text;org uuid;BEGIN
 snap:=public.rr_display_poll(p_secret);IF NOT coalesce((snap->>'enabled')::boolean,false) OR NOT coalesce((snap->'config'->>'photos')::boolean,false) THEN RAISE EXCEPTION 'Photo unavailable' USING ERRCODE='42501';END IF;
 SELECT organization_id INTO org FROM public.rr_display_devices WHERE secret_hash=public.rr_display_hash(p_secret);
 SELECT value->>'photo' INTO path FROM jsonb_array_elements(snap->'students') WHERE value->>'id'=p_student::text;
 IF path NOT LIKE 'motivation-private:'||org::text||'/students/'||p_student::text||'/%' THEN RETURN NULL;END IF;RETURN path;END $$;
CREATE OR REPLACE FUNCTION public.rr_display_preview(p_org uuid,p_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$BEGIN
 PERFORM public.rr_motivation_require_access(p_org);
 IF NOT EXISTS(SELECT 1 FROM public.rr_display_devices WHERE id=p_id AND organization_id=p_org) THEN RAISE EXCEPTION 'Display not found' USING ERRCODE='42501';END IF;
 RETURN public.rr_display_snapshot(p_id,true);
END $$;
REVOKE ALL ON FUNCTION public.rr_display_preview(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rr_display_preview(uuid,uuid) TO authenticated;
-- No direct table access, including for authenticated users. Grant only intentional RPCs.
REVOKE ALL ON FUNCTION public.rr_display_hash(text),public.rr_display_snapshot(uuid,boolean),public.rr_display_window(jsonb,text,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.rr_display_enroll(text,boolean),public.rr_display_poll(text),public.rr_display_scan(text,uuid,text),public.rr_display_photo_path(text,uuid),public.rr_display_claim(uuid,uuid,text,text),public.rr_display_list(uuid),public.rr_display_save(uuid,uuid,bigint,text,boolean,jsonb,jsonb),public.rr_display_unpair(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rr_display_enroll(text,boolean),public.rr_display_poll(text),public.rr_display_scan(text,uuid,text),public.rr_display_photo_path(text,uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.rr_display_claim(uuid,uuid,text,text),public.rr_display_list(uuid),public.rr_display_save(uuid,uuid,bigint,text,boolean,jsonb,jsonb),public.rr_display_unpair(uuid,uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
SELECT 'DISPLAY_DEVICES_READY' AS result;
