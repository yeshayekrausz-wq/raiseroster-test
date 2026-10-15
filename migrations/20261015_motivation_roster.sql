-- Stage 3B: shared school roster. Requires Stage 3A Hatzlacha setup.
BEGIN;
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
NOTIFY pgrst,'reload schema';
COMMIT;
SELECT 'MOTIVATION_ROSTER_READY' AS result;
