# Teacher email changes and invitations

This update is ready to install. It has not been deployed to your Supabase project or GitHub website. No real emails were sent during development.

## What the administrator does

Open Motivation Admin → Teacher Portals → Edit teacher. Change the email and Save.

The new email becomes the teacher login for all assignments using the previous email **within this school**. Classes, teacher assignment IDs, students, points and cards remain in place. Attendance, exams, seating, chavrusas, notes (including private notes) and reminders remain stored and move to the verified new login when it opens the teacher portal. The old email no longer grants teacher access to these assignments. Existing admin/Super Admin roles, passwords and assignments in other schools are not changed.

New account: a secure invitation asks the teacher to set a password.
Existing account: a secure sign-in email opens the portal using that account, without changing its password or creating a duplicate account. Existing accounts can also use their regular password and the nine-dot app menu.

An email already assigned to a different teacher in the same school is rejected to avoid silently combining private workspaces. Change the email and the class in separate saves. Keep the selected assignment active during an email change; it can be disabled separately afterward.

If delivery fails, the assignment and data remain saved. The admin sees the delivery error and can use **Send setup email** to retry after two minutes. Changing to a new email clears the previous email's cooldown. Supabase accepting a send request does not guarantee inbox delivery; check spam and the email provider's delivery logs if needed.

## Install

1. Extract the ZIP and upload its contents to the existing GitHub repository, preserving folders.
2. Run the entire **Activate_Teacher_Email_Invites.sql** file in a new Supabase SQL Editor query. Requires the original Teacher Workspace SQL already installed. It contains its own RLS and grants. Do not rerun older migrations afterward: they can restore the superseded teacher-save behavior. It does not reset data.
3. Supabase → Edge Functions → create or update **teacher-invite** using `supabase/functions/teacher-invite/index.ts`. Deploy it. Disable **Verify JWT with legacy secret** for this function; the code verifies the signed-in caller and the database checks school-admin access.
   CLI alternative: `supabase functions deploy teacher-invite --project-ref jqylxbqwznoohscjbxrx --no-verify-jwt`
4. Supabase → Authentication → URL Configuration → Redirect URLs. Add both, keeping existing URLs:

   https://yeshayekrausz-wq.github.io/raiseroster-test/motivation/teacher/?setup=1

   https://yeshayekrausz-wq.github.io/raiseroster-test/motivation/teacher/

5. Supabase → Authentication → Email / SMTP Settings: configure your email provider's SMTP host, port, username, password and sender address. Use the provider's issued credentials. Do not put SMTP passwords in GitHub or send them in chat. Supabase's default email service is restricted to project-team recipients and is not for production teacher invitations.
6. In Authentication → Email Templates, ensure **Invite User** and **Magic Link** use `{{ .ConfirmationURL }}` as the link. A template containing only `{{ .Token }}` sends a numeric code, while this portal expects a clickable link. Password-reset templates should also retain their confirmation link.
7. Ctrl+F5 in the admin. Test with your own teacher test address before inviting the staff. Check a saved private note and an exam before and after changing to another email you control. Verify the old email loses the class, the new email retains those entries and any admin role remains unchanged.

## Implementation / validation

The email is changed on school-scoped teacher assignments, not by rewriting the shared Supabase Auth identity. A pending, RLS-protected transfer records the prior owner and class scope. Claiming requires a verified matching email and current matching assignments. Teacher writes and email changes serialize on the school row to avoid losing records during a simultaneous save. A chain of changes before acceptance (A → B → C) preserves the original records. Ownership changes are audited; historical points/redemption audit actors are not rewritten.

Locally tested: repeated migration, two-class transfer, new unverified destination, existing-account destination, pending chains, old-access denial, preservation of private content, other-school isolation, unchanged admin identity/role, stale-revision checks, collision rejection, legacy-save bypass denial, invite authorization, new-account mail and existing-account sign-in mail, mail-failure reporting. Actual email delivery requires the deployment and SMTP setup above.

Docs:
https://supabase.com/docs/reference/javascript/auth-admin-inviteuserbyemail
https://supabase.com/docs/reference/javascript/auth-signinwithotp
https://supabase.com/docs/guides/auth/auth-smtp
