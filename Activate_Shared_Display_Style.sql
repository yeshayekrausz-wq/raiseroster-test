-- Shared appearance and celebrations for each school's Motivation program.
-- Requires Activate_Display_Controls.sql. No existing device settings are overwritten.
BEGIN;
CREATE TABLE IF NOT EXISTS public.rr_display_program_style(
 organization_id uuid NOT NULL REFERENCES public.organizations(id),
 program_id uuid NOT NULL REFERENCES public.rr_motivation_programs(id),
 design jsonb NOT NULL DEFAULT '{}',options jsonb NOT NULL DEFAULT '{}',revision bigint NOT NULL DEFAULT 1,
 PRIMARY KEY(organization_id,program_id));
ALTER TABLE public.rr_display_program_style ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rr_display_program_style FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.rr_display_style_read(p_org uuid,p_program uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM public.rr_motivation_require_access(p_org);
 IF NOT EXISTS(SELECT 1 FROM public.rr_motivation_programs WHERE id=p_program AND organization_id=p_org) THEN RAISE EXCEPTION 'Program not found' USING ERRCODE='42501';END IF;
 RETURN (SELECT jsonb_build_object('design',design,'options',options,'revision',revision) FROM public.rr_display_program_style WHERE organization_id=p_org AND program_id=p_program);
END $$;
CREATE OR REPLACE FUNCTION public.rr_display_save_shared(p_org uuid,p_id uuid,p_revision bigint,p_label text,p_enabled boolean,p_config jsonb,p_design jsonb,p_style_revision bigint,p_options jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE d public.rr_display_devices%ROWTYPE;s public.rr_display_program_style%ROWTYPE;c jsonb;v jsonb;result jsonb;
BEGIN
 PERFORM public.rr_motivation_require_access(p_org);
 SELECT * INTO d FROM public.rr_display_devices WHERE id=p_id AND organization_id=p_org;
 IF NOT FOUND THEN RAISE EXCEPTION 'Display not found' USING ERRCODE='42501';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_org::text||d.program_id::text,880026));
 SELECT * INTO s FROM public.rr_display_program_style WHERE organization_id=p_org AND program_id=d.program_id;
 IF p_style_revision IS NULL OR coalesce(s.revision,0)<>p_style_revision THEN RAISE EXCEPTION 'Shared display design changed on another computer. Reload before saving.' USING ERRCODE='40001';END IF;
 IF jsonb_typeof(p_options) IS DISTINCT FROM 'object' OR octet_length(p_options::text)>50000 OR coalesce(p_options->>'theme','') NOT IN ('light','dark') OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_options) k WHERE k NOT IN ('theme','celebrations')) THEN RAISE EXCEPTION 'Invalid shared appearance';END IF;
 c:=p_options->'celebrations';
 IF jsonb_typeof(c) IS DISTINCT FROM 'object' OR jsonb_typeof(c->'birthdays') IS DISTINCT FROM 'boolean' OR jsonb_typeof(c->'messages') IS DISTINCT FROM 'array' OR jsonb_array_length(c->'messages')>30 THEN RAISE EXCEPTION 'Invalid celebrations';END IF;
 IF (c->>'birthdays')::boolean THEN
  IF coalesce(c->>'calendar','') NOT IN ('hebrew','gregorian') OR length(btrim(coalesce(c->>'birthdayText',''))) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'Choose a birthday calendar and write a greeting.';END IF;
 END IF;
 IF (c->>'birthdays')::boolean OR jsonb_array_length(c->'messages')>0 THEN
  IF coalesce(c->>'seconds','') !~ '^\d+$' OR (c->>'seconds')::int NOT BETWEEN 3 AND 120 OR coalesce(c->>'interval','') !~ '^\d+$' OR (c->>'interval')::int NOT BETWEEN 10 AND 3600 THEN RAISE EXCEPTION 'Enter greeting duration (3–120 seconds) and time between greetings (10–3600 seconds).';END IF;
 END IF;
 FOR v IN SELECT value FROM jsonb_array_elements(c->'messages') LOOP
  IF jsonb_typeof(v) IS DISTINCT FROM 'object' OR length(btrim(coalesce(v->>'text',''))) NOT BETWEEN 1 AND 1000 OR coalesce(v->>'from','') !~ '^\d{4}-\d{2}-\d{2}$' OR coalesce(v->>'through','') !~ '^\d{4}-\d{2}-\d{2}$' OR (v->>'through')::date<(v->>'from')::date THEN RAISE EXCEPTION 'Enter a message and valid start/end dates.';END IF;
 END LOOP;
 result:=public.rr_display_save(p_org,p_id,p_revision,p_label,p_enabled,p_config,p_design);
 INSERT INTO public.rr_display_program_style(organization_id,program_id,design,options,revision) VALUES(p_org,d.program_id,p_design,p_options,1)
 ON CONFLICT(organization_id,program_id) DO UPDATE SET design=EXCLUDED.design,options=EXCLUDED.options,revision=rr_display_program_style.revision+1 RETURNING * INTO s;
 RETURN result||jsonb_build_object('styleRevision',s.revision);
END $$;
REVOKE ALL ON FUNCTION public.rr_display_style_read(uuid,uuid),public.rr_display_save_shared(uuid,uuid,bigint,text,boolean,jsonb,jsonb,bigint,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_display_style_read(uuid,uuid),public.rr_display_save_shared(uuid,uuid,bigint,text,boolean,jsonb,jsonb,bigint,jsonb) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_display_snapshot(p_id uuid,p_preview boolean DEFAULT false) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE d public.rr_display_devices%ROWTYPE;plan public.rr_planner_plans%ROWTYPE;zone text;current_period uuid;due_periods uuid[];due_end timestamptz;due_target numeric;week_num int;student_rows jsonb;shared public.rr_display_program_style%ROWTYPE;BEGIN
 SELECT * INTO d FROM public.rr_display_devices WHERE id=p_id;
 IF d.organization_id IS NULL THEN RETURN jsonb_build_object('paired',false);END IF;
 IF NOT EXISTS(SELECT 1 FROM public.organization_members WHERE organization_id=d.organization_id AND user_id=d.paired_by AND role::text IN ('admin','super_admin')) THEN RETURN jsonb_build_object('paired',true,'enabled',false,'label',d.label);END IF;
 IF NOT p_preview AND d.config->>'screenMode'='background' THEN RETURN jsonb_build_object('paired',true,'enabled',false,'screenMode','background','label',d.label,'revision',d.revision);END IF;
 SELECT * INTO plan FROM public.rr_planner_plans WHERE id=(d.config->>'plan')::uuid AND organization_id=d.organization_id AND program_id=d.program_id;
 IF NOT FOUND OR (NOT d.enabled AND NOT p_preview) THEN RETURN jsonb_build_object('paired',true,'enabled',false,'label',d.label,'revision',d.revision);END IF;
 SELECT * INTO shared FROM public.rr_display_program_style WHERE organization_id=d.organization_id AND program_id=d.program_id;
 zone:=plan.preview->>'timezone';
 IF NOT p_preview AND NOT public.rr_display_window(d.config,zone) THEN RETURN jsonb_build_object('paired',true,'enabled',false,'label',d.label,'revision',d.revision);END IF;
 SELECT array_agg(w.period_id),max((plan.preview->'weeks'->(w.ordinal-1)->>'end_at')::timestamptz) INTO due_periods,due_end FROM public.rr_planner_weeks w WHERE w.plan_id=plan.id AND (plan.preview->'weeks'->(w.ordinal-1)->>'end_at')::timestamptz<=now();
 due_target:=floor((plan.preview->>'target')::numeric*coalesce(cardinality(due_periods),0)/jsonb_array_length(plan.preview->'weeks'));
 SELECT period_id,ordinal INTO current_period,week_num FROM public.rr_planner_weeks WHERE plan_id=plan.id AND (plan.preview->'weeks'->(ordinal-1)->>'start_at')::timestamptz<=now() ORDER BY ordinal DESC LIMIT 1;
 WITH totals AS(SELECT student_id,sum(points) n FROM public.rr_motivation_points WHERE organization_id=d.organization_id AND program_id=d.program_id AND available_at<=now() GROUP BY student_id),
 points AS(SELECT r.student_id,sum(CASE WHEN r.period_id=ANY(due_periods) THEN round(r.base_points*r.pct/100,4) ELSE 0 END) due,sum(CASE WHEN r.period_id=current_period THEN r.base_points-round(r.base_points*r.pct/100,4) ELSE 0 END) held FROM public.rr_reward_redemptions r JOIN public.rr_motivation_cards c ON c.id=r.card_id WHERE r.organization_id=d.organization_id AND c.program_id=d.program_id GROUP BY r.student_id),
 manual AS(SELECT p.student_id,sum(p.points) n FROM public.rr_motivation_points p WHERE p.organization_id=d.organization_id AND p.program_id=d.program_id AND p.available_at<=due_end AND NOT EXISTS(SELECT 1 FROM public.rr_reward_redemptions r WHERE r.point_id=p.id) GROUP BY p.student_id)
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'class_id',a.class_id,'approved',coalesce(t.n,0),'due',coalesce(p.due,0)+coalesce(m.n,0),'held',coalesce(p.held,0),'birthday',CASE WHEN coalesce((shared.options->'celebrations'->>'birthdays')::boolean,false) THEN jsonb_build_object('gregorian',s.gregorian_birthday,'hebrew',s.hebrew_birthday) ELSE NULL END,'photo',CASE WHEN coalesce((d.config->>'photos')::boolean,false) THEN s.photo_url ELSE NULL END,'override',coalesce(d.config->'overrides'->>s.id::text,'auto')) ORDER BY s.name),'[]') INTO student_rows FROM public.students s JOIN public.student_class_assignments a ON a.student_id=s.id AND a.organization_id=d.organization_id AND a.is_current JOIN public.classes c ON c.id=a.class_id JOIN public.school_years y ON y.id=c.school_year_id AND y.is_current LEFT JOIN totals t ON t.student_id=s.id LEFT JOIN points p ON p.student_id=s.id LEFT JOIN manual m ON m.student_id=s.id WHERE s.organization_id=d.organization_id AND NOT s.is_archived AND d.config->'classes' ? a.class_id::text;
 RETURN jsonb_build_object('paired',true,'enabled',true,'label',d.label,'revision',d.revision,'config',d.config||coalesce(shared.options,'{}'::jsonb),'design',coalesce(shared.design,d.design),'styleRevision',coalesce(shared.revision,0),'localDate',to_char(now() AT TIME ZONE zone,'YYYY-MM-DD'),'timezone',zone,'week',coalesce(week_num,1),'dueTarget',due_target,'goal',plan.preview->'target','students',student_rows,'classes',coalesce((SELECT jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) ORDER BY c.sort_order,c.name) FROM public.classes c WHERE c.organization_id=d.organization_id AND d.config->'classes' ? c.id::text),'[]'));
END $$;


COMMIT;
