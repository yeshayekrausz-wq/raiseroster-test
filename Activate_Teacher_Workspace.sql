-- Run this complete file once in Supabase SQL Editor. Additive: no roster or points reset.
BEGIN;
ALTER TABLE public.rr_teacher_portals ADD COLUMN IF NOT EXISTS invited_at timestamptz;
ALTER TABLE public.rr_teacher_portals ADD COLUMN IF NOT EXISTS invited_by uuid;
CREATE TABLE IF NOT EXISTS public.rr_teacher_records (
 id uuid PRIMARY KEY, organization_id uuid NOT NULL REFERENCES public.organizations(id),
 class_id uuid NOT NULL REFERENCES public.classes(id), owner_id uuid NOT NULL REFERENCES auth.users(id),
 kind text NOT NULL CHECK(kind IN ('attendance','exam','seating','pairs','note','reminder')),
 title text NOT NULL CHECK(length(title) BETWEEN 1 AND 160), day date NOT NULL,
 payload jsonb NOT NULL DEFAULT '{}', shared_with uuid[] NOT NULL DEFAULT '{}',
 revision bigint NOT NULL DEFAULT 1, updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS rr_teacher_records_class ON public.rr_teacher_records(organization_id,class_id,day);
ALTER TABLE public.rr_teacher_records ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rr_teacher_records FROM PUBLIC,anon,authenticated;
-- Access is checked inside every RPC. No organization membership is granted to a teacher.
CREATE OR REPLACE FUNCTION public.rr_teacher_access(p_org uuid,p_class uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT EXISTS(SELECT 1 FROM public.rr_teacher_portals t JOIN auth.users u ON u.id=auth.uid() AND lower(u.email)=lower(t.email) AND u.email_confirmed_at IS NOT NULL
 JOIN public.classes c ON c.id=t.class_id AND c.organization_id=t.organization_id AND c.is_active
 WHERE t.organization_id=p_org AND t.class_id=p_class AND t.enabled)
$$;
CREATE OR REPLACE FUNCTION public.rr_teacher_home() RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'org',t.organization_id,'class_id',t.class_id,'class',c.name,'name',t.name,'session',t.session) ORDER BY c.name,t.session),'[]')
 FROM public.rr_teacher_portals t JOIN auth.users u ON u.id=auth.uid() AND lower(u.email)=lower(t.email) AND u.email_confirmed_at IS NOT NULL
 JOIN public.classes c ON c.id=t.class_id AND c.organization_id=t.organization_id AND c.is_active WHERE t.enabled
$$;
CREATE OR REPLACE FUNCTION public.rr_teacher_workspace(p_org uuid,p_class uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE pupils jsonb;rec jsonb;people jsonb;programs jsonb;
BEGIN
 IF NOT public.rr_teacher_access(p_org,p_class) THEN RAISE EXCEPTION 'No access to this class' USING ERRCODE='42501'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'number',a.short_id,'phone',s.phone,'home_phone',s.home_phone,'father_phone',s.father_phone,'mother_phone',s.mother_phone,'address',s.address,'birthday',s.gregorian_birthday,'hebrew_birthday',s.hebrew_birthday) ORDER BY s.name),'[]') INTO pupils
 FROM public.students s LEFT JOIN public.rr_student_aliases a ON a.student_id=s.id AND a.organization_id=p_org
 WHERE s.organization_id=p_org AND NOT s.is_archived AND EXISTS(SELECT 1 FROM public.student_class_assignments c WHERE c.student_id=s.id AND c.organization_id=p_org AND c.class_id=p_class AND c.is_current);
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY day DESC,updated_at DESC),'[]') INTO rec FROM public.rr_teacher_records r
 WHERE r.organization_id=p_org AND ((r.class_id=p_class AND (r.owner_id=auth.uid() OR r.kind IN ('attendance','exam','seating','pairs'))) OR (auth.uid()=ANY(r.shared_with) AND r.kind IN ('note','reminder')));
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',u.id,'name',coalesce(nullif(u.raw_user_meta_data->>'name',''),u.email)) ORDER BY u.email),'[]') INTO people FROM auth.users u WHERE u.email_confirmed_at IS NOT NULL AND (EXISTS(SELECT 1 FROM public.organization_members m WHERE m.organization_id=p_org AND m.user_id=u.id) OR EXISTS(SELECT 1 FROM public.rr_teacher_portals t WHERE t.organization_id=p_org AND t.enabled AND lower(t.email)=lower(u.email)));
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',config->>'name','term',config->>'term_name')),'[]') INTO programs FROM public.rr_motivation_programs WHERE organization_id=p_org;
 RETURN jsonb_build_object('students',pupils,'records',rec,'people',people,'programs',programs);
END $$;
CREATE OR REPLACE FUNCTION public.rr_teacher_save(p_org uuid,p_class uuid,p_id uuid,p_revision bigint,p_kind text,p_title text,p_day date,p_payload jsonb,p_shared uuid[] DEFAULT '{}') RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE old public.rr_teacher_records%ROWTYPE;r jsonb;sid uuid;member uuid;result jsonb;
BEGIN
 IF NOT public.rr_teacher_access(p_org,p_class) THEN RAISE EXCEPTION 'No access to this class' USING ERRCODE='42501';END IF;
 IF p_id IS NULL OR p_day IS NULL OR p_title IS NULL OR length(btrim(p_title)) NOT BETWEEN 1 AND 160 OR p_kind IS NULL OR p_kind NOT IN ('attendance','exam','seating','pairs','note','reminder') OR jsonb_typeof(p_payload) IS DISTINCT FROM 'object' OR octet_length(p_payload::text)>250000 OR p_shared IS NULL THEN RAISE EXCEPTION 'Invalid entry';END IF;
 PERFORM 1 FROM public.classes WHERE id=p_class AND organization_id=p_org FOR UPDATE;
 SELECT * INTO old FROM public.rr_teacher_records WHERE id=p_id FOR UPDATE;
 IF FOUND AND (old.organization_id<>p_org OR old.class_id<>p_class OR old.owner_id<>auth.uid() OR old.kind<>p_kind) THEN RAISE EXCEPTION 'Only the author may edit this entry' USING ERRCODE='42501';END IF;
 IF p_revision IS DISTINCT FROM coalesce(old.revision,0) THEN RAISE EXCEPTION 'Entry changed. Reload before saving.' USING ERRCODE='40001';END IF;
 IF p_kind NOT IN ('note','reminder') AND cardinality(p_shared)>0 THEN RAISE EXCEPTION 'Sharing is for notes and reminders';END IF;
 FOREACH member IN ARRAY p_shared LOOP
  IF NOT EXISTS(SELECT 1 FROM auth.users u WHERE u.id=member AND u.email_confirmed_at IS NOT NULL AND (EXISTS(SELECT 1 FROM public.organization_members m WHERE m.organization_id=p_org AND m.user_id=u.id) OR EXISTS(SELECT 1 FROM public.rr_teacher_portals t WHERE t.organization_id=p_org AND t.enabled AND lower(t.email)=lower(u.email)))) THEN RAISE EXCEPTION 'Share only within this school' USING ERRCODE='42501';END IF;
 END LOOP;
 IF p_kind IN ('attendance','exam') THEN
  IF jsonb_typeof(p_payload->'rows') IS DISTINCT FROM 'array' OR jsonb_array_length(p_payload->'rows')>500 THEN RAISE EXCEPTION 'Invalid class sheet';END IF;
  IF (SELECT count(*)<>count(DISTINCT value->>'id') FROM jsonb_array_elements(p_payload->'rows')) THEN RAISE EXCEPTION 'Duplicate student';END IF;
  FOR r IN SELECT value FROM jsonb_array_elements(p_payload->'rows') LOOP
   sid:=(r->>'id')::uuid;
   IF sid IS NULL OR NOT EXISTS(SELECT 1 FROM public.students s JOIN public.student_class_assignments a ON a.student_id=s.id AND a.organization_id=p_org AND a.class_id=p_class AND a.is_current WHERE s.id=sid AND s.organization_id=p_org AND NOT s.is_archived) THEN RAISE EXCEPTION 'Student is not in this class' USING ERRCODE='42501';END IF;
   IF p_kind='attendance' AND (coalesce(r->>'status','') NOT IN ('','present','absent','late') OR length(coalesce(r->>'reason',''))>1000) THEN RAISE EXCEPTION 'Invalid attendance';END IF;
   IF p_kind='exam' AND r->>'score' IS NOT NULL AND ((r->>'score')::numeric<0 OR (r->>'score')::numeric>(p_payload->>'max')::numeric) THEN RAISE EXCEPTION 'Score must be between zero and the maximum';END IF;
  END LOOP;
 END IF;
 IF p_kind='exam' AND (coalesce(p_payload->>'subject','')='' OR coalesce((p_payload->>'max')::numeric,0)<=0 OR (p_payload->>'max')::numeric>100000) THEN RAISE EXCEPTION 'Enter a subject and positive maximum';END IF;
 IF p_kind='pairs' THEN
  IF jsonb_typeof(p_payload->'rounds') IS DISTINCT FROM 'array' OR jsonb_array_length(p_payload->'rounds')>500 THEN RAISE EXCEPTION 'Invalid pair rounds';END IF;
  FOR r IN SELECT value FROM jsonb_array_elements(p_payload->'rounds') LOOP
   IF jsonb_typeof(r) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Invalid round';END IF;
   IF EXISTS(SELECT 1 FROM jsonb_array_elements(r) pair WHERE jsonb_typeof(pair) IS DISTINCT FROM 'array' OR jsonb_array_length(pair)<>2) THEN RAISE EXCEPTION 'Each group needs two slots';END IF;
   IF (SELECT count(v)<>count(DISTINCT v) FROM jsonb_array_elements(r) pair CROSS JOIN LATERAL jsonb_array_elements_text(pair) v WHERE v IS NOT NULL) THEN RAISE EXCEPTION 'A child appears twice in a round';END IF;
   IF EXISTS(SELECT 1 FROM jsonb_array_elements(r) pair CROSS JOIN LATERAL jsonb_array_elements_text(pair) v WHERE v IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.student_class_assignments a JOIN public.students s ON s.id=a.student_id AND s.organization_id=p_org AND NOT s.is_archived WHERE a.student_id=v::uuid AND a.organization_id=p_org AND a.class_id=p_class AND a.is_current)) THEN RAISE EXCEPTION 'Pair contains a student outside this class';END IF;
  END LOOP;
 END IF;
 IF p_kind='seating' THEN
  IF jsonb_typeof(p_payload->'seats') IS DISTINCT FROM 'array' OR jsonb_array_length(p_payload->'seats')>80 THEN RAISE EXCEPTION 'Invalid seating chart';END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_payload->'seats') v WHERE coalesce((v->>'x')::numeric,-1) NOT BETWEEN 0 AND 82 OR coalesce((v->>'y')::numeric,-1) NOT BETWEEN 0 AND 87 OR length(coalesce(v->>'label',''))>200) THEN RAISE EXCEPTION 'Invalid chair position or name';END IF;
 END IF;
 INSERT INTO public.rr_teacher_records(id,organization_id,class_id,owner_id,kind,title,day,payload,shared_with)
 VALUES(p_id,p_org,p_class,auth.uid(),p_kind,btrim(p_title),p_day,p_payload,p_shared)
 ON CONFLICT(id) DO UPDATE SET title=excluded.title,day=excluded.day,payload=excluded.payload,shared_with=excluded.shared_with,revision=rr_teacher_records.revision+1,updated_at=now() RETURNING to_jsonb(rr_teacher_records.*) INTO result;
 RETURN result;
END $$;
CREATE OR REPLACE FUNCTION public.rr_teacher_delete(p_org uuid,p_class uuid,p_id uuid,p_revision bigint) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF NOT public.rr_teacher_access(p_org,p_class) THEN RAISE EXCEPTION 'No class access' USING ERRCODE='42501';END IF;
 DELETE FROM public.rr_teacher_records WHERE id=p_id AND organization_id=p_org AND class_id=p_class AND owner_id=auth.uid() AND revision=p_revision;
 IF NOT FOUND THEN RAISE EXCEPTION 'Entry changed or not owned by you' USING ERRCODE='40001';END IF;
END $$;
CREATE OR REPLACE FUNCTION public.rr_teacher_invite_claim(p_portal uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t public.rr_teacher_portals%ROWTYPE;
BEGIN
 SELECT * INTO t FROM public.rr_teacher_portals WHERE id=p_portal FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Teacher not found' USING ERRCODE='42501';END IF;
 PERFORM public.rr_motivation_require_access(t.organization_id);
 IF NOT t.enabled OR t.email IS NULL THEN RAISE EXCEPTION 'Enable the assignment and enter an email';END IF;
 IF t.invited_at>now()-interval '2 minutes' THEN RAISE EXCEPTION 'Please wait two minutes before sending again';END IF;
 UPDATE public.rr_teacher_portals SET invited_at=now(),invited_by=auth.uid() WHERE id=t.id;
 RETURN jsonb_build_object('id',t.id,'email',t.email,'name',t.name);
END $$;
CREATE OR REPLACE FUNCTION public.rr_teacher_points(p_org uuid,p_class uuid,p_program uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF NOT public.rr_teacher_access(p_org,p_class) OR NOT EXISTS(SELECT 1 FROM public.rr_motivation_programs WHERE id=p_program AND organization_id=p_org) THEN RAISE EXCEPTION 'No program access' USING ERRCODE='42501';END IF;
 RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id',s.id,'approved',coalesce((SELECT sum(points) FROM public.rr_motivation_points WHERE organization_id=p_org AND student_id=s.id AND program_id=p_program),0),'held',coalesce((SELECT sum(d.base_points-round(d.base_points*d.pct/100,4)) FROM public.rr_reward_redemptions d JOIN public.rr_motivation_cards c ON c.id=d.card_id AND c.program_id=p_program WHERE d.organization_id=p_org AND d.student_id=s.id),0))) FROM public.students s WHERE s.organization_id=p_org AND NOT s.is_archived AND EXISTS(SELECT 1 FROM public.student_class_assignments a WHERE a.student_id=s.id AND a.organization_id=p_org AND a.class_id=p_class AND a.is_current)),'[]');
END $$;
REVOKE ALL ON FUNCTION public.rr_teacher_access(uuid,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.rr_teacher_home(),public.rr_teacher_workspace(uuid,uuid),public.rr_teacher_save(uuid,uuid,uuid,bigint,text,text,date,jsonb,uuid[]),public.rr_teacher_delete(uuid,uuid,uuid,bigint),public.rr_teacher_invite_claim(uuid),public.rr_teacher_points(uuid,uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_teacher_home(),public.rr_teacher_workspace(uuid,uuid),public.rr_teacher_save(uuid,uuid,uuid,bigint,text,text,date,jsonb,uuid[]),public.rr_teacher_delete(uuid,uuid,uuid,bigint),public.rr_teacher_invite_claim(uuid),public.rr_teacher_points(uuid,uuid,uuid) TO authenticated;
-- Shared recipients may read the inbox even if they are office staff without a class.
CREATE OR REPLACE FUNCTION public.rr_teacher_shared() RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.day DESC),'[]') FROM public.rr_teacher_records r
 WHERE r.kind IN ('note','reminder') AND auth.uid()=ANY(r.shared_with)
 AND EXISTS(SELECT 1 FROM auth.users u WHERE u.id=auth.uid() AND u.email_confirmed_at IS NOT NULL)
 AND (EXISTS(SELECT 1 FROM public.organization_members m WHERE m.organization_id=r.organization_id AND m.user_id=auth.uid()) OR EXISTS(SELECT 1 FROM public.rr_teacher_portals t JOIN auth.users u ON u.id=auth.uid() AND lower(t.email)=lower(u.email) WHERE t.organization_id=r.organization_id AND t.enabled))
$$;
CREATE TABLE IF NOT EXISTS public.rr_teacher_card_requests(teacher_id uuid NOT NULL,request_id uuid NOT NULL,payload jsonb NOT NULL,result jsonb NOT NULL,PRIMARY KEY(teacher_id,request_id));
ALTER TABLE public.rr_teacher_card_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rr_teacher_card_requests FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.rr_teacher_redeem(p_org uuid,p_class uuid,p_program uuid,p_student uuid,p_code text,p_request uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t public.rr_teacher_portals%ROWTYPE;card public.rr_motivation_cards%ROWTYPE;original_sub text;teacher uuid:=auth.uid();answer jsonb;body jsonb;old public.rr_teacher_card_requests%ROWTYPE;
BEGIN
 IF NOT public.rr_teacher_access(p_org,p_class) THEN RAISE EXCEPTION 'No class access' USING ERRCODE='42501';END IF;
 IF p_request IS NULL OR p_code IS NULL OR p_code !~ '^[0-9]{6,13}$' THEN RAISE EXCEPTION 'Enter a numeric card code';END IF;
 SELECT a.* INTO t FROM public.rr_teacher_portals a JOIN auth.users u ON u.id=teacher AND lower(u.email)=lower(a.email) WHERE a.organization_id=p_org AND a.class_id=p_class AND a.enabled AND EXISTS(SELECT 1 FROM public.organization_members m WHERE m.organization_id=p_org AND m.user_id=a.invited_by AND m.role::text IN ('admin','super_admin')) ORDER BY a.invited_at DESC NULLS LAST LIMIT 1 FOR UPDATE OF a;
 IF NOT FOUND THEN RAISE EXCEPTION 'Ask your school administrator to send your portal setup invitation before redeeming cards.' USING ERRCODE='42501';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.students s JOIN public.student_class_assignments a ON a.student_id=s.id AND a.organization_id=p_org AND a.class_id=p_class AND a.is_current WHERE s.id=p_student AND s.organization_id=p_org AND NOT s.is_archived) THEN RAISE EXCEPTION 'Student is not in your class' USING ERRCODE='42501';END IF;
 body:=jsonb_build_object('org',p_org,'class',p_class,'program',p_program,'student',p_student,'code',p_code);
 SELECT * INTO old FROM public.rr_teacher_card_requests WHERE teacher_id=teacher AND request_id=p_request;
 IF FOUND THEN IF old.payload<>body THEN RAISE EXCEPTION 'Request already used';END IF;RETURN old.result;END IF;
 SELECT * INTO card FROM public.rr_motivation_cards WHERE organization_id=p_org AND program_id=p_program AND (code=p_code OR barcode=p_code) LIMIT 1 FOR UPDATE;
 IF NOT FOUND OR card.class_id IS DISTINCT FROM p_class THEN RAISE EXCEPTION 'Card does not belong to your class and program';END IF;
 -- Delegate only this checked redemption to the existing rewards engine; never broaden teacher membership.
 original_sub:=current_setting('request.jwt.claim.sub',true);
 PERFORM set_config('request.jwt.claim.sub',t.invited_by::text,true);
 BEGIN
  answer:=public.rr_motivation_command(p_org,gen_random_uuid(),'redeem',jsonb_build_object('program',p_program,'student',p_student,'code',card.code));
 EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claim.sub',coalesce(original_sub,''),true);RAISE;
 END;
 PERFORM set_config('request.jwt.claim.sub',coalesce(original_sub,''),true);
 INSERT INTO public.rr_motivation_events(organization_id,program_id,student_id,class_id,actor_id,kind,detail) VALUES(p_org,p_program,p_student,p_class,teacher,'teacher_redemption',jsonb_build_object('request',p_request,'portal',t.id,'card',card.id,'result',answer));
 INSERT INTO public.rr_teacher_card_requests VALUES(teacher,p_request,body,answer);RETURN answer;
END $$;
REVOKE ALL ON FUNCTION public.rr_teacher_shared(),public.rr_teacher_redeem(uuid,uuid,uuid,uuid,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_teacher_shared(),public.rr_teacher_redeem(uuid,uuid,uuid,uuid,text,uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
