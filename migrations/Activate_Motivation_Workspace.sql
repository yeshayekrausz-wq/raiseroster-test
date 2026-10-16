-- Activate Hatzlacha setup and the shared school roster. Safe to rerun.
-- Existing complete installations and data are preserved. Partial installations stop with an error.
BEGIN;
DO $installer$
BEGIN
IF to_regclass('public.rr_motivation_programs') IS NULL AND to_regclass('public.rr_motivation_setup_audit') IS NULL AND to_regprocedure('public.rr_motivation_require_access(uuid)') IS NULL AND to_regprocedure('public.rr_motivation_list(uuid)') IS NULL AND to_regprocedure('public.rr_motivation_save(uuid,uuid,jsonb,bigint)') IS NULL THEN
EXECUTE $stage_a$

CREATE TABLE public.rr_motivation_programs (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
 product_key text NOT NULL DEFAULT 'hatzlacha' CHECK(product_key='hatzlacha'),
 config jsonb NOT NULL,
 revision bigint NOT NULL DEFAULT 1 CHECK(revision>0),
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON public.rr_motivation_programs(organization_id,updated_at DESC);
CREATE TABLE public.rr_motivation_setup_audit (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 organization_id uuid NOT NULL,
 program_id uuid NOT NULL,
 actor_id uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 before_config jsonb,
 after_config jsonb NOT NULL,
 revision bigint NOT NULL
);
CREATE INDEX ON public.rr_motivation_setup_audit(organization_id,program_id,created_at DESC);
ALTER TABLE public.rr_motivation_programs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rr_motivation_setup_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rr_motivation_programs,public.rr_motivation_setup_audit FROM PUBLIC,anon,authenticated;
REVOKE ALL ON SEQUENCE public.rr_motivation_setup_audit_id_seq FROM PUBLIC,anon,authenticated;

-- Central authorization boundary for this module. Existing accounts currently use
-- admin/super_admin only. Future verified purchases and per-user assignments must
-- be checked HERE (and on every future module RPC), never through menu toggles.
CREATE FUNCTION public.rr_motivation_require_access(p_org uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.organization_members
   WHERE organization_id=p_org AND user_id=auth.uid() AND role::text IN ('admin','super_admin'))
 THEN RAISE EXCEPTION 'School administrator access required' USING ERRCODE='42501'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.rr_motivation_require_access(uuid) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.rr_motivation_list(p_org uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.rr_motivation_require_access(p_org);
 SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.updated_at DESC,p.id),'[]'::jsonb) INTO result
 FROM public.rr_motivation_programs p WHERE organization_id=p_org;
 RETURN result;
END $$;

CREATE FUNCTION public.rr_motivation_save(p_org uuid,p_id uuid,p_config jsonb,p_expected_revision bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE old_config jsonb; rev bigint; subject jsonb; band jsonb; last_min numeric;
 max_score numeric; min_score numeric; points numeric; v_id uuid:=p_id; start_day date; end_day date;
BEGIN
 PERFORM public.rr_motivation_require_access(p_org);
 IF p_config IS NULL OR jsonb_typeof(p_config)<>'object' OR
 NOT p_config ?& ARRAY['name','term_name','start_date','end_date','target_points','subjects'] OR
 p_config-ARRAY['name','term_name','start_date','end_date','target_points','subjects']<>'{}'::jsonb OR
 jsonb_typeof(p_config->'name') IS DISTINCT FROM 'string' OR length(btrim(p_config->>'name')) NOT BETWEEN 1 AND 120 OR
 jsonb_typeof(p_config->'term_name') IS DISTINCT FROM 'string' OR length(btrim(p_config->>'term_name')) NOT BETWEEN 1 AND 120 OR
 jsonb_typeof(p_config->'start_date') IS DISTINCT FROM 'string' OR
 jsonb_typeof(p_config->'end_date') IS DISTINCT FROM 'string' OR
 jsonb_typeof(p_config->'subjects') IS DISTINCT FROM 'array'
 THEN RAISE EXCEPTION 'Invalid program details' USING ERRCODE='22023'; END IF;
 BEGIN
  IF (p_config->>'start_date') !~ '^\d{4}-\d{2}-\d{2}$' OR (p_config->>'end_date') !~ '^\d{4}-\d{2}-\d{2}$' THEN RAISE EXCEPTION 'Invalid dates'; END IF;
  start_day:=(p_config->>'start_date')::date; end_day:=(p_config->>'end_date')::date;
 EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'Enter valid term dates' USING ERRCODE='22023'; END;
 IF end_day<start_day THEN RAISE EXCEPTION 'Term end must follow its start' USING ERRCODE='22023'; END IF;
 IF p_config->'target_points'<>'null'::jsonb THEN
  IF jsonb_typeof(p_config->'target_points')<>'number' THEN RAISE EXCEPTION 'Invalid target' USING ERRCODE='22023'; END IF;
  IF (p_config->>'target_points')::numeric NOT BETWEEN 1 AND 1000000 THEN RAISE EXCEPTION 'Invalid target' USING ERRCODE='22023'; END IF;
 END IF;
 IF jsonb_array_length(p_config->'subjects')>30 THEN RAISE EXCEPTION 'Maximum 30 subjects' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_config->'subjects') s GROUP BY lower(btrim(s->>'name')) HAVING count(*)>1)
 THEN RAISE EXCEPTION 'Subject names must be unique' USING ERRCODE='22023'; END IF;
 FOR subject IN SELECT * FROM jsonb_array_elements(p_config->'subjects') LOOP
  IF jsonb_typeof(subject)<>'object' OR NOT subject ?& ARRAY['name','max_score','bands'] OR
   subject-ARRAY['name','max_score','bands']<>'{}'::jsonb OR
   jsonb_typeof(subject->'name') IS DISTINCT FROM 'string' OR length(btrim(subject->>'name')) NOT BETWEEN 1 AND 80 OR
   jsonb_typeof(subject->'max_score') IS DISTINCT FROM 'number' OR jsonb_typeof(subject->'bands') IS DISTINCT FROM 'array'
  THEN RAISE EXCEPTION 'Invalid subject' USING ERRCODE='22023'; END IF;
  max_score:=(subject->>'max_score')::numeric;
  IF max_score NOT BETWEEN 1 AND 10000 OR jsonb_array_length(subject->'bands') NOT BETWEEN 1 AND 50
  THEN RAISE EXCEPTION 'Set a valid maximum score and 1 to 50 rules' USING ERRCODE='22023'; END IF;
  last_min:=-1;
  FOR band IN SELECT * FROM jsonb_array_elements(subject->'bands') LOOP
   IF jsonb_typeof(band)<>'object' OR NOT band ?& ARRAY['minimum','points'] OR
    band-ARRAY['minimum','points']<>'{}'::jsonb OR
    jsonb_typeof(band->'minimum') IS DISTINCT FROM 'number' OR jsonb_typeof(band->'points') IS DISTINCT FROM 'number'
   THEN RAISE EXCEPTION 'Invalid score rule' USING ERRCODE='22023'; END IF;
   min_score:=(band->>'minimum')::numeric; points:=(band->>'points')::numeric;
   IF min_score<0 OR min_score>max_score OR min_score<=last_min OR points NOT BETWEEN 0 AND 1000000
   THEN RAISE EXCEPTION 'Rules must have unique ascending minimum scores and valid points' USING ERRCODE='22023'; END IF;
   last_min:=min_score;
  END LOOP;
 END LOOP;
 -- Lock even first creations, and reject stale edits instead of overwriting them.
 PERFORM 1 FROM public.organizations WHERE id=p_org FOR UPDATE;
 IF p_id IS NULL THEN
  IF p_expected_revision IS DISTINCT FROM 0 THEN RAISE EXCEPTION 'Invalid initial revision' USING ERRCODE='40001'; END IF;
  v_id:=gen_random_uuid(); rev:=0;
 ELSE
  SELECT config,revision INTO old_config,rev FROM public.rr_motivation_programs WHERE id=p_id AND organization_id=p_org FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Program not found in this school' USING ERRCODE='42501'; END IF;
  IF p_expected_revision IS DISTINCT FROM rev THEN RAISE EXCEPTION 'Another administrator changed this program. Reload before saving.' USING ERRCODE='40001'; END IF;
  IF old_config=p_config THEN RETURN jsonb_build_object('id',v_id,'revision',rev,'changed',false); END IF;
 END IF;
 INSERT INTO public.rr_motivation_programs(id,organization_id,config,revision) VALUES(v_id,p_org,p_config,rev+1)
 ON CONFLICT(id) DO UPDATE SET config=excluded.config,revision=excluded.revision,updated_at=now();
 INSERT INTO public.rr_motivation_setup_audit(organization_id,program_id,actor_id,before_config,after_config,revision)
 VALUES(p_org,v_id,auth.uid(),old_config,p_config,rev+1);
 RETURN jsonb_build_object('id',v_id,'revision',rev+1,'changed',true);
END $$;
REVOKE ALL ON FUNCTION public.rr_motivation_list(uuid),public.rr_motivation_save(uuid,uuid,jsonb,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_motivation_list(uuid),public.rr_motivation_save(uuid,uuid,jsonb,bigint) TO authenticated;


$stage_a$;
ELSIF to_regclass('public.rr_motivation_programs') IS NULL OR to_regclass('public.rr_motivation_setup_audit') IS NULL OR to_regprocedure('public.rr_motivation_require_access(uuid)') IS NULL OR to_regprocedure('public.rr_motivation_list(uuid)') IS NULL OR to_regprocedure('public.rr_motivation_save(uuid,uuid,jsonb,bigint)') IS NULL THEN
RAISE EXCEPTION 'Incomplete motivation stage A. Stop and review the prior installation.';
END IF;
IF to_regclass('public.rr_motivation_roster_actions') IS NULL AND to_regprocedure('public.rr_motivation_roster(uuid)') IS NULL AND to_regprocedure('public.rr_motivation_add_student(uuid,uuid,text,text,uuid)') IS NULL THEN
EXECUTE $stage_b$

CREATE TABLE public.rr_motivation_roster_actions (
 organization_id uuid NOT NULL REFERENCES public.organizations(id),
 request_id uuid NOT NULL,
 actor_id uuid NOT NULL,
 payload jsonb NOT NULL,
 student_id uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(organization_id,request_id)
);
ALTER TABLE public.rr_motivation_roster_actions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rr_motivation_roster_actions FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.rr_motivation_roster(p_org uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE v_classes jsonb;v_students jsonb;
BEGIN
 PERFORM public.rr_motivation_require_access(p_org);
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) ORDER BY c.sort_order,c.name,c.id),'[]') INTO v_classes
 FROM public.classes c JOIN public.school_years y ON y.id=c.school_year_id AND y.organization_id=p_org AND y.is_current
 WHERE c.organization_id=p_org AND c.is_active;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'phone',s.phone,
 'home_phone',s.home_phone,'father_phone',s.father_phone,'mother_phone',s.mother_phone,'other_phone',s.other_phone,
 'class_id',(SELECT a.class_id FROM public.student_class_assignments a
 JOIN public.classes c ON c.id=a.class_id AND c.organization_id=p_org AND c.is_active
 JOIN public.school_years y ON y.id=c.school_year_id AND y.organization_id=p_org AND y.is_current
 WHERE a.organization_id=p_org AND a.student_id=s.id AND a.is_current LIMIT 1)) ORDER BY s.name,s.id),'[]') INTO v_students
 FROM public.students s WHERE s.organization_id=p_org AND NOT s.is_archived;
 RETURN jsonb_build_object('classes',v_classes,'students',v_students);
END $$;
CREATE FUNCTION public.rr_motivation_add_student(p_org uuid,p_class uuid,p_name text,p_phone text,p_request uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE v_year uuid;v_id uuid;v_name text;v_phone text;v_payload jsonb;v_old jsonb;
BEGIN
 PERFORM public.rr_motivation_require_access(p_org);
 v_name:=regexp_replace(btrim(p_name),'\s+',' ','g');v_phone:=regexp_replace(coalesce(p_phone,''),'[^0-9]','','g');
 IF v_name IS NULL OR length(v_name) NOT BETWEEN 1 AND 160 OR length(v_phone)>15 OR (length(v_phone)>0 AND length(v_phone)<7) OR p_request IS NULL
 THEN RAISE EXCEPTION 'Enter a name and a valid phone number (or leave phone blank)' USING ERRCODE='22023'; END IF;
 v_payload:=jsonb_build_object('class_id',p_class,'name',v_name,'phone',v_phone);
 PERFORM 1 FROM public.organizations WHERE id=p_org FOR UPDATE;
 SELECT payload,student_id INTO v_old,v_id FROM public.rr_motivation_roster_actions WHERE organization_id=p_org AND request_id=p_request;
 IF FOUND THEN
  IF v_old<>v_payload THEN RAISE EXCEPTION 'This request was already used. Reload before adding another student.' USING ERRCODE='22023'; END IF;
  RETURN jsonb_build_object('student_id',v_id,'created',false,'replayed',true);
 END IF;
 SELECT c.school_year_id INTO v_year FROM public.classes c JOIN public.school_years y ON y.id=c.school_year_id AND y.organization_id=p_org AND y.is_current
 WHERE c.id=p_class AND c.organization_id=p_org AND c.is_active FOR UPDATE OF c;
 IF NOT FOUND THEN RAISE EXCEPTION 'Select an active class in this school year' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM public.students s JOIN public.student_class_assignments a ON a.student_id=s.id AND a.organization_id=p_org AND a.is_current
 WHERE s.organization_id=p_org AND NOT s.is_archived AND a.class_id=p_class AND lower(regexp_replace(btrim(s.name),'\s+',' ','g'))=lower(v_name))
 THEN RAISE EXCEPTION 'This name already exists in this class. Select the existing student.' USING ERRCODE='23505'; END IF;
 INSERT INTO public.students(organization_id,name,phone) VALUES(p_org,v_name,nullif(v_phone,'')) RETURNING id INTO v_id;
 INSERT INTO public.student_class_assignments(organization_id,student_id,school_year_id,class_id,is_current)
 VALUES(p_org,v_id,v_year,p_class,true);
 INSERT INTO public.rr_motivation_roster_actions(organization_id,request_id,actor_id,payload,student_id)
 VALUES(p_org,p_request,auth.uid(),v_payload,v_id);
 RETURN jsonb_build_object('student_id',v_id,'created',true,'replayed',false);
END $$;
REVOKE ALL ON FUNCTION public.rr_motivation_roster(uuid),public.rr_motivation_add_student(uuid,uuid,text,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_motivation_roster(uuid),public.rr_motivation_add_student(uuid,uuid,text,text,uuid) TO authenticated;


$stage_b$;
ELSIF to_regclass('public.rr_motivation_roster_actions') IS NULL OR to_regprocedure('public.rr_motivation_roster(uuid)') IS NULL OR to_regprocedure('public.rr_motivation_add_student(uuid,uuid,text,text,uuid)') IS NULL THEN
RAISE EXCEPTION 'Incomplete motivation stage B. Stop and review the prior installation.';
END IF;
END $installer$;

DO $workspace_installer$
BEGIN
IF to_regclass('public.rr_motivation_options') IS NULL AND to_regclass('public.rr_motivation_events') IS NULL AND to_regclass('public.rr_motivation_points') IS NULL AND to_regclass('public.rr_motivation_cards') IS NULL AND to_regclass('public.rr_motivation_requests') IS NULL AND to_regprocedure('public.rr_motivation_defaults()') IS NULL AND to_regprocedure('public.rr_motivation_workspace(uuid,uuid)') IS NULL AND to_regprocedure('public.rr_motivation_report(uuid,jsonb)') IS NULL AND to_regprocedure('public.rr_motivation_command(uuid,uuid,text,jsonb)') IS NULL THEN
EXECUTE $workspace_ddl$

CREATE TABLE public.rr_motivation_options(
 organization_id uuid PRIMARY KEY REFERENCES public.organizations(id),revision bigint NOT NULL DEFAULT 1,
 settings jsonb NOT NULL,updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.rr_motivation_events(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,organization_id uuid NOT NULL,program_id uuid,
 student_id uuid,class_id uuid,actor_id uuid NOT NULL,kind text NOT NULL,outcome text NOT NULL DEFAULT 'accepted',
 detail jsonb NOT NULL DEFAULT '{}',created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX ON public.rr_motivation_events(organization_id,created_at DESC,id DESC);
CREATE INDEX ON public.rr_motivation_events(organization_id,student_id,id DESC);
CREATE TABLE public.rr_motivation_points(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,program_id uuid NOT NULL REFERENCES public.rr_motivation_programs(id),
 student_id uuid NOT NULL REFERENCES public.students(id),points numeric NOT NULL,available_at timestamptz NOT NULL DEFAULT now(),
 event_id bigint NOT NULL REFERENCES public.rr_motivation_events(id));
CREATE INDEX ON public.rr_motivation_points(organization_id,program_id,student_id);
CREATE TABLE public.rr_motivation_cards(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,program_id uuid NOT NULL REFERENCES public.rr_motivation_programs(id),
 class_id uuid NOT NULL REFERENCES public.classes(id),code text NOT NULL UNIQUE DEFAULT upper(replace(gen_random_uuid()::text,'-','')),
 points numeric NOT NULL CHECK(points>=0),teacher text,student_id uuid,status text NOT NULL DEFAULT 'available' CHECK(status IN ('available','redeemed','blocked')),
 batch_id uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX ON public.rr_motivation_cards(organization_id,program_id,created_at DESC);
CREATE TABLE public.rr_motivation_requests(organization_id uuid NOT NULL,request_id uuid NOT NULL,payload jsonb NOT NULL,result jsonb NOT NULL,PRIMARY KEY(organization_id,request_id));
ALTER TABLE public.rr_motivation_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rr_motivation_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rr_motivation_points ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rr_motivation_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rr_motivation_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rr_motivation_options,public.rr_motivation_events,public.rr_motivation_points,public.rr_motivation_cards,public.rr_motivation_requests FROM PUBLIC,anon,authenticated;
REVOKE ALL ON SEQUENCE public.rr_motivation_events_id_seq FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.rr_motivation_defaults() RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
 SELECT '{"cards_enabled":false,"weekly_cap":12,"reveal_next_day":false,"teacher_cards":false,"phone_frozen":true,"allow_home":true,"allow_father":false,"allow_mother":false,"allow_other":false,"blocked_students":[],"display_enabled":false,"timezone":"America/New_York","display_start":"08:00","display_end":"17:00","display_days":[0,1,2,3,4,5],"show_birthdays":false,"playlist":[{"type":"totals","text":"","path":"","seconds":15},{"type":"date","text":"","path":"","seconds":5}]}'::jsonb
$$;
REVOKE ALL ON FUNCTION public.rr_motivation_defaults() FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.rr_motivation_workspace(p_org uuid,p_program uuid DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE v_settings jsonb;v_revision bigint;v_totals jsonb;v_cards jsonb;v_birthdays jsonb;
BEGIN
 PERFORM public.rr_motivation_require_access(p_org);
 IF p_program IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.rr_motivation_programs WHERE id=p_program AND organization_id=p_org) THEN RAISE EXCEPTION 'Program not found' USING ERRCODE='42501';END IF;
 SELECT settings,revision INTO v_settings,v_revision FROM public.rr_motivation_options WHERE organization_id=p_org;
 SELECT coalesce(jsonb_object_agg(student_id,total),'{}') INTO v_totals FROM (SELECT student_id,sum(points) total FROM public.rr_motivation_points WHERE organization_id=p_org AND program_id=p_program AND available_at<=now() GROUP BY student_id) t;
 SELECT coalesce(jsonb_agg(to_jsonb(c) ORDER BY created_at DESC,id),'[]') INTO v_cards FROM (SELECT * FROM public.rr_motivation_cards WHERE organization_id=p_org AND program_id=p_program ORDER BY created_at DESC,id LIMIT 500) c;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'birthday',gregorian_birthday)),'[]') INTO v_birthdays FROM public.students WHERE organization_id=p_org AND NOT is_archived AND gregorian_birthday IS NOT NULL;
 RETURN jsonb_build_object('settings',coalesce(v_settings,public.rr_motivation_defaults()),'revision',coalesce(v_revision,0),'totals',v_totals,'cards',v_cards,'birthdays',v_birthdays);
END $$;
CREATE FUNCTION public.rr_motivation_report(p_org uuid,p_filters jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.rr_motivation_require_access(p_org);
 SELECT coalesce(jsonb_agg(to_jsonb(e) ORDER BY e.id DESC),'[]') INTO result FROM (
 SELECT e.*,s.name student_name,c.name class_name FROM public.rr_motivation_events e
 LEFT JOIN public.students s ON s.id=e.student_id AND s.organization_id=p_org
 LEFT JOIN public.classes c ON c.id=e.class_id AND c.organization_id=p_org
 WHERE e.organization_id=p_org
 AND (coalesce(p_filters->>'program','')='' OR e.program_id IS NULL OR e.program_id=(p_filters->>'program')::uuid)
 AND (coalesce(p_filters->>'student','')='' OR e.student_id=(p_filters->>'student')::uuid)
 AND (coalesce(p_filters->>'class','')='' OR e.class_id=(p_filters->>'class')::uuid)
 AND (coalesce(p_filters->>'kind','')='' OR e.kind=p_filters->>'kind')
 AND (coalesce(p_filters->>'outcome','')='' OR e.outcome=p_filters->>'outcome')
 AND (coalesce(p_filters->>'from','')='' OR e.created_at>=(p_filters->>'from')::timestamptz)
 AND (coalesce(p_filters->>'to','')='' OR e.created_at<=(p_filters->>'to')::timestamptz)
 AND (coalesce(p_filters->>'q','')='' OR concat_ws(' ',s.name,c.name,e.kind,e.detail::text) ILIKE '%'||(p_filters->>'q')||'%')
 AND (coalesce(p_filters->>'before','')='' OR e.id<(p_filters->>'before')::bigint)
 ORDER BY e.id DESC LIMIT 200) e;
 RETURN result;
END $$;
CREATE FUNCTION public.rr_motivation_command(p_org uuid,p_request uuid,p_action text,p_data jsonb) RETURNS jsonb
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
  IF jsonb_typeof(v_old->'weekly_cap') IS DISTINCT FROM 'number' OR (v_old->>'weekly_cap')::numeric NOT BETWEEN 1 AND 1000 OR trunc((v_old->>'weekly_cap')::numeric)<>(v_old->>'weekly_cap')::numeric THEN RAISE EXCEPTION 'Weekly cap must be 1 to 1000' USING ERRCODE='22023';END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=v_old->>'timezone') OR coalesce(v_old->>'display_start','')!~'^([01][0-9]|2[0-3]):[0-5][0-9]$' OR coalesce(v_old->>'display_end','')!~'^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN RAISE EXCEPTION 'Invalid timezone or schedule' USING ERRCODE='22023';END IF;
  IF jsonb_typeof(v_old->'display_days') IS DISTINCT FROM 'array' OR jsonb_typeof(v_old->'blocked_students') IS DISTINCT FROM 'array' OR jsonb_typeof(v_old->'playlist') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Invalid lists' USING ERRCODE='22023';END IF;
  FOR row_data IN SELECT value FROM jsonb_array_elements(v_old->'display_days') LOOP IF row_data::text NOT IN ('0','1','2','3','4','5','6') THEN RAISE EXCEPTION 'Invalid day' USING ERRCODE='22023';END IF;END LOOP;
  FOR row_data IN SELECT value FROM jsonb_array_elements(v_old->'blocked_students') LOOP IF NOT EXISTS(SELECT 1 FROM public.students WHERE id=(row_data#>>'{}')::uuid AND organization_id=p_org) THEN RAISE EXCEPTION 'Invalid blocked student' USING ERRCODE='42501';END IF;END LOOP;
  IF jsonb_array_length(v_old->'playlist') NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'Playlist needs 1 to 100 slides' USING ERRCODE='22023';END IF;
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
REVOKE ALL ON FUNCTION public.rr_motivation_workspace(uuid,uuid),public.rr_motivation_report(uuid,jsonb),public.rr_motivation_command(uuid,uuid,text,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_motivation_workspace(uuid,uuid),public.rr_motivation_report(uuid,jsonb),public.rr_motivation_command(uuid,uuid,text,jsonb) TO authenticated;


$workspace_ddl$;
ELSIF to_regclass('public.rr_motivation_options') IS NULL OR to_regclass('public.rr_motivation_events') IS NULL OR to_regclass('public.rr_motivation_points') IS NULL OR to_regclass('public.rr_motivation_cards') IS NULL OR to_regclass('public.rr_motivation_requests') IS NULL OR to_regprocedure('public.rr_motivation_defaults()') IS NULL OR to_regprocedure('public.rr_motivation_workspace(uuid,uuid)') IS NULL OR to_regprocedure('public.rr_motivation_report(uuid,jsonb)') IS NULL OR to_regprocedure('public.rr_motivation_command(uuid,uuid,text,jsonb)') IS NULL THEN
RAISE EXCEPTION 'Incomplete workspace installation. Review before continuing.';
END IF;
END $workspace_installer$;
DO $media_installer$
DECLARE policy_count integer;
BEGIN
 IF to_regclass('storage.buckets') IS NULL OR to_regclass('storage.objects') IS NULL THEN
  RAISE EXCEPTION 'This installer requires Supabase Storage.';
 END IF;
 SELECT count(*) INTO policy_count FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname IN ('motivation_media_read','motivation_media_insert','motivation_media_delete','motivation_media_boundary','motivation_media_anonymous_boundary');
 IF policy_count=0 AND NOT EXISTS(SELECT 1 FROM storage.buckets WHERE id='motivation-media') THEN
 EXECUTE $media_ddl$

INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES('motivation-media','motivation-media',false,26214400,ARRAY['image/png','image/jpeg','image/webp','video/mp4','video/webm'])
ON CONFLICT(id) DO NOTHING;
CREATE POLICY motivation_media_read ON storage.objects FOR SELECT TO authenticated
USING(bucket_id='motivation-media' AND EXISTS(SELECT 1 FROM public.organization_members m WHERE m.user_id=auth.uid() AND m.role::text IN ('admin','super_admin') AND m.organization_id::text=(storage.foldername(name))[1]));
CREATE POLICY motivation_media_insert ON storage.objects FOR INSERT TO authenticated
WITH CHECK(bucket_id='motivation-media' AND EXISTS(SELECT 1 FROM public.organization_members m WHERE m.user_id=auth.uid() AND m.role::text IN ('admin','super_admin') AND m.organization_id::text=(storage.foldername(name))[1]));
CREATE POLICY motivation_media_delete ON storage.objects FOR DELETE TO authenticated
USING(bucket_id='motivation-media' AND EXISTS(SELECT 1 FROM public.organization_members m WHERE m.user_id=auth.uid() AND m.role::text IN ('admin','super_admin') AND m.organization_id::text=(storage.foldername(name))[1]));
-- Restrictive boundaries keep older broad Storage policies from opening this bucket.
CREATE POLICY motivation_media_boundary ON storage.objects AS RESTRICTIVE FOR ALL TO authenticated
USING(bucket_id<>'motivation-media' OR EXISTS(SELECT 1 FROM public.organization_members m WHERE m.user_id=auth.uid() AND m.role::text IN ('admin','super_admin') AND m.organization_id::text=(storage.foldername(name))[1]))
WITH CHECK(bucket_id<>'motivation-media' OR EXISTS(SELECT 1 FROM public.organization_members m WHERE m.user_id=auth.uid() AND m.role::text IN ('admin','super_admin') AND m.organization_id::text=(storage.foldername(name))[1]));
CREATE POLICY motivation_media_anonymous_boundary ON storage.objects AS RESTRICTIVE FOR ALL TO anon
USING(bucket_id<>'motivation-media') WITH CHECK(bucket_id<>'motivation-media');

$media_ddl$;
 ELSIF policy_count<>5 OR NOT EXISTS(SELECT 1 FROM storage.buckets WHERE id='motivation-media' AND public=false) THEN
  RAISE EXCEPTION 'Incomplete or non-private motivation-media setup. Review before continuing.';
 END IF;
END $media_installer$;
NOTIFY pgrst,'reload schema';
COMMIT;
SELECT 'MOTIVATION_WORKSPACE_READY' AS result;
