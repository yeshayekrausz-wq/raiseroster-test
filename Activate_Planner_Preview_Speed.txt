-- Incremental performance update. Existing cards and plans are unchanged.
BEGIN;
CREATE OR REPLACE FUNCTION public.rr_planner_preview(p_org uuid,p_program uuid,p_data jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE target numeric;extra numeric;goal numeric;each_count int:=0;w jsonb;cl text;allocation jsonb;session_row jsonb;teacher_rows jsonb;members jsonb;class_rows jsonb:='[]';week_rows jsonb:='[]';rows jsonb;ns int;nw int;idx int:=0;start_at timestamptz;end_at timestamptz;last_end timestamptz;zone text;settings jsonb;epoch bigint;result jsonb;previous_target numeric:=0;week_target numeric;ses jsonb;teacher_count int;mode text;available_sessions jsonb;allocation_cache jsonb:='{}';allocation_key text;
BEGIN
PERFORM public.rr_motivation_require_access(p_org);
available_sessions:=public.rr_planner_sessions_read(p_org);
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
 IF coalesce(ses->>'each','') !~ '^\d+$' OR (ses->>'each')::numeric NOT BETWEEN 0 AND 1000 OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(available_sessions) WHERE value->>'key'=ses->>'key') THEN RAISE EXCEPTION 'Invalid session quantity' USING ERRCODE='22023';END IF;each_count:=each_count+(ses->>'each')::int;
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
 IF teacher_count<>1 THEN RAISE EXCEPTION 'Class % needs exactly one teacher for session %', (SELECT name FROM public.classes WHERE id=cl::uuid),(SELECT value->>'label' FROM jsonb_array_elements(available_sessions) WHERE value->>'key'=ses->>'key') USING ERRCODE='22023';END IF;
 rows:=rows||jsonb_build_array(jsonb_build_object('session',ses->>'key','session_label',(SELECT value->>'label' FROM jsonb_array_elements(available_sessions) WHERE value->>'key'=ses->>'key'),'each',(ses->>'each')::int,'count',ns*(ses->>'each')::int,'teachers',teacher_rows,'teacher',teacher_rows->0->>'name'));
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
 allocation_key:=(session_row->>'students')||':'||week_target::text;
 allocation:=allocation_cache->allocation_key;
 IF allocation IS NULL THEN
  allocation:=public.rr_planner_distribution((session_row->>'students')::int*each_count,week_target*(session_row->>'students')::int,coalesce(p_data->'rules','[]'));
  allocation_cache:=jsonb_set(allocation_cache,ARRAY[allocation_key],allocation);
 END IF;
 rows:=rows||jsonb_build_array(session_row||allocation||jsonb_build_object('per_child',round((allocation->>'points')::numeric/(session_row->>'students')::int,4)));
 END LOOP;
 week_rows:=week_rows||jsonb_build_array(jsonb_build_object('number',idx,'start',w->>'start','end',w->>'end','start_at',start_at,'end_at',end_at,'from',substr(w->>'start',1,10),'through',to_char(((w->>'end')::timestamp-interval '1 second'),'YYYY-MM-DD'),'release',w->>'release','target',week_target,'classes',rows));
END LOOP;
result:=jsonb_build_object('target',target,'extra',extra,'required',goal,'each',each_count,'timezone',zone,'epoch',epoch,'weeks',week_rows);
RETURN result||jsonb_build_object('token',md5(result::text));END $$;

NOTIFY pgrst,'reload schema';
COMMIT;
SELECT 'PLANNER_PREVIEW_SPEED_READY' AS result;
