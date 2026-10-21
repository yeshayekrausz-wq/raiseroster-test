-- Settings navigation update. Requires Stage 5; safe to run again.
BEGIN;
CREATE TABLE IF NOT EXISTS public.rr_motivation_clock(organization_id uuid PRIMARY KEY REFERENCES public.organizations(id),week_day integer NOT NULL CHECK(week_day BETWEEN 0 AND 6),week_time time NOT NULL,revision bigint NOT NULL DEFAULT 1);
ALTER TABLE public.rr_motivation_clock ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rr_motivation_clock FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.rr_motivation_week_start(p_org uuid,p_now timestamptz,p_zone text) RETURNS timestamptz LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE d integer;t time;local_now timestamp;boundary timestamp;
BEGIN
 SELECT week_day,week_time INTO d,t FROM public.rr_motivation_clock WHERE organization_id=p_org;
 -- Preserve the old boundary until the school explicitly chooses a new one.
 d:=coalesce(d,1);t:=coalesce(t,time '00:00');local_now:=p_now AT TIME ZONE p_zone;
 boundary:=local_now::date-((extract(dow FROM local_now)::int-d+7)%7)+t;
 IF boundary>local_now THEN boundary:=boundary-interval '7 days';END IF;
 RETURN boundary AT TIME ZONE p_zone;
END $$;
REVOKE ALL ON FUNCTION public.rr_motivation_week_start(uuid,timestamptz,text) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.rr_motivation_clock_read(p_org uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM public.rr_motivation_require_access(p_org);
 RETURN coalesce((SELECT jsonb_build_object('day',week_day,'time',to_char(week_time,'HH24:MI'),'revision',revision) FROM public.rr_motivation_clock WHERE organization_id=p_org),'{"day":null,"time":"","revision":0}'::jsonb);
END $$;
CREATE OR REPLACE FUNCTION public.rr_motivation_clock_save(p_org uuid,p_day integer,p_time text,p_revision bigint) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE rev bigint;old jsonb;
BEGIN
 PERFORM public.rr_motivation_require_access(p_org);PERFORM 1 FROM public.organizations WHERE id=p_org FOR UPDATE;
 IF p_day IS NULL OR p_day NOT BETWEEN 0 AND 6 OR p_time IS NULL OR p_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN RAISE EXCEPTION 'Choose a week day and time' USING ERRCODE='22023';END IF;
 SELECT revision,to_jsonb(c) INTO rev,old FROM public.rr_motivation_clock c WHERE organization_id=p_org;
 IF p_revision IS DISTINCT FROM coalesce(rev,0) THEN RAISE EXCEPTION 'Week settings changed. Reload before saving.' USING ERRCODE='40001';END IF;
 INSERT INTO public.rr_motivation_clock VALUES(p_org,p_day,p_time::time,coalesce(rev,0)+1) ON CONFLICT(organization_id) DO UPDATE SET week_day=excluded.week_day,week_time=excluded.week_time,revision=excluded.revision;
 INSERT INTO public.rr_motivation_events(organization_id,actor_id,kind,detail) VALUES(p_org,auth.uid(),'settings',jsonb_build_object('section','week','before',old,'day',p_day,'time',p_time));
 RETURN public.rr_motivation_clock_read(p_org);
END $$;
REVOKE ALL ON FUNCTION public.rr_motivation_clock_read(uuid),public.rr_motivation_clock_save(uuid,integer,text,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_motivation_clock_read(uuid),public.rr_motivation_clock_save(uuid,integer,text,bigint) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_motivation_command(p_org uuid,p_request uuid,p_action text,p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE v_payload jsonb;v_old jsonb;v_result jsonb;v_program uuid;v_student uuid;v_class uuid;v_year uuid;v_event bigint;
 v_settings jsonb;v_rev bigint;v_points numeric;v_config jsonb;v_subject jsonb;v_score numeric;v_card public.rr_motivation_cards%ROWTYPE;
 row_data jsonb;before_data jsonb;v_name text;v_phone text;v_count int;v_batch uuid;v_outcome text:='accepted';v_message text:='Saved'; k text;
BEGIN
 PERFORM public.rr_motivation_require_access(p_org);
 IF p_request IS NULL OR p_action IS NULL OR jsonb_typeof(p_data) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Invalid request' USING ERRCODE='22023';END IF;
 v_payload:=jsonb_build_object('action',p_action,'data',p_data);
 PERFORM 1 FROM public.organizations WHERE id=p_org FOR UPDATE;
 SELECT payload,result INTO v_old,v_result FROM public.rr_motivation_requests WHERE organization_id=p_org AND request_id=p_request;
 IF FOUND THEN IF v_old<>v_payload THEN RAISE EXCEPTION 'Request already used' USING ERRCODE='22023';END IF;RETURN v_result;END IF;
 SELECT settings,revision INTO v_settings,v_rev FROM public.rr_motivation_options WHERE organization_id=p_org;
 v_settings:=coalesce(v_settings,public.rr_motivation_defaults());v_rev:=coalesce(v_rev,0);
 IF p_action IN ('points','exam','cards','redeem','unblock') THEN
  v_program:=(p_data->>'program')::uuid;
  SELECT config INTO v_config FROM public.rr_motivation_programs WHERE id=v_program AND organization_id=p_org;
  IF NOT FOUND THEN RAISE EXCEPTION 'Select a school program' USING ERRCODE='42501';END IF;
 END IF;
 IF p_action IN ('points','exam','redeem') THEN
  v_student:=(p_data->>'student')::uuid;
  PERFORM 1 FROM public.students WHERE id=v_student AND organization_id=p_org AND NOT is_archived FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Student not found' USING ERRCODE='42501';END IF;
  SELECT class_id INTO v_class FROM public.student_class_assignments WHERE student_id=v_student AND organization_id=p_org AND is_current LIMIT 1;
 END IF;
 IF p_action='workspace_open' THEN
  INSERT INTO public.rr_motivation_events(organization_id,actor_id,kind,detail) VALUES(p_org,auth.uid(),'workspace_open',jsonb_build_object('source','admin_workspace'));
 ELSIF p_action='settings' THEN
  IF (p_data->>'revision')::bigint IS DISTINCT FROM v_rev THEN RAISE EXCEPTION 'Settings changed. Reload before saving.' USING ERRCODE='40001';END IF;
  v_old:=p_data->'settings';
  IF jsonb_typeof(v_old) IS DISTINCT FROM 'object' OR (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(v_old) key) IS DISTINCT FROM (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(public.rr_motivation_defaults()) key) THEN RAISE EXCEPTION 'Invalid settings fields' USING ERRCODE='22023';END IF;
  FOREACH k IN ARRAY ARRAY['cards_enabled','reveal_next_day','teacher_cards','phone_frozen','allow_home','allow_father','allow_mother','allow_other','display_enabled','show_birthdays'] LOOP
   IF jsonb_typeof(v_old->k) IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'Invalid switch' USING ERRCODE='22023';END IF;
  END LOOP;
  IF v_old->'weekly_cap'<>'null'::jsonb AND (jsonb_typeof(v_old->'weekly_cap') IS DISTINCT FROM 'number' OR (v_old->>'weekly_cap')::numeric NOT BETWEEN 1 AND 1000 OR trunc((v_old->>'weekly_cap')::numeric)<>(v_old->>'weekly_cap')::numeric) THEN RAISE EXCEPTION 'Enter a valid weekly cap' USING ERRCODE='22023';END IF;
  IF (v_old->>'cards_enabled')::boolean AND v_old->'weekly_cap'='null'::jsonb THEN RAISE EXCEPTION 'Set your weekly cap before enabling cards' USING ERRCODE='22023';END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=v_old->>'timezone') THEN RAISE EXCEPTION 'Confirm a timezone' USING ERRCODE='22023';END IF;
  IF (v_old->>'display_enabled')::boolean AND (coalesce(v_old->>'display_start','')!~'^([01][0-9]|2[0-3]):[0-5][0-9]$' OR coalesce(v_old->>'display_end','')!~'^([01][0-9]|2[0-3]):[0-5][0-9]$') THEN RAISE EXCEPTION 'Choose display start and end times' USING ERRCODE='22023';END IF;
  IF jsonb_typeof(v_old->'display_days') IS DISTINCT FROM 'array' OR jsonb_typeof(v_old->'blocked_students') IS DISTINCT FROM 'array' OR jsonb_typeof(v_old->'playlist') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Invalid lists' USING ERRCODE='22023';END IF;
  FOR row_data IN SELECT value FROM jsonb_array_elements(v_old->'display_days') LOOP IF row_data::text NOT IN ('0','1','2','3','4','5','6') THEN RAISE EXCEPTION 'Invalid day' USING ERRCODE='22023';END IF;END LOOP;
  FOR row_data IN SELECT value FROM jsonb_array_elements(v_old->'blocked_students') LOOP IF NOT EXISTS(SELECT 1 FROM public.students WHERE id=(row_data#>>'{}')::uuid AND organization_id=p_org) THEN RAISE EXCEPTION 'Invalid blocked student' USING ERRCODE='42501';END IF;END LOOP;
  IF jsonb_array_length(v_old->'playlist')>100 OR ((v_old->>'display_enabled')::boolean AND jsonb_array_length(v_old->'playlist')=0) THEN RAISE EXCEPTION 'Playlist needs 1 to 100 slides' USING ERRCODE='22023';END IF;
  FOR row_data IN SELECT value FROM jsonb_array_elements(v_old->'playlist') LOOP
   IF coalesce(row_data->>'type','') NOT IN ('totals','date','text','image','video','background_image','background_video') OR jsonb_typeof(row_data->'seconds') IS DISTINCT FROM 'number' OR (row_data->>'seconds')::numeric NOT BETWEEN 2 AND 600 OR length(coalesce(row_data->>'text',''))>1000 THEN RAISE EXCEPTION 'Invalid slide' USING ERRCODE='22023';END IF;
   IF row_data->>'type' IN ('image','video','background_image','background_video') AND (coalesce(row_data->>'path','') NOT LIKE p_org::text||'/%' OR row_data->>'path' LIKE '%..%') THEN RAISE EXCEPTION 'Media must belong to this school' USING ERRCODE='42501';END IF;
  END LOOP;
  INSERT INTO public.rr_motivation_options VALUES(p_org,v_rev+1,v_old,now()) ON CONFLICT(organization_id) DO UPDATE SET revision=excluded.revision,settings=excluded.settings,updated_at=now();
  INSERT INTO public.rr_motivation_events(organization_id,actor_id,kind,detail) VALUES(p_org,auth.uid(),'settings',jsonb_build_object('before',v_settings,'after',v_old));
 ELSIF p_action='bulk_students' THEN
  IF jsonb_typeof(p_data->'rows') IS DISTINCT FROM 'array' OR jsonb_array_length(p_data->'rows') NOT BETWEEN 1 AND 200 THEN RAISE EXCEPTION 'Choose 1 to 200 students' USING ERRCODE='22023';END IF;
  FOR row_data IN SELECT value FROM jsonb_array_elements(p_data->'rows') LOOP
   v_student:=(row_data->>'id')::uuid;v_name:=regexp_replace(btrim(row_data->>'name'),'\s+',' ','g');v_phone:=regexp_replace(coalesce(row_data->>'phone',''),'[^0-9]','','g');v_class:=(row_data->>'class_id')::uuid;
   SELECT jsonb_build_object('name',name,'phone',coalesce(phone,''),'class_id',(SELECT class_id FROM public.student_class_assignments WHERE organization_id=p_org AND student_id=v_student AND is_current LIMIT 1)) INTO before_data FROM public.students WHERE id=v_student AND organization_id=p_org AND NOT is_archived FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'Student not found' USING ERRCODE='42501';END IF;
   IF before_data IS DISTINCT FROM row_data->'before' THEN RAISE EXCEPTION 'Student changed. Reload before editing.' USING ERRCODE='40001';END IF;
   IF v_name IS NULL OR length(v_name) NOT BETWEEN 1 AND 160 OR (length(v_phone)>0 AND length(v_phone) NOT BETWEEN 7 AND 15) THEN RAISE EXCEPTION 'Invalid student details' USING ERRCODE='22023';END IF;
   SELECT c.school_year_id INTO v_year FROM public.classes c JOIN public.school_years y ON y.id=c.school_year_id AND y.organization_id=p_org AND y.is_current WHERE c.id=v_class AND c.organization_id=p_org AND c.is_active;
   IF NOT FOUND THEN RAISE EXCEPTION 'Choose a current class' USING ERRCODE='22023';END IF;
   IF EXISTS(SELECT 1 FROM public.students s JOIN public.student_class_assignments a ON a.student_id=s.id AND a.organization_id=p_org AND a.is_current WHERE s.organization_id=p_org AND NOT s.is_archived AND s.id<>v_student AND a.class_id=v_class AND lower(regexp_replace(btrim(s.name),'\s+',' ','g'))=lower(v_name)) THEN RAISE EXCEPTION 'Duplicate name in this class' USING ERRCODE='23505';END IF;
   UPDATE public.students SET name=v_name,phone=nullif(v_phone,'') WHERE id=v_student AND organization_id=p_org;
   IF (before_data->>'class_id')::uuid IS DISTINCT FROM v_class THEN
    UPDATE public.student_class_assignments SET is_current=false,ended_at=now() WHERE student_id=v_student AND organization_id=p_org AND is_current;
    INSERT INTO public.student_class_assignments(organization_id,student_id,school_year_id,class_id,is_current) VALUES(p_org,v_student,v_year,v_class,true);
   END IF;
   INSERT INTO public.rr_motivation_events(organization_id,student_id,class_id,actor_id,kind,detail) VALUES(p_org,v_student,v_class,auth.uid(),'student_edit',jsonb_build_object('before',before_data,'after',row_data- 'before'));
  END LOOP;
 ELSIF p_action='class_rename' THEN
  v_class:=(p_data->>'class_id')::uuid;v_name:=btrim(p_data->>'name');
  SELECT jsonb_build_object('name',name) INTO before_data FROM public.classes WHERE id=v_class AND organization_id=p_org FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Class not found' USING ERRCODE='42501';END IF;
  IF before_data->>'name' IS DISTINCT FROM p_data->>'before' THEN RAISE EXCEPTION 'Class changed. Reload.' USING ERRCODE='40001';END IF;
  IF v_name IS NULL OR length(v_name) NOT BETWEEN 1 AND 80 THEN RAISE EXCEPTION 'Enter a class name' USING ERRCODE='22023';END IF;
  IF EXISTS(SELECT 1 FROM public.classes c WHERE c.organization_id=p_org AND c.id<>v_class AND c.school_year_id=(SELECT school_year_id FROM public.classes WHERE id=v_class) AND lower(btrim(c.name))=lower(v_name)) THEN RAISE EXCEPTION 'This class name already exists in the school year' USING ERRCODE='23505';END IF;
  UPDATE public.classes SET name=v_name WHERE id=v_class AND organization_id=p_org;
  INSERT INTO public.rr_motivation_events(organization_id,class_id,actor_id,kind,detail) VALUES(p_org,v_class,auth.uid(),'class_rename',jsonb_build_object('before',before_data,'name',v_name));
 ELSIF p_action IN ('points','exam') THEN
  IF length(btrim(coalesce(p_data->>'reason',''))) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'Enter a reason or exam title' USING ERRCODE='22023';END IF;
  IF p_action='points' THEN
   IF jsonb_typeof(p_data->'points') IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'Enter points' USING ERRCODE='22023';END IF;v_points:=(p_data->>'points')::numeric;
   IF v_points NOT BETWEEN -1000000 AND 1000000 OR v_points=0 THEN RAISE EXCEPTION 'Invalid points' USING ERRCODE='22023';END IF;
  ELSE
   SELECT value INTO v_subject FROM jsonb_array_elements(v_config->'subjects') WHERE value->>'name'=p_data->>'subject';
   IF v_subject IS NULL OR jsonb_typeof(p_data->'score') IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'Choose a subject and enter a score' USING ERRCODE='22023';END IF;
   v_score:=(p_data->>'score')::numeric;IF v_score<0 OR v_score>(v_subject->>'max_score')::numeric THEN RAISE EXCEPTION 'Score exceeds maximum' USING ERRCODE='22023';END IF;
   SELECT coalesce(max((value->>'minimum')::numeric),-1) INTO v_points FROM jsonb_array_elements(v_subject->'bands') WHERE (value->>'minimum')::numeric<=v_score;
   SELECT coalesce((SELECT (value->>'points')::numeric FROM jsonb_array_elements(v_subject->'bands') WHERE (value->>'minimum')::numeric=v_points),0) INTO v_points;
  END IF;
  INSERT INTO public.rr_motivation_events(organization_id,program_id,student_id,class_id,actor_id,kind,detail) VALUES(p_org,v_program,v_student,v_class,auth.uid(),p_action,p_data||jsonb_build_object('awarded',v_points,'rules_snapshot',v_subject)) RETURNING id INTO v_event;
  INSERT INTO public.rr_motivation_points(organization_id,program_id,student_id,points,event_id) VALUES(p_org,v_program,v_student,v_points,v_event);
 ELSIF p_action='cards' THEN
  IF NOT (v_settings->>'cards_enabled')::boolean THEN RAISE EXCEPTION 'Enable cards in Program Settings first' USING ERRCODE='22023';END IF;
  v_class:=(p_data->>'class_id')::uuid;v_count:=(p_data->>'count')::int;v_points:=(p_data->>'points')::numeric;v_batch:=gen_random_uuid();
  IF v_count IS NULL OR v_count NOT BETWEEN 1 AND 200 OR v_points IS NULL OR v_points NOT BETWEEN 0 AND 1000000 OR length(coalesce(p_data->>'teacher',''))>120 THEN RAISE EXCEPTION 'Invalid card batch' USING ERRCODE='22023';END IF;
  IF NOT EXISTS(SELECT 1 FROM public.classes WHERE id=v_class AND organization_id=p_org AND is_active) THEN RAISE EXCEPTION 'Class not found' USING ERRCODE='42501';END IF;
  INSERT INTO public.rr_motivation_cards(organization_id,program_id,class_id,points,teacher,batch_id) SELECT p_org,v_program,v_class,v_points,CASE WHEN (v_settings->>'teacher_cards')::boolean THEN p_data->>'teacher' ELSE NULL END,v_batch FROM generate_series(1,v_count);
  INSERT INTO public.rr_motivation_events(organization_id,program_id,class_id,actor_id,kind,detail) VALUES(p_org,v_program,v_class,auth.uid(),'cards_generated',p_data||jsonb_build_object('batch_id',v_batch));
 ELSIF p_action IN ('redeem','unblock') THEN
  SELECT * INTO v_card FROM public.rr_motivation_cards WHERE organization_id=p_org AND program_id=v_program AND code=upper(btrim(p_data->>'code')) FOR UPDATE;
  IF NOT FOUND THEN v_outcome:='denied';v_message:='Card not found';
  ELSIF p_action='unblock' THEN
   IF length(btrim(coalesce(p_data->>'reason',''))) NOT BETWEEN 1 AND 500 OR v_card.status<>'blocked' THEN RAISE EXCEPTION 'Only blocked cards may be reopened; a reason is required' USING ERRCODE='22023';END IF;
   UPDATE public.rr_motivation_cards SET status='available' WHERE id=v_card.id;v_message:='Card reopened';
  ELSIF NOT (v_settings->>'cards_enabled')::boolean THEN v_outcome:='denied';v_message:='Cards are disabled';
  ELSIF v_card.status<>'available' THEN v_outcome:='denied';v_message:='Card is '||v_card.status;
  ELSIF v_class IS DISTINCT FROM v_card.class_id THEN
   UPDATE public.rr_motivation_cards SET status='blocked' WHERE id=v_card.id;v_outcome:='denied';v_message:='Wrong class. Card permanently blocked until an administrator reopens it.';
  ELSE
   SELECT count(*) INTO v_count FROM public.rr_motivation_events WHERE organization_id=p_org AND program_id=v_program AND student_id=v_student AND kind='redeem' AND outcome='accepted' AND created_at>=public.rr_motivation_week_start(p_org,now(),v_settings->>'timezone');
   IF v_count>=(v_settings->>'weekly_cap')::int THEN v_outcome:='denied';v_message:='Weekly redemption cap reached';
   ELSE UPDATE public.rr_motivation_cards SET status='redeemed',student_id=v_student WHERE id=v_card.id;v_points:=v_card.points;v_message:='Card redeemed';END IF;
  END IF;
  INSERT INTO public.rr_motivation_events(organization_id,program_id,student_id,class_id,actor_id,kind,outcome,detail) VALUES(p_org,v_program,v_student,coalesce(v_class,v_card.class_id),auth.uid(),p_action,v_outcome,p_data||jsonb_build_object('message',v_message,'awarded',v_points,'source','admin')) RETURNING id INTO v_event;
  IF p_action='redeem' AND v_outcome='accepted' THEN INSERT INTO public.rr_motivation_points(organization_id,program_id,student_id,points,event_id,available_at) VALUES(p_org,v_program,v_student,v_points,v_event,CASE WHEN (v_settings->>'reveal_next_day')::boolean THEN ((now() AT TIME ZONE (v_settings->>'timezone'))::date+1)::timestamp AT TIME ZONE (v_settings->>'timezone') ELSE now() END);END IF;
 ELSE RAISE EXCEPTION 'Unknown action' USING ERRCODE='22023';
 END IF;
 v_result:=jsonb_build_object('outcome',v_outcome,'message',v_message,'batch_id',v_batch);
 INSERT INTO public.rr_motivation_requests VALUES(p_org,p_request,v_payload,v_result);RETURN v_result;
END $$;

CREATE OR REPLACE FUNCTION public.rr_motivation_redeem_override(p_org uuid,p_request uuid,p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE payload jsonb;previous jsonb;result jsonb;card public.rr_motivation_cards%ROWTYPE;
 student uuid;program uuid;student_class uuid;settings jsonb;event bigint;used int;outcome text:='accepted';message text:='Card redeemed with class override';
BEGIN
 PERFORM public.rr_motivation_require_access(p_org);
 IF p_request IS NULL OR jsonb_typeof(p_data) IS DISTINCT FROM 'object' OR p_data->'confirmed' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'Confirm the class override first' USING ERRCODE='22023';END IF;
 payload:=jsonb_build_object('action','redeem_override','data',p_data);
 PERFORM 1 FROM public.organizations WHERE id=p_org FOR UPDATE;
 SELECT q.payload,q.result INTO previous,result FROM public.rr_motivation_requests q WHERE organization_id=p_org AND request_id=p_request;
 IF FOUND THEN IF previous<>payload THEN RAISE EXCEPTION 'Request already used' USING ERRCODE='22023';END IF;RETURN result;END IF;
 student:=(p_data->>'student')::uuid;program:=(p_data->>'program')::uuid;
 IF NOT EXISTS(SELECT 1 FROM public.rr_motivation_programs WHERE id=program AND organization_id=p_org) OR NOT EXISTS(SELECT 1 FROM public.students WHERE id=student AND organization_id=p_org AND NOT is_archived) THEN RAISE EXCEPTION 'Student or program not found' USING ERRCODE='42501';END IF;
 SELECT class_id INTO student_class FROM public.student_class_assignments WHERE organization_id=p_org AND student_id=student AND is_current LIMIT 1;
 SELECT * INTO card FROM public.rr_motivation_cards WHERE organization_id=p_org AND program_id=program AND code=upper(btrim(p_data->>'code')) FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Card not found' USING ERRCODE='22023';END IF;
 SELECT coalesce((SELECT o.settings FROM public.rr_motivation_options o WHERE organization_id=p_org),public.rr_motivation_defaults()) INTO settings;
 IF card.status<>'blocked' THEN outcome:='denied';message:='Only a card blocked by a class mismatch can be overridden';
 ELSIF student_class IS NULL OR student_class=card.class_id THEN outcome:='denied';message:='The student class changed. Review the card again';
 ELSIF NOT EXISTS(SELECT 1 FROM public.rr_motivation_events e WHERE e.organization_id=p_org AND e.program_id=program AND e.student_id=student AND e.actor_id=auth.uid() AND e.kind='redeem' AND e.outcome='denied' AND upper(e.detail->>'code')=card.code AND e.detail->>'message' LIKE 'Wrong class.%') THEN outcome:='denied';message:='Scan this card for this student and confirm the warning first';
 ELSIF NOT (settings->>'cards_enabled')::boolean THEN outcome:='denied';message:='Cards are disabled';
 ELSE
  SELECT count(*) INTO used FROM public.rr_motivation_events e WHERE e.organization_id=p_org AND e.program_id=program AND e.student_id=student AND e.kind='redeem' AND e.outcome='accepted' AND e.created_at>=public.rr_motivation_week_start(p_org,now(),settings->>'timezone');
  IF settings->>'weekly_cap' IS NULL OR used>=(settings->>'weekly_cap')::int THEN outcome:='denied';message:='Weekly redemption cap reached';
  ELSE UPDATE public.rr_motivation_cards SET status='redeemed',student_id=student WHERE id=card.id;END IF;
 END IF;
 INSERT INTO public.rr_motivation_events(organization_id,program_id,student_id,class_id,actor_id,kind,outcome,detail)
 VALUES(p_org,program,student,student_class,auth.uid(),'redeem',outcome,p_data||jsonb_build_object('class_override',true,'original_card_class',card.class_id,'student_class',student_class,'message',message,'source','admin_scanner','awarded',CASE WHEN outcome='accepted' THEN card.points ELSE 0 END)) RETURNING id INTO event;
 IF outcome='accepted' THEN INSERT INTO public.rr_motivation_points(organization_id,program_id,student_id,points,event_id,available_at) VALUES(p_org,program,student,card.points,event,CASE WHEN (settings->>'reveal_next_day')::boolean THEN ((now() AT TIME ZONE (settings->>'timezone'))::date+1)::timestamp AT TIME ZONE (settings->>'timezone') ELSE now() END);END IF;
 result:=jsonb_build_object('outcome',outcome,'message',message);INSERT INTO public.rr_motivation_requests VALUES(p_org,p_request,payload,result);RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.rr_motivation_redeem_override(uuid,uuid,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_motivation_redeem_override(uuid,uuid,jsonb) TO authenticated;



-- Daily limits and card expiry. Requires the settings navigation migration.
CREATE TABLE IF NOT EXISTS public.rr_motivation_policy (
 organization_id uuid PRIMARY KEY REFERENCES public.organizations(id),
 daily_cap integer CHECK(daily_cap BETWEEN 1 AND 1000),
 expiry_days integer CHECK(expiry_days BETWEEN 1 AND 3650),
 revision bigint NOT NULL DEFAULT 1
);
ALTER TABLE public.rr_motivation_policy ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rr_motivation_policy FROM PUBLIC,anon,authenticated;
ALTER TABLE public.rr_motivation_cards ADD COLUMN IF NOT EXISTS expires_at timestamptz;
CREATE OR REPLACE FUNCTION public.rr_motivation_policy_read(p_org uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM public.rr_motivation_require_access(p_org);
 RETURN coalesce((SELECT jsonb_build_object('daily_cap',daily_cap,'expiry_days',expiry_days,'revision',revision) FROM public.rr_motivation_policy WHERE organization_id=p_org),'{"daily_cap":null,"expiry_days":null,"revision":0}'::jsonb);
END $$;
CREATE OR REPLACE FUNCTION public.rr_motivation_policy_save(p_org uuid,p_daily integer,p_expiry integer,p_revision bigint) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE rev bigint;old jsonb;
BEGIN
 PERFORM public.rr_motivation_require_access(p_org);
 PERFORM 1 FROM public.organizations WHERE id=p_org FOR UPDATE;
 IF (p_daily IS NOT NULL AND p_daily NOT BETWEEN 1 AND 1000) OR (p_expiry IS NOT NULL AND p_expiry NOT BETWEEN 1 AND 3650) THEN RAISE EXCEPTION 'Enter whole positive numbers within the allowed range, or leave blank' USING ERRCODE='22023';END IF;
 SELECT revision,to_jsonb(t) INTO rev,old FROM public.rr_motivation_policy t WHERE organization_id=p_org;
 IF p_revision IS DISTINCT FROM coalesce(rev,0) THEN RAISE EXCEPTION 'Rules changed. Reload before saving.' USING ERRCODE='40001';END IF;
 INSERT INTO public.rr_motivation_policy VALUES(p_org,p_daily,p_expiry,coalesce(rev,0)+1) ON CONFLICT(organization_id) DO UPDATE SET daily_cap=excluded.daily_cap,expiry_days=excluded.expiry_days,revision=excluded.revision;
 INSERT INTO public.rr_motivation_events(organization_id,actor_id,kind,detail) VALUES(p_org,auth.uid(),'settings',jsonb_build_object('section','card_policy','before',old,'daily_cap',p_daily,'expiry_days',p_expiry));
 RETURN public.rr_motivation_policy_read(p_org);
END $$;
-- Private helpers: callers already hold the organization lock.
CREATE OR REPLACE FUNCTION public.rr_motivation_card_expiry(p_org uuid,p_now timestamptz,p_zone text) RETURNS timestamptz LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT (((p_now AT TIME ZONE p_zone)::date + expiry_days)::timestamp AT TIME ZONE p_zone) FROM public.rr_motivation_policy WHERE organization_id=p_org
$$;
CREATE OR REPLACE FUNCTION public.rr_motivation_daily_reached(p_org uuid,p_program uuid,p_student uuid,p_now timestamptz,p_zone text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT coalesce((SELECT (SELECT count(*) FROM public.rr_motivation_events e WHERE e.organization_id=p_org AND e.program_id=p_program AND e.student_id=p_student AND e.kind='redeem' AND e.outcome='accepted' AND e.created_at>=((p_now AT TIME ZONE p_zone)::date::timestamp AT TIME ZONE p_zone))>=daily_cap FROM public.rr_motivation_policy WHERE organization_id=p_org),false)
$$;
REVOKE ALL ON FUNCTION public.rr_motivation_card_expiry(uuid,timestamptz,text),public.rr_motivation_daily_reached(uuid,uuid,uuid,timestamptz,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.rr_motivation_policy_read(uuid),public.rr_motivation_policy_save(uuid,integer,integer,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_motivation_policy_read(uuid),public.rr_motivation_policy_save(uuid,integer,integer,bigint) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_motivation_command(p_org uuid,p_request uuid,p_action text,p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE v_payload jsonb;v_old jsonb;v_result jsonb;v_program uuid;v_student uuid;v_class uuid;v_year uuid;v_event bigint;
 v_settings jsonb;v_rev bigint;v_points numeric;v_config jsonb;v_subject jsonb;v_score numeric;v_card public.rr_motivation_cards%ROWTYPE;
 row_data jsonb;before_data jsonb;v_name text;v_phone text;v_count int;v_batch uuid;v_outcome text:='accepted';v_message text:='Saved'; k text;
BEGIN
 PERFORM public.rr_motivation_require_access(p_org);
 IF p_request IS NULL OR p_action IS NULL OR jsonb_typeof(p_data) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Invalid request' USING ERRCODE='22023';END IF;
 v_payload:=jsonb_build_object('action',p_action,'data',p_data);
 PERFORM 1 FROM public.organizations WHERE id=p_org FOR UPDATE;
 SELECT payload,result INTO v_old,v_result FROM public.rr_motivation_requests WHERE organization_id=p_org AND request_id=p_request;
 IF FOUND THEN IF v_old<>v_payload THEN RAISE EXCEPTION 'Request already used' USING ERRCODE='22023';END IF;RETURN v_result;END IF;
 SELECT settings,revision INTO v_settings,v_rev FROM public.rr_motivation_options WHERE organization_id=p_org;
 v_settings:=coalesce(v_settings,public.rr_motivation_defaults());v_rev:=coalesce(v_rev,0);
 IF p_action IN ('points','exam','cards','redeem','unblock') THEN
  v_program:=(p_data->>'program')::uuid;
  SELECT config INTO v_config FROM public.rr_motivation_programs WHERE id=v_program AND organization_id=p_org;
  IF NOT FOUND THEN RAISE EXCEPTION 'Select a school program' USING ERRCODE='42501';END IF;
 END IF;
 IF p_action IN ('points','exam','redeem') THEN
  v_student:=(p_data->>'student')::uuid;
  PERFORM 1 FROM public.students WHERE id=v_student AND organization_id=p_org AND NOT is_archived FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Student not found' USING ERRCODE='42501';END IF;
  SELECT class_id INTO v_class FROM public.student_class_assignments WHERE student_id=v_student AND organization_id=p_org AND is_current LIMIT 1;
 END IF;
 IF p_action='workspace_open' THEN
  INSERT INTO public.rr_motivation_events(organization_id,actor_id,kind,detail) VALUES(p_org,auth.uid(),'workspace_open',jsonb_build_object('source','admin_workspace'));
 ELSIF p_action='settings' THEN
  IF (p_data->>'revision')::bigint IS DISTINCT FROM v_rev THEN RAISE EXCEPTION 'Settings changed. Reload before saving.' USING ERRCODE='40001';END IF;
  v_old:=p_data->'settings';
  IF jsonb_typeof(v_old) IS DISTINCT FROM 'object' OR (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(v_old) key) IS DISTINCT FROM (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(public.rr_motivation_defaults()) key) THEN RAISE EXCEPTION 'Invalid settings fields' USING ERRCODE='22023';END IF;
  FOREACH k IN ARRAY ARRAY['cards_enabled','reveal_next_day','teacher_cards','phone_frozen','allow_home','allow_father','allow_mother','allow_other','display_enabled','show_birthdays'] LOOP
   IF jsonb_typeof(v_old->k) IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'Invalid switch' USING ERRCODE='22023';END IF;
  END LOOP;
  IF v_old->'weekly_cap'<>'null'::jsonb AND (jsonb_typeof(v_old->'weekly_cap') IS DISTINCT FROM 'number' OR (v_old->>'weekly_cap')::numeric NOT BETWEEN 1 AND 1000 OR trunc((v_old->>'weekly_cap')::numeric)<>(v_old->>'weekly_cap')::numeric) THEN RAISE EXCEPTION 'Enter a valid weekly cap' USING ERRCODE='22023';END IF;
  IF (v_old->>'cards_enabled')::boolean AND v_old->'weekly_cap'='null'::jsonb THEN RAISE EXCEPTION 'Set your weekly cap before enabling cards' USING ERRCODE='22023';END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=v_old->>'timezone') THEN RAISE EXCEPTION 'Confirm a timezone' USING ERRCODE='22023';END IF;
  IF (v_old->>'display_enabled')::boolean AND (coalesce(v_old->>'display_start','')!~'^([01][0-9]|2[0-3]):[0-5][0-9]$' OR coalesce(v_old->>'display_end','')!~'^([01][0-9]|2[0-3]):[0-5][0-9]$') THEN RAISE EXCEPTION 'Choose display start and end times' USING ERRCODE='22023';END IF;
  IF jsonb_typeof(v_old->'display_days') IS DISTINCT FROM 'array' OR jsonb_typeof(v_old->'blocked_students') IS DISTINCT FROM 'array' OR jsonb_typeof(v_old->'playlist') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Invalid lists' USING ERRCODE='22023';END IF;
  FOR row_data IN SELECT value FROM jsonb_array_elements(v_old->'display_days') LOOP IF row_data::text NOT IN ('0','1','2','3','4','5','6') THEN RAISE EXCEPTION 'Invalid day' USING ERRCODE='22023';END IF;END LOOP;
  FOR row_data IN SELECT value FROM jsonb_array_elements(v_old->'blocked_students') LOOP IF NOT EXISTS(SELECT 1 FROM public.students WHERE id=(row_data#>>'{}')::uuid AND organization_id=p_org) THEN RAISE EXCEPTION 'Invalid blocked student' USING ERRCODE='42501';END IF;END LOOP;
  IF jsonb_array_length(v_old->'playlist')>100 OR ((v_old->>'display_enabled')::boolean AND jsonb_array_length(v_old->'playlist')=0) THEN RAISE EXCEPTION 'Playlist needs 1 to 100 slides' USING ERRCODE='22023';END IF;
  FOR row_data IN SELECT value FROM jsonb_array_elements(v_old->'playlist') LOOP
   IF coalesce(row_data->>'type','') NOT IN ('totals','date','text','image','video','background_image','background_video') OR jsonb_typeof(row_data->'seconds') IS DISTINCT FROM 'number' OR (row_data->>'seconds')::numeric NOT BETWEEN 2 AND 600 OR length(coalesce(row_data->>'text',''))>1000 THEN RAISE EXCEPTION 'Invalid slide' USING ERRCODE='22023';END IF;
   IF row_data->>'type' IN ('image','video','background_image','background_video') AND (coalesce(row_data->>'path','') NOT LIKE p_org::text||'/%' OR row_data->>'path' LIKE '%..%') THEN RAISE EXCEPTION 'Media must belong to this school' USING ERRCODE='42501';END IF;
  END LOOP;
  INSERT INTO public.rr_motivation_options VALUES(p_org,v_rev+1,v_old,now()) ON CONFLICT(organization_id) DO UPDATE SET revision=excluded.revision,settings=excluded.settings,updated_at=now();
  INSERT INTO public.rr_motivation_events(organization_id,actor_id,kind,detail) VALUES(p_org,auth.uid(),'settings',jsonb_build_object('before',v_settings,'after',v_old));
 ELSIF p_action='bulk_students' THEN
  IF jsonb_typeof(p_data->'rows') IS DISTINCT FROM 'array' OR jsonb_array_length(p_data->'rows') NOT BETWEEN 1 AND 200 THEN RAISE EXCEPTION 'Choose 1 to 200 students' USING ERRCODE='22023';END IF;
  FOR row_data IN SELECT value FROM jsonb_array_elements(p_data->'rows') LOOP
   v_student:=(row_data->>'id')::uuid;v_name:=regexp_replace(btrim(row_data->>'name'),'\s+',' ','g');v_phone:=regexp_replace(coalesce(row_data->>'phone',''),'[^0-9]','','g');v_class:=(row_data->>'class_id')::uuid;
   SELECT jsonb_build_object('name',name,'phone',coalesce(phone,''),'class_id',(SELECT class_id FROM public.student_class_assignments WHERE organization_id=p_org AND student_id=v_student AND is_current LIMIT 1)) INTO before_data FROM public.students WHERE id=v_student AND organization_id=p_org AND NOT is_archived FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'Student not found' USING ERRCODE='42501';END IF;
   IF before_data IS DISTINCT FROM row_data->'before' THEN RAISE EXCEPTION 'Student changed. Reload before editing.' USING ERRCODE='40001';END IF;
   IF v_name IS NULL OR length(v_name) NOT BETWEEN 1 AND 160 OR (length(v_phone)>0 AND length(v_phone) NOT BETWEEN 7 AND 15) THEN RAISE EXCEPTION 'Invalid student details' USING ERRCODE='22023';END IF;
   SELECT c.school_year_id INTO v_year FROM public.classes c JOIN public.school_years y ON y.id=c.school_year_id AND y.organization_id=p_org AND y.is_current WHERE c.id=v_class AND c.organization_id=p_org AND c.is_active;
   IF NOT FOUND THEN RAISE EXCEPTION 'Choose a current class' USING ERRCODE='22023';END IF;
   IF EXISTS(SELECT 1 FROM public.students s JOIN public.student_class_assignments a ON a.student_id=s.id AND a.organization_id=p_org AND a.is_current WHERE s.organization_id=p_org AND NOT s.is_archived AND s.id<>v_student AND a.class_id=v_class AND lower(regexp_replace(btrim(s.name),'\s+',' ','g'))=lower(v_name)) THEN RAISE EXCEPTION 'Duplicate name in this class' USING ERRCODE='23505';END IF;
   UPDATE public.students SET name=v_name,phone=nullif(v_phone,'') WHERE id=v_student AND organization_id=p_org;
   IF (before_data->>'class_id')::uuid IS DISTINCT FROM v_class THEN
    UPDATE public.student_class_assignments SET is_current=false,ended_at=now() WHERE student_id=v_student AND organization_id=p_org AND is_current;
    INSERT INTO public.student_class_assignments(organization_id,student_id,school_year_id,class_id,is_current) VALUES(p_org,v_student,v_year,v_class,true);
   END IF;
   INSERT INTO public.rr_motivation_events(organization_id,student_id,class_id,actor_id,kind,detail) VALUES(p_org,v_student,v_class,auth.uid(),'student_edit',jsonb_build_object('before',before_data,'after',row_data- 'before'));
  END LOOP;
 ELSIF p_action='class_rename' THEN
  v_class:=(p_data->>'class_id')::uuid;v_name:=btrim(p_data->>'name');
  SELECT jsonb_build_object('name',name) INTO before_data FROM public.classes WHERE id=v_class AND organization_id=p_org FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Class not found' USING ERRCODE='42501';END IF;
  IF before_data->>'name' IS DISTINCT FROM p_data->>'before' THEN RAISE EXCEPTION 'Class changed. Reload.' USING ERRCODE='40001';END IF;
  IF v_name IS NULL OR length(v_name) NOT BETWEEN 1 AND 80 THEN RAISE EXCEPTION 'Enter a class name' USING ERRCODE='22023';END IF;
  IF EXISTS(SELECT 1 FROM public.classes c WHERE c.organization_id=p_org AND c.id<>v_class AND c.school_year_id=(SELECT school_year_id FROM public.classes WHERE id=v_class) AND lower(btrim(c.name))=lower(v_name)) THEN RAISE EXCEPTION 'This class name already exists in the school year' USING ERRCODE='23505';END IF;
  UPDATE public.classes SET name=v_name WHERE id=v_class AND organization_id=p_org;
  INSERT INTO public.rr_motivation_events(organization_id,class_id,actor_id,kind,detail) VALUES(p_org,v_class,auth.uid(),'class_rename',jsonb_build_object('before',before_data,'name',v_name));
 ELSIF p_action IN ('points','exam') THEN
  IF length(btrim(coalesce(p_data->>'reason',''))) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'Enter a reason or exam title' USING ERRCODE='22023';END IF;
  IF p_action='points' THEN
   IF jsonb_typeof(p_data->'points') IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'Enter points' USING ERRCODE='22023';END IF;v_points:=(p_data->>'points')::numeric;
   IF v_points NOT BETWEEN -1000000 AND 1000000 OR v_points=0 THEN RAISE EXCEPTION 'Invalid points' USING ERRCODE='22023';END IF;
  ELSE
   SELECT value INTO v_subject FROM jsonb_array_elements(v_config->'subjects') WHERE value->>'name'=p_data->>'subject';
   IF v_subject IS NULL OR jsonb_typeof(p_data->'score') IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'Choose a subject and enter a score' USING ERRCODE='22023';END IF;
   v_score:=(p_data->>'score')::numeric;IF v_score<0 OR v_score>(v_subject->>'max_score')::numeric THEN RAISE EXCEPTION 'Score exceeds maximum' USING ERRCODE='22023';END IF;
   SELECT coalesce(max((value->>'minimum')::numeric),-1) INTO v_points FROM jsonb_array_elements(v_subject->'bands') WHERE (value->>'minimum')::numeric<=v_score;
   SELECT coalesce((SELECT (value->>'points')::numeric FROM jsonb_array_elements(v_subject->'bands') WHERE (value->>'minimum')::numeric=v_points),0) INTO v_points;
  END IF;
  INSERT INTO public.rr_motivation_events(organization_id,program_id,student_id,class_id,actor_id,kind,detail) VALUES(p_org,v_program,v_student,v_class,auth.uid(),p_action,p_data||jsonb_build_object('awarded',v_points,'rules_snapshot',v_subject)) RETURNING id INTO v_event;
  INSERT INTO public.rr_motivation_points(organization_id,program_id,student_id,points,event_id) VALUES(p_org,v_program,v_student,v_points,v_event);
 ELSIF p_action='cards' THEN
  IF NOT (v_settings->>'cards_enabled')::boolean THEN RAISE EXCEPTION 'Enable cards in Program Settings first' USING ERRCODE='22023';END IF;
  v_class:=(p_data->>'class_id')::uuid;v_count:=(p_data->>'count')::int;v_points:=(p_data->>'points')::numeric;v_batch:=gen_random_uuid();
  IF v_count IS NULL OR v_count NOT BETWEEN 1 AND 200 OR v_points IS NULL OR v_points NOT BETWEEN 0 AND 1000000 OR length(coalesce(p_data->>'teacher',''))>120 THEN RAISE EXCEPTION 'Invalid card batch' USING ERRCODE='22023';END IF;
  IF NOT EXISTS(SELECT 1 FROM public.classes WHERE id=v_class AND organization_id=p_org AND is_active) THEN RAISE EXCEPTION 'Class not found' USING ERRCODE='42501';END IF;
  INSERT INTO public.rr_motivation_cards(organization_id,program_id,class_id,points,teacher,batch_id,expires_at) SELECT p_org,v_program,v_class,v_points,CASE WHEN (v_settings->>'teacher_cards')::boolean THEN p_data->>'teacher' ELSE NULL END,v_batch,public.rr_motivation_card_expiry(p_org,now(),v_settings->>'timezone') FROM generate_series(1,v_count);
  INSERT INTO public.rr_motivation_events(organization_id,program_id,class_id,actor_id,kind,detail) VALUES(p_org,v_program,v_class,auth.uid(),'cards_generated',p_data||jsonb_build_object('batch_id',v_batch));
 ELSIF p_action IN ('redeem','unblock') THEN
  SELECT * INTO v_card FROM public.rr_motivation_cards WHERE organization_id=p_org AND program_id=v_program AND code=upper(btrim(p_data->>'code')) FOR UPDATE;
  IF NOT FOUND THEN v_outcome:='denied';v_message:='Card not found';
  ELSIF p_action='unblock' THEN
   IF length(btrim(coalesce(p_data->>'reason',''))) NOT BETWEEN 1 AND 500 OR v_card.status<>'blocked' THEN RAISE EXCEPTION 'Only blocked cards may be reopened; a reason is required' USING ERRCODE='22023';END IF;
   UPDATE public.rr_motivation_cards SET status='available' WHERE id=v_card.id;v_message:='Card reopened';
  ELSIF NOT (v_settings->>'cards_enabled')::boolean THEN v_outcome:='denied';v_message:='Cards are disabled';
  ELSIF v_card.status<>'available' THEN v_outcome:='denied';v_message:='Card is '||v_card.status;
  ELSIF v_card.expires_at IS NOT NULL AND now()>=v_card.expires_at THEN v_outcome:='denied';v_message:='Card expired';
  ELSIF public.rr_motivation_daily_reached(p_org,v_program,v_student,now(),v_settings->>'timezone') THEN v_outcome:='denied';v_message:='Daily redemption cap reached';
  ELSIF v_class IS DISTINCT FROM v_card.class_id THEN
   UPDATE public.rr_motivation_cards SET status='blocked' WHERE id=v_card.id;v_outcome:='denied';v_message:='Wrong class. Card permanently blocked until an administrator reopens it.';
  ELSE
   SELECT count(*) INTO v_count FROM public.rr_motivation_events WHERE organization_id=p_org AND program_id=v_program AND student_id=v_student AND kind='redeem' AND outcome='accepted' AND created_at>=public.rr_motivation_week_start(p_org,now(),v_settings->>'timezone');
   IF v_count>=(v_settings->>'weekly_cap')::int THEN v_outcome:='denied';v_message:='Weekly redemption cap reached';
   ELSE UPDATE public.rr_motivation_cards SET status='redeemed',student_id=v_student WHERE id=v_card.id;v_points:=v_card.points;v_message:='Card redeemed';END IF;
  END IF;
  INSERT INTO public.rr_motivation_events(organization_id,program_id,student_id,class_id,actor_id,kind,outcome,detail) VALUES(p_org,v_program,v_student,coalesce(v_class,v_card.class_id),auth.uid(),p_action,v_outcome,p_data||jsonb_build_object('message',v_message,'awarded',v_points,'source','admin')) RETURNING id INTO v_event;
  IF p_action='redeem' AND v_outcome='accepted' THEN INSERT INTO public.rr_motivation_points(organization_id,program_id,student_id,points,event_id,available_at) VALUES(p_org,v_program,v_student,v_points,v_event,CASE WHEN (v_settings->>'reveal_next_day')::boolean THEN ((now() AT TIME ZONE (v_settings->>'timezone'))::date+1)::timestamp AT TIME ZONE (v_settings->>'timezone') ELSE now() END);END IF;
 ELSE RAISE EXCEPTION 'Unknown action' USING ERRCODE='22023';
 END IF;
 v_result:=jsonb_build_object('outcome',v_outcome,'message',v_message,'batch_id',v_batch);
 INSERT INTO public.rr_motivation_requests VALUES(p_org,p_request,v_payload,v_result);RETURN v_result;
END $$;

CREATE OR REPLACE FUNCTION public.rr_motivation_redeem_override(p_org uuid,p_request uuid,p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE payload jsonb;previous jsonb;result jsonb;card public.rr_motivation_cards%ROWTYPE;
 student uuid;program uuid;student_class uuid;settings jsonb;event bigint;used int;outcome text:='accepted';message text:='Card redeemed with class override';
BEGIN
 PERFORM public.rr_motivation_require_access(p_org);
 IF p_request IS NULL OR jsonb_typeof(p_data) IS DISTINCT FROM 'object' OR p_data->'confirmed' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'Confirm the class override first' USING ERRCODE='22023';END IF;
 payload:=jsonb_build_object('action','redeem_override','data',p_data);
 PERFORM 1 FROM public.organizations WHERE id=p_org FOR UPDATE;
 SELECT q.payload,q.result INTO previous,result FROM public.rr_motivation_requests q WHERE organization_id=p_org AND request_id=p_request;
 IF FOUND THEN IF previous<>payload THEN RAISE EXCEPTION 'Request already used' USING ERRCODE='22023';END IF;RETURN result;END IF;
 student:=(p_data->>'student')::uuid;program:=(p_data->>'program')::uuid;
 IF NOT EXISTS(SELECT 1 FROM public.rr_motivation_programs WHERE id=program AND organization_id=p_org) OR NOT EXISTS(SELECT 1 FROM public.students WHERE id=student AND organization_id=p_org AND NOT is_archived) THEN RAISE EXCEPTION 'Student or program not found' USING ERRCODE='42501';END IF;
 SELECT class_id INTO student_class FROM public.student_class_assignments WHERE organization_id=p_org AND student_id=student AND is_current LIMIT 1;
 SELECT * INTO card FROM public.rr_motivation_cards WHERE organization_id=p_org AND program_id=program AND code=upper(btrim(p_data->>'code')) FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Card not found' USING ERRCODE='22023';END IF;
 SELECT coalesce((SELECT o.settings FROM public.rr_motivation_options o WHERE organization_id=p_org),public.rr_motivation_defaults()) INTO settings;
 IF card.status<>'blocked' THEN outcome:='denied';message:='Only a card blocked by a class mismatch can be overridden';
 ELSIF student_class IS NULL OR student_class=card.class_id THEN outcome:='denied';message:='The student class changed. Review the card again';
 ELSIF NOT EXISTS(SELECT 1 FROM public.rr_motivation_events e WHERE e.organization_id=p_org AND e.program_id=program AND e.student_id=student AND e.actor_id=auth.uid() AND e.kind='redeem' AND e.outcome='denied' AND upper(e.detail->>'code')=card.code AND e.detail->>'message' LIKE 'Wrong class.%') THEN outcome:='denied';message:='Scan this card for this student and confirm the warning first';
 ELSIF card.expires_at IS NOT NULL AND now()>=card.expires_at THEN outcome:='denied';message:='Card expired';
 ELSIF public.rr_motivation_daily_reached(p_org,program,student,now(),settings->>'timezone') THEN outcome:='denied';message:='Daily redemption cap reached';
 ELSIF NOT (settings->>'cards_enabled')::boolean THEN outcome:='denied';message:='Cards are disabled';
 ELSE
  SELECT count(*) INTO used FROM public.rr_motivation_events e WHERE e.organization_id=p_org AND e.program_id=program AND e.student_id=student AND e.kind='redeem' AND e.outcome='accepted' AND e.created_at>=public.rr_motivation_week_start(p_org,now(),settings->>'timezone');
  IF settings->>'weekly_cap' IS NULL OR used>=(settings->>'weekly_cap')::int THEN outcome:='denied';message:='Weekly redemption cap reached';
  ELSE UPDATE public.rr_motivation_cards SET status='redeemed',student_id=student WHERE id=card.id;END IF;
 END IF;
 INSERT INTO public.rr_motivation_events(organization_id,program_id,student_id,class_id,actor_id,kind,outcome,detail)
 VALUES(p_org,program,student,student_class,auth.uid(),'redeem',outcome,p_data||jsonb_build_object('class_override',true,'original_card_class',card.class_id,'student_class',student_class,'message',message,'source','admin_scanner','awarded',CASE WHEN outcome='accepted' THEN card.points ELSE 0 END)) RETURNING id INTO event;
 IF outcome='accepted' THEN INSERT INTO public.rr_motivation_points(organization_id,program_id,student_id,points,event_id,available_at) VALUES(p_org,program,student,card.points,event,CASE WHEN (settings->>'reveal_next_day')::boolean THEN ((now() AT TIME ZONE (settings->>'timezone'))::date+1)::timestamp AT TIME ZONE (settings->>'timezone') ELSE now() END);END IF;
 result:=jsonb_build_object('outcome',outcome,'message',message);INSERT INTO public.rr_motivation_requests VALUES(p_org,p_request,payload,result);RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.rr_motivation_redeem_override(uuid,uuid,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_motivation_redeem_override(uuid,uuid,jsonb) TO authenticated;



-- Practical cards release; install after Card Policy (included in full installer).
ALTER TABLE public.rr_teacher_portals ALTER COLUMN email DROP NOT NULL;
ALTER TABLE public.rr_teacher_portals ADD COLUMN IF NOT EXISTS session text CHECK(session IN ('full','morning','afternoon'));
ALTER TABLE public.rr_teacher_portals ADD COLUMN IF NOT EXISTS revision bigint NOT NULL DEFAULT 1;
ALTER TABLE public.rr_motivation_cards ADD COLUMN IF NOT EXISTS valid_from timestamptz;
ALTER TABLE public.rr_motivation_cards ADD COLUMN IF NOT EXISTS valid_from_date date;
ALTER TABLE public.rr_motivation_cards ADD COLUMN IF NOT EXISTS valid_through_date date;
ALTER TABLE public.rr_motivation_cards ADD COLUMN IF NOT EXISTS card_number bigint GENERATED BY DEFAULT AS IDENTITY;
CREATE TABLE IF NOT EXISTS public.rr_motivation_orders(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL REFERENCES public.organizations(id),program_id uuid NOT NULL REFERENCES public.rr_motivation_programs(id),request_id uuid NOT NULL,payload jsonb NOT NULL,plan jsonb NOT NULL,batches jsonb NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(organization_id,request_id));
ALTER TABLE public.rr_motivation_orders ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rr_motivation_orders FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.rr_motivation_roster_v5(p_org uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE result jsonb;v_max bigint;v_students jsonb;
BEGIN
 PERFORM public.rr_motivation_require_access(p_org);PERFORM 1 FROM public.organizations WHERE id=p_org FOR UPDATE;
 -- Keep existing four-digit numbers; assign unused four-digit numbers to everyone else.
 WITH missing AS (SELECT s.id,row_number() OVER(ORDER BY s.created_at,s.id) n FROM public.students s LEFT JOIN public.rr_student_aliases a ON a.student_id=s.id WHERE s.organization_id=p_org AND (a.short_id IS NULL OR a.short_id NOT BETWEEN 1000 AND 9999)),free AS (SELECT v,row_number() OVER(ORDER BY v) n FROM generate_series(1000,9999) v WHERE NOT EXISTS(SELECT 1 FROM public.rr_student_aliases a WHERE a.organization_id=p_org AND a.short_id=v))
 INSERT INTO public.rr_student_aliases(organization_id,student_id,short_id) SELECT p_org,m.id,f.v FROM missing m JOIN free f USING(n) ON CONFLICT(student_id) DO UPDATE SET short_id=excluded.short_id;
 IF EXISTS(SELECT 1 FROM public.students s LEFT JOIN public.rr_student_aliases a ON a.student_id=s.id WHERE s.organization_id=p_org AND (a.short_id IS NULL OR a.short_id NOT BETWEEN 1000 AND 9999)) THEN RAISE EXCEPTION 'No four-digit student numbers available for this school' USING ERRCODE='22023';END IF;
 result:=public.rr_motivation_roster(p_org);
 SELECT coalesce(jsonb_agg(value||public.rr_motivation_student_snapshot((value->>'id')::uuid)||jsonb_build_object('snapshot',public.rr_motivation_student_snapshot((value->>'id')::uuid),'short_id',(SELECT short_id FROM public.rr_student_aliases WHERE student_id=(value->>'id')::uuid),'files',coalesce((SELECT jsonb_agg(to_jsonb(f)) FROM public.rr_student_files f WHERE f.organization_id=p_org AND f.student_id=(value->>'id')::uuid),'[]'::jsonb))),'[]') INTO v_students FROM jsonb_array_elements(result->'students');
 RETURN jsonb_set(result,'{students}',v_students);
END $$;
CREATE OR REPLACE FUNCTION public.rr_motivation_teacher_save(p_org uuid,p_id uuid,p_revision bigint,p_name text,p_email text,p_class uuid,p_session text,p_enabled boolean) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE old public.rr_teacher_portals%ROWTYPE;result jsonb;email_value text;
BEGIN
 PERFORM public.rr_motivation_require_access(p_org);PERFORM 1 FROM public.organizations WHERE id=p_org FOR UPDATE;
 email_value:=nullif(lower(btrim(p_email)),'');
 IF p_name IS NULL OR length(btrim(p_name)) NOT BETWEEN 1 AND 120 OR p_session IS NULL OR p_session NOT IN ('full','morning','afternoon') OR p_enabled IS NULL OR (email_value IS NOT NULL AND email_value !~ '^[^ @]+@[^ @]+\.[^ @]+$') THEN RAISE EXCEPTION 'Enter a teacher name, session and valid optional email' USING ERRCODE='22023';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.classes c JOIN public.school_years y ON y.id=c.school_year_id AND y.is_current WHERE c.id=p_class AND c.organization_id=p_org AND c.is_active) THEN RAISE EXCEPTION 'Choose a current class' USING ERRCODE='22023';END IF;
 IF p_id IS NOT NULL THEN SELECT * INTO old FROM public.rr_teacher_portals WHERE id=p_id AND organization_id=p_org FOR UPDATE;IF NOT FOUND THEN RAISE EXCEPTION 'Teacher not found' USING ERRCODE='42501';END IF;END IF;
 IF p_revision IS DISTINCT FROM coalesce(old.revision,0) THEN RAISE EXCEPTION 'Teacher changed. Reload before saving.' USING ERRCODE='40001';END IF;
 IF p_enabled AND EXISTS(SELECT 1 FROM public.rr_teacher_portals t WHERE organization_id=p_org AND class_id=p_class AND enabled AND (p_id IS NULL OR id<>p_id) AND (session IS NULL OR session='full' OR p_session='full' OR session=p_session)) THEN RAISE EXCEPTION 'This class already has a teacher for that session. Edit or disable that assignment first.' USING ERRCODE='22023';END IF;
 IF p_id IS NULL THEN INSERT INTO public.rr_teacher_portals(organization_id,class_id,name,email,session,enabled) VALUES(p_org,p_class,btrim(p_name),email_value,p_session,p_enabled) RETURNING to_jsonb(rr_teacher_portals.*) INTO result;
 ELSE UPDATE public.rr_teacher_portals SET name=btrim(p_name),email=email_value,class_id=p_class,session=p_session,enabled=p_enabled,revision=revision+1 WHERE id=p_id RETURNING to_jsonb(rr_teacher_portals.*) INTO result;END IF;
 INSERT INTO public.rr_motivation_events(organization_id,actor_id,kind,detail) VALUES(p_org,auth.uid(),'teacher_assignment',jsonb_build_object('before',to_jsonb(old),'after',result));RETURN result;
END $$;
CREATE OR REPLACE FUNCTION public.rr_motivation_order_plan(p_org uuid,p_program uuid,p_data jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE cls uuid;student_count int;full_count int;morning_count int;afternoon_count int;unknown_count int;total_each int;am int;pm int;rows jsonb:='[]';row jsonb;teacher record;amount int;grand_total int:=0;start_day date;end_day date;points numeric;zone text;settings jsonb;members jsonb;result jsonb;
BEGIN
 PERFORM public.rr_motivation_require_access(p_org);
 IF NOT EXISTS(SELECT 1 FROM public.rr_motivation_programs WHERE organization_id=p_org AND id=p_program) THEN RAISE EXCEPTION 'Choose a school program' USING ERRCODE='42501';END IF;
 IF jsonb_typeof(p_data) IS DISTINCT FROM 'object' OR jsonb_typeof(p_data->'classes') IS DISTINCT FROM 'array' OR jsonb_array_length(p_data->'classes') NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'Choose classes' USING ERRCODE='22023';END IF;
 IF (SELECT count(*) FROM jsonb_array_elements_text(p_data->'classes'))<>(SELECT count(DISTINCT value) FROM jsonb_array_elements_text(p_data->'classes')) THEN RAISE EXCEPTION 'Duplicate class' USING ERRCODE='22023';END IF;
 IF coalesce(p_data->>'from','') !~ '^\d{4}-\d{2}-\d{2}$' OR coalesce(p_data->>'through','') !~ '^\d{4}-\d{2}-\d{2}$' THEN RAISE EXCEPTION 'Choose valid from and through dates' USING ERRCODE='22023';END IF;
 start_day:=(p_data->>'from')::date;end_day:=(p_data->>'through')::date;
 IF end_day<start_day OR end_day-start_day>366 THEN RAISE EXCEPTION 'Choose an ordered date range of at most 367 days' USING ERRCODE='22023';END IF;
 IF coalesce(p_data->>'each','') !~ '^[0-9]+$' OR coalesce(p_data->>'points','') !~ '^[0-9]+(\.[0-9]+)?$' THEN RAISE EXCEPTION 'Enter cards per child and points per card' USING ERRCODE='22023';END IF;
 total_each:=(p_data->>'each')::int;points:=(p_data->>'points')::numeric;
 IF total_each NOT BETWEEN 1 AND 1000 OR points NOT BETWEEN 0 AND 1000000 THEN RAISE EXCEPTION 'Card count or points outside supported range' USING ERRCODE='22023';END IF;
 SELECT coalesce((SELECT o.settings FROM public.rr_motivation_options o WHERE organization_id=p_org),public.rr_motivation_defaults()) INTO settings;zone:=settings->>'timezone';
 IF NOT coalesce((settings->>'cards_enabled')::boolean,false) THEN RAISE EXCEPTION 'Enable cards in Program Settings first' USING ERRCODE='22023';END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=zone) THEN RAISE EXCEPTION 'Set the school timezone first' USING ERRCODE='22023';END IF;
 FOR cls IN SELECT value::uuid FROM jsonb_array_elements_text(p_data->'classes') LOOP
  IF NOT EXISTS(SELECT 1 FROM public.classes c JOIN public.school_years y ON y.id=c.school_year_id AND y.is_current WHERE c.id=cls AND c.organization_id=p_org AND c.is_active) THEN RAISE EXCEPTION 'Choose current classes from this school' USING ERRCODE='42501';END IF;
  SELECT count(*),coalesce(jsonb_agg(s.id ORDER BY s.id),'[]') INTO student_count,members FROM public.students s JOIN public.student_class_assignments a ON a.student_id=s.id AND a.organization_id=p_org AND a.is_current WHERE s.organization_id=p_org AND NOT s.is_archived AND a.class_id=cls;
  IF student_count=0 THEN RAISE EXCEPTION 'A selected class has no active students' USING ERRCODE='22023';END IF;
  SELECT count(*) FILTER(WHERE session='full'),count(*) FILTER(WHERE session='morning'),count(*) FILTER(WHERE session='afternoon'),count(*) FILTER(WHERE session IS NULL) INTO full_count,morning_count,afternoon_count,unknown_count FROM public.rr_teacher_portals WHERE organization_id=p_org AND class_id=cls AND enabled;
  IF unknown_count>0 OR NOT ((full_count=1 AND morning_count=0 AND afternoon_count=0) OR (full_count=0 AND morning_count=1 AND afternoon_count=1)) THEN RAISE EXCEPTION 'Each class needs one full-day teacher OR one morning and one afternoon teacher. Check Teacher Portals.' USING ERRCODE='22023';END IF;
  IF full_count=0 THEN
   IF coalesce(p_data->>'morning','') !~ '^[0-9]+$' OR coalesce(p_data->>'afternoon','') !~ '^[0-9]+$' THEN RAISE EXCEPTION 'Enter both session allocations for split classes' USING ERRCODE='22023';END IF;
   am:=(p_data->>'morning')::int;pm:=(p_data->>'afternoon')::int;
   IF am<0 OR pm<0 OR am+pm<>total_each THEN RAISE EXCEPTION 'Morning plus afternoon must equal cards per child' USING ERRCODE='22023';END IF;
  END IF;
  FOR teacher IN SELECT * FROM public.rr_teacher_portals WHERE organization_id=p_org AND class_id=cls AND enabled ORDER BY session,id LOOP
   amount:=CASE teacher.session WHEN 'full' THEN total_each WHEN 'morning' THEN am ELSE pm END;
   row:=jsonb_build_object('teacher_id',teacher.id,'teacher',teacher.name,'revision',teacher.revision,'session',teacher.session,'class_id',cls,'class_name',(SELECT name FROM public.classes WHERE id=cls),'students',student_count,'members',members,'each',amount,'count',amount*student_count);
   rows:=rows||jsonb_build_array(row);grand_total:=grand_total+amount*student_count;
  END LOOP;
 END LOOP;
 IF grand_total>20000 THEN RAISE EXCEPTION 'An order may contain at most 20,000 cards. Choose fewer classes or cards.' USING ERRCODE='22023';END IF;
 result:=jsonb_build_object('rows',rows,'total',grand_total,'timezone',zone,'from',start_day,'through',end_day,'points',points);
 RETURN result||jsonb_build_object('token',md5(result::text));
END $$;
CREATE OR REPLACE FUNCTION public.rr_motivation_order_create(p_org uuid,p_program uuid,p_request uuid,p_data jsonb,p_token text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE plan jsonb;old public.rr_motivation_orders%ROWTYPE;row jsonb;batch uuid;order_id uuid;batches jsonb:='[]';payload jsonb;
BEGIN
 PERFORM public.rr_motivation_require_access(p_org);IF p_request IS NULL THEN RAISE EXCEPTION 'Missing request' USING ERRCODE='22023';END IF;
 PERFORM 1 FROM public.organizations WHERE id=p_org FOR UPDATE;payload:=jsonb_build_object('program',p_program,'data',p_data,'token',p_token);
 SELECT * INTO old FROM public.rr_motivation_orders WHERE organization_id=p_org AND request_id=p_request;
 IF FOUND THEN IF old.payload<>payload THEN RAISE EXCEPTION 'Request already used' USING ERRCODE='22023';END IF;RETURN jsonb_build_object('id',old.id,'total',old.plan->'total');END IF;
 plan:=public.rr_motivation_order_plan(p_org,p_program,p_data);
 IF p_token IS DISTINCT FROM plan->>'token' THEN RAISE EXCEPTION 'Roster or teacher assignments changed. Preview again.' USING ERRCODE='40001';END IF;
 FOR row IN SELECT value FROM jsonb_array_elements(plan->'rows') LOOP
  IF (row->>'count')::int=0 THEN CONTINUE;END IF;batch:=gen_random_uuid();
  INSERT INTO public.rr_motivation_cards(organization_id,program_id,class_id,points,teacher,batch_id,valid_from,expires_at,valid_from_date,valid_through_date)
  SELECT p_org,p_program,(row->>'class_id')::uuid,(plan->>'points')::numeric,row->>'teacher',batch,(plan->>'from')::date::timestamp AT TIME ZONE (plan->>'timezone'),((plan->>'through')::date+1)::timestamp AT TIME ZONE (plan->>'timezone'),(plan->>'from')::date,(plan->>'through')::date FROM generate_series(1,(row->>'count')::int);
  batches:=batches||jsonb_build_array(row-'members'||jsonb_build_object('batch_id',batch));
 END LOOP;
 INSERT INTO public.rr_motivation_orders(organization_id,program_id,request_id,payload,plan,batches) VALUES(p_org,p_program,p_request,payload,plan,batches) RETURNING id INTO order_id;
 INSERT INTO public.rr_motivation_events(organization_id,program_id,actor_id,kind,detail) VALUES(p_org,p_program,auth.uid(),'cards_generated',jsonb_build_object('order',order_id,'plan',plan-'rows','batches',batches));
 RETURN jsonb_build_object('id',order_id,'total',plan->'total');
END $$;
CREATE OR REPLACE FUNCTION public.rr_motivation_orders_read(p_org uuid,p_program uuid,p_order uuid DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE selected public.rr_motivation_orders%ROWTYPE;
BEGIN
 PERFORM public.rr_motivation_require_access(p_org);
 IF p_order IS NULL THEN RETURN coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY created_at DESC) FROM (SELECT id,created_at,plan->>'from' AS valid_from,plan->>'through' AS valid_through,plan->'total' AS total FROM public.rr_motivation_orders WHERE organization_id=p_org AND program_id=p_program ORDER BY created_at DESC LIMIT 100) t),'[]');END IF;
 SELECT * INTO selected FROM public.rr_motivation_orders WHERE id=p_order AND organization_id=p_org AND program_id=p_program;
 IF NOT FOUND THEN RAISE EXCEPTION 'Order not found' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('batches',selected.batches,'cards',coalesce((SELECT jsonb_agg(to_jsonb(c) ORDER BY card_number) FROM public.rr_motivation_cards c WHERE c.organization_id=p_org AND c.program_id=p_program AND c.batch_id IN (SELECT (value->>'batch_id')::uuid FROM jsonb_array_elements(selected.batches))),'[]'));
END $$;
REVOKE ALL ON FUNCTION public.rr_motivation_teacher_save(uuid,uuid,bigint,text,text,uuid,text,boolean),public.rr_motivation_order_plan(uuid,uuid,jsonb),public.rr_motivation_order_create(uuid,uuid,uuid,jsonb,text),public.rr_motivation_orders_read(uuid,uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_motivation_teacher_save(uuid,uuid,bigint,text,text,uuid,text,boolean),public.rr_motivation_order_plan(uuid,uuid,jsonb),public.rr_motivation_order_create(uuid,uuid,uuid,jsonb,text),public.rr_motivation_orders_read(uuid,uuid,uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_motivation_command(p_org uuid,p_request uuid,p_action text,p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE v_payload jsonb;v_old jsonb;v_result jsonb;v_program uuid;v_student uuid;v_class uuid;v_year uuid;v_event bigint;
 v_settings jsonb;v_rev bigint;v_points numeric;v_config jsonb;v_subject jsonb;v_score numeric;v_card public.rr_motivation_cards%ROWTYPE;
 row_data jsonb;before_data jsonb;v_name text;v_phone text;v_count int;v_batch uuid;v_outcome text:='accepted';v_message text:='Saved'; k text;
BEGIN
 PERFORM public.rr_motivation_require_access(p_org);
 IF p_request IS NULL OR p_action IS NULL OR jsonb_typeof(p_data) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Invalid request' USING ERRCODE='22023';END IF;
 v_payload:=jsonb_build_object('action',p_action,'data',p_data);
 PERFORM 1 FROM public.organizations WHERE id=p_org FOR UPDATE;
 SELECT payload,result INTO v_old,v_result FROM public.rr_motivation_requests WHERE organization_id=p_org AND request_id=p_request;
 IF FOUND THEN IF v_old<>v_payload THEN RAISE EXCEPTION 'Request already used' USING ERRCODE='22023';END IF;RETURN v_result;END IF;
 SELECT settings,revision INTO v_settings,v_rev FROM public.rr_motivation_options WHERE organization_id=p_org;
 v_settings:=coalesce(v_settings,public.rr_motivation_defaults());v_rev:=coalesce(v_rev,0);
 IF p_action IN ('points','exam','cards','redeem','unblock') THEN
  v_program:=(p_data->>'program')::uuid;
  SELECT config INTO v_config FROM public.rr_motivation_programs WHERE id=v_program AND organization_id=p_org;
  IF NOT FOUND THEN RAISE EXCEPTION 'Select a school program' USING ERRCODE='42501';END IF;
 END IF;
 IF p_action IN ('points','exam','redeem') THEN
  v_student:=(p_data->>'student')::uuid;
  PERFORM 1 FROM public.students WHERE id=v_student AND organization_id=p_org AND NOT is_archived FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Student not found' USING ERRCODE='42501';END IF;
  SELECT class_id INTO v_class FROM public.student_class_assignments WHERE student_id=v_student AND organization_id=p_org AND is_current LIMIT 1;
 END IF;
 IF p_action='workspace_open' THEN
  INSERT INTO public.rr_motivation_events(organization_id,actor_id,kind,detail) VALUES(p_org,auth.uid(),'workspace_open',jsonb_build_object('source','admin_workspace'));
 ELSIF p_action='settings' THEN
  IF (p_data->>'revision')::bigint IS DISTINCT FROM v_rev THEN RAISE EXCEPTION 'Settings changed. Reload before saving.' USING ERRCODE='40001';END IF;
  v_old:=p_data->'settings';
  IF jsonb_typeof(v_old) IS DISTINCT FROM 'object' OR (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(v_old) key) IS DISTINCT FROM (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(public.rr_motivation_defaults()) key) THEN RAISE EXCEPTION 'Invalid settings fields' USING ERRCODE='22023';END IF;
  FOREACH k IN ARRAY ARRAY['cards_enabled','reveal_next_day','teacher_cards','phone_frozen','allow_home','allow_father','allow_mother','allow_other','display_enabled','show_birthdays'] LOOP
   IF jsonb_typeof(v_old->k) IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'Invalid switch' USING ERRCODE='22023';END IF;
  END LOOP;
  IF v_old->'weekly_cap'<>'null'::jsonb AND (jsonb_typeof(v_old->'weekly_cap') IS DISTINCT FROM 'number' OR (v_old->>'weekly_cap')::numeric NOT BETWEEN 1 AND 1000 OR trunc((v_old->>'weekly_cap')::numeric)<>(v_old->>'weekly_cap')::numeric) THEN RAISE EXCEPTION 'Enter a valid weekly cap' USING ERRCODE='22023';END IF;
  IF (v_old->>'cards_enabled')::boolean AND v_old->'weekly_cap'='null'::jsonb THEN RAISE EXCEPTION 'Set your weekly cap before enabling cards' USING ERRCODE='22023';END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=v_old->>'timezone') THEN RAISE EXCEPTION 'Confirm a timezone' USING ERRCODE='22023';END IF;
  IF (v_old->>'display_enabled')::boolean AND (coalesce(v_old->>'display_start','')!~'^([01][0-9]|2[0-3]):[0-5][0-9]$' OR coalesce(v_old->>'display_end','')!~'^([01][0-9]|2[0-3]):[0-5][0-9]$') THEN RAISE EXCEPTION 'Choose display start and end times' USING ERRCODE='22023';END IF;
  IF jsonb_typeof(v_old->'display_days') IS DISTINCT FROM 'array' OR jsonb_typeof(v_old->'blocked_students') IS DISTINCT FROM 'array' OR jsonb_typeof(v_old->'playlist') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Invalid lists' USING ERRCODE='22023';END IF;
  FOR row_data IN SELECT value FROM jsonb_array_elements(v_old->'display_days') LOOP IF row_data::text NOT IN ('0','1','2','3','4','5','6') THEN RAISE EXCEPTION 'Invalid day' USING ERRCODE='22023';END IF;END LOOP;
  FOR row_data IN SELECT value FROM jsonb_array_elements(v_old->'blocked_students') LOOP IF NOT EXISTS(SELECT 1 FROM public.students WHERE id=(row_data#>>'{}')::uuid AND organization_id=p_org) THEN RAISE EXCEPTION 'Invalid blocked student' USING ERRCODE='42501';END IF;END LOOP;
  IF jsonb_array_length(v_old->'playlist')>100 OR ((v_old->>'display_enabled')::boolean AND jsonb_array_length(v_old->'playlist')=0) THEN RAISE EXCEPTION 'Playlist needs 1 to 100 slides' USING ERRCODE='22023';END IF;
  FOR row_data IN SELECT value FROM jsonb_array_elements(v_old->'playlist') LOOP
   IF coalesce(row_data->>'type','') NOT IN ('totals','date','text','image','video','background_image','background_video') OR jsonb_typeof(row_data->'seconds') IS DISTINCT FROM 'number' OR (row_data->>'seconds')::numeric NOT BETWEEN 2 AND 600 OR length(coalesce(row_data->>'text',''))>1000 THEN RAISE EXCEPTION 'Invalid slide' USING ERRCODE='22023';END IF;
   IF row_data->>'type' IN ('image','video','background_image','background_video') AND (coalesce(row_data->>'path','') NOT LIKE p_org::text||'/%' OR row_data->>'path' LIKE '%..%') THEN RAISE EXCEPTION 'Media must belong to this school' USING ERRCODE='42501';END IF;
  END LOOP;
  INSERT INTO public.rr_motivation_options VALUES(p_org,v_rev+1,v_old,now()) ON CONFLICT(organization_id) DO UPDATE SET revision=excluded.revision,settings=excluded.settings,updated_at=now();
  INSERT INTO public.rr_motivation_events(organization_id,actor_id,kind,detail) VALUES(p_org,auth.uid(),'settings',jsonb_build_object('before',v_settings,'after',v_old));
 ELSIF p_action='bulk_students' THEN
  IF jsonb_typeof(p_data->'rows') IS DISTINCT FROM 'array' OR jsonb_array_length(p_data->'rows') NOT BETWEEN 1 AND 200 THEN RAISE EXCEPTION 'Choose 1 to 200 students' USING ERRCODE='22023';END IF;
  FOR row_data IN SELECT value FROM jsonb_array_elements(p_data->'rows') LOOP
   v_student:=(row_data->>'id')::uuid;v_name:=regexp_replace(btrim(row_data->>'name'),'\s+',' ','g');v_phone:=regexp_replace(coalesce(row_data->>'phone',''),'[^0-9]','','g');v_class:=(row_data->>'class_id')::uuid;
   SELECT jsonb_build_object('name',name,'phone',coalesce(phone,''),'class_id',(SELECT class_id FROM public.student_class_assignments WHERE organization_id=p_org AND student_id=v_student AND is_current LIMIT 1)) INTO before_data FROM public.students WHERE id=v_student AND organization_id=p_org AND NOT is_archived FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'Student not found' USING ERRCODE='42501';END IF;
   IF before_data IS DISTINCT FROM row_data->'before' THEN RAISE EXCEPTION 'Student changed. Reload before editing.' USING ERRCODE='40001';END IF;
   IF v_name IS NULL OR length(v_name) NOT BETWEEN 1 AND 160 OR (length(v_phone)>0 AND length(v_phone) NOT BETWEEN 7 AND 15) THEN RAISE EXCEPTION 'Invalid student details' USING ERRCODE='22023';END IF;
   SELECT c.school_year_id INTO v_year FROM public.classes c JOIN public.school_years y ON y.id=c.school_year_id AND y.organization_id=p_org AND y.is_current WHERE c.id=v_class AND c.organization_id=p_org AND c.is_active;
   IF NOT FOUND THEN RAISE EXCEPTION 'Choose a current class' USING ERRCODE='22023';END IF;
   IF EXISTS(SELECT 1 FROM public.students s JOIN public.student_class_assignments a ON a.student_id=s.id AND a.organization_id=p_org AND a.is_current WHERE s.organization_id=p_org AND NOT s.is_archived AND s.id<>v_student AND a.class_id=v_class AND lower(regexp_replace(btrim(s.name),'\s+',' ','g'))=lower(v_name)) THEN RAISE EXCEPTION 'Duplicate name in this class' USING ERRCODE='23505';END IF;
   UPDATE public.students SET name=v_name,phone=nullif(v_phone,'') WHERE id=v_student AND organization_id=p_org;
   IF (before_data->>'class_id')::uuid IS DISTINCT FROM v_class THEN
    UPDATE public.student_class_assignments SET is_current=false,ended_at=now() WHERE student_id=v_student AND organization_id=p_org AND is_current;
    INSERT INTO public.student_class_assignments(organization_id,student_id,school_year_id,class_id,is_current) VALUES(p_org,v_student,v_year,v_class,true);
   END IF;
   INSERT INTO public.rr_motivation_events(organization_id,student_id,class_id,actor_id,kind,detail) VALUES(p_org,v_student,v_class,auth.uid(),'student_edit',jsonb_build_object('before',before_data,'after',row_data- 'before'));
  END LOOP;
 ELSIF p_action='class_rename' THEN
  v_class:=(p_data->>'class_id')::uuid;v_name:=btrim(p_data->>'name');
  SELECT jsonb_build_object('name',name) INTO before_data FROM public.classes WHERE id=v_class AND organization_id=p_org FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Class not found' USING ERRCODE='42501';END IF;
  IF before_data->>'name' IS DISTINCT FROM p_data->>'before' THEN RAISE EXCEPTION 'Class changed. Reload.' USING ERRCODE='40001';END IF;
  IF v_name IS NULL OR length(v_name) NOT BETWEEN 1 AND 80 THEN RAISE EXCEPTION 'Enter a class name' USING ERRCODE='22023';END IF;
  IF EXISTS(SELECT 1 FROM public.classes c WHERE c.organization_id=p_org AND c.id<>v_class AND c.school_year_id=(SELECT school_year_id FROM public.classes WHERE id=v_class) AND lower(btrim(c.name))=lower(v_name)) THEN RAISE EXCEPTION 'This class name already exists in the school year' USING ERRCODE='23505';END IF;
  UPDATE public.classes SET name=v_name WHERE id=v_class AND organization_id=p_org;
  INSERT INTO public.rr_motivation_events(organization_id,class_id,actor_id,kind,detail) VALUES(p_org,v_class,auth.uid(),'class_rename',jsonb_build_object('before',before_data,'name',v_name));
 ELSIF p_action IN ('points','exam') THEN
  IF length(btrim(coalesce(p_data->>'reason',''))) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'Enter a reason or exam title' USING ERRCODE='22023';END IF;
  IF p_action='points' THEN
   IF jsonb_typeof(p_data->'points') IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'Enter points' USING ERRCODE='22023';END IF;v_points:=(p_data->>'points')::numeric;
   IF v_points NOT BETWEEN -1000000 AND 1000000 OR v_points=0 THEN RAISE EXCEPTION 'Invalid points' USING ERRCODE='22023';END IF;
  ELSE
   SELECT value INTO v_subject FROM jsonb_array_elements(v_config->'subjects') WHERE value->>'name'=p_data->>'subject';
   IF v_subject IS NULL OR jsonb_typeof(p_data->'score') IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'Choose a subject and enter a score' USING ERRCODE='22023';END IF;
   v_score:=(p_data->>'score')::numeric;IF v_score<0 OR v_score>(v_subject->>'max_score')::numeric THEN RAISE EXCEPTION 'Score exceeds maximum' USING ERRCODE='22023';END IF;
   SELECT coalesce(max((value->>'minimum')::numeric),-1) INTO v_points FROM jsonb_array_elements(v_subject->'bands') WHERE (value->>'minimum')::numeric<=v_score;
   SELECT coalesce((SELECT (value->>'points')::numeric FROM jsonb_array_elements(v_subject->'bands') WHERE (value->>'minimum')::numeric=v_points),0) INTO v_points;
  END IF;
  INSERT INTO public.rr_motivation_events(organization_id,program_id,student_id,class_id,actor_id,kind,detail) VALUES(p_org,v_program,v_student,v_class,auth.uid(),p_action,p_data||jsonb_build_object('awarded',v_points,'rules_snapshot',v_subject)) RETURNING id INTO v_event;
  INSERT INTO public.rr_motivation_points(organization_id,program_id,student_id,points,event_id) VALUES(p_org,v_program,v_student,v_points,v_event);
 ELSIF p_action='cards' THEN
  IF NOT (v_settings->>'cards_enabled')::boolean THEN RAISE EXCEPTION 'Enable cards in Program Settings first' USING ERRCODE='22023';END IF;
  v_class:=(p_data->>'class_id')::uuid;v_count:=(p_data->>'count')::int;v_points:=(p_data->>'points')::numeric;v_batch:=gen_random_uuid();
  IF v_count IS NULL OR v_count NOT BETWEEN 1 AND 200 OR v_points IS NULL OR v_points NOT BETWEEN 0 AND 1000000 OR length(coalesce(p_data->>'teacher',''))>120 THEN RAISE EXCEPTION 'Invalid card batch' USING ERRCODE='22023';END IF;
  IF NOT EXISTS(SELECT 1 FROM public.classes WHERE id=v_class AND organization_id=p_org AND is_active) THEN RAISE EXCEPTION 'Class not found' USING ERRCODE='42501';END IF;
  INSERT INTO public.rr_motivation_cards(organization_id,program_id,class_id,points,teacher,batch_id,expires_at) SELECT p_org,v_program,v_class,v_points,CASE WHEN (v_settings->>'teacher_cards')::boolean THEN p_data->>'teacher' ELSE NULL END,v_batch,public.rr_motivation_card_expiry(p_org,now(),v_settings->>'timezone') FROM generate_series(1,v_count);
  INSERT INTO public.rr_motivation_events(organization_id,program_id,class_id,actor_id,kind,detail) VALUES(p_org,v_program,v_class,auth.uid(),'cards_generated',p_data||jsonb_build_object('batch_id',v_batch));
 ELSIF p_action IN ('redeem','unblock') THEN
  SELECT * INTO v_card FROM public.rr_motivation_cards WHERE organization_id=p_org AND program_id=v_program AND (code=upper(btrim(p_data->>'code')) OR card_number::text=btrim(p_data->>'code')) FOR UPDATE;
  IF NOT FOUND THEN v_outcome:='denied';v_message:='Card not found';
  ELSIF p_action='unblock' THEN
   IF length(btrim(coalesce(p_data->>'reason',''))) NOT BETWEEN 1 AND 500 OR v_card.status<>'blocked' THEN RAISE EXCEPTION 'Only blocked cards may be reopened; a reason is required' USING ERRCODE='22023';END IF;
   UPDATE public.rr_motivation_cards SET status='available' WHERE id=v_card.id;v_message:='Card reopened';
  ELSIF NOT (v_settings->>'cards_enabled')::boolean THEN v_outcome:='denied';v_message:='Cards are disabled';
  ELSIF v_card.status<>'available' THEN v_outcome:='denied';v_message:='Card is '||v_card.status;
  ELSIF v_card.valid_from IS NOT NULL AND now()<v_card.valid_from THEN v_outcome:='denied';v_message:='Card is not valid yet';
  ELSIF v_card.expires_at IS NOT NULL AND now()>=v_card.expires_at THEN v_outcome:='denied';v_message:='Card expired';
  ELSIF public.rr_motivation_daily_reached(p_org,v_program,v_student,now(),v_settings->>'timezone') THEN v_outcome:='denied';v_message:='Daily redemption cap reached';
  ELSIF v_class IS DISTINCT FROM v_card.class_id THEN
   UPDATE public.rr_motivation_cards SET status='blocked' WHERE id=v_card.id;v_outcome:='denied';v_message:='Wrong class. Card permanently blocked until an administrator reopens it.';
  ELSE
   SELECT count(*) INTO v_count FROM public.rr_motivation_events WHERE organization_id=p_org AND program_id=v_program AND student_id=v_student AND kind='redeem' AND outcome='accepted' AND created_at>=public.rr_motivation_week_start(p_org,now(),v_settings->>'timezone');
   IF v_count>=(v_settings->>'weekly_cap')::int THEN v_outcome:='denied';v_message:='Weekly redemption cap reached';
   ELSE UPDATE public.rr_motivation_cards SET status='redeemed',student_id=v_student WHERE id=v_card.id;v_points:=v_card.points;v_message:='Card redeemed';END IF;
  END IF;
  INSERT INTO public.rr_motivation_events(organization_id,program_id,student_id,class_id,actor_id,kind,outcome,detail) VALUES(p_org,v_program,v_student,coalesce(v_class,v_card.class_id),auth.uid(),p_action,v_outcome,p_data||jsonb_build_object('message',v_message,'awarded',v_points,'source','admin')) RETURNING id INTO v_event;
  IF p_action='redeem' AND v_outcome='accepted' THEN INSERT INTO public.rr_motivation_points(organization_id,program_id,student_id,points,event_id,available_at) VALUES(p_org,v_program,v_student,v_points,v_event,CASE WHEN (v_settings->>'reveal_next_day')::boolean THEN ((now() AT TIME ZONE (v_settings->>'timezone'))::date+1)::timestamp AT TIME ZONE (v_settings->>'timezone') ELSE now() END);END IF;
 ELSE RAISE EXCEPTION 'Unknown action' USING ERRCODE='22023';
 END IF;
 v_result:=jsonb_build_object('outcome',v_outcome,'message',v_message,'batch_id',v_batch);
 INSERT INTO public.rr_motivation_requests VALUES(p_org,p_request,v_payload,v_result);RETURN v_result;
END $$;

CREATE OR REPLACE FUNCTION public.rr_motivation_redeem_override(p_org uuid,p_request uuid,p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE payload jsonb;previous jsonb;result jsonb;card public.rr_motivation_cards%ROWTYPE;
 student uuid;program uuid;student_class uuid;settings jsonb;event bigint;used int;outcome text:='accepted';message text:='Card redeemed with class override';
BEGIN
 PERFORM public.rr_motivation_require_access(p_org);
 IF p_request IS NULL OR jsonb_typeof(p_data) IS DISTINCT FROM 'object' OR p_data->'confirmed' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'Confirm the class override first' USING ERRCODE='22023';END IF;
 payload:=jsonb_build_object('action','redeem_override','data',p_data);
 PERFORM 1 FROM public.organizations WHERE id=p_org FOR UPDATE;
 SELECT q.payload,q.result INTO previous,result FROM public.rr_motivation_requests q WHERE organization_id=p_org AND request_id=p_request;
 IF FOUND THEN IF previous<>payload THEN RAISE EXCEPTION 'Request already used' USING ERRCODE='22023';END IF;RETURN result;END IF;
 student:=(p_data->>'student')::uuid;program:=(p_data->>'program')::uuid;
 IF NOT EXISTS(SELECT 1 FROM public.rr_motivation_programs WHERE id=program AND organization_id=p_org) OR NOT EXISTS(SELECT 1 FROM public.students WHERE id=student AND organization_id=p_org AND NOT is_archived) THEN RAISE EXCEPTION 'Student or program not found' USING ERRCODE='42501';END IF;
 SELECT class_id INTO student_class FROM public.student_class_assignments WHERE organization_id=p_org AND student_id=student AND is_current LIMIT 1;
 SELECT * INTO card FROM public.rr_motivation_cards WHERE organization_id=p_org AND program_id=program AND (code=upper(btrim(p_data->>'code')) OR card_number::text=btrim(p_data->>'code')) FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Card not found' USING ERRCODE='22023';END IF;
 SELECT coalesce((SELECT o.settings FROM public.rr_motivation_options o WHERE organization_id=p_org),public.rr_motivation_defaults()) INTO settings;
 IF card.status<>'blocked' THEN outcome:='denied';message:='Only a card blocked by a class mismatch can be overridden';
 ELSIF student_class IS NULL OR student_class=card.class_id THEN outcome:='denied';message:='The student class changed. Review the card again';
 ELSIF NOT EXISTS(SELECT 1 FROM public.rr_motivation_events e WHERE e.organization_id=p_org AND e.program_id=program AND e.student_id=student AND e.actor_id=auth.uid() AND e.kind='redeem' AND e.outcome='denied' AND (upper(e.detail->>'code')=card.code OR e.detail->>'code'=card.card_number::text) AND e.detail->>'message' LIKE 'Wrong class.%') THEN outcome:='denied';message:='Scan this card for this student and confirm the warning first';
 ELSIF card.valid_from IS NOT NULL AND now()<card.valid_from THEN outcome:='denied';message:='Card is not valid yet';
 ELSIF card.expires_at IS NOT NULL AND now()>=card.expires_at THEN outcome:='denied';message:='Card expired';
 ELSIF public.rr_motivation_daily_reached(p_org,program,student,now(),settings->>'timezone') THEN outcome:='denied';message:='Daily redemption cap reached';
 ELSIF NOT (settings->>'cards_enabled')::boolean THEN outcome:='denied';message:='Cards are disabled';
 ELSE
  SELECT count(*) INTO used FROM public.rr_motivation_events e WHERE e.organization_id=p_org AND e.program_id=program AND e.student_id=student AND e.kind='redeem' AND e.outcome='accepted' AND e.created_at>=public.rr_motivation_week_start(p_org,now(),settings->>'timezone');
  IF settings->>'weekly_cap' IS NULL OR used>=(settings->>'weekly_cap')::int THEN outcome:='denied';message:='Weekly redemption cap reached';
  ELSE UPDATE public.rr_motivation_cards SET status='redeemed',student_id=student WHERE id=card.id;END IF;
 END IF;
 INSERT INTO public.rr_motivation_events(organization_id,program_id,student_id,class_id,actor_id,kind,outcome,detail)
 VALUES(p_org,program,student,student_class,auth.uid(),'redeem',outcome,p_data||jsonb_build_object('class_override',true,'original_card_class',card.class_id,'student_class',student_class,'message',message,'source','admin_scanner','awarded',CASE WHEN outcome='accepted' THEN card.points ELSE 0 END)) RETURNING id INTO event;
 IF outcome='accepted' THEN INSERT INTO public.rr_motivation_points(organization_id,program_id,student_id,points,event_id,available_at) VALUES(p_org,program,student,card.points,event,CASE WHEN (settings->>'reveal_next_day')::boolean THEN ((now() AT TIME ZONE (settings->>'timezone'))::date+1)::timestamp AT TIME ZONE (settings->>'timezone') ELSE now() END);END IF;
 result:=jsonb_build_object('outcome',outcome,'message',message);INSERT INTO public.rr_motivation_requests VALUES(p_org,p_request,payload,result);RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.rr_motivation_redeem_override(uuid,uuid,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_motivation_redeem_override(uuid,uuid,jsonb) TO authenticated;

NOTIFY pgrst,'reload schema';
COMMIT;
SELECT 'MOTIVATION_PRACTICAL_READY' AS result;
