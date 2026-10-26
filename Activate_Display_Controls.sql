-- Display controls. Run after Activate_Display_Upgrade.sql. No student records are removed.
BEGIN;
CREATE OR REPLACE FUNCTION public.rr_display_control(p_org uuid,p_id uuid,p_revision bigint,p_mode text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE d public.rr_display_devices%ROWTYPE;
BEGIN
 PERFORM public.rr_motivation_require_access(p_org);
 IF p_mode IS NULL OR p_mode NOT IN ('display','black','background') THEN RAISE EXCEPTION 'Invalid screen mode' USING ERRCODE='22023';END IF;
 SELECT * INTO d FROM public.rr_display_devices WHERE id=p_id AND organization_id=p_org FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Display not found' USING ERRCODE='42501';END IF;
 IF d.revision<>p_revision THEN RAISE EXCEPTION 'Display changed. Reload before saving.' USING ERRCODE='40001';END IF;
 UPDATE public.rr_display_devices SET config=jsonb_set(config,'{screenMode}',to_jsonb(p_mode)),enabled=p_mode='display',active_student=NULL,session_expires=NULL,revision=revision+1 WHERE id=p_id RETURNING * INTO d;
 INSERT INTO public.rr_motivation_events(organization_id,program_id,actor_id,kind,detail) VALUES(p_org,d.program_id,auth.uid(),'display_control',jsonb_build_object('device',d.id,'mode',p_mode));
 RETURN jsonb_build_object('revision',d.revision);
END $$;
REVOKE ALL ON FUNCTION public.rr_display_control(uuid,uuid,bigint,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_display_control(uuid,uuid,bigint,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.rr_display_snapshot(p_id uuid,p_preview boolean DEFAULT false) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE d public.rr_display_devices%ROWTYPE;plan public.rr_planner_plans%ROWTYPE;zone text;current_period uuid;due_periods uuid[];due_end timestamptz;due_target numeric;week_num int;student_rows jsonb;BEGIN
 SELECT * INTO d FROM public.rr_display_devices WHERE id=p_id;
 IF d.organization_id IS NULL THEN RETURN jsonb_build_object('paired',false);END IF;
 IF NOT EXISTS(SELECT 1 FROM public.organization_members WHERE organization_id=d.organization_id AND user_id=d.paired_by AND role::text IN ('admin','super_admin')) THEN RETURN jsonb_build_object('paired',true,'enabled',false,'label',d.label);END IF;
 IF NOT p_preview AND d.config->>'screenMode'='background' THEN RETURN jsonb_build_object('paired',true,'enabled',false,'screenMode','background','label',d.label,'revision',d.revision);END IF;
 SELECT * INTO plan FROM public.rr_planner_plans WHERE id=(d.config->>'plan')::uuid AND organization_id=d.organization_id AND program_id=d.program_id;
 IF NOT FOUND OR (NOT d.enabled AND NOT p_preview) THEN RETURN jsonb_build_object('paired',true,'enabled',false,'label',d.label,'revision',d.revision);END IF;
 zone:=plan.preview->>'timezone';
 IF NOT p_preview AND NOT public.rr_display_window(d.config,zone) THEN RETURN jsonb_build_object('paired',true,'enabled',false,'label',d.label,'revision',d.revision);END IF;
 SELECT array_agg(w.period_id),max((plan.preview->'weeks'->(w.ordinal-1)->>'end_at')::timestamptz) INTO due_periods,due_end FROM public.rr_planner_weeks w WHERE w.plan_id=plan.id AND (plan.preview->'weeks'->(w.ordinal-1)->>'end_at')::timestamptz<=now();
 due_target:=floor((plan.preview->>'target')::numeric*coalesce(cardinality(due_periods),0)/jsonb_array_length(plan.preview->'weeks'));
 SELECT period_id,ordinal INTO current_period,week_num FROM public.rr_planner_weeks WHERE plan_id=plan.id AND (plan.preview->'weeks'->(ordinal-1)->>'start_at')::timestamptz<=now() ORDER BY ordinal DESC LIMIT 1;
 WITH totals AS(SELECT student_id,sum(points) n FROM public.rr_motivation_points WHERE organization_id=d.organization_id AND program_id=d.program_id AND available_at<=now() GROUP BY student_id),
 points AS(SELECT r.student_id,sum(CASE WHEN r.period_id=ANY(due_periods) THEN round(r.base_points*r.pct/100,4) ELSE 0 END) due,sum(CASE WHEN r.period_id=current_period THEN r.base_points-round(r.base_points*r.pct/100,4) ELSE 0 END) held FROM public.rr_reward_redemptions r JOIN public.rr_motivation_cards c ON c.id=r.card_id WHERE r.organization_id=d.organization_id AND c.program_id=d.program_id GROUP BY r.student_id),
 manual AS(SELECT p.student_id,sum(p.points) n FROM public.rr_motivation_points p WHERE p.organization_id=d.organization_id AND p.program_id=d.program_id AND p.available_at<=due_end AND NOT EXISTS(SELECT 1 FROM public.rr_reward_redemptions r WHERE r.point_id=p.id) GROUP BY p.student_id)
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'class_id',a.class_id,'approved',coalesce(t.n,0),'due',coalesce(p.due,0)+coalesce(m.n,0),'held',coalesce(p.held,0),'photo',CASE WHEN coalesce((d.config->>'photos')::boolean,false) THEN s.photo_url ELSE NULL END,'override',coalesce(d.config->'overrides'->>s.id::text,'auto')) ORDER BY s.name),'[]') INTO student_rows FROM public.students s JOIN public.student_class_assignments a ON a.student_id=s.id AND a.organization_id=d.organization_id AND a.is_current JOIN public.classes c ON c.id=a.class_id JOIN public.school_years y ON y.id=c.school_year_id AND y.is_current LEFT JOIN totals t ON t.student_id=s.id LEFT JOIN points p ON p.student_id=s.id LEFT JOIN manual m ON m.student_id=s.id WHERE s.organization_id=d.organization_id AND NOT s.is_archived AND d.config->'classes' ? a.class_id::text;
 RETURN jsonb_build_object('paired',true,'enabled',true,'label',d.label,'revision',d.revision,'config',d.config,'design',d.design,'timezone',zone,'week',coalesce(week_num,1),'dueTarget',due_target,'goal',plan.preview->'target','students',student_rows,'classes',coalesce((SELECT jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) ORDER BY c.sort_order,c.name) FROM public.classes c WHERE c.organization_id=d.organization_id AND d.config->'classes' ? c.id::text),'[]'));
END $$;

COMMIT;
