# Stage 3A — Hatzlacha program setup

Prepared October 15, 2026. Source update; not deployed by the assistant.

## What is working

- Create multiple Hatzlacha programs/terms within the signed-in school.
- Set program name, term name, dates and an optional points target.
- Set subjects, maximum exam scores and score-to-point thresholds per subject.
- Preview points for an exam score without changing saved settings.
- Save, reopen and edit program settings in Supabase.
- Save immutable before/after audit records; reject stale revisions.
- Keep unsaved changes when a save fails; guard navigation/discard.
- English interface with automatic RTL direction for entered Hebrew/Yiddish names.

The rule with the highest minimum score at or below the exam score wins. Below the first minimum gives zero. Rules are not cumulative. No reward amounts are supplied by default; the deputy/admin chooses them. The maximum score starts at 100 and is editable. Program terms, targets and subjects are independent.

## Install this update

1. Keep a backup of the repository/database.
2. In Supabase SQL Editor, run `migrations/20261015_hatzlacha_setup.sql` **once**. Successful completion returns `HATZLACHA_SETUP_READY`.
3. Extract `Hatzlacha_Setup_Update.zip`. Upload the contents to the existing repository root, preserving `motivation/admin/`, `shared/`, and the other included paths. Replace matching files. Do not upload the ZIP itself or delete existing files.
4. Wait for GitHub Pages deployment. Close all old app tabs and reopen, or test in a private browser window (service worker version is now 1.3.0).
5. Open Motivation → Admin portal → New program. Enter a term and one subject with your own rules. Save; close/reopen the program to verify persistence with an authorized account.

This is an incremental ZIP. It includes only changed/new files, not the entire website. Existing campaign/admin/projector files remain in the repository. No older SQL migrations need rerunning for this step. If the SQL is not installed, the screen explicitly reports that setup is not activated and disables creation.

## What is still pending

Student exam entry and earned-point records, cards/generation/printing/redemption, hotline, cap rules, overrides, reports and motivation projector are not implemented in this release. The preview is a calculator, not a posted student award. Term dates and target points are stored settings only. Program deletion/archiving and an audit viewer are not included.

The current database only has admin and super_admin roles. Both may configure programs within their own school. This release does not implement a distinct deputy role or program/class-specific assignments, and does not modify existing membership policies. Hiding Motivation in the launcher is not access revocation.

## Confirmed future purchase model

Users must be able to choose the programs they want when purchasing a plan through a self-service automated system. Motivation is a category with multiple distinct program products, beginning with Hatzlacha. Program instances/terms belong to a school; a purchased product must not be confused with a single term.

This release uses a separate `product_key` (`hatzlacha`) and a central server-side module authorization helper. Future development must add a product catalog, school entitlements, verified/idempotent billing webhooks and user assignments. Every module RPC must enforce those entitlements server-side. Frontend menus and client-submitted purchase claims are not payment authorization. No billing provider, pricing, checkout or automatic entitlement provisioning is implemented now. The initial product-key constraint must be extended when new motivation products ship.

## Database design and verification

New tables: `rr_motivation_programs`, `rr_motivation_setup_audit`. Both have RLS enabled and no direct anon/authenticated table access. Public RPCs validate current school membership; clients cannot set product keys, actor IDs, revisions or organization IDs on existing records outside their school. Security-definer functions use a fixed pg_catalog search path. Every accepted config change and its audit entry are in one transaction. Same-config saves do not create audit noise. The migration is additive and leaves student/campaign data unchanged.

Local PostgreSQL-compatible PGlite tests passed: migration, create/edit/multiple terms, no-op, audit, input/date/rule validation, stale-version rejection, cross-school isolation, anonymous and direct-table denial. Browser tests with mocked Supabase passed: score boundaries, save/reopen, text escaping, failed-save retention, discard guard, mobile fit, and setup/permission errors. Desktop and mobile screenshots were visually inspected. No live database writes or deployment were performed by the assistant. End-to-end verification against the user's live Supabase remains an installation step.
