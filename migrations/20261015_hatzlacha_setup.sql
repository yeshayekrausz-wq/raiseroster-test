-- Hatzlacha setup only. Run once in Supabase SQL Editor after backing up.
-- Additive: does not change students, campaign data, existing roles or policies.
BEGIN;
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
NOTIFY pgrst,'reload schema';
COMMIT;
SELECT 'HATZLACHA_SETUP_READY' AS result;
