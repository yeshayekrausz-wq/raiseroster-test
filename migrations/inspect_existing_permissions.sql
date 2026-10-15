-- READ ONLY. Run in Supabase SQL Editor and export the result for the next permissions phase.
-- Contains schema/policy/function definitions, not student data or auth-user records.
-- Review function definitions before sharing in case old functions contain embedded secrets.
SELECT jsonb_build_object(
 'columns',(SELECT jsonb_agg(to_jsonb(c)) FROM (
   SELECT table_name,column_name,data_type,udt_name,is_nullable,column_default
   FROM information_schema.columns WHERE table_schema='public'
   AND table_name IN ('organizations','organization_members','classes','students','student_current_class','campaigns','contributions','platform_audit_log','organization_status_history')
   ORDER BY table_name,ordinal_position) c),
 'policies',(SELECT jsonb_agg(to_jsonb(p)) FROM pg_policies p WHERE schemaname='public'),
 'rls',(SELECT jsonb_agg(jsonb_build_object('table',c.relname,'enabled',c.relrowsecurity,'forced',c.relforcerowsecurity))
   FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r'),
 'constraints',(SELECT jsonb_agg(jsonb_build_object('table',c.conrelid::regclass::text,'name',c.conname,'definition',pg_get_constraintdef(c.oid)))
   FROM pg_constraint c WHERE c.conrelid IN ('public.organizations'::regclass,'public.organization_members'::regclass)),
 'functions',(SELECT jsonb_agg(jsonb_build_object('name',p.proname,'signature',pg_get_function_identity_arguments(p.oid),'security_definer',p.prosecdef,'definition',pg_get_functiondef(p.oid)))
   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prokind='f'
   AND (p.proname LIKE 'sa_%' OR p.proname ILIKE '%member%' OR p.proname ILIKE '%admin%' OR p.proname ILIKE '%access%' OR p.proname ILIKE '%permission%'))
) AS permission_schema;
