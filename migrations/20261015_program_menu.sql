-- Stage 2A: school launcher configuration, NOT legacy data-access enforcement.
-- Requires organizations(id uuid), organization_members(organization_id,user_id,role).
-- Run on a staging database first. Does not modify existing table policies or roles.
BEGIN;

CREATE TABLE public.rr_school_program_settings (
  organization_id uuid PRIMARY KEY REFERENCES public.organizations(id) ON DELETE CASCADE,
  programs jsonb NOT NULL,
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (jsonb_typeof(programs)='object' AND programs ?& ARRAY['campaigns','motivation','library']
    AND programs - ARRAY['campaigns','motivation','library'] = '{}'::jsonb
    AND jsonb_typeof(programs->'campaigns')='boolean'
    AND jsonb_typeof(programs->'motivation')='boolean'
    AND jsonb_typeof(programs->'library')='boolean')
);
CREATE TABLE public.rr_program_menu_audit (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  organization_id uuid NOT NULL,
  actor_id uuid NOT NULL,
  actor_label text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  reason text NOT NULL CHECK (char_length(reason) BETWEEN 1 AND 500),
  before_settings jsonb NOT NULL,
  after_settings jsonb NOT NULL,
  revision bigint NOT NULL
);
CREATE INDEX ON public.rr_program_menu_audit(organization_id,created_at DESC,id DESC);
ALTER TABLE public.rr_school_program_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rr_program_menu_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rr_school_program_settings, public.rr_program_menu_audit FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE public.rr_program_menu_audit_id_seq FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.rr_sa_get_program_settings(p_org uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE v_programs jsonb; v_revision bigint; v_history jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.organization_members WHERE user_id=auth.uid() AND role::text='super_admin'
  ) THEN RAISE EXCEPTION 'Super Admin access required' USING ERRCODE='42501'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=p_org) THEN
    RAISE EXCEPTION 'School not found' USING ERRCODE='22023'; END IF;
  SELECT programs,revision INTO v_programs,v_revision FROM public.rr_school_program_settings WHERE organization_id=p_org;
  SELECT coalesce(jsonb_agg(t.payload),'[]'::jsonb) INTO v_history FROM (
    SELECT jsonb_build_object('actor_label',actor_label,'created_at',created_at,'reason',reason,
      'before',before_settings,'after',after_settings,'revision',revision) payload
    FROM public.rr_program_menu_audit WHERE organization_id=p_org ORDER BY created_at DESC,id DESC LIMIT 50
  ) t;
  RETURN jsonb_build_object('programs',coalesce(v_programs,'{"campaigns":true,"motivation":true,"library":false}'::jsonb),
    'revision',coalesce(v_revision,0),'history',v_history);
END $$;

CREATE FUNCTION public.rr_sa_set_program_settings(p_org uuid,p_programs jsonb,p_reason text,p_expected_revision bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE v_before jsonb; v_revision bigint; v_actor uuid:=auth.uid(); v_label text;
BEGIN
  IF v_actor IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.organization_members WHERE user_id=v_actor AND role::text='super_admin'
  ) THEN RAISE EXCEPTION 'Super Admin access required' USING ERRCODE='42501'; END IF;
  IF p_programs IS NULL OR jsonb_typeof(p_programs)<>'object'
    OR NOT p_programs ?& ARRAY['campaigns','motivation','library']
    OR p_programs - ARRAY['campaigns','motivation','library'] <> '{}'::jsonb
    OR jsonb_typeof(p_programs->'campaigns') IS DISTINCT FROM 'boolean'
    OR jsonb_typeof(p_programs->'motivation') IS DISTINCT FROM 'boolean'
    OR jsonb_typeof(p_programs->'library') IS DISTINCT FROM 'boolean'
    THEN RAISE EXCEPTION 'Invalid program settings' USING ERRCODE='22023'; END IF;
  IF p_reason IS NULL OR char_length(btrim(p_reason)) NOT BETWEEN 1 AND 500 THEN
    RAISE EXCEPTION 'A reason of 1 to 500 characters is required' USING ERRCODE='22023'; END IF;
  -- Lock the school row so simultaneous first writes serialize as well as updates.
  PERFORM 1 FROM public.organizations WHERE id=p_org FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'School not found' USING ERRCODE='22023'; END IF;
  SELECT programs,revision INTO v_before,v_revision FROM public.rr_school_program_settings WHERE organization_id=p_org;
  v_revision:=coalesce(v_revision,0);
  v_before:=coalesce(v_before,'{"campaigns":true,"motivation":true,"library":false}'::jsonb);
  IF p_expected_revision IS NULL OR p_expected_revision<>v_revision THEN
    RAISE EXCEPTION 'Program settings changed; reload before saving' USING ERRCODE='40001'; END IF;
  IF v_before=p_programs THEN RETURN jsonb_build_object('revision',v_revision,'changed',false); END IF;
  SELECT coalesce(email,v_actor::text) INTO v_label FROM auth.users WHERE id=v_actor;
  INSERT INTO public.rr_school_program_settings(organization_id,programs,revision)
    VALUES(p_org,p_programs,v_revision+1) ON CONFLICT(organization_id) DO UPDATE
    SET programs=excluded.programs,revision=excluded.revision,updated_at=now();
  INSERT INTO public.rr_program_menu_audit(organization_id,actor_id,actor_label,reason,before_settings,after_settings,revision)
    VALUES(p_org,v_actor,coalesce(v_label,v_actor::text),btrim(p_reason),v_before,p_programs,v_revision+1);
  RETURN jsonb_build_object('revision',v_revision+1,'changed',true);
END $$;

CREATE FUNCTION public.rr_school_program_menu(p_org uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE v_programs jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.organization_members WHERE user_id=auth.uid() AND organization_id=p_org
  ) THEN RAISE EXCEPTION 'School membership required' USING ERRCODE='42501'; END IF;
  SELECT programs INTO v_programs FROM public.rr_school_program_settings WHERE organization_id=p_org;
  RETURN coalesce(v_programs,'{"campaigns":true,"motivation":true,"library":false}'::jsonb);
END $$;

REVOKE ALL ON FUNCTION public.rr_sa_get_program_settings(uuid),
 public.rr_sa_set_program_settings(uuid,jsonb,text,bigint),public.rr_school_program_menu(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rr_sa_get_program_settings(uuid),
 public.rr_sa_set_program_settings(uuid,jsonb,text,bigint),public.rr_school_program_menu(uuid) TO authenticated;
COMMIT;
