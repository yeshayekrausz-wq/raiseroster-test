-- Requires Activate_Teacher_Workspace.sql and the existing planner teacher settings.
-- Changes the teacher's login for this school, not the underlying admin Auth account.
BEGIN;
CREATE TABLE IF NOT EXISTS public.rr_teacher_email_moves(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL REFERENCES public.organizations(id),
 portal_ids uuid[] NOT NULL,class_ids uuid[] NOT NULL,source_user uuid NOT NULL REFERENCES auth.users(id),
 target_email text NOT NULL,initiated_by uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),
 claimed_by uuid,claimed_at timestamptz
);
ALTER TABLE public.rr_teacher_email_moves ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rr_teacher_email_moves FROM PUBLIC,anon,authenticated;
CREATE INDEX IF NOT EXISTS rr_teacher_email_moves_pending ON public.rr_teacher_email_moves(target_email) WHERE claimed_at IS NULL;
CREATE OR REPLACE FUNCTION public.rr_teacher_claim_email() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE email_value text;school uuid;m public.rr_teacher_email_moves%ROWTYPE;
BEGIN
 SELECT lower(email) INTO email_value FROM auth.users WHERE id=auth.uid() AND email_confirmed_at IS NOT NULL;
 IF email_value IS NULL THEN RETURN;END IF;
 FOR school IN SELECT DISTINCT organization_id FROM public.rr_teacher_email_moves WHERE target_email=email_value AND claimed_at IS NULL ORDER BY organization_id LOOP
  PERFORM 1 FROM public.organizations WHERE id=school FOR UPDATE;
  FOR m IN SELECT * FROM public.rr_teacher_email_moves WHERE organization_id=school AND target_email=email_value AND claimed_at IS NULL ORDER BY created_at,id FOR UPDATE LOOP
   IF EXISTS(SELECT 1 FROM unnest(m.portal_ids) p WHERE NOT EXISTS(SELECT 1 FROM public.rr_teacher_portals t WHERE t.id=p AND t.organization_id=school AND lower(t.email)=email_value)) THEN CONTINUE;END IF;
   IF NOT EXISTS(SELECT 1 FROM public.rr_teacher_portals t WHERE t.id=ANY(m.portal_ids) AND t.enabled AND lower(t.email)=email_value) THEN CONTINUE;END IF;
   UPDATE public.rr_teacher_records SET owner_id=auth.uid(),revision=revision+1,updated_at=now()
   WHERE organization_id=school AND class_id=ANY(m.class_ids) AND owner_id=m.source_user AND owner_id<>auth.uid();
   UPDATE public.rr_teacher_records SET shared_with=ARRAY(SELECT DISTINCT x FROM unnest(array_replace(shared_with,m.source_user,auth.uid())) x),revision=revision+1,updated_at=now()
   WHERE organization_id=school AND class_id=ANY(m.class_ids) AND m.source_user=ANY(shared_with) AND m.source_user<>auth.uid();
   UPDATE public.rr_teacher_email_moves SET claimed_by=auth.uid(),claimed_at=now() WHERE id=m.id;
   INSERT INTO public.rr_motivation_events(organization_id,actor_id,kind,detail) VALUES(school,auth.uid(),'teacher_email_claimed',jsonb_build_object('move',m.id,'previous_owner',m.source_user,'classes',m.class_ids));
  END LOOP;
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.rr_teacher_claim_email() FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.rr_motivation_teacher_save_v2(p_org uuid,p_id uuid,p_revision bigint,p_name text,p_email text,p_class uuid,p_session text,p_enabled boolean) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE old public.rr_teacher_portals%ROWTYPE;target text:=nullif(lower(btrim(p_email)),'');old_email text;portals uuid[];classes uuid[];source_id uuid;result jsonb;
BEGIN
 PERFORM public.rr_motivation_require_access(p_org);
 PERFORM 1 FROM public.organizations WHERE id=p_org FOR UPDATE;
 IF p_id IS NOT NULL THEN
  SELECT * INTO old FROM public.rr_teacher_portals WHERE id=p_id AND organization_id=p_org FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Teacher not found' USING ERRCODE='42501';END IF;
  IF p_revision IS DISTINCT FROM old.revision THEN RAISE EXCEPTION 'Teacher changed. Reload before saving.' USING ERRCODE='40001';END IF;
 END IF;
 old_email:=nullif(lower(btrim(old.email)),'');
 IF old_email IS NOT NULL AND target IS DISTINCT FROM old_email THEN
  IF NOT p_enabled THEN RAISE EXCEPTION 'Keep this assignment active when changing the login email. You can disable it afterward.';END IF;
  IF target IS NULL THEN RAISE EXCEPTION 'Enter the new login email, or disable the assignment to suspend access.';END IF;
  IF p_class IS DISTINCT FROM old.class_id THEN RAISE EXCEPTION 'Save the email change first, then change the class separately.';END IF;
  SELECT array_agg(id ORDER BY id),array_agg(DISTINCT class_id) INTO portals,classes FROM public.rr_teacher_portals WHERE organization_id=p_org AND lower(email)=old_email;
  -- Prevent accidentally merging two teachers' private workspaces.
  IF EXISTS(SELECT 1 FROM public.rr_teacher_portals WHERE organization_id=p_org AND lower(email)=target AND NOT(id=ANY(portals))) THEN RAISE EXCEPTION 'This email is assigned to another teacher in this school. Use a different email; workspaces were not merged.';END IF;
  SELECT id INTO source_id FROM auth.users WHERE lower(email)=old_email;
  result:=public.rr_motivation_teacher_save(p_org,p_id,p_revision,p_name,target,p_class,p_session,p_enabled);
  UPDATE public.rr_teacher_portals SET email=target,revision=revision+1,invited_at=NULL,invited_by=auth.uid() WHERE id=ANY(portals) AND id<>p_id;
  UPDATE public.rr_teacher_portals SET invited_at=NULL,invited_by=auth.uid() WHERE id=p_id;
  -- Retarget unfinished moves too, so A -> B -> C before acceptance retains A's data.
  UPDATE public.rr_teacher_email_moves SET target_email=target WHERE organization_id=p_org AND claimed_at IS NULL AND target_email=old_email AND portal_ids && portals;
  IF source_id IS NOT NULL THEN
   INSERT INTO public.rr_teacher_email_moves(organization_id,portal_ids,class_ids,source_user,target_email,initiated_by) VALUES(p_org,portals,classes,source_id,target,auth.uid());
  END IF;
  INSERT INTO public.rr_motivation_events(organization_id,actor_id,kind,detail) VALUES(p_org,auth.uid(),'teacher_email_changed',jsonb_build_object('from',old_email,'to',target,'portals',portals,'classes',classes));
 ELSE
  result:=public.rr_motivation_teacher_save(p_org,p_id,p_revision,p_name,target,p_class,p_session,p_enabled);
 END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.rr_motivation_teacher_save_v2(uuid,uuid,bigint,text,text,uuid,text,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_motivation_teacher_save_v2(uuid,uuid,bigint,text,text,uuid,text,boolean) TO authenticated;
-- Older frontends must refresh rather than bypassing the data-preserving change handler.
REVOKE EXECUTE ON FUNCTION public.rr_motivation_teacher_save(uuid,uuid,bigint,text,text,uuid,text,boolean) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.rr_teacher_home() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM public.rr_teacher_claim_email();
 RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'org',t.organization_id,'class_id',t.class_id,'class',c.name,'name',t.name,'session',t.session) ORDER BY c.name,t.session),'[]')
 FROM public.rr_teacher_portals t JOIN auth.users u ON u.id=auth.uid() AND lower(u.email)=lower(t.email) AND u.email_confirmed_at IS NOT NULL
 JOIN public.classes c ON c.id=t.class_id AND c.organization_id=t.organization_id AND c.is_active WHERE t.enabled);
END $$;
CREATE OR REPLACE FUNCTION public.rr_teacher_workspace(p_org uuid,p_class uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE pupils jsonb;rec jsonb;people jsonb;programs jsonb;
BEGIN
 PERFORM public.rr_teacher_claim_email();
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
 PERFORM 1 FROM public.organizations WHERE id=p_org FOR UPDATE;
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
REVOKE ALL ON FUNCTION public.rr_teacher_home() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_teacher_home() TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_teacher_invite_claim(p_portal uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t public.rr_teacher_portals%ROWTYPE;
BEGIN
 SELECT * INTO t FROM public.rr_teacher_portals WHERE id=p_portal FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Teacher not found' USING ERRCODE='42501';END IF;
 PERFORM public.rr_motivation_require_access(t.organization_id);
 IF NOT t.enabled OR t.email IS NULL THEN RAISE EXCEPTION 'Enable the assignment and enter an email';END IF;
 IF t.invited_at>now()-interval '2 minutes' THEN RAISE EXCEPTION 'Please wait two minutes before sending again';END IF;
 UPDATE public.rr_teacher_portals SET invited_at=now(),invited_by=auth.uid() WHERE id=t.id;
 RETURN jsonb_build_object('id',t.id,'email',t.email,'name',t.name,'needs_setup',EXISTS(SELECT 1 FROM auth.users WHERE lower(email)=lower(t.email) AND email_confirmed_at IS NULL));
END $$;
NOTIFY pgrst,'reload schema';
COMMIT;
