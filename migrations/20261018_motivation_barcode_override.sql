-- Stage 5.1: run after Stage 5. Safe to run again. No student/card data is reset.
BEGIN;
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
  SELECT count(*) INTO used FROM public.rr_motivation_events e WHERE e.organization_id=p_org AND e.program_id=program AND e.student_id=student AND e.kind='redeem' AND e.outcome='accepted' AND e.created_at>=date_trunc('week',now() AT TIME ZONE (settings->>'timezone')) AT TIME ZONE (settings->>'timezone');
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
SELECT 'MOTIVATION_BARCODE_READY' AS result;
