# Motivation — Stage 4 workspace

Prepared October 16, 2026. Source update for the existing RaiseRoster repository; not deployed by the assistant. This package supersedes the earlier Motivation ZIPs and includes their frontend changes.

## Install

1. Keep a backup of the existing database and repository.
2. In **Supabase → SQL Editor**, run **migrations/Activate_Motivation_Workspace.sql**. It installs missing Stage 3A, Stage 3B, Stage 4 and private display-media storage in one transaction. It returns **MOTIVATION_WORKSPACE_READY**. Existing complete stages are preserved; partial installations stop with an error. Re-running a complete installation is safe. Do not additionally run the individual historical migration files.
3. Extract **Motivation_Workspace_Stage4.zip** and upload its contents into the existing GitHub repository root, preserving the paths. Replace matching files. Do not delete old project folders or upload the ZIP itself. Campaign Admin/Projector remain unchanged and must stay in the repository.
4. After Pages deployment, close old app tabs and reopen, or test privately. Service worker version: 1.5.0.
5. Open Motivation → Admin. Create/select a program, verify the shared roster, then test an authorized student operation. Use Display Settings → Open display with the chosen program. Media upload requires the private bucket installed by the SQL.

## Included functionality

### Same application family

The left menu follows Dashboard, Documents, Reports, Program Settings, Display Settings, Phone Settings, then Support, Questions & Answers and Training. Light panels, a teal sidebar, class cards, full-screen profiles, top search, Enter selection and Shift navigation follow the existing Campaign Admin workflow. Desktop and mobile layouts are included. Student entries, class assignments and names are shared; motivation points are separate per program/term.

### Dashboard and profiles

All students and their currently revealed point totals are visible. Add Student uses the existing shared-roster operation. Bulk Edit changes name, main phone and class for all students or the opened class (maximum 200 in one save). Only changed rows are submitted. The server checks snapshots and saves the batch atomically; one invalid row rolls back the batch. Rename Class updates the same class used by other programs and rejects a duplicate name in the same school year. Other open program tabs may need to refresh to see changes; no new cross-tab realtime subscription is implemented.

Profiles support manual point adjustments (positive/negative with a reason), exam entry using server-side subject rules, administrator card redemption, shared profile editing and a personal activity log. Exam rules are snapshotted with each award. Later setting changes do not rewrite earlier points. Corrections can be recorded as a new signed point adjustment; immutable awards are not silently overwritten. Term dates organize programs; automatic term-date enforcement is not implemented. Manual/exam awards are immediate; card awards can be delayed until the next local midnight.

### Documents

Printable student ID cards (existing UUID identifiers), per-student points report cards, teacher points reports and reward-card batches. Browser Print can save to PDF. Cards have unique codes, a class and an optional teacher name. The administrator chooses a fixed points value for each batch; the value is omitted from the printed card. Multiple batches can have different values. Automated random distributions, weekly auto-generation, barcode/QR encoding, printable student photos and numeric hotline-friendly IDs are not part of this release. Report cards show totals/target and comments space, not a full exam transcript. The document list shows the newest 500 reward cards; it is not a general uploaded-document archive.

### Cards and rules

Cards can be enabled/disabled. Wrong-class redemption blocks a card until an administrator reopens it with a reason; already redeemed/blocked cards are denied. A weekly per-student, per-program redemption cap is enforced with serialized writes. The week starts Monday at midnight in the selected school timezone. Late cards can be redeemed within that cap. Day-level earning/abuse rules, deputy overrides, extra teacher/class permissions and additional exam eligibility conditions still need implementation/decisions. Current redemption is from the authorized administrator workspace, not a telephone endpoint.

### Reports and audit

Filter by selected program (plus shared events), student, class, action, accepted/denied outcome, datetime range and free text including card codes/reasons. Load older events in batches of 200. CSV and browser print/PDF export include the loaded results. Each student has a newest-200 personal log without searching the whole school. Dates in the report filters and table use the browser timezone. The log records new workspace opens, edits, settings, points/exams, card generation, redemption attempts and reopening. Workspace opens are browser-page activity, not authoritative authentication/login audit records. Legacy campaign actions and old Stage 3 audit tables are not merged into this report.

### Display

Authenticated display with a school timezone, selected weekdays, start/end times including overnight windows, an ordered timed playlist, dates, text announcements, points, full-screen pictures/videos and picture/video backgrounds. Scores paginate 12 students at a time. Refreshes server data every 30 seconds; connection/auth failures clear the display rather than retaining student data indefinitely. Gregorian birthdays can add a greeting slide (Hebrew birthday calculation is not implemented). A loop's total durations determine repeat frequency; individual independent per-slide recurrence rules are not included.

Upload PNG/JPG/WebP/MP4/WebM up to 25 MB into private school-scoped Storage. Saved playlist paths belong to the school; the display obtains short-lived signed URLs. Videos autoplay muted. PowerPoint must first be exported to slide images; direct PPTX playback/conversion is not implemented. Removing a playlist row does not delete the uploaded file. Media retention/deletion UI is pending. A browser/device must already be running the display; the schedule does not power on hardware or open a closed browser.

### Telephone, support and training boundaries

Phone Settings saves freeze state, allowed registered phone types and selected blocked students, but these preferences do not control live calls until a hotline provider is connected. No inbound number, call webhook, family caller-ID validation or phone log collection is fabricated. Phone freeze does not block administrator card redemption. Existing member roles remain admin/super_admin; separate deputy/teacher assignments and purchased entitlements are future work.

Support offers a diagnostic file without student data, not an outbound ticket service. Q&A and a written quick-start guide are included. Training videos have not been supplied/created. These limitations are visibly labeled in the application.

## Security and validation

All new database reads/mutations check membership as admin/super_admin in the exact school. New business tables have RLS with no direct authenticated/anonymous privileges; the fixed-search-path RPCs own validation. Point/event writes, card transitions and edit transactions are atomic. Mutation request IDs provide idempotent retries; stale settings/student edits are rejected. Existing student/legacy policies are not rewritten. New private media policies include restrictive boundaries so an older broad authenticated policy does not expose this bucket across schools; anonymous access to this bucket is blocked. The installer refuses a pre-existing incomplete/non-private bucket setup.

GitHub is the official host, not an enforceable data-access boundary. A copied frontend does not replace authenticated school authorization. This update is not a full security certification of legacy RPCs, Storage buckets or billing. Self-service purchases/entitlement enforcement remain planned, with the central module authorization helper retained.

## Verification performed

- PostgreSQL-compatible PGlite: fresh/repeated complete installation, preserving saved data; school/anonymous isolation; direct-table denial; idempotent point writes; exam scoring; malformed settings/revision conflicts; cards and wrong-class blocking/reopening; duplicate redemption/weekly cap; shared bulk edits and transactional rollback; class rename; report filtering; private Storage school boundaries even with a deliberately broad pre-existing policy.
- Mocked-browser integration: points/exams and totals, student log/edit, bulk edit, class rename, reward cards/printing, reports/CSV, display settings/projector, phone preference persistence and mobile width.
- Schedule checks: timezone, day boundaries, overnight sessions and weekday restrictions.
- Desktop/mobile/projector screenshots inspected; source syntax and diff checks.

No live student records were used and no deployment/live database mutation was performed by the assistant. Supabase Storage uploads, real accounts and existing live triggers/constraints still need an authorized installation smoke test. Detailed tests are included in tests/.
