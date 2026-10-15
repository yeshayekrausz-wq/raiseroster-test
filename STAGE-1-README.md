# RaiseRoster — Stage 1: program hub

This is an updated source package, not a live deployment.

## Included

- Root login and a program hub with Campaigns and Motivation.
- Campaigns opens the existing Admin or Projector portal.
- Motivation opens authenticated, clearly marked preparation pages; no reward data is created.
- School selection for accounts with multiple memberships. Campaign links carry the selected organization.
- Existing Super Admin control center linked for accounts with a `super_admin` membership; return-to-programs navigation and a mobile sign-out button.
- Shared hub/admin authentication. A projector opened from the hub reuses that session. Existing standalone projector authentication and embedded preview token handoff remain supported.
- Teacher/staff accounts are kept out of the legacy full-admin hub routes. Class-specific portals are not yet implemented.
- Updated app shell cache version and RaiseRoster manifest name.

## Install and review

1. Keep a backup of the current deployment.
2. Unzip and deploy the **contents of ykonnect-main**, preserving every folder. Deploying only index.html will not work. Include shared/, motivation/, admin/, projector/, superadmin/, sw.js and manifest.webmanifest.
3. Use the existing HTTPS host and Supabase configuration. No database migration is supplied in this stage.
4. Close all old app/browser windows and reopen after the new service worker finishes installing; it deliberately does not interrupt an editing session.
5. Before replacing the production site, verify in a staging environment with authorized test accounts: login/recovery, school switching, campaign data, projector/embedded preview, Super Admin authorization, account actions, and sign-out.

## Verification performed

- Node syntax checks passed for all 19 JavaScript/inline script blocks.
- Mocked-DOM/auth logic checks passed for login success and errors, hub links, selected-school routing, staff exclusion, Super Admin visibility, sign-out, workspace-load errors, and rejection of a nonmember school.
- Actual browser rendering could not be verified in this environment: no browser binary was available and browser downloads failed. Mock tests are not browser tests.
- No live Supabase data was read or changed. Account creation, billing, recovery, and other existing backend operations have not been live-tested.

## Existing backend dependencies

The uploaded project did not include its database migrations, RLS policies or deployed Edge Functions. Existing Super Admin operations still depend on that backend (including sa-user-admin and existing RPCs). Client-side visibility and organization filters are not a substitute for database authorization. Review the existing RLS policies before enabling new user roles.

## Next stage

Program entitlements per school, platform-owner permissions, owner transfer, teacher/class/subject permissions, motivation tables and workflows, point/card/exam rules, reports, phone integration, and remote projector device pairing remain to be implemented. The preserved Super Admin is not a newly implemented platform-owner authorization system.

## Changed files

index.html; shared/config.js; shared/membership.js; shared/hub.js; shared/hub.css; admin/index.html; projector/index.html; superadmin/index.html; motivation/admin/index.html; motivation/projector/index.html; manifest.webmanifest; sw.js; this README.
