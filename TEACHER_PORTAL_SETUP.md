# YKonnect Teacher Portal update

This is a source update, not a live deployment. No teacher emails have been sent by preparing this ZIP.

If the first Teacher Portal update is already installed, this account-switcher update needs the GitHub files and a redeployment of **teacher-invite** only. There is no new SQL migration. Keep the existing Redirect URL and SMTP configuration.

## Install in this order

1. Extract this ZIP. Upload its contents to the root of `yeshayekrausz-wq/raiseroster-test`, preserving the `motivation`, `shared` and `supabase` folders. Replace files with the same paths. Do not upload the ZIP itself as the website.
2. In Supabase SQL Editor, open a **new query**. Paste the **entire contents** of `Activate_Teacher_Workspace.sql` and run it. Only this `.sql` file belongs in SQL Editor. It starts with a comment and `BEGIN;`, not `<!doctype html>`. It adds teacher tables/functions and enables RLS itself. It does not erase students, cards or points. Requires the existing Motivation/Reward Cards/Planner updates already installed.
3. In Supabase Authentication → URL Configuration, **add** this exact Redirect URL (keep your existing URLs):
   `https://yeshayekrausz-wq.github.io/raiseroster-test/motivation/teacher/?setup=1`
4. Deploy the new Edge Function **teacher-invite**, using the complete code from `supabase/functions/teacher-invite/index.ts`. Disable the gateway's **Verify JWT with legacy secret** toggle for this function. The function still calls Auth `getUser()` and a database RPC that checks school administrator permission before sending any email. Never put the service role key in GitHub or frontend code. Supabase provides the server key to the Edge Function environment.
   CLI alternative: `supabase functions deploy teacher-invite --project-ref jqylxbqwznoohscjbxrx --no-verify-jwt`
5. Configure a working **custom SMTP email provider** in Supabase Authentication for delivery to real teacher email addresses. Supabase's default email service can restrict recipients and delivery volume. If custom Auth email templates were previously changed, the Invite User and Reset Password templates must retain the secure `{{ .ConfirmationURL }}` link. Do not replace it with a plain website link.
6. Refresh the admin website with Ctrl+F5. In **Teacher Portals**, save an enabled teacher with an email. A new/changed email or re-enabled assignment automatically requests a setup email. Existing teachers have a **Send setup email** button. A mail failure is shown separately; the teacher assignment remains saved. Wait two minutes before retrying the same assignment.
7. Open the email link, set a password, and enter the portal. If that email already has an account, it is connected to the class without a second account, invitation email or password reset. The existing user opens Teacher from the nine-dot app menu. New accounts still receive a secure setup email.

Teacher portal:
https://yeshayekrausz-wq.github.io/raiseroster-test/motivation/teacher/

Assign the same email to both classes for a teacher who teaches two classes. Both class buttons appear at the top. A teacher account does not need an organization admin membership. Do not give teachers admin access just to make this portal work.

## Included

- Teacher dashboard and class switcher, authenticated before displaying class data.
- Class-only student directory with phone numbers, dates and address.
- Attendance: present / absent / late, reason, civil date (MM/DD/YYYY), Hebrew date, weekday and editable parsha. Date/parsha calculation uses the Diaspora schedule; parsha can be entered manually if the calendar module is blocked by a filter.
- Exams: custom subject, title/date, maximum mark and per-child marks/notes. A blank mark is excluded, not treated as zero.
- Averages by selected exams, subject and date range: child and whole-class averages. Each recorded mark counts equally after conversion to a percentage. The class average is the average of all included recorded marks, not an average of student averages with unequal sample sizes.
- Drag-and-drop chairs, editable names, keyboard movement, automatic class layout, save/reopen and print. Maximum 80 chairs. The supplied workbook was used as a reference for rotating pairs and printable seating; its VBA macros were not executed or copied.
- Chavrusas: manual rounds or a full rotating cycle with no repeated pair. With an odd class, one child is unpaired in each round. Editable pairs and print one/all rounds.
- Private notes and reminders by default. Share with selected verified users from the same school. Recipients can read; only the author can edit. Other class teachers can view attendance, exams, seating and pairs for their assigned class but cannot overwrite another author's entry. Office staff can open the same portal URL to read notes explicitly shared with them, even without a class assignment.
- Daily reminder filter and printable checklist; the bell shows pending reminders due today or earlier. This is an in-app reminder list, not email/SMS or background notification delivery.
- Nine-dot app launcher in Super Admin, Campaign Admin, Motivation Admin, the main hub and Teacher. One account can have admin and teacher assignments at the same time; switching apps preserves the current sign-in. Teacher access still requires that email to be assigned to a class.
- Nine-dot app launcher at the top right. Motivation includes class-only approved/held balances and card redemption. Uses the existing reward engine for caps, duplicate protection and holds. There is no other-class override. Redemption requires an invitation issued by a school admin who still has administrator access; removing that administrator can require a fresh invitation from a current admin.
- Save buttons, conflict detection, unsaved-change warnings and print controls.

## Deliberately later

- Automatic release of held points based on exam marks/averages. This update stores structured marks; recording an exam does not change rewards eligibility.
- AI integration, as requested for a later phase.
- This teacher workspace does not grant school-wide settings, roster administration, reset actions or cross-class overrides. Motivation is a scoped teacher view, not a full clone of every admin screen.

## First live check

Use your own test teacher email, assigned to a test class. Check that the setup email arrives; set a password; verify only assigned class buttons appear; save and reopen an attendance sheet and exam; check averages; print a seating chart; share a note with a second test account and verify that private notes are absent. Only test card redemption with a card you intend to redeem: this is real redemption, unlike the phone simulator.

No EXE rebuild is needed for this teacher-only update. There are no changes to projector polling, display media or the phone provider.

## Validation completed locally

- PostgreSQL-compatible PGlite tests: repeatable migration, school/class isolation, verified assignment checks, anonymous/table access denial, private/shared notes, author-only writes, stale revision protection, exam limits, pair membership/duplicates, chair bounds, invitation throttling, delegated redemption scope/idempotency and actor restoration.
- Browser tests with mocked backend: 30-student attendance, blank marks, averages, 29 rounds for 30 students, private note defaults, class switching, seating movement and one-page A4 print, card entry and signout data clearing.
- Edge function tests with mocked Auth: authentication/administrator checks, fixed redirect, new-account invitation, existing-account linking without a password reset and mail failure reporting.
- Live Supabase email delivery, real account onboarding and production database compatibility must be checked after installation. No live migration or email was run here.

References for email setup:
https://supabase.com/docs/reference/javascript/auth-admin-inviteuserbyemail
https://supabase.com/docs/reference/javascript/auth-resetpasswordforemail
https://supabase.com/docs/guides/auth/auth-smtp
