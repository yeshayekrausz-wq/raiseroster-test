# YK Connect — Daily limits and card expiry

## Install

1. Extract `YK_Card_Policy_Update.zip`. Upload the contents to the existing GitHub repository root, keeping folders intact. Do not upload the ZIP itself.
2. Open `Activate_Card_Policy.txt` with Notepad. Copy its entire contents into Supabase SQL Editor and run. It starts with SQL comments and BEGIN, never <!doctype html>. It includes the previous week/navigation migration, followed by this release. Stage 5 must already be installed.
3. Final result: `MOTIVATION_CARD_POLICY_READY`. Refresh the application after GitHub Pages finishes publishing.
4. Do not rerun older incremental migrations after this installer; they can replace the new redemption functions.

## Included

- Program Settings → Limits → Weekly / Daily.
- Program Settings → Cards → Rules / Expiry.
- Daily cap is optional, blank initially: no daily cap. Counts accepted cards per student/program, including class overrides. It resets at midnight in the school timezone. Weekly caps still apply. Manual point adjustments and exam points are not card redemptions and do not count toward this cap.
- Expiry days are optional, blank initially: no expiry for new cards. Days are calendar days in the school timezone. For example, 1 expires at the next midnight; 2 at the following midnight. This explanation is not a prefilled default.
- Generated cards store an immutable expiry timestamp; changing the rule/timezone does not rewrite existing card expiry dates. Old cards remain without expiry. At the exact expiry instant and afterward, normal and class-override redemption are denied. Reopening a blocked card does not remove its expiry.
- Documents shows each card’s expiry in school time. Printed layout is unchanged.
- Settings apply across the school's Motivation programs, matching existing card-rule scope. Optimistic revisions prevent silent overwrites, changes and denied redemption are logged, and all enforcement happens in the database.

## Verification and scope

PGlite database tests cover normal and override redemption, limits, midnight reset, DST, expiry, duplicate requests, revisions, blank values, repeat installation, school isolation and unauthorized users, plus previous Stage 4/5, barcode and week regressions. Browser tests use mocked Supabase responses and cover nested menus, blank inputs, saving, stale edits, reload, scanning, exports, student editing and mobile layout. They do not verify a live installation or physical scanner.

Combined conditions, random point distribution, cap exceptions and detailed permission controls are still pending. This release does not claim to implement every planned setting. No live data was changed or deployment performed.
