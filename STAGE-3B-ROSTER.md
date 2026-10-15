# Stage 3B — Motivation with the shared school roster

Prepared October 15, 2026. This update supersedes Hatzlacha_Setup_Update.zip. It includes Stage 3A setup plus the new dashboard and roster; it is an incremental package for the existing website, not a standalone site.

## Installation — one SQL, one ZIP

1. Keep a backup of the database and repository.
2. Open Supabase SQL Editor, paste **migrations/Activate_Motivation.sql**, and Run. Completion returns **MOTIVATION_READY**. This installer adds Stage 3A if missing, then Stage 3B if missing. Already installed complete stages are preserved; reruns preserve data. A partial installation stops with an explanatory error. Do not separately run the older migration files if using this installer.
3. Extract **Motivation_Shared_Students_Update.zip**. Upload its contents into the existing GitHub repository root, preserving folders and replacing matching files. Do not upload the ZIP itself, delete existing folders, or nest the contents under an extra directory. Existing Campaign Admin/Projector files are not in this package and must remain on GitHub.
4. Wait for GitHub Pages deployment. Close old app tabs and reopen, or use a private window. Service-worker shell version is 1.4.0.
5. Open Motivation → Admin portal. Verify that your existing school students appear. Open a class, search by name/phone, open a profile and try Shift navigation. Program Settings retains term and exam-rule setup.

## User experience

- Campaign-style light panels, a colored side menu, class tiles, student rows, a prominent search box and full-screen profiles.
- Search a name or a saved phone number. Arrow keys select results; Enter opens a student and clears the search. Alt+1 returns focus to search on the dashboard.
- Within a profile, hold Shift to preview students. Up/down changes student; right/left changes class, skipping empty classes. Release Shift to open the selected student; Escape cancels the preview without changing the student. Escape again closes the profile. Other modifier shortcuts and normal Shift typing cancel the preview. Window blur cancels without selecting.
- Names sort by the last whitespace-separated name component, as in the existing Campaign implementation.
- Add Student accepts name, an existing active class in the current school year, and optional phone. It writes to the shared school students and student_class_assignments tables atomically. It is not a separate Motivation roster. Existing students need no import.
- Adding a duplicate normalized name in the same class through this module is rejected; the same name in different classes is allowed. Blank optional phone creates a new record with no phone; existing records are never overwritten by Add Student.
- Failed saves keep the inputs. Retrying the same payload uses the same request ID to prevent duplicate writes after uncertain network responses. A committed student and class assignment have an immutable action record. No manual undo/delete is provided by this screen.
- Refresh students reloads the shared roster. Other open Campaign tabs may need their normal refresh to see newly added students; cross-tab realtime syncing is not implemented here.
- Students without a current active class appear under Unassigned; Add Student requires an active class. Configure school years/classes through the existing Campaign workflow.

## Scope and access

Student viewing/creation and program setup work in this stage. Student exam results, earned-point transactions, cards, redemptions, reports and Motivation projector remain pending. All current school students are available; program enrollment restrictions are not implemented. The current backend still uses admin/super_admin, not a separate deputy/teacher permission model.

The new server RPCs require membership as admin/super_admin in the exact requested organization. Class IDs are checked against that organization and its current school year. Archived students and other schools' data are excluded. These checks do not rely on client-side hidden buttons or GitHub URLs. The new audit table has RLS and no direct authenticated/anonymous access. No existing business table policies or helpers are changed.

The official entry point is the user's GitHub Pages website. A static site's public JavaScript cannot enforce exclusive backend use from that origin. No claim of a GitHub-only security boundary is made: Supabase authentication and server authorization remain the boundary. Existing legacy RPCs, policies, storage and origin architecture still need a separate full review before public release. New module tests do not establish the security of all legacy endpoints.

The future self-service plan requirement remains: school buyers choose products; verified billing establishes server-side entitlements, combined with user assignments on every operation. The product/instance distinction and central module access helper are retained; billing and paid entitlement enforcement are not activated in this update.

## Verification

PostgreSQL-compatible PGlite tests passed for a fresh installer, repeated installation with saved students preserved, roster isolation, shared student creation, atomic assignments, duplicate handling, idempotent retry, invalid/foreign classes, archived filtering, action audit and anonymous denial. Fixtures use the supplied student/class column schema and assignment fields used by the existing source. The full live assignment constraints/triggers have not been retrieved, so live installation and one authorized end-to-end check remain necessary.

Mocked-browser tests passed for roster/search/class/profile flows, keyboard/Shift/Escape navigation, add/retry/duplicate behavior, unsaved settings navigation guards, setup/permission errors and mobile width. Prior program setup tests passed again after integration. Desktop, mobile and Shift navigator rendering were inspected. No real child records were used in these tests. No deployment or live database mutation was performed by the assistant.
