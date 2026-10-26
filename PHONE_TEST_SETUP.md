# Phone simulator — stage 1

## Install
1. Extract YKonnect_Phone_Test.zip.
2. Upload the motivation folder to the root of the GitHub repository, preserving paths; commit.
3. Open Activate_Phone_Test.sql in Notepad. Copy the COMPLETE SQL into a new Supabase SQL Editor query and Run. This installer creates an RLS-enabled private test-call table and authenticated admin RPC functions. It does not reset student or reward data. No EXE build or Edge Function deployment is required.
4. Refresh the admin website. Select your Motivation program.
5. Phone Settings > Numbers: save the desired allowed phone types. Telephone access must not be frozen if you want to test successful calls. These preferences will also govern future real phone access.
6. Phone Settings > Test: enter a phone number saved on the student. Start test call; enter the four-digit student ID and #. Then enter a six-digit reward-card code and #. * clears the keypad. End call hangs up.
7. Previous test calls shows your most recent 20 simulations for this school/program.

## Behavior
- Admin-only simulator. Calling number is manually supplied for testing, NOT proof of actual caller identity.
- Main phone and home phone follow Home phone permission. +1 US/Canada formatting is normalized; other international country codes are retained.
- School freeze, student freeze, allowed phone types, active student and class checks apply on the server.
- No telephone class override. Six-digit card code only; student ID is four digits.
- Calls expire after 15 minutes, with at most 100 recorded steps per test call.
- Accepted codes are replayed within a rolled-back database transaction so subsequent cards obey the same daily/weekly cap logic. All simulated card, point, normal log and redemption request changes are rolled back. Separate private test-call history is retained.
- Simulations use the real redemption engine and current eligibility rules. They do not reserve cards and do not simulate competing callers.
- Not connected to a real phone line. No audio recordings, provider webhook, caller verification, production rate limits or calling schedules are implemented in this stage.

## Provider integration boundary
A future provider adapter must verify the provider's webhook signature, bind the called number to one school/program, take the caller number from the verified provider payload, and bind a provider call ID to a server-owned session. Never expose the admin test RPC as an anonymous production phone API. Add production attempt limits, call schedules, idempotent real redemption and per-call auditing before enabling a live line. Real redemption must reuse rr_motivation_command with a narrowly authorized service entry point, enforce class matching before redemption and never allow override.
Do not accept school/program/student identity or caller identity supplied by an unauthenticated browser.

## Validation
Tested against the existing migrations in PostgreSQL-compatible PGlite:
repeat installation, formatted phone match, wrong caller denial, global freeze,
class mismatch, duplicate cards and request retries, weekly cap across cards,
cross-organization and anonymous denial, direct table access denial,
and unchanged real points/cards/events.
Browser tested keypad, lengths, #/Enter, result display and hang-up.
