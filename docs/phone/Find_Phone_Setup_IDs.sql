-- Read-only. Run in the Supabase SQL Editor, not in a browser.
SELECT organization_id AS "PHONE_ORGANIZATION_ID", id AS "PHONE_PROGRAM_ID", config->>'name' AS "Program"
FROM public.rr_motivation_programs ORDER BY organization_id,config->>'name';

SELECT m.organization_id AS "School",m.user_id AS "PHONE_ADMIN_USER_ID",u.email,m.role
FROM public.organization_members m LEFT JOIN auth.users u ON u.id=m.user_id
WHERE m.role::text IN ('admin','super_admin') ORDER BY m.organization_id,u.email;
