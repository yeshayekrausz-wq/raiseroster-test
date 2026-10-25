Planner preview speed update

1. Run Activate_Planner_Preview_Speed.txt in Supabase SQL Editor. It replaces only the preview calculation function, preserves its permissions and does not change existing plans, cards, points or students. Success: PLANNER_PREVIEW_SPEED_READY.
2. Upload motivation/admin/planner.js and sw.js to the same GitHub paths. Keep other files.
3. Refresh with Ctrl+Shift+R.

The server reads session definitions once per calculation and reuses identical allocations within that calculation. Cache data is never reused across requests, schools or changed inputs. Week detail tables render only when opened. Initial planner reads run concurrently. Preview shows elapsed time and returns a retryable message after 30 seconds without losing entries; write operations are unaffected.

Validation: local 52-week fixture median 52.3 ms before / 37.5 ms after (five runs each), identical full response and verification token. This is a local benchmark, not a measurement of the live Supabase project. Database regression and browser/navigation tests pass, including a nonresponding preview, timeout, preserved inputs and successful retry. The live cause of prolonged waiting is not yet confirmed.
