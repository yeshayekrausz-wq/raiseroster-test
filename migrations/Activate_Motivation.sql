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
NOTIFY pgrst,'reload schema';
COMMIT;
SELECT 'MOTIVATION_READY' AS result;
