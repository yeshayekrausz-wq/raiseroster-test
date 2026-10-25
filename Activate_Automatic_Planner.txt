-- Incremental update: requires Random Cards and Hold Overview. Does not reset existing data.
BEGIN;
CREATE TABLE IF NOT EXISTS public.rr_planner_sessions(organization_id uuid NOT NULL REFERENCES public.organizations(id),key text NOT NULL,label text NOT NULL CHECK(length(label) BETWEEN 1 AND 60),PRIMARY KEY(organization_id,key),UNIQUE(organization_id,label));
CREATE TABLE IF NOT EXISTS public.rr_planner_plans(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL REFERENCES public.organizations(id),program_id uuid NOT NULL REFERENCES public.rr_motivation_programs(id),request_id uuid NOT NULL,created_by uuid NOT NULL,payload jsonb NOT NULL,preview jsonb NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(organization_id,request_id));
CREATE TABLE IF NOT EXISTS public.rr_planner_weeks(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),plan_id uuid NOT NULL REFERENCES public.rr_planner_plans(id) ON DELETE CASCADE,period_id uuid NOT NULL UNIQUE REFERENCES public.rr_reward_periods(id) ON DELETE CASCADE,ordinal int NOT NULL,release_mode text NOT NULL CHECK(release_mode IN ('open','manual','start','end')),release_at timestamptz,processed boolean NOT NULL DEFAULT false,order_id uuid REFERENCES public.rr_motivation_orders(id) ON DELETE SET NULL,UNIQUE(plan_id,ordinal));
ALTER TABLE public.rr_planner_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rr_planner_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rr_planner_weeks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rr_planner_sessions,public.rr_planner_plans,public.rr_planner_weeks FROM PUBLIC,anon,authenticated;
ALTER TABLE public.rr_teacher_portals DROP CONSTRAINT IF EXISTS rr_teacher_portals_session_check;
ALTER TABLE public.rr_teacher_portals DROP CONSTRAINT IF EXISTS rr_teacher_portals_organization_id_email_class_id_key;
CREATE UNIQUE INDEX IF NOT EXISTS rr_teacher_email_class_session ON public.rr_teacher_portals(organization_id,email,class_id,session);
ALTER TABLE public.rr_motivation_cards DROP CONSTRAINT IF EXISTS rr_motivation_cards_session_check;
ALTER TABLE public.rr_motivation_cards ADD COLUMN IF NOT EXISTS session_label text;
CREATE OR REPLACE FUNCTION public.rr_planner_sessions_read(p_org uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN PERFORM public.rr_motivation_require_access(p_org);RETURN '[{"key":"morning","label":"לפנה״צ"},{"key":"afternoon","label":"אחה״צ"}]'::jsonb||coalesce((SELECT jsonb_agg(to_jsonb(s)-'organization_id' ORDER BY label) FROM public.rr_planner_sessions s WHERE organization_id=p_org),'[]');END $$;
CREATE OR REPLACE FUNCTION public.rr_planner_session_add(p_org uuid,p_label text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN PERFORM public.rr_motivation_require_access(p_org);PERFORM 1 FROM public.organizations WHERE id=p_org FOR UPDATE;
IF p_label IS NULL OR length(btrim(p_label)) NOT BETWEEN 1 AND 60 OR btrim(p_label) IN ('לפנה״צ','אחה״צ') THEN RAISE EXCEPTION 'Enter a unique session name (1–60 characters)' USING ERRCODE='22023';END IF;
IF (SELECT count(*) FROM public.rr_planner_sessions WHERE organization_id=p_org)>=10 THEN RAISE EXCEPTION 'At most 10 custom sessions' USING ERRCODE='22023';END IF;
INSERT INTO public.rr_planner_sessions VALUES(p_org,'s_'||replace(gen_random_uuid()::text,'-',''),btrim(p_label)) ON CONFLICT(organization_id,label) DO NOTHING;
RETURN public.rr_planner_sessions_read(p_org);END $$;
CREATE OR REPLACE FUNCTION public.rr_motivation_teacher_save(p_org uuid,p_id uuid,p_revision bigint,p_name text,p_email text,p_class uuid,p_session text,p_enabled boolean) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE old public.rr_teacher_portals%ROWTYPE;result jsonb;email_value text;
BEGIN
 PERFORM public.rr_motivation_require_access(p_org);PERFORM 1 FROM public.organizations WHERE id=p_org FOR UPDATE;
 email_value:=nullif(lower(btrim(p_email)),'');
 IF p_name IS NULL OR length(btrim(p_name)) NOT BETWEEN 1 AND 120 OR p_session IS NULL OR (p_session NOT IN ('full','morning','afternoon') AND NOT EXISTS(SELECT 1 FROM public.rr_planner_sessions WHERE organization_id=p_org AND key=p_session)) OR p_enabled IS NULL OR (email_value IS NOT NULL AND email_value !~ '^[^ @]+@[^ @]+\.[^ @]+$') THEN RAISE EXCEPTION 'Enter a teacher name, session and valid optional email' USING ERRCODE='22023';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.classes c JOIN public.school_years y ON y.id=c.school_year_id AND y.is_current WHERE c.id=p_class AND c.organization_id=p_org AND c.is_active) THEN RAISE EXCEPTION 'Choose a current class' USING ERRCODE='22023';END IF;
 IF p_id IS NOT NULL THEN SELECT * INTO old FROM public.rr_teacher_portals WHERE id=p_id AND organization_id=p_org FOR UPDATE;IF NOT FOUND THEN RAISE EXCEPTION 'Teacher not found' USING ERRCODE='42501';END IF;END IF;
 IF p_revision IS DISTINCT FROM coalesce(old.revision,0) THEN RAISE EXCEPTION 'Teacher changed. Reload before saving.' USING ERRCODE='40001';END IF;
 IF p_enabled AND EXISTS(SELECT 1 FROM public.rr_teacher_portals t WHERE organization_id=p_org AND class_id=p_class AND enabled AND (p_id IS NULL OR id<>p_id) AND (session IS NULL OR session=p_session OR (session='full' AND p_session IN ('morning','afternoon')) OR (p_session='full' AND session IN ('morning','afternoon')))) THEN RAISE EXCEPTION 'This class already has a teacher for that session. Edit or disable that assignment first.' USING ERRCODE='22023';END IF;
 IF p_id IS NULL THEN INSERT INTO public.rr_teacher_portals(organization_id,class_id,name,email,session,enabled) VALUES(p_org,p_class,btrim(p_name),email_value,p_session,p_enabled) RETURNING to_jsonb(rr_teacher_portals.*) INTO result;
 ELSE UPDATE public.rr_teacher_portals SET name=btrim(p_name),email=email_value,class_id=p_class,session=p_session,enabled=p_enabled,revision=revision+1 WHERE id=p_id RETURNING to_jsonb(rr_teacher_portals.*) INTO result;END IF;
 INSERT INTO public.rr_motivation_events(organization_id,actor_id,kind,detail) VALUES(p_org,auth.uid(),'teacher_assignment',jsonb_build_object('before',to_jsonb(old),'after',result));RETURN result;
END $$;

-- Integer class/week allocation. Every requested percentage is a minimum; impossible rounding is rejected.
CREATE OR REPLACE FUNCTION public.rr_planner_distribution(p_count int,p_required numeric,p_rules jsonb) RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE r jsonb;n int;used int:=0;fixed_total numeric:=0;offset_total numeric:=0;variable_count int;fixed_count int:=0;base int;points int;dist jsonb:='[]';pct numeric:=0;total numeric:=0;unrounded_min numeric:=0;
BEGIN
IF p_count IS NULL OR p_count NOT BETWEEN 1 AND 20000 OR p_required IS NULL OR p_required<=0 OR jsonb_typeof(p_rules) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rules)>20 THEN RAISE EXCEPTION 'Invalid allocation' USING ERRCODE='22023';END IF;
FOR r IN SELECT value FROM jsonb_array_elements(p_rules) LOOP
 IF coalesce(r->>'percent','') !~ '^\d+(\.\d{1,4})?$' OR (r->>'percent')::numeric<=0 OR (r->>'percent')::numeric>100 OR coalesce(r->>'value','') !~ '^\d+$' OR (r->>'value')::numeric>1000000 OR coalesce(r->>'kind','') NOT IN ('fixed','extra') THEN RAISE EXCEPTION 'Enter a positive percentage and whole points value for each rule' USING ERRCODE='22023';END IF;
 unrounded_min:=unrounded_min+p_count*(r->>'percent')::numeric/100*(r->>'value')::numeric;
 n:=ceil(p_count*(r->>'percent')::numeric/100);used:=used+n;pct:=pct+(r->>'percent')::numeric;
 IF r->>'kind'='fixed' THEN fixed_count:=fixed_count+n;fixed_total:=fixed_total+n*(r->>'value')::numeric;ELSE offset_total:=offset_total+n*(r->>'value')::numeric;END IF;
END LOOP;
IF pct>100 OR used>p_count THEN RAISE EXCEPTION 'Rounded percentage groups exceed the number of cards. Reduce a percentage or increase cards per child.' USING ERRCODE='22023';END IF;
variable_count:=p_count-fixed_count;
IF variable_count=0 AND fixed_total<p_required THEN RAISE EXCEPTION 'Fixed card values cannot reach the target. Leave cards for automatic calculation or increase their value.' USING ERRCODE='22023';END IF;
base:=CASE WHEN variable_count>0 THEN greatest(0,ceil((p_required-fixed_total-offset_total)/variable_count)) ELSE 0 END;
IF base>1000000 THEN RAISE EXCEPTION 'Points per card exceed supported range' USING ERRCODE='22023';END IF;
FOR r IN SELECT value FROM jsonb_array_elements(p_rules) LOOP
 n:=ceil(p_count*(r->>'percent')::numeric/100);points:=CASE WHEN r->>'kind'='fixed' THEN (r->>'value')::int ELSE base+(r->>'value')::int END;
 IF points>1000000 THEN RAISE EXCEPTION 'Points per card exceed supported range' USING ERRCODE='22023';END IF;
 dist:=dist||jsonb_build_array(jsonb_build_object('points',points,'count',n,'requested_percent',(r->>'percent')::numeric,'actual_percent',round(100.0*n/p_count,4),'kind',r->>'kind'));total:=total+n*points;
END LOOP;
IF used<p_count THEN dist:=dist||jsonb_build_array(jsonb_build_object('points',base,'count',p_count-used,'requested_percent',NULL,'actual_percent',round(100.0*(p_count-used)/p_count,4),'kind','base'));total:=total+(p_count-used)*base;END IF;
SELECT jsonb_agg(jsonb_build_object('points',combined.points,'count',combined.n,'requested_percent',combined.requested,'actual_percent',round(100.0*combined.n/p_count,4)) ORDER BY combined.first_position) INTO dist FROM (SELECT (value->>'points')::int points,sum((value->>'count')::int)::int n,sum((value->>'requested_percent')::numeric) requested,min(ordinality) first_position FROM jsonb_array_elements(dist) WITH ORDINALITY GROUP BY (value->>'points')::int) combined;
RETURN jsonb_build_object('base',base,'distribution',dist,'points',total,'required',p_required,'rule_extra_points',greatest(0,unrounded_min-p_required),'rounding_points',total-greatest(p_required,unrounded_min),'rounding_percent',round(100*(total-greatest(p_required,unrounded_min))/p_required,4));END $$;
CREATE OR REPLACE FUNCTION public.rr_planner_preview(p_org uuid,p_program uuid,p_data jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE target numeric;extra numeric;goal numeric;each_count int:=0;w jsonb;cl text;allocation jsonb;session_row jsonb;teacher_rows jsonb;members jsonb;class_rows jsonb:='[]';week_rows jsonb:='[]';rows jsonb;ns int;nw int;idx int:=0;start_at timestamptz;end_at timestamptz;last_end timestamptz;zone text;settings jsonb;epoch bigint;result jsonb;previous_target numeric:=0;week_target numeric;ses jsonb;teacher_count int;mode text;
BEGIN
PERFORM public.rr_motivation_require_access(p_org);
IF NOT EXISTS(SELECT 1 FROM public.rr_motivation_programs WHERE id=p_program AND organization_id=p_org) THEN RAISE EXCEPTION 'Choose a school program' USING ERRCODE='42501';END IF;
SELECT coalesce((SELECT c.epoch FROM public.rr_reward_control c WHERE organization_id=p_org),0) INTO epoch;
IF (p_data->>'epoch')::bigint IS DISTINCT FROM epoch THEN RAISE EXCEPTION 'Test data changed. Reload planner.' USING ERRCODE='40001';END IF;
IF coalesce(p_data->>'target','') !~ '^\d+$' OR (p_data->>'target')::numeric NOT BETWEEN 1 AND 100000000 OR coalesce(p_data->>'extra','') !~ '^\d+(\.\d{1,4})?$' OR (p_data->>'extra')::numeric NOT BETWEEN 0 AND 1000 THEN RAISE EXCEPTION 'Enter a whole target and extra percentage (0 is allowed)' USING ERRCODE='22023';END IF;
target:=(p_data->>'target')::numeric;extra:=(p_data->>'extra')::numeric;goal:=ceil(target*(1+extra/100));mode:=p_data->>'mode';
IF mode IS NULL OR mode NOT IN ('total','sessions') THEN RAISE EXCEPTION 'Choose total or sessions' USING ERRCODE='22023';END IF;
IF mode='total' THEN
 IF coalesce(p_data->>'each','') !~ '^\d+$' THEN RAISE EXCEPTION 'Enter cards per child' USING ERRCODE='22023';END IF;each_count:=(p_data->>'each')::int;
ELSE
 IF jsonb_typeof(p_data->'sessions') IS DISTINCT FROM 'array' OR jsonb_array_length(p_data->'sessions') NOT BETWEEN 1 AND 12 THEN RAISE EXCEPTION 'Choose session quantities' USING ERRCODE='22023';END IF;
 IF (SELECT count(*) FROM jsonb_array_elements(p_data->'sessions'))<>(SELECT count(DISTINCT value->>'key') FROM jsonb_array_elements(p_data->'sessions')) THEN RAISE EXCEPTION 'Duplicate session' USING ERRCODE='22023';END IF;
 FOR ses IN SELECT value FROM jsonb_array_elements(p_data->'sessions') LOOP
 IF coalesce(ses->>'each','') !~ '^\d+$' OR (ses->>'each')::numeric NOT BETWEEN 0 AND 1000 OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.rr_planner_sessions_read(p_org)) WHERE value->>'key'=ses->>'key') THEN RAISE EXCEPTION 'Invalid session quantity' USING ERRCODE='22023';END IF;each_count:=each_count+(ses->>'each')::int;
 END LOOP;
END IF;
IF each_count NOT BETWEEN 1 AND 1000 THEN RAISE EXCEPTION 'Choose 1–1000 cards per child per week' USING ERRCODE='22023';END IF;
IF jsonb_typeof(p_data->'weeks') IS DISTINCT FROM 'array' OR jsonb_array_length(p_data->'weeks') NOT BETWEEN 1 AND 104 OR jsonb_typeof(p_data->'classes') IS DISTINCT FROM 'array' OR jsonb_array_length(p_data->'classes') NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'Select weeks and classes' USING ERRCODE='22023';END IF;
IF (SELECT count(*) FROM jsonb_array_elements_text(p_data->'classes'))<>(SELECT count(DISTINCT value) FROM jsonb_array_elements_text(p_data->'classes')) THEN RAISE EXCEPTION 'Duplicate class' USING ERRCODE='22023';END IF;
SELECT coalesce((SELECT o.settings FROM public.rr_motivation_options o WHERE organization_id=p_org),public.rr_motivation_defaults()) INTO settings;zone:=settings->>'timezone';
IF NOT coalesce((settings->>'cards_enabled')::boolean,false) THEN RAISE EXCEPTION 'Enable reward cards in Program Settings' USING ERRCODE='22023';END IF;
IF coalesce((settings->>'weekly_cap')::int,0)<each_count THEN RAISE EXCEPTION 'Weekly redemption cap is lower than cards per child. Increase it in Program Settings / Limits first.' USING ERRCODE='22023';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=zone) THEN RAISE EXCEPTION 'Set the school timezone first' USING ERRCODE='22023';END IF;
FOR cl IN SELECT value FROM jsonb_array_elements_text(p_data->'classes') LOOP
 IF NOT EXISTS(SELECT 1 FROM public.classes c JOIN public.school_years y ON y.id=c.school_year_id AND y.is_current WHERE c.id=cl::uuid AND c.organization_id=p_org AND c.is_active) THEN RAISE EXCEPTION 'Choose current school classes' USING ERRCODE='42501';END IF;
 SELECT count(*),jsonb_agg(s.id ORDER BY s.id) INTO ns,members FROM public.students s JOIN public.student_class_assignments a ON a.student_id=s.id AND a.organization_id=p_org AND a.is_current AND a.class_id=cl::uuid WHERE s.organization_id=p_org AND NOT s.is_archived;
 IF ns=0 OR ns*each_count>20000 THEN RAISE EXCEPTION 'Class is empty or exceeds 20,000 cards per week' USING ERRCODE='22023';END IF;
 rows:='[]';
 IF mode='total' THEN
 SELECT jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,'revision',t.revision) ORDER BY t.id) INTO teacher_rows FROM public.rr_teacher_portals t WHERE organization_id=p_org AND class_id=cl::uuid AND enabled;
 IF teacher_rows IS NULL THEN RAISE EXCEPTION 'Assign a teacher for every selected class' USING ERRCODE='22023';END IF;
 rows:=jsonb_build_array(jsonb_build_object('session',NULL,'session_label','','each',each_count,'count',ns*each_count,'teachers',teacher_rows,'teacher',(SELECT string_agg(value->>'name',' / ') FROM jsonb_array_elements(teacher_rows))));
 ELSE
 FOR ses IN SELECT value FROM jsonb_array_elements(p_data->'sessions') WHERE (value->>'each')::int>0 LOOP
 SELECT count(*),jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,'revision',t.revision) ORDER BY t.id) INTO teacher_count,teacher_rows FROM public.rr_teacher_portals t WHERE organization_id=p_org AND class_id=cl::uuid AND enabled AND (session=ses->>'key' OR (session='full' AND ses->>'key' IN ('morning','afternoon')));
 IF teacher_count<>1 THEN RAISE EXCEPTION 'Class % needs exactly one teacher for session %', (SELECT name FROM public.classes WHERE id=cl::uuid),(SELECT value->>'label' FROM jsonb_array_elements(public.rr_planner_sessions_read(p_org)) WHERE value->>'key'=ses->>'key') USING ERRCODE='22023';END IF;
 rows:=rows||jsonb_build_array(jsonb_build_object('session',ses->>'key','session_label',(SELECT value->>'label' FROM jsonb_array_elements(public.rr_planner_sessions_read(p_org)) WHERE value->>'key'=ses->>'key'),'each',(ses->>'each')::int,'count',ns*(ses->>'each')::int,'teachers',teacher_rows,'teacher',teacher_rows->0->>'name'));
 END LOOP;END IF;
 class_rows:=class_rows||jsonb_build_array(jsonb_build_object('class_id',cl,'class_name',(SELECT name FROM public.classes WHERE id=cl::uuid),'students',ns,'members',members,'sessions',rows));
END LOOP;
IF (SELECT sum((value->>'students')::int*each_count) FROM jsonb_array_elements(class_rows))>20000 THEN RAISE EXCEPTION 'At most 20,000 cards per week across selected classes' USING ERRCODE='22023';END IF;
nw:=jsonb_array_length(p_data->'weeks');
FOR w IN SELECT value FROM jsonb_array_elements(p_data->'weeks') LOOP
 idx:=idx+1;
 IF coalesce(w->>'start','') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$' OR coalesce(w->>'end','') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$' OR coalesce(w->>'release','') NOT IN ('open','manual','start','end') THEN RAISE EXCEPTION 'Set week start, end and release mode' USING ERRCODE='22023';END IF;
 start_at:=(w->>'start')::timestamp AT TIME ZONE zone;end_at:=(w->>'end')::timestamp AT TIME ZONE zone;
 IF end_at<=start_at OR end_at-start_at>interval '8 days' OR (last_end IS NOT NULL AND start_at<last_end) THEN RAISE EXCEPTION 'Weeks must be ordered, non-overlapping and at most eight days long' USING ERRCODE='22023';END IF;
 IF to_char(start_at AT TIME ZONE zone,'YYYY-MM-DD"T"HH24:MI')<>w->>'start' OR to_char(end_at AT TIME ZONE zone,'YYYY-MM-DD"T"HH24:MI')<>w->>'end' THEN RAISE EXCEPTION 'A selected time does not exist because of daylight saving. Choose another time.' USING ERRCODE='22023';END IF;
 last_end:=end_at;week_target:=floor(goal*idx/nw)-previous_target;previous_target:=floor(goal*idx/nw);
 IF week_target<=0 THEN RAISE EXCEPTION 'Target is too small for the selected number of weeks' USING ERRCODE='22023';END IF;
 rows:='[]';
 FOR session_row IN SELECT value FROM jsonb_array_elements(class_rows) LOOP
 allocation:=public.rr_planner_distribution((session_row->>'students')::int*each_count,week_target*(session_row->>'students')::int,coalesce(p_data->'rules','[]'));
 rows:=rows||jsonb_build_array(session_row||allocation||jsonb_build_object('per_child',round((allocation->>'points')::numeric/(session_row->>'students')::int,4)));
 END LOOP;
 week_rows:=week_rows||jsonb_build_array(jsonb_build_object('number',idx,'start',w->>'start','end',w->>'end','start_at',start_at,'end_at',end_at,'from',substr(w->>'start',1,10),'through',to_char(((w->>'end')::timestamp-interval '1 second'),'YYYY-MM-DD'),'release',w->>'release','target',week_target,'classes',rows));
END LOOP;
result:=jsonb_build_object('target',target,'extra',extra,'required',goal,'each',each_count,'timezone',zone,'epoch',epoch,'weeks',week_rows);
RETURN result||jsonb_build_object('token',md5(result::text));END $$;
CREATE OR REPLACE FUNCTION public.rr_planner_save(p_org uuid,p_program uuid,p_request uuid,p_data jsonb,p_token text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE plan jsonb;old public.rr_planner_plans%ROWTYPE;pid uuid;period uuid;w jsonb;BEGIN
PERFORM public.rr_motivation_require_access(p_org);PERFORM 1 FROM public.organizations WHERE id=p_org FOR UPDATE;
IF p_request IS NULL THEN RAISE EXCEPTION 'Missing request' USING ERRCODE='22023';END IF;
SELECT * INTO old FROM public.rr_planner_plans WHERE organization_id=p_org AND request_id=p_request;
IF FOUND THEN IF old.payload<>p_data OR old.program_id<>p_program OR old.preview->>'token' IS DISTINCT FROM p_token THEN RAISE EXCEPTION 'Request already used' USING ERRCODE='22023';END IF;RETURN jsonb_build_object('id',old.id);END IF;
plan:=public.rr_planner_preview(p_org,p_program,p_data);
IF plan->>'token' IS DISTINCT FROM p_token THEN RAISE EXCEPTION 'Roster or teachers changed. Preview again.' USING ERRCODE='40001';END IF;
INSERT INTO public.rr_planner_plans(organization_id,program_id,request_id,created_by,payload,preview) VALUES(p_org,p_program,p_request,auth.uid(),p_data,plan) RETURNING id INTO pid;
FOR w IN SELECT value FROM jsonb_array_elements(plan->'weeks') LOOP
 IF EXISTS(SELECT 1 FROM public.rr_reward_periods WHERE organization_id=p_org AND program_id=p_program AND starts<=(w->>'through')::date AND ends>=(w->>'from')::date) THEN RAISE EXCEPTION 'A card week already overlaps %. Existing cards were not changed.',w->>'from' USING ERRCODE='22023';END IF;
 INSERT INTO public.rr_reward_periods(organization_id,program_id,starts,ends) VALUES(p_org,p_program,(w->>'from')::date,(w->>'through')::date) RETURNING id INTO period;
 INSERT INTO public.rr_planner_weeks(plan_id,period_id,ordinal,release_mode,release_at) VALUES(pid,period,(w->>'number')::int,w->>'release',CASE w->>'release' WHEN 'start' THEN (w->>'start_at')::timestamptz WHEN 'end' THEN (w->>'end_at')::timestamptz ELSE NULL END);
END LOOP;
INSERT INTO public.rr_motivation_events(organization_id,program_id,actor_id,kind,detail) VALUES(p_org,p_program,auth.uid(),'planner_saved',jsonb_build_object('plan',pid,'target',plan->'target','weeks',jsonb_array_length(plan->'weeks')));
RETURN jsonb_build_object('id',pid);END $$;
CREATE OR REPLACE FUNCTION public.rr_planner_generate(p_org uuid,p_week uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE week public.rr_planner_weeks%ROWTYPE;plan public.rr_planner_plans%ROWTYPE;w jsonb;c jsonb;s jsonb;batch uuid;oid uuid;batches jsonb:='[]';pool numeric[];pos int;i int;total int:=0;current_members jsonb;teacher jsonb;
BEGIN
PERFORM public.rr_motivation_require_access(p_org);PERFORM 1 FROM public.organizations WHERE id=p_org FOR UPDATE;
SELECT * INTO week FROM public.rr_planner_weeks WHERE id=p_week;SELECT * INTO plan FROM public.rr_planner_plans WHERE id=week.plan_id AND organization_id=p_org;
IF NOT FOUND THEN RAISE EXCEPTION 'Week not found' USING ERRCODE='42501';END IF;
IF week.order_id IS NOT NULL THEN RETURN jsonb_build_object('id',week.order_id);END IF;
w:=plan.preview->'weeks'->(week.ordinal-1);
FOR c IN SELECT value FROM jsonb_array_elements(w->'classes') LOOP
 SELECT jsonb_agg(s.id ORDER BY s.id) INTO current_members FROM public.students s JOIN public.student_class_assignments a ON a.student_id=s.id AND a.organization_id=p_org AND a.is_current AND a.class_id=(c->>'class_id')::uuid WHERE s.organization_id=p_org AND NOT s.is_archived;
 IF current_members IS DISTINCT FROM c->'members' THEN RAISE EXCEPTION 'Class roster changed after planning. No cards generated for this week. Refresh remaining weeks to update the roster.' USING ERRCODE='40001';END IF;
 FOR s IN SELECT value FROM jsonb_array_elements(c->'sessions') LOOP
 FOR teacher IN SELECT value FROM jsonb_array_elements(s->'teachers') LOOP
 IF NOT EXISTS(SELECT 1 FROM public.rr_teacher_portals WHERE id=(teacher->>'id')::uuid AND organization_id=p_org AND class_id=(c->>'class_id')::uuid AND enabled AND revision=(teacher->>'revision')::bigint) THEN RAISE EXCEPTION 'Teacher assignment changed. Refresh remaining weeks before generating.' USING ERRCODE='40001';END IF;
 END LOOP;END LOOP;
 SELECT array_agg(points ORDER BY random()) INTO pool FROM (SELECT (d.value->>'points')::numeric points FROM jsonb_array_elements(c->'distribution') d CROSS JOIN LATERAL generate_series(1,(d.value->>'count')::int)) items;pos:=1;
 FOR s IN SELECT value FROM jsonb_array_elements(c->'sessions') LOOP
 batch:=gen_random_uuid();
 FOR i IN 1..(s->>'count')::int LOOP
 INSERT INTO public.rr_motivation_cards(organization_id,program_id,class_id,points,teacher,batch_id,valid_from_date,valid_through_date,period_id,session,session_label)
 VALUES(p_org,plan.program_id,(c->>'class_id')::uuid,pool[pos],s->>'teacher',batch,(w->>'from')::date,(w->>'through')::date,week.period_id,s->>'session',s->>'session_label');pos:=pos+1;total:=total+1;
 END LOOP;
 batches:=batches||jsonb_build_array(s-'teachers'||jsonb_build_object('batch_id',batch,'class_id',c->>'class_id','class_name',c->>'class_name'));
 END LOOP;
END LOOP;
INSERT INTO public.rr_motivation_orders(organization_id,program_id,request_id,payload,plan,batches) VALUES(p_org,plan.program_id,p_week,jsonb_build_object('planner_week',p_week),jsonb_build_object('from',w->>'from','through',w->>'through','total',total,'period_id',week.period_id),batches) RETURNING id INTO oid;
UPDATE public.rr_planner_weeks SET order_id=oid WHERE id=p_week;
INSERT INTO public.rr_motivation_events(organization_id,program_id,actor_id,kind,detail) VALUES(p_org,plan.program_id,auth.uid(),'cards_generated',jsonb_build_object('planner_week',p_week,'order',oid,'total',total));
RETURN jsonb_build_object('id',oid,'total',total);END $$;
CREATE OR REPLACE FUNCTION public.rr_planner_refresh(p_org uuid,p_plan uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE old public.rr_planner_plans%ROWTYPE;fresh jsonb;weeks jsonb:='[]';w jsonb;BEGIN
PERFORM public.rr_motivation_require_access(p_org);PERFORM 1 FROM public.organizations WHERE id=p_org FOR UPDATE;
SELECT * INTO old FROM public.rr_planner_plans WHERE id=p_plan AND organization_id=p_org;
IF NOT FOUND THEN RAISE EXCEPTION 'Plan not found' USING ERRCODE='42501';END IF;
fresh:=public.rr_planner_preview(p_org,old.program_id,old.payload);
FOR w IN SELECT value FROM jsonb_array_elements(fresh->'weeks') LOOP
 IF EXISTS(SELECT 1 FROM public.rr_planner_weeks WHERE plan_id=p_plan AND ordinal=(w->>'number')::int AND order_id IS NOT NULL) THEN weeks:=weeks||jsonb_build_array(old.preview->'weeks'->((w->>'number')::int-1));ELSE weeks:=weeks||jsonb_build_array(w);END IF;
END LOOP;
UPDATE public.rr_planner_plans SET preview=jsonb_set(fresh,'{weeks}',weeks) WHERE id=p_plan;
INSERT INTO public.rr_motivation_events(organization_id,program_id,actor_id,kind,detail) VALUES(p_org,old.program_id,auth.uid(),'planner_refreshed',jsonb_build_object('plan',p_plan,'generated_weeks_preserved',true));END $$;
CREATE OR REPLACE FUNCTION public.rr_reward_percent(p_card public.rr_motivation_cards,p_student uuid) RETURNS numeric LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE result numeric;choice text;
BEGIN
 IF p_card.period_id IS NULL THEN RETURN 100;END IF;
 SELECT a.pct INTO result FROM public.rr_reward_authorizations a WHERE a.period_id=p_card.period_id AND a.student_id=p_student AND (a.day IS NULL OR a.day=p_card.card_day) AND (a.session IS NULL OR a.session=p_card.session) AND (a.card_id IS NULL OR a.card_id=p_card.id) ORDER BY (CASE WHEN a.card_id IS NOT NULL THEN 4 WHEN a.day IS NOT NULL AND a.session IS NOT NULL THEN 3 WHEN a.day IS NOT NULL THEN 2 WHEN a.session IS NOT NULL THEN 1 ELSE 0 END) DESC LIMIT 1;
 IF FOUND THEN RETURN result;END IF;
 SELECT e.choice INTO choice FROM public.rr_reward_eligibility e WHERE e.period_id=p_card.period_id AND e.student_id=p_student;
 IF NOT FOUND AND EXISTS(SELECT 1 FROM public.rr_planner_weeks WHERE period_id=p_card.period_id AND (release_mode='open' OR (release_mode IN ('start','end') AND release_at<=now()))) THEN RETURN 100;END IF;
 RETURN CASE WHEN choice='all' OR choice=p_card.session THEN 100 ELSE 0 END;
END $$;

ALTER TABLE public.rr_reward_eligibility DROP CONSTRAINT IF EXISTS rr_reward_eligibility_choice_check;
CREATE OR REPLACE FUNCTION public.rr_reward_sheet(p_org uuid,p_period uuid,p_class uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE period public.rr_reward_periods%ROWTYPE;rows jsonb;
BEGIN
 PERFORM public.rr_motivation_require_access(p_org);SELECT * INTO period FROM public.rr_reward_periods WHERE id=p_period AND organization_id=p_org;IF NOT FOUND THEN RAISE EXCEPTION 'Period not found' USING ERRCODE='42501';END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'choice',coalesce(e.choice,CASE WHEN EXISTS(SELECT 1 FROM public.rr_planner_weeks WHERE period_id=p_period AND (release_mode='open' OR (release_mode IN ('start','end') AND release_at<=now()))) THEN 'all' ELSE 'none' END)) ORDER BY s.name),'[]') INTO rows FROM public.students s JOIN public.student_class_assignments a ON a.student_id=s.id AND a.organization_id=p_org AND a.is_current AND a.class_id=p_class LEFT JOIN public.rr_reward_eligibility e ON e.period_id=p_period AND e.student_id=s.id WHERE s.organization_id=p_org AND NOT s.is_archived;
 RETURN jsonb_build_object('revision',period.revision,'rows',rows,'sessions',public.rr_planner_sessions_read(p_org));
END $$;
CREATE OR REPLACE FUNCTION public.rr_reward_sheet_save(p_org uuid,p_period uuid,p_class uuid,p_revision bigint,p_rows jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE rev bigint;r jsonb;old text;BEGIN
 PERFORM public.rr_motivation_require_access(p_org);PERFORM 1 FROM public.organizations WHERE id=p_org FOR UPDATE;
 SELECT revision INTO rev FROM public.rr_reward_periods WHERE id=p_period AND organization_id=p_org;IF NOT FOUND THEN RAISE EXCEPTION 'Period not found' USING ERRCODE='42501';END IF;
 IF p_revision IS DISTINCT FROM rev THEN RAISE EXCEPTION 'Sheet changed. Reload before saving.' USING ERRCODE='40001';END IF;
 IF jsonb_typeof(p_rows) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rows)>1000 THEN RAISE EXCEPTION 'Invalid sheet' USING ERRCODE='22023';END IF;
 FOR r IN SELECT value FROM jsonb_array_elements(p_rows) LOOP
 IF (coalesce(r->>'choice','') NOT IN ('all','morning','afternoon','none') AND NOT EXISTS(SELECT 1 FROM public.rr_planner_sessions WHERE organization_id=p_org AND key=r->>'choice')) OR NOT EXISTS(SELECT 1 FROM public.students s JOIN public.student_class_assignments a ON a.student_id=s.id AND a.organization_id=p_org AND a.is_current AND a.class_id=p_class WHERE s.id=(r->>'id')::uuid AND s.organization_id=p_org AND NOT s.is_archived) THEN RAISE EXCEPTION 'Invalid student or choice' USING ERRCODE='22023';END IF;
 SELECT choice INTO old FROM public.rr_reward_eligibility WHERE period_id=p_period AND student_id=(r->>'id')::uuid;
 IF old IS DISTINCT FROM r->>'choice' THEN
 INSERT INTO public.rr_reward_eligibility VALUES(p_period,(r->>'id')::uuid,r->>'choice') ON CONFLICT(period_id,student_id) DO UPDATE SET choice=excluded.choice;
 DELETE FROM public.rr_reward_authorizations WHERE period_id=p_period AND student_id=(r->>'id')::uuid;
 PERFORM public.rr_reward_recalculate(p_period,(r->>'id')::uuid);
 INSERT INTO public.rr_motivation_events(organization_id,program_id,student_id,class_id,actor_id,kind,detail) VALUES(p_org,(SELECT program_id FROM public.rr_reward_periods WHERE id=p_period),(r->>'id')::uuid,p_class,auth.uid(),'eligibility',jsonb_build_object('period',p_period,'before',coalesce(old,'none'),'choice',r->>'choice'));
 END IF;END LOOP;
 UPDATE public.rr_reward_periods SET revision=revision+1 WHERE id=p_period;
 INSERT INTO public.rr_motivation_events(organization_id,actor_id,kind,detail) VALUES(p_org,auth.uid(),'eligibility',jsonb_build_object('period',p_period,'class',p_class,'rows',p_rows));
 RETURN public.rr_reward_sheet(p_org,p_period,p_class);
END $$;

-- Safe for cron; deliberately not callable by browser roles.
CREATE OR REPLACE FUNCTION public.rr_planner_tick() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE w record;s uuid;BEGIN
FOR w IN SELECT pw.id,pw.period_id,p.organization_id,p.program_id,p.created_by FROM public.rr_planner_weeks pw JOIN public.rr_planner_plans p ON p.id=pw.plan_id WHERE NOT pw.processed AND (pw.release_mode='open' OR (pw.release_mode IN ('start','end') AND pw.release_at<=now())) ORDER BY p.organization_id,pw.id LOOP
 PERFORM 1 FROM public.organizations WHERE id=w.organization_id FOR UPDATE;
 IF NOT EXISTS(SELECT 1 FROM public.rr_planner_weeks WHERE id=w.id AND NOT processed) THEN CONTINUE;END IF;
 FOR s IN SELECT DISTINCT student_id FROM public.rr_reward_redemptions WHERE period_id=w.period_id LOOP PERFORM public.rr_reward_recalculate(w.period_id,s);END LOOP;
 UPDATE public.rr_planner_weeks SET processed=true WHERE id=w.id;
 UPDATE public.rr_reward_periods SET revision=revision+1 WHERE id=w.period_id;
 INSERT INTO public.rr_motivation_events(organization_id,program_id,actor_id,kind,detail) VALUES(w.organization_id,w.program_id,w.created_by,'scheduled_release',jsonb_build_object('automatic',true,'period',w.period_id,'manual_decisions_preserved',true));
END LOOP;END $$;
CREATE OR REPLACE FUNCTION public.rr_planner_read(p_org uuid,p_program uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN PERFORM public.rr_motivation_require_access(p_org);RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id',p.id,'created_at',p.created_at,'preview',p.preview,'weeks',(SELECT jsonb_agg(to_jsonb(w) ORDER BY ordinal) FROM public.rr_planner_weeks w WHERE w.plan_id=p.id)) ORDER BY p.created_at DESC) FROM public.rr_planner_plans p WHERE organization_id=p_org AND program_id=p_program),'[]');END $$;
-- Only unused plans can be removed for revision; generated cards and logs are never deleted here.
CREATE OR REPLACE FUNCTION public.rr_planner_discard(p_org uuid,p_plan uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE periods uuid[];BEGIN PERFORM public.rr_motivation_require_access(p_org);PERFORM 1 FROM public.organizations WHERE id=p_org FOR UPDATE;
IF NOT EXISTS(SELECT 1 FROM public.rr_planner_plans WHERE id=p_plan AND organization_id=p_org) THEN RAISE EXCEPTION 'Plan not found' USING ERRCODE='42501';END IF;
SELECT array_agg(period_id) INTO periods FROM public.rr_planner_weeks WHERE plan_id=p_plan;
IF EXISTS(SELECT 1 FROM public.rr_motivation_cards WHERE period_id=ANY(periods)) OR EXISTS(SELECT 1 FROM public.rr_reward_eligibility WHERE period_id=ANY(periods)) OR EXISTS(SELECT 1 FROM public.rr_reward_authorizations WHERE period_id=ANY(periods)) THEN RAISE EXCEPTION 'This plan has cards or eligibility decisions and cannot be discarded' USING ERRCODE='22023';END IF;
DELETE FROM public.rr_planner_plans WHERE id=p_plan;DELETE FROM public.rr_reward_periods WHERE id=ANY(periods);
INSERT INTO public.rr_motivation_events(organization_id,actor_id,kind,detail) VALUES(p_org,auth.uid(),'planner_discarded',jsonb_build_object('plan',p_plan));END $$;
CREATE OR REPLACE FUNCTION public.rr_reward_release(p_org uuid,p_student uuid,p_period uuid,p_day date,p_session text,p_card uuid,p_percent numeric) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE scope_value text;BEGIN
 PERFORM public.rr_motivation_require_access(p_org);PERFORM 1 FROM public.organizations WHERE id=p_org FOR UPDATE;
 IF NOT EXISTS(SELECT 1 FROM public.rr_reward_periods WHERE id=p_period AND organization_id=p_org) OR NOT EXISTS(SELECT 1 FROM public.students WHERE id=p_student AND organization_id=p_org) THEN RAISE EXCEPTION 'Student or period not found' USING ERRCODE='42501';END IF;
 IF p_percent IS NULL OR p_percent NOT BETWEEN 0 AND 100 OR (p_session IS NOT NULL AND p_session NOT IN ('morning','afternoon') AND NOT EXISTS(SELECT 1 FROM public.rr_planner_sessions WHERE organization_id=p_org AND key=p_session)) THEN RAISE EXCEPTION 'Enter a percentage from 0 to 100' USING ERRCODE='22023';END IF;
 IF p_card IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.rr_reward_redemptions d JOIN public.rr_motivation_cards c ON c.id=d.card_id WHERE d.card_id=p_card AND d.student_id=p_student AND d.period_id=p_period AND (p_day IS NULL OR c.card_day=p_day) AND (p_session IS NULL OR c.session=p_session)) THEN RAISE EXCEPTION 'Card does not match this student and scope' USING ERRCODE='42501';END IF;
 IF p_day IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.rr_reward_periods WHERE id=p_period AND p_day BETWEEN starts AND ends) THEN RAISE EXCEPTION 'Day is outside the accounting week' USING ERRCODE='22023';END IF;
 scope_value:=coalesce(p_card::text,'*')||':'||coalesce(p_day::text,'*')||':'||coalesce(p_session,'*');
 -- A broader new decision supersedes narrower prior authorizations within its scope.
 DELETE FROM public.rr_reward_authorizations a WHERE a.period_id=p_period AND a.student_id=p_student AND (p_card IS NULL OR a.card_id=p_card) AND (p_day IS NULL OR a.day=p_day OR a.card_id IN(SELECT id FROM public.rr_motivation_cards WHERE card_day=p_day)) AND (p_session IS NULL OR a.session=p_session OR a.card_id IN(SELECT id FROM public.rr_motivation_cards WHERE session=p_session));
 INSERT INTO public.rr_reward_authorizations VALUES(p_period,p_student,scope_value,p_day,p_session,p_card,p_percent);
 PERFORM public.rr_reward_recalculate(p_period,p_student);
 UPDATE public.rr_reward_periods SET revision=revision+1 WHERE id=p_period;
 INSERT INTO public.rr_motivation_events(organization_id,program_id,student_id,class_id,actor_id,kind,detail) VALUES(p_org,(SELECT program_id FROM public.rr_reward_periods WHERE id=p_period),p_student,(SELECT class_id FROM public.student_class_assignments WHERE student_id=p_student AND organization_id=p_org AND is_current LIMIT 1),auth.uid(),'unfreeze',jsonb_build_object('period',p_period,'day',p_day,'session',p_session,'card',p_card,'percent',p_percent));
 RETURN jsonb_build_object('saved',true);
END $$;
CREATE OR REPLACE FUNCTION public.rr_reward_reset(p_org uuid,p_request uuid,p_confirmation text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE last uuid;BEGIN
 PERFORM public.rr_motivation_require_access(p_org);IF p_request IS NULL OR p_confirmation IS DISTINCT FROM 'RESET MOTIVATION' THEN RAISE EXCEPTION 'Type RESET MOTIVATION to confirm' USING ERRCODE='22023';END IF;
 PERFORM 1 FROM public.organizations WHERE id=p_org FOR UPDATE;
 INSERT INTO public.rr_reward_control(organization_id) VALUES(p_org) ON CONFLICT DO NOTHING;SELECT last_reset INTO last FROM public.rr_reward_control WHERE organization_id=p_org;IF last=p_request THEN RETURN jsonb_build_object('reset',true);END IF;
 DELETE FROM public.rr_reward_authorizations WHERE period_id IN(SELECT id FROM public.rr_reward_periods WHERE organization_id=p_org);
 DELETE FROM public.rr_reward_eligibility WHERE period_id IN(SELECT id FROM public.rr_reward_periods WHERE organization_id=p_org);
 DELETE FROM public.rr_reward_redemptions WHERE organization_id=p_org;
 DELETE FROM public.rr_motivation_points WHERE organization_id=p_org;
 DELETE FROM public.rr_motivation_cards WHERE organization_id=p_org;
 DELETE FROM public.rr_motivation_orders WHERE organization_id=p_org;
 DELETE FROM public.rr_reward_periods WHERE organization_id=p_org;
 DELETE FROM public.rr_planner_plans WHERE organization_id=p_org;
 DELETE FROM public.rr_motivation_requests WHERE organization_id=p_org;
 DELETE FROM public.rr_motivation_events WHERE organization_id=p_org;
 UPDATE public.rr_reward_control SET epoch=epoch+1,last_reset=p_request WHERE organization_id=p_org;
 RETURN jsonb_build_object('reset',true);
END $$;

DO $$ DECLARE f record;BEGIN
FOR f IN SELECT oid::regprocedure sig,proname FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname LIKE 'rr_planner_%' LOOP
 EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',f.sig);
 IF f.proname NOT IN ('rr_planner_tick','rr_planner_distribution') THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',f.sig);END IF;
END LOOP;END $$;
-- Supabase supports pg_cron. Installation fails transactionally if scheduling is unavailable.
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
SELECT cron.schedule('yk-motivation-week-release','* * * * *','SELECT public.rr_planner_tick()');
NOTIFY pgrst,'reload schema';
COMMIT;
SELECT 'MOTIVATION_PLANNER_READY' AS result;
