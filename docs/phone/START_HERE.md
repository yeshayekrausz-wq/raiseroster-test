# YKonnect Phone — Telnyx webhook, first telephone test

This update connects a real incoming Telnyx call to the existing phone simulator.
**It does not commit points or consume cards. It announces test mode on each call.**
Only the caller numbers explicitly listed in PHONE_TEST_CALLERS can use it.
The teachers' attendance/exam menu and production redemption are not enabled in this release.
Prompts are currently spoken in English. Real call costs may still apply.

## 1. Database

In your existing Supabase project, open SQL Editor → New query.
Run the entire `Activate_Telnyx_Webhook.sql`, from BEGIN through COMMIT.
This is SQL; do not paste index.ts or an HTML page into SQL Editor.
It creates private RLS-enabled transport tables and installs the phone simulator dependency.
It does not delete students, cards, points, or existing logs.
Do not use an automatic rewrite to add RLS: the script already enables it on every new table.

## 2. Deploy the Edge Function

Supabase → Edge Functions → Deploy a new function → Via Editor.
Name the function EXACTLY `telnyx-phone` (not a generated random name).
Replace index.ts with all of `supabase/functions/telnyx-phone/index.ts`, then deploy.
Turn OFF the function setting named Verify JWT / Enforce JWT verification.
The endpoint authenticates Telnyx's Ed25519 signature instead; it does not accept unsigned requests.

CLI alternative, from the repository root:

    supabase functions deploy telnyx-phone --project-ref jqylxbqwznoohscjbxrx

The supplied supabase/config.toml includes verify_jwt=false for this function and preserves the other functions' entries.
GitHub uploading alone does NOT deploy Supabase functions or execute SQL.

## 3. Create the Telnyx application

Application name: YKonnect Phone
Webhook API Version: API v2
Webhook URL:

    https://jqylxbqwznoohscjbxrx.supabase.co/functions/v1/telnyx-phone

Leave failover URL blank for this first test. Leave the other defaults unless Telnyx requires an account-specific setting.
Save the application and copy its application / connection ID.
Assign a voice-capable Telnyx number to this application.
Trial restrictions still apply; verify what your account permits before purchasing anything.
Do not yet change the school's existing Skywire routing.

## 4. Supabase Edge Function Secrets

Enter these values in Supabase → Edge Functions → Secrets, not in GitHub or browser JavaScript:

| Secret | Value |
|---|---|
| TELNYX_API_KEY | Your Telnyx API key |
| TELNYX_PUBLIC_KEY | Your account's Telnyx Ed25519 public key (base64) |
| TELNYX_APPLICATION_ID | The Voice API application's ID |
| TELNYX_PHONE_NUMBER | The Telnyx number, international format, e.g. +1 followed by ten digits |
| PHONE_ORGANIZATION_ID | Your school's organization UUID |
| PHONE_PROGRAM_ID | The motivation program UUID |
| PHONE_ADMIN_USER_ID | A current admin/super_admin user UUID for that school |
| PHONE_TEST_CALLERS | Your test caller number(s), international format, comma-separated |

SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are supplied by the Supabase hosted runtime.
Never put the service-role key or Telnyx API key in a public file, screenshot, or chat message.

If you need the school/program/admin IDs, run `Find_Phone_Setup_IDs.sql` in SQL Editor. Choose the correct school and program from the results. Do not select an unrelated admin.
The authorized admin is checked again for every processed call event.

## 5. Make one real test call

1. In YKonnect Phone Settings, enable telephone access and the appropriate allowed phone category.
2. Ensure your test caller number is also on the test student's permitted phone field.
3. Call the Telnyx number directly from that number.
4. You should hear: "YKonnect telephone test. No points will be saved."
5. One matching child is selected automatically. For several children, enter the child's four-digit ID.
6. Enter a six-digit points card from the selected child's class. Enter the same code again; it must be rejected.
7. Confirm that the child's actual balance and the real card remain unchanged.
8. Try an invalid card / wrong class / frozen student. No class override is available.

If the calling phone is on the test allowlist but not permitted in the school roster, the call says it is not registered and ends. Callers outside the explicit test allowlist are not answered by this webhook.
After no input, 30 input steps, or 15 minutes of activity, the session ends.

## Troubleshooting

- Opening the webhook in a browser returns POST required. That is expected.
- Unsigned requests return 401. Do not remove signature verification to bypass this.
- Setup incomplete (503): a secret is missing or an ID/number is malformed.
- No answer: check the number-to-application assignment, exact application ID, caller allowlist, and international number format.
- Database failure: ensure the whole SQL file succeeded, the selected program belongs to the school, and the admin still has access.
- Command failure: check Telnyx trial restrictions, API key, credits, and Telnyx Debugging. Logs record status/event ID without secrets or full caller/card payloads.
- A delivery error returns 503 so Telnyx can retry. The same event returns its saved command ID; repeated deliveries do not reprocess the card.
- This initial synchronous transport awaits database persistence and command acceptance before returning 200. It uses bounded timeouts and Telnyx retries, not an unmonitored background task. Sustained concurrency/100-call testing has not been performed.

## What is verified locally

- Real Ed25519 signed fixtures: valid, forged, changed body, expired timestamp.
- App, number, incoming direction and test caller checks.
- Failure response on database/API failure rather than acknowledging lost commands.
- SQL repeat installation, admin authorization, denied anon/authenticated table/RPC access.
- Single-child auto-selection, sibling ID selection, frozen/unknown callers.
- Duplicate event ID, reused ID with changed input, stale gather state, out-of-order hangup.
- Accepted test card, repeated code rejection, and rollback of actual points.

No real Telnyx call or production deployment was performed while preparing these files.
