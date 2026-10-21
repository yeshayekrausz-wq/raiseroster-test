YK Connect — Hold overview, Documents navigation and sign-in gate

INSTALL
Requires the earlier Class Unfreeze and Random Cards updates.
1. Run Activate_Hold_Overview.txt in Supabase SQL Editor. Expected: MOTIVATION_HOLD_OVERVIEW_READY.
2. Extract this ZIP. Upload motivation/ and sw.js at the repository root, preserving folder paths. Commit changes.
3. After Pages deployment, close old tabs and reopen. Use Ctrl+Shift+R if required.
No card code changes or reset are performed. No card reprint is needed.

CHANGES
Eligibility: choose an accounting week to see class summaries with pupils on Hold, partly authorized and fully authorized. Open a class for its vertical sheet, approved points, held points and status. Names are sorted by the final word of the saved name (family-name convention used by the existing roster). Row numbers are on the right.
Hold amounts count already redeemed/scanned card points that have not been authorized. Unredeemed cards have no assigned pupil and are not included in pupil totals. Eligibility status describes the permissions for that pupil's class cards in the chosen week, even when they have not redeemed any cards. A normal week can have every pupil on Hold.
Dashboard/profile: approved and held totals are separate. Dashboard sums cover the selected program and current non-archived roster. Profile totals appear below the name. Admin approved totals include authorized points scheduled for next-day display; the child-facing reveal timing is unchanged. Week-specific Eligibility totals include redeemed reward cards for that week; dashboard totals also include manual/exam points across the program.
Exam approval remains the existing administrator decision through Eligibility/Unfreeze. This update does not automatically interpret exam results or change approval rules.
Documents: home choices New cards, Saved orders, Student cards and Layout. New cards has its own route and fresh form, with Documents → New cards breadcrumbs. Saved orders remain available for reprints. Successful generation opens Saved orders. Clicking Documents returns to the home choices.
Security: the Motivation admin shell is hidden in the original HTML before JavaScript runs. The page verifies the server-side user session, school membership and server-authorized program-list call before opening the shell and initiating roster/workspace loading. Missing, invalid or forbidden sessions stay locked; sign-out locks the page immediately. Backend authorization and RLS remain enforced independently of the visual gate. A valid remembered session can still sign in automatically; no forced password prompt on every visit was added.
Scope: this patch covers Motivation Admin. It is not a security audit of every other application or the live Supabase configuration.

טעסטן זענען דורכגעפירט לאקאל. קיין לעבעדיגע דאטאבעיס אדער GitHub Pages איז נישט געטוישט געווארן.
