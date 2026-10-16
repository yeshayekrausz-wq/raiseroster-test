-- Stage 5. Run once after Stage 4. Existing user-entered settings are preserved.
BEGIN;
CREATE TABLE public.rr_student_aliases(organization_id uuid NOT NULL REFERENCES public.organizations(id),student_id uuid PRIMARY KEY REFERENCES public.students(id) ON DELETE CASCADE,short_id bigint NOT NULL,UNIQUE(organization_id,short_id));
CREATE TABLE public.rr_motivation_designs(organization_id uuid PRIMARY KEY REFERENCES public.organizations(id),revision bigint NOT NULL,design jsonb NOT NULL);
CREATE TABLE public.rr_student_files(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,path text NOT NULL,title text NOT NULL,created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.rr_teacher_portals(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL REFERENCES public.organizations(id),class_id uuid NOT NULL REFERENCES public.classes(id),name text NOT NULL,email text NOT NULL,enabled boolean NOT NULL DEFAULT true,created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(organization_id,email,class_id));
ALTER TABLE public.rr_student_aliases ENABLE ROW LEVEL SECURITY;ALTER TABLE public.rr_motivation_designs ENABLE ROW LEVEL SECURITY;ALTER TABLE public.rr_student_files ENABLE ROW LEVEL SECURITY;ALTER TABLE public.rr_teacher_portals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rr_student_aliases,public.rr_motivation_designs,public.rr_student_files,public.rr_teacher_portals FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.rr_motivation_student_snapshot(p_student uuid) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('name',s.name,'phone',coalesce(s.phone,''),'home_phone',coalesce(s.home_phone,''),'father_phone',coalesce(s.father_phone,''),'mother_phone',coalesce(s.mother_phone,''),'other_phone',coalesce(s.other_phone,''),'address',coalesce(s.address,''),'gregorian_birthday',coalesce(s.gregorian_birthday::text,''),'hebrew_birthday',coalesce(s.hebrew_birthday,''),'notes',coalesce(s.notes,''),'photo_url',coalesce(s.photo_url,''),'class_id',(SELECT class_id FROM public.student_class_assignments WHERE student_id=s.id AND organization_id=s.organization_id AND is_current LIMIT 1)) FROM public.students s WHERE id=p_student
$$;
REVOKE ALL ON FUNCTION public.rr_motivation_student_snapshot(uuid) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.rr_motivation_roster_v5(p_org uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE result jsonb;v_max bigint;v_students jsonb;
BEGIN
 PERFORM public.rr_motivation_require_access(p_org);PERFORM 1 FROM public.organizations WHERE id=p_org FOR UPDATE;
 SELECT coalesce(max(short_id),0) INTO v_max FROM public.rr_student_aliases WHERE organization_id=p_org;
 INSERT INTO public.rr_student_aliases SELECT p_org,id,v_max+row_number() OVER(ORDER BY created_at,id) FROM public.students s WHERE s.organization_id=p_org AND NOT EXISTS(SELECT 1 FROM public.rr_student_aliases WHERE student_id=s.id);
 result:=public.rr_motivation_roster(p_org);
 SELECT coalesce(jsonb_agg(value||public.rr_motivation_student_snapshot((value->>'id')::uuid)||jsonb_build_object('snapshot',public.rr_motivation_student_snapshot((value->>'id')::uuid),'short_id',(SELECT short_id FROM public.rr_student_aliases WHERE student_id=(value->>'id')::uuid),'files',coalesce((SELECT jsonb_agg(to_jsonb(f)) FROM public.rr_student_files f WHERE f.organization_id=p_org AND f.student_id=(value->>'id')::uuid),'[]'::jsonb))),'[]') INTO v_students FROM jsonb_array_elements(result->'students');
 RETURN jsonb_set(result,'{students}',v_students);
END $$;
CREATE FUNCTION public.rr_motivation_extras(p_org uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.rr_motivation_require_access(p_org);
 RETURN jsonb_build_object('design',coalesce((SELECT design FROM public.rr_motivation_designs WHERE organization_id=p_org),'{"lines":[]}'::jsonb),'revision',coalesce((SELECT revision FROM public.rr_motivation_designs WHERE organization_id=p_org),0),'portals',coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY created_at) FROM public.rr_teacher_portals p WHERE organization_id=p_org),'[]'::jsonb));
END $$;
CREATE FUNCTION public.rr_motivation_command_v5(p_org uuid,p_request uuid,p_action text,p_data jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE saved jsonb;payload jsonb;result jsonb:='{"outcome":"accepted","message":"Saved"}';r jsonb;before_data jsonb;old_rows jsonb:='[]';v_student uuid;v_class uuid;v_id uuid;v_key text;v_rev bigint;v_design jsonb;v_email text;v_path text;
BEGIN
 PERFORM public.rr_motivation_require_access(p_org);
 IF p_action NOT IN ('profiles','unassign','attachment','design','teacher_portal','teacher_toggle','support') THEN RETURN public.rr_motivation_command(p_org,p_request,p_action,p_data);END IF;
 IF p_request IS NULL OR jsonb_typeof(p_data) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Invalid request' USING ERRCODE='22023';END IF;
 payload:=jsonb_build_object('action',p_action,'data',p_data);PERFORM 1 FROM public.organizations WHERE id=p_org FOR UPDATE;
 SELECT q.payload,q.result INTO saved,result FROM public.rr_motivation_requests q WHERE organization_id=p_org AND request_id=p_request;
 IF FOUND THEN IF saved<>payload THEN RAISE EXCEPTION 'Request already used' USING ERRCODE='22023';END IF;RETURN result;END IF;
 result:='{"outcome":"accepted","message":"Saved"}';
 IF p_action='profiles' THEN
  IF jsonb_typeof(p_data->'rows') IS DISTINCT FROM 'array' OR jsonb_array_length(p_data->'rows') NOT BETWEEN 1 AND 200 THEN RAISE EXCEPTION 'Choose 1 to 200 students' USING ERRCODE='22023';END IF;
  FOR r IN SELECT value FROM jsonb_array_elements(p_data->'rows') LOOP
   v_student:=(r->>'id')::uuid;PERFORM 1 FROM public.students WHERE id=v_student AND organization_id=p_org AND NOT is_archived FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'Student not found' USING ERRCODE='42501';END IF;
   before_data:=public.rr_motivation_student_snapshot(v_student);IF before_data IS DISTINCT FROM r->'before' THEN RAISE EXCEPTION 'Student changed. Reload before saving.' USING ERRCODE='40001';END IF;
   FOREACH v_key IN ARRAY ARRAY['phone','home_phone','father_phone','mother_phone','other_phone'] LOOP
    IF coalesce(r->>v_key,'') !~ '^[0-9]{0,15}$' OR length(coalesce(r->>v_key,'')) BETWEEN 1 AND 6 THEN RAISE EXCEPTION 'Invalid phone number' USING ERRCODE='22023';END IF;
   END LOOP;
   IF length(coalesce(r->>'address',''))>500 OR length(coalesce(r->>'notes',''))>4000 OR length(coalesce(r->>'hebrew_birthday',''))>100 THEN RAISE EXCEPTION 'Field too long' USING ERRCODE='22023';END IF;
   IF coalesce(r->>'gregorian_birthday','')<>'' AND ((r->>'gregorian_birthday')::date>current_date OR (r->>'gregorian_birthday')::date<date '1900-01-01') THEN RAISE EXCEPTION 'Invalid birth date' USING ERRCODE='22023';END IF;
   v_path:=coalesce(r->>'photo_url','');IF v_path<>coalesce(before_data->>'photo_url','') AND v_path<>'' AND (v_path NOT LIKE 'motivation-private:'||p_org::text||'/students/'||v_student::text||'/%' OR v_path LIKE '%..%') THEN RAISE EXCEPTION 'Photo must be uploaded for this student' USING ERRCODE='42501';END IF;
   old_rows:=old_rows||jsonb_build_array(jsonb_build_object('id',v_student,'name',r->>'name','phone',r->>'phone','class_id',r->>'class_id','before',jsonb_build_object('name',before_data->>'name','phone',before_data->>'phone','class_id',before_data->'class_id')));
  END LOOP;
  PERFORM public.rr_motivation_command(p_org,gen_random_uuid(),'bulk_students',jsonb_build_object('rows',old_rows));
  FOR r IN SELECT value FROM jsonb_array_elements(p_data->'rows') LOOP
   v_student:=(r->>'id')::uuid;
   UPDATE public.students SET home_phone=nullif(r->>'home_phone',''),father_phone=nullif(r->>'father_phone',''),mother_phone=nullif(r->>'mother_phone',''),other_phone=nullif(r->>'other_phone',''),address=nullif(r->>'address',''),gregorian_birthday=nullif(r->>'gregorian_birthday','')::date,hebrew_birthday=nullif(r->>'hebrew_birthday',''),notes=nullif(r->>'notes',''),photo_url=nullif(r->>'photo_url','') WHERE id=v_student AND organization_id=p_org;
   INSERT INTO public.rr_motivation_events(organization_id,student_id,class_id,actor_id,kind,detail) VALUES(p_org,v_student,(r->>'class_id')::uuid,auth.uid(),'profile_edit',jsonb_build_object('before',r->'before','after',r-'before'));
  END LOOP;
 ELSIF p_action IN ('unassign','attachment') THEN
  v_student:=(p_data->>'student')::uuid;PERFORM 1 FROM public.students WHERE id=v_student AND organization_id=p_org AND NOT is_archived FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Student not found' USING ERRCODE='42501';END IF;
  IF p_action='unassign' THEN
   v_class:=(p_data->>'class_id')::uuid;UPDATE public.student_class_assignments SET is_current=false,ended_at=now() WHERE organization_id=p_org AND student_id=v_student AND class_id=v_class AND is_current;
   IF NOT FOUND THEN RAISE EXCEPTION 'Class assignment changed. Reload.' USING ERRCODE='40001';END IF;
  ELSE
   v_path:=p_data->>'path';IF v_path IS NULL OR v_path NOT LIKE p_org::text||'/students/'||v_student::text||'/%' OR v_path LIKE '%..%' OR length(btrim(coalesce(p_data->>'title',''))) NOT BETWEEN 1 AND 200 THEN RAISE EXCEPTION 'Invalid student file' USING ERRCODE='22023';END IF;
   INSERT INTO public.rr_student_files(organization_id,student_id,path,title) VALUES(p_org,v_student,v_path,p_data->>'title');
  END IF;
  INSERT INTO public.rr_motivation_events(organization_id,student_id,class_id,actor_id,kind,detail) VALUES(p_org,v_student,v_class,auth.uid(),p_action,p_data);
 ELSIF p_action='design' THEN
  SELECT revision INTO v_rev FROM public.rr_motivation_designs WHERE organization_id=p_org;IF (p_data->>'revision')::bigint IS DISTINCT FROM coalesce(v_rev,0) THEN RAISE EXCEPTION 'Card layout changed. Reload.' USING ERRCODE='40001';END IF;
  v_design:=p_data->'design';IF jsonb_typeof(v_design->'lines') IS DISTINCT FROM 'array' OR jsonb_array_length(v_design->'lines')>12 THEN RAISE EXCEPTION 'Maximum 12 card lines' USING ERRCODE='22023';END IF;
  FOR r IN SELECT value FROM jsonb_array_elements(v_design->'lines') LOOP
   IF jsonb_typeof(r->'text') IS DISTINCT FROM 'string' OR length(r->>'text')>500 OR coalesce(r->>'align','') NOT IN ('left','center','right') OR coalesce(r->>'size','') NOT IN ('small','normal','large') THEN RAISE EXCEPTION 'Invalid card line' USING ERRCODE='22023';END IF;
  END LOOP;
  INSERT INTO public.rr_motivation_designs VALUES(p_org,coalesce(v_rev,0)+1,v_design) ON CONFLICT(organization_id) DO UPDATE SET revision=excluded.revision,design=excluded.design;
 ELSIF p_action='teacher_portal' THEN
  v_class:=(p_data->>'class_id')::uuid;v_email:=lower(btrim(p_data->>'email'));
  IF NOT EXISTS(SELECT 1 FROM public.classes WHERE id=v_class AND organization_id=p_org AND is_active) THEN RAISE EXCEPTION 'Select a school class' USING ERRCODE='42501';END IF;
  IF length(btrim(coalesce(p_data->>'name',''))) NOT BETWEEN 1 AND 120 OR v_email IS NULL OR v_email !~ '^[^ @]+@[^ @]+\.[^ @]+$' OR length(v_email)>254 THEN RAISE EXCEPTION 'Enter a teacher name and email' USING ERRCODE='22023';END IF;
  IF EXISTS(SELECT 1 FROM auth.users u JOIN public.organization_members m ON m.user_id=u.id WHERE lower(u.email)=v_email) THEN RAISE EXCEPTION 'Use a separate teacher login. This email already has school administrator membership.' USING ERRCODE='22023';END IF;
  INSERT INTO public.rr_teacher_portals(organization_id,class_id,name,email) VALUES(p_org,v_class,btrim(p_data->>'name'),v_email) RETURNING id INTO v_id;result:=result||jsonb_build_object('id',v_id);
 ELSIF p_action='teacher_toggle' THEN
  IF jsonb_typeof(p_data->'enabled') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'Invalid state' USING ERRCODE='22023';END IF;
  UPDATE public.rr_teacher_portals SET enabled=(p_data->>'enabled')::boolean WHERE id=(p_data->>'id')::uuid AND organization_id=p_org;
  IF NOT FOUND THEN RAISE EXCEPTION 'Portal not found' USING ERRCODE='42501';END IF;
 ELSIF p_action='support' THEN
  IF length(btrim(coalesce(p_data->>'body',''))) NOT BETWEEN 1 AND 5000 THEN RAISE EXCEPTION 'Enter a message (maximum 5000 characters)' USING ERRCODE='22023';END IF;
  IF to_regclass('public.support_threads') IS NULL OR to_regclass('public.support_messages') IS NULL THEN RAISE EXCEPTION 'Support inbox is not installed. Contact the platform administrator.' USING ERRCODE='22023';END IF;
  IF coalesce(p_data->>'thread','')='' THEN INSERT INTO public.support_threads(organization_id,created_by,scope,category,subject) VALUES(p_org,auth.uid(),'PRIVATE_USER','problem',left(p_data->>'body',80)) RETURNING id INTO v_id;
  ELSE v_id:=(p_data->>'thread')::uuid;IF NOT EXISTS(SELECT 1 FROM public.support_threads WHERE id=v_id AND organization_id=p_org AND created_by=auth.uid()) THEN RAISE EXCEPTION 'Thread not found' USING ERRCODE='42501';END IF;END IF;
  INSERT INTO public.support_messages(thread_id,organization_id,sender_user_id,body) VALUES(v_id,p_org,auth.uid(),p_data->>'body');
  UPDATE public.support_threads SET updated_at=now() WHERE id=v_id;result:=result||jsonb_build_object('id',v_id);
 END IF;
 INSERT INTO public.rr_motivation_requests VALUES(p_org,p_request,payload,result);RETURN result;
END $$;
CREATE FUNCTION public.rr_motivation_support(p_org uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM public.rr_motivation_require_access(p_org);
 RETURN coalesce((SELECT jsonb_agg(to_jsonb(t)||jsonb_build_object('messages',coalesce((SELECT jsonb_agg(to_jsonb(m) ORDER BY created_at) FROM public.support_messages m WHERE m.thread_id=t.id AND m.organization_id=p_org),'[]'::jsonb)) ORDER BY updated_at DESC) FROM public.support_threads t WHERE t.organization_id=p_org AND t.created_by=auth.uid()),'[]'::jsonb);
END $$;
CREATE FUNCTION public.rr_teacher_view(p_portal uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE p public.rr_teacher_portals%ROWTYPE;v_students jsonb;v_programs jsonb;
BEGIN
 SELECT t.* INTO p FROM public.rr_teacher_portals t JOIN auth.users u ON lower(u.email)=t.email AND u.id=auth.uid() AND u.email_confirmed_at IS NOT NULL WHERE t.id=p_portal AND t.enabled;
 IF NOT FOUND OR EXISTS(SELECT 1 FROM public.organization_members WHERE user_id=auth.uid()) THEN RAISE EXCEPTION 'This verified teacher login is not assigned to the portal' USING ERRCODE='42501';END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('name',s.name,'student_number',a.short_id,'points',coalesce((SELECT jsonb_object_agg(program_id,total) FROM (SELECT program_id,sum(points) total FROM public.rr_motivation_points WHERE organization_id=p.organization_id AND student_id=s.id AND available_at<=now() GROUP BY program_id) totals),'{}'::jsonb)) ORDER BY s.name),'[]') INTO v_students FROM public.students s JOIN public.student_class_assignments c ON c.student_id=s.id AND c.organization_id=p.organization_id AND c.class_id=p.class_id AND c.is_current LEFT JOIN public.rr_student_aliases a ON a.student_id=s.id AND a.organization_id=p.organization_id WHERE s.organization_id=p.organization_id AND NOT s.is_archived;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',config->>'name','term',config->>'term_name')),'[]') INTO v_programs FROM public.rr_motivation_programs WHERE organization_id=p.organization_id;
 RETURN jsonb_build_object('teacher',p.name,'class',(SELECT name FROM public.classes WHERE id=p.class_id AND organization_id=p.organization_id),'students',v_students,'programs',v_programs);
END $$;
REVOKE ALL ON FUNCTION public.rr_motivation_roster_v5(uuid),public.rr_motivation_extras(uuid),public.rr_motivation_command_v5(uuid,uuid,text,jsonb),public.rr_motivation_support(uuid),public.rr_teacher_view(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_motivation_roster_v5(uuid),public.rr_motivation_extras(uuid),public.rr_motivation_command_v5(uuid,uuid,text,jsonb),public.rr_motivation_support(uuid),public.rr_teacher_view(uuid) TO authenticated;
-- Permit student photos and PDF/card attachments in the existing private school bucket.
UPDATE storage.buckets SET allowed_mime_types=ARRAY['image/png','image/jpeg','image/webp','video/mp4','video/webm','application/pdf'] WHERE id='motivation-media' AND public=false;

CREATE OR REPLACE FUNCTION public.rr_motivation_defaults() RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
 SELECT '{"cards_enabled":false,"weekly_cap":null,"reveal_next_day":false,"teacher_cards":false,"phone_frozen":true,"allow_home":true,"allow_father":false,"allow_mother":false,"allow_other":false,"blocked_students":[],"display_enabled":false,"timezone":"","display_start":"","display_end":"","display_days":[],"show_birthdays":false,"playlist":[]}'::jsonb
$$;
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
   SELECT count(*) INTO v_count FROM public.rr_motivation_events WHERE organization_id=p_org AND program_id=v_program AND student_id=v_student AND kind='redeem' AND outcome='accepted' AND created_at>=date_trunc('week',now() AT TIME ZONE (v_settings->>'timezone')) AT TIME ZONE (v_settings->>'timezone');
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

NOTIFY pgrst,'reload schema';
COMMIT;
SELECT 'MOTIVATION_STAGE5_READY' AS result;
