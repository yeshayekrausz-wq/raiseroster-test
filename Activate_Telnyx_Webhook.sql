BEGIN;
-- Admin-only simulator. No public phone endpoint and no real rewards are committed.
CREATE TABLE IF NOT EXISTS public.rr_phone_test_calls(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL REFERENCES public.organizations(id),
 program_id uuid NOT NULL REFERENCES public.rr_motivation_programs(id),actor_id uuid NOT NULL,
 caller text NOT NULL,student_id uuid,accepted_codes jsonb NOT NULL DEFAULT '[]',
 history jsonb NOT NULL DEFAULT '[]',requests jsonb NOT NULL DEFAULT '{}',
 closed boolean NOT NULL DEFAULT false,created_at timestamptz NOT NULL DEFAULT now(),
 expires_at timestamptz NOT NULL DEFAULT now()+interval '15 minutes'
);
ALTER TABLE public.rr_phone_test_calls ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rr_phone_test_calls FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.rr_phone_normalize(p_phone text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
 SELECT CASE WHEN length(n)=11 AND left(n,1)='1' THEN substr(n,2) ELSE n END
 FROM (SELECT regexp_replace(coalesce(p_phone,''),'[^0-9]','','g') n) x
$$;
REVOKE ALL ON FUNCTION public.rr_phone_normalize(text) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.rr_phone_test(p_org uuid,p_program uuid,p_call uuid,p_request uuid,p_action text,p_value text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c public.rr_phone_test_calls%ROWTYPE;s public.students%ROWTYPE;card public.rr_motivation_cards%ROWTYPE;
 opts jsonb;r jsonb;payload jsonb;prior jsonb;sid uuid;cl uuid;code text;answer jsonb;
BEGIN
 PERFORM public.rr_motivation_require_access(p_org);
 IF p_request IS NULL OR p_action NOT IN ('start','identify','card','end') OR p_action IS NULL OR length(coalesce(p_value,''))>40 THEN RAISE EXCEPTION 'Invalid phone test request' USING ERRCODE='22023';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.rr_motivation_programs WHERE id=p_program AND organization_id=p_org) THEN RAISE EXCEPTION 'Choose a program' USING ERRCODE='42501';END IF;
 payload:=jsonb_build_object('action',p_action,'value',p_value);
 -- Serialize retries of the same start request without holding an organization-wide lock.
 PERFORM pg_advisory_xact_lock(hashtextextended(p_org::text||p_request::text,0));
 IF p_action='start' THEN
  IF p_call IS NOT NULL THEN RAISE EXCEPTION 'Start a new test call';END IF;
  SELECT * INTO c FROM public.rr_phone_test_calls WHERE id=p_request;
  IF FOUND THEN
   IF c.organization_id<>p_org OR c.actor_id<>auth.uid() OR c.program_id<>p_program OR c.requests->p_request::text->'payload' IS DISTINCT FROM payload THEN RAISE EXCEPTION 'Request already used' USING ERRCODE='42501';END IF;
   RETURN c.requests->p_request::text->'result';
  END IF;
  code:=public.rr_phone_normalize(p_value);
  IF length(code) NOT BETWEEN 7 AND 15 THEN RAISE EXCEPTION 'Enter the calling phone number' USING ERRCODE='22023';END IF;
  INSERT INTO public.rr_phone_test_calls(id,organization_id,program_id,actor_id,caller) VALUES(p_request,p_org,p_program,auth.uid(),code) RETURNING * INTO c;
 ELSE
  SELECT * INTO c FROM public.rr_phone_test_calls WHERE id=p_call AND organization_id=p_org AND program_id=p_program AND actor_id=auth.uid() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Test call not found' USING ERRCODE='42501';END IF;
  prior:=c.requests->p_request::text;
  IF prior IS NOT NULL THEN IF prior->'payload' IS DISTINCT FROM payload THEN RAISE EXCEPTION 'Request already used';END IF;RETURN prior->'result';END IF;
  IF c.closed OR c.expires_at<=now() THEN RAISE EXCEPTION 'This test call ended. Start a new call.' USING ERRCODE='22023';END IF;
  IF jsonb_array_length(c.history)>=100 THEN RAISE EXCEPTION 'Test call limit reached. Start a new call.';END IF;
 END IF;
 SELECT coalesce((SELECT settings FROM public.rr_motivation_options WHERE organization_id=p_org),public.rr_motivation_defaults()) INTO opts;
 IF p_action='end' THEN c.closed:=true;r:=jsonb_build_object('outcome','ended','message','Thank you. The test call has ended.');
 ELSIF coalesce((opts->>'phone_frozen')::boolean,true) THEN r:=jsonb_build_object('outcome','denied','message','Telephone access is frozen.'); 
 ELSIF p_action='start' THEN r:=jsonb_build_object('outcome','ready','message','Enter your four-digit student ID, then press #.');
 ELSE
  IF p_action='identify' THEN
   IF p_value !~ '^[0-9]{4}$' OR p_value IS NULL THEN RAISE EXCEPTION 'Enter a four-digit student ID';END IF;
   IF c.student_id IS NOT NULL THEN RAISE EXCEPTION 'End this call before changing students';END IF;
   SELECT student_id INTO sid FROM public.rr_student_aliases WHERE organization_id=p_org AND short_id::text=p_value;
  ELSE sid:=c.student_id;END IF;
  SELECT * INTO s FROM public.students WHERE id=sid AND organization_id=p_org AND NOT is_archived;
  IF NOT FOUND THEN r:=jsonb_build_object('outcome','denied','message','Student or calling number not recognized.');
  ELSIF coalesce(opts->'blocked_students','[]') ? sid::text THEN r:=jsonb_build_object('outcome','denied','message','Telephone access is frozen for this student.');
  ELSIF NOT (
   (coalesce((opts->>'allow_home')::boolean,false) AND c.caller IN (public.rr_phone_normalize(s.home_phone),public.rr_phone_normalize(s.phone))) OR
   (coalesce((opts->>'allow_father')::boolean,false) AND c.caller=public.rr_phone_normalize(s.father_phone)) OR
   (coalesce((opts->>'allow_mother')::boolean,false) AND c.caller=public.rr_phone_normalize(s.mother_phone)) OR
   (coalesce((opts->>'allow_other')::boolean,false) AND c.caller=public.rr_phone_normalize(s.other_phone))
  ) THEN r:=jsonb_build_object('outcome','denied','message','This calling number is not allowed for this student.');
  ELSIF p_action='identify' THEN c.student_id:=sid;r:=jsonb_build_object('outcome','identified','name',s.name,'message','Enter a six-digit points card code, then press #.');
  ELSE
   IF p_value IS NULL OR p_value !~ '^[0-9]{6}$' THEN RAISE EXCEPTION 'Enter a six-digit points card code';END IF;
   SELECT class_id INTO cl FROM public.student_class_assignments WHERE organization_id=p_org AND student_id=sid AND is_current LIMIT 1;
   SELECT q.* INTO card FROM public.rr_motivation_cards q WHERE q.organization_id=p_org AND q.program_id=p_program AND q.code=p_value;
   IF NOT FOUND OR cl IS NULL OR card.class_id IS DISTINCT FROM cl THEN r:=jsonb_build_object('outcome','denied','message','Card not accepted for this class. No telephone override is allowed.');
   ELSIF c.accepted_codes ? p_value THEN r:=jsonb_build_object('outcome','denied','message','This card was already entered during this test call.');
   ELSE
    -- Run the real redemption engine in a subtransaction, replaying this call's
    -- accepted cards so daily/weekly caps also apply. Always roll back rewards,
    -- card changes, normal events and idempotency entries before returning.
    BEGIN
     FOR code IN SELECT jsonb_array_elements_text(c.accepted_codes) LOOP
      PERFORM public.rr_motivation_command(p_org,gen_random_uuid(),'redeem',jsonb_build_object('program',p_program,'student',sid,'code',code));
     END LOOP;
     answer:=public.rr_motivation_command(p_org,gen_random_uuid(),'redeem',jsonb_build_object('program',p_program,'student',sid,'code',p_value));
     RAISE EXCEPTION USING ERRCODE='PHT01',MESSAGE='Rollback phone simulation';
    EXCEPTION WHEN SQLSTATE 'PHT01' THEN NULL;
    END;
    r:=jsonb_build_object('outcome',answer->>'outcome','message',answer->>'message','points',CASE WHEN answer->>'outcome'='accepted' THEN card.points ELSE 0 END,'held',coalesce(answer->'held','false'));
    IF answer->>'outcome'='accepted' THEN c.accepted_codes:=c.accepted_codes||jsonb_build_array(p_value);END IF;
   END IF;
  END IF;
 END IF;
 r:=r||jsonb_build_object('call',c.id,'test',true,'identified',c.student_id IS NOT NULL,'expires_at',c.expires_at);
 c.history:=c.history||jsonb_build_array(jsonb_build_object('at',now(),'action',p_action,'result',r));
 UPDATE public.rr_phone_test_calls SET student_id=c.student_id,accepted_codes=c.accepted_codes,closed=c.closed,history=c.history,
 requests=c.requests||jsonb_build_object(p_request::text,jsonb_build_object('payload',payload,'result',r)) WHERE id=c.id;
 RETURN r;
END $$;
REVOKE ALL ON FUNCTION public.rr_phone_test(uuid,uuid,uuid,uuid,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rr_phone_test(uuid,uuid,uuid,uuid,text,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_phone_test_history(p_org uuid,p_program uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE result jsonb;BEGIN
 PERFORM public.rr_motivation_require_access(p_org);
 SELECT coalesce(jsonb_agg(to_jsonb(x)),'[]') INTO result FROM
 (SELECT id,created_at,closed,history FROM public.rr_phone_test_calls
 WHERE organization_id=p_org AND program_id=p_program AND actor_id=auth.uid()
 ORDER BY created_at DESC LIMIT 20) x;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.rr_phone_test_history(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rr_phone_test_history(uuid,uuid) TO authenticated;
NOTIFY pgrst,'reload schema';

-- Telnyx transport: test mode only. This version never commits rewards.
CREATE TABLE IF NOT EXISTS public.rr_telnyx_calls (
 control_id text PRIMARY KEY, organization_id uuid NOT NULL, program_id uuid NOT NULL,
 actor_id uuid NOT NULL, caller text NOT NULL, test_id uuid,
 stage text NOT NULL DEFAULT 'answer', nonce uuid NOT NULL DEFAULT gen_random_uuid(),
 attempts integer NOT NULL DEFAULT 0, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.rr_telnyx_events (
 event_id uuid PRIMARY KEY, control_id text NOT NULL, input jsonb NOT NULL,
 result jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.rr_telnyx_calls ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rr_telnyx_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rr_telnyx_calls,public.rr_telnyx_events FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.rr_telnyx_test_event(
 p_org uuid,p_program uuid,p_actor uuid,p_event uuid,p_control text,
 p_type text,p_caller text,p_digits text DEFAULT '',p_state text DEFAULT ''
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c public.rr_telnyx_calls%ROWTYPE; previous public.rr_telnyx_events%ROWTYPE;
 input jsonb;result jsonb:='{}';r jsonb;opts jsonb;candidate uuid; candidates uuid[];
 shortid text;prompt text;action text;old_actor text;new_request uuid:=gen_random_uuid();
BEGIN
 IF p_event IS NULL OR p_org IS NULL OR p_program IS NULL OR p_actor IS NULL OR
 p_control IS NULL OR length(p_control) NOT BETWEEN 1 AND 512 OR length(coalesce(p_digits,''))>16 THEN
 RAISE EXCEPTION 'Invalid event';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.organization_members WHERE organization_id=p_org AND user_id=p_actor AND role::text IN ('admin','super_admin')) OR
 NOT EXISTS(SELECT 1 FROM public.rr_motivation_programs WHERE id=p_program AND organization_id=p_org) THEN
 RAISE EXCEPTION 'Phone administrator or program is not authorized' USING ERRCODE='42501';END IF;
 input:=jsonb_build_object('org',p_org,'program',p_program,'actor',p_actor,'control',p_control,'type',p_type,'caller',p_caller,'digits',p_digits,'state',p_state);
 PERFORM pg_advisory_xact_lock(hashtextextended(p_control,0));
 SELECT * INTO previous FROM public.rr_telnyx_events WHERE event_id=p_event;
 IF FOUND THEN
 IF previous.input IS DISTINCT FROM input THEN RAISE EXCEPTION 'Event ID reused';END IF;
 RETURN previous.result;END IF;
 old_actor:=current_setting('request.jwt.claim.sub',true);
 PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
 SELECT * INTO c FROM public.rr_telnyx_calls WHERE control_id=p_control FOR UPDATE;
 IF FOUND AND (c.organization_id<>p_org OR c.program_id<>p_program OR c.actor_id<>p_actor OR c.caller IS DISTINCT FROM p_caller) THEN
 RAISE EXCEPTION 'Call context changed' USING ERRCODE='42501';END IF;
 IF NOT FOUND THEN
 IF p_type='call.hangup' THEN
 INSERT INTO public.rr_telnyx_calls(control_id,organization_id,program_id,actor_id,caller,stage)
 VALUES(p_control,p_org,p_program,p_actor,p_caller,'closed') RETURNING * INTO c;
 ELSIF p_type='call.initiated' THEN
 INSERT INTO public.rr_telnyx_calls(control_id,organization_id,program_id,actor_id,caller)
 VALUES(p_control,p_org,p_program,p_actor,p_caller) RETURNING * INTO c;
 action:='answer';
 ELSE RAISE EXCEPTION 'Call start has not arrived yet';END IF;
 ELSIF p_type='call.hangup' THEN c.stage:='closed';
 ELSIF c.stage='closed' THEN NULL;
 ELSIF c.created_at<now()-interval '15 minutes' THEN action:='hangup';c.stage:='closed';
 ELSIF p_type='call.answered' AND c.stage='answer' THEN
 c.test_id:=gen_random_uuid();
 r:=public.rr_phone_test(p_org,p_program,NULL,c.test_id,'start',p_caller);
 SELECT coalesce((SELECT settings FROM public.rr_motivation_options WHERE organization_id=p_org),public.rr_motivation_defaults()) INTO opts;
 IF r->>'outcome'='denied' THEN c.stage:='closing';prompt:=r->>'message';
 ELSE
 SELECT array_agg(s.id) INTO candidates FROM public.students s WHERE s.organization_id=p_org AND NOT s.is_archived
 AND NOT (coalesce(opts->'blocked_students','[]') ? s.id::text)
 AND EXISTS(SELECT 1 FROM public.student_class_assignments a WHERE a.organization_id=p_org AND a.student_id=s.id AND a.is_current)
 AND (
 (coalesce((opts->>'allow_home')::boolean,false) AND public.rr_phone_normalize(p_caller) IN(public.rr_phone_normalize(s.home_phone),public.rr_phone_normalize(s.phone))) OR
 (coalesce((opts->>'allow_father')::boolean,false) AND public.rr_phone_normalize(p_caller)=public.rr_phone_normalize(s.father_phone)) OR
 (coalesce((opts->>'allow_mother')::boolean,false) AND public.rr_phone_normalize(p_caller)=public.rr_phone_normalize(s.mother_phone)) OR
 (coalesce((opts->>'allow_other')::boolean,false) AND public.rr_phone_normalize(p_caller)=public.rr_phone_normalize(s.other_phone)));
 IF coalesce(cardinality(candidates),0)=0 THEN c.stage:='closing';prompt:='This telephone number is not registered for telephone access.';
 ELSIF cardinality(candidates)=1 THEN
 candidate:=candidates[1];SELECT short_id::text INTO shortid FROM public.rr_student_aliases WHERE organization_id=p_org AND student_id=candidate;
 IF shortid IS NULL THEN c.stage:='closing';prompt:='Please ask the school to assign your student ID.';
 ELSE r:=public.rr_phone_test(p_org,p_program,c.test_id,new_request,'identify',shortid);
 IF (r->>'identified')::boolean THEN c.stage:='card';ELSE c.stage:='closing';END IF;prompt:=r->>'message';END IF;
 ELSE c.stage:='identify';prompt:='Enter your four digit student ID, followed by pound.';END IF;
 END IF;
 prompt:='YKonnect telephone test. No points will be saved. '||prompt;
 ELSIF p_type='call.gather.ended' AND c.stage IN('identify','card') AND p_state=c.nonce::text THEN
 c.attempts:=c.attempts+1;
 IF c.attempts>=30 OR p_digits='' THEN c.stage:='closing';prompt:='The test call has ended. Thank you.';
 ELSIF (c.stage='identify' AND p_digits !~ '^[0-9]{4}$') OR (c.stage='card' AND p_digits !~ '^[0-9]{6}$') THEN
 prompt:='Invalid code. '||CASE WHEN c.stage='identify' THEN 'Enter four digits.' ELSE 'Enter six digits.' END;
 ELSE
 r:=public.rr_phone_test(p_org,p_program,c.test_id,new_request,c.stage,p_digits);
 IF c.stage='identify' AND coalesce((r->>'identified')::boolean,false) THEN c.stage:='card';END IF;
 prompt:=coalesce(r->>'message','Please try again.');
 IF c.stage='card' THEN prompt:=prompt||' Enter another six digit points card, followed by pound.';END IF;
 IF c.stage='identify' AND c.attempts>=3 THEN c.stage:='closing';prompt:='The student could not be verified. Goodbye.';END IF;
 END IF;
 ELSIF p_type='call.speak.ended' AND c.stage='closing' AND p_state=c.nonce::text THEN
 action:='hangup';c.stage:='closed';
 END IF;
 IF prompt IS NOT NULL THEN
 c.nonce:=gen_random_uuid();action:=CASE WHEN c.stage='closing' THEN 'speak' ELSE 'gather_using_speak' END;
 END IF;
 UPDATE public.rr_telnyx_calls SET stage=c.stage,test_id=c.test_id,nonce=c.nonce,attempts=c.attempts WHERE control_id=p_control;
 IF action IS NOT NULL THEN
 result:=jsonb_build_object('action',action,'command_id',gen_random_uuid(),'state',c.nonce,'prompt',prompt,'digits',CASE WHEN c.stage='identify' THEN 4 ELSE 6 END);
 END IF;
 INSERT INTO public.rr_telnyx_events(event_id,control_id,input,result) VALUES(p_event,p_control,input,result);
 PERFORM set_config('request.jwt.claim.sub',coalesce(old_actor,''),true);
 RETURN result;
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('request.jwt.claim.sub',coalesce(old_actor,''),true);RAISE;
END $$;
REVOKE ALL ON FUNCTION public.rr_telnyx_test_event(uuid,uuid,uuid,uuid,text,text,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rr_telnyx_test_event(uuid,uuid,uuid,uuid,text,text,text,text,text) TO service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
