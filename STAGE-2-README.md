# Stage 2A — School program menu and Super Admin fixes

This branch is prepared for review. It has not been deployed to the live Supabase project.

## Included

- School detail → Programs: show/hide Campaigns, Motivation and Library in the launcher.
- Motivation is a category for multiple future programs; Hatzlacha is the first planned program.
- Library remains an honest, non-clickable “In preparation” card.
- Each actual menu change requires a reason and creates an atomic before/after audit record.
- Concurrent administrators cannot silently overwrite a newer saved revision.
- Super Admin role changes use an explicit selector and confirmation for platform-wide authority.
- UI prevents disabling or changing the current Super Admin’s own role.
- Account status filter, user search and account-table column alignment are fixed.
- Existing accounts, campaign data and branding are preserved. Nine-dot launcher remains deferred.

## Scope boundary

These are **program-menu settings**, not a security lock. Hiding Campaigns does not revoke direct
Admin/Projector links or database permissions. Existing legacy policies and Edge Functions remain
authoritative. Owner/Deputy/Teacher roles, class/subject permissions, ownership transfer and account
status enforcement are not implemented by this stage.

The source repository does not contain the existing migrations 0002/0003 or `sa-user-admin` source.
Do not recreate those unknown implementations or assign new role strings based only on UI names.
The new RPCs trust the existing `organization_members.role = super_admin` model. Its policies must
prevent users from granting themselves that role. This cannot be verified from the current source.

## Installation and review

1. Review `migrations/inspect_existing_permissions.sql`. It reads schema and permission definitions;
   it does not modify data. Export its result and obtain the existing `sa-user-admin` source before
   implementing the next permission layer. Do not share service-role keys or passwords.
2. Use an isolated staging Supabase project/schema copy to review and run
   `migrations/20261015_program_menu.sql` once. The transaction creates two tables and three RPCs;
   it does not replace existing role policies or functions. Re-running intentionally fails rather
   than silently replacing objects. No credentials are included in this repository.
3. Test with a platform Super Admin, school admin and a nonmember. Check a saved menu change,
   audit entry, second-admin stale revision, reload, unauthorized access and direct table denial.
4. Upload the complete changed tree to the test host after reviewing the migration result.
   Changes include `superadmin/index.html`, `shared/hub.js`, `shared/programs.js`,
   `shared/program-panel.js`, and `sw.js` (cache version 1.2.0).
5. Open a clean browser session. At Super Admin → Accounts → Open → Programs, save a change with
   a reason. Reload the school launcher to see it. Old open launcher tabs are not realtime-synced.

If the migration is absent, the Programs tab explicitly says setup is incomplete and cannot save.
The launcher uses previous defaults **only** for a missing RPC, not for network/auth failures.
No backend SQL was run against the live school. The test site currently references the same
Supabase project as the uploaded source; a separate GitHub repository is not a separate database.

## Verification

See `tests/program-settings-db.mjs` for isolated Postgres-compatible PGlite checks. Run with the
`PGLITE_MODULE` environment variable pointing to an installed `@electric-sql/pglite` module.
Browser regression tests use a mocked Supabase client; they do not validate the production RLS
policies or Edge Functions. Verification results are recorded in the accompanying PR.

## Continuity note

This supplements `School_Platform_Master_Plan_YI_EN.docx` version 1.0 (October 15, 2026).
Next dependency: existing database permission definitions and the deployed user-admin function.
Next development phase: actual school/program/class authorization, followed by Hatzlacha.
