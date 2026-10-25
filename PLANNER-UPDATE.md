# Automatic Motivation planner

Install `migrations/20261023_motivation_planner.sql` in Supabase SQL Editor first. It requires the previously installed Random Cards and Hold Overview updates. Success ends with `MOTIVATION_PLANNER_READY`. Then upload the supplied `motivation` folder and `sw.js` to GitHub, preserving paths, and refresh the site.

The SQL installs a private planner schema, authenticated school-admin RPCs and a pg_cron job that checks releases every minute. It does not reset existing cards, students, points or logs. If pg_cron cannot be installed, the transaction fails without a partial planner installation. Enable pg_cron in the Supabase project and retry the same SQL.

## Use

1. Choose the program on Dashboard. Enable reward cards and set the school timezone and weekly redemption cap in Program Settings.
2. Open Program Settings > Planner. Complete Goal, Weeks, Cards, Values, Classes, Review.
3. Target and extra percentage are supplied by the user; no example quantities are prefilled. Use total-only cards, or per-session quantities with an automatic total.
4. Custom sessions can be added in Cards. Assign their teachers in Teacher Portals. A full-day teacher covers morning and afternoon only; custom sessions need an assignment.
5. Build weeks using the selected start/end days and times. Exclude holiday weeks, or edit individual boundaries and release modes. Times use the configured school timezone; the end time is the release boundary.
6. Percentage rules are minimums for each class in each week. Each rule rounds up to whole cards; impossible combinations are rejected. Remaining cards get a whole calculated base value. Matching point values are combined so the actual percentage is truthful. The preview separates extra points caused by selected fixed values from rounding excess.
7. Create week folders, then open Documents > Weeks. Generate one week or all remaining weeks. Retries do not duplicate cards. Each generated week opens the existing Word, Excel and Print/PDF downloads, with teacher/session batches.
8. If student or teacher assignments change, Refresh remaining weeks updates only ungenerated weeks. Generated cards keep their original allocation. Entire unused plans without eligibility decisions may be discarded and recreated.

Card values are distributed across a class pool, not assigned in advance to individual children. Per-child numbers shown in the preview are the class allocation divided by student count, not a guarantee that each child receives the same random mix.

Planned default release modes are immediate, manual, week start and week end. A manual student eligibility or percentage decision takes precedence over automatic release. Scheduled changes recalculate existing redemptions without adding duplicate points. The class sheet now saves only touched rows, preserving automatic defaults for untouched children. New custom sessions appear in the sheet and the individual unfreeze filters. Reset Motivation also clears planner plans/weeks while keeping students, teacher assignments and custom session definitions.

## Validation

- PGlite with the existing migrations: installation twice, per-class/week counts and actual generated values, rounding conflicts, fixed-point impossibility, DST boundaries, private tables/RPCs, cross-school denial, total-only mode, custom-session generation and labels, stale roster detection, refreshing remaining weeks, idempotent generation, automatic-release recalculation, manual Hold precedence, repeat ticks, and reset preservation.
- Chromium with mocked RPC responses: step navigation, week builder, totals, custom sessions, preview, folder generation and download routing.
- Full admin shell with mocked Supabase: login gate, integration with existing settings/documents routes and hidden sibling panels.
- JavaScript syntax and git whitespace checks.

Live Supabase and GitHub Pages were not modified. The cron extension itself is activated on Supabase during installation; local database tests exercise the scheduled function directly.
