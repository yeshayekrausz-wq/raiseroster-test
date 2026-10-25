# Planner save navigation fix — 1.15.5

Extract the ZIP. Upload motivation/ and sw.js to the existing GitHub repository paths. No SQL is needed. Refresh after deployment with Ctrl+Shift+R.

After saving a plan, the interface now unlocks before requesting navigation to Documents > Weeks. Previously, the planner's own busy guard rejected that transition when folder loading took long enough for the hashchange event to run. Folder reads now occur only through accepted navigation. Save status no longer displays the obsolete Preview ready message. Failed saves retain entries and the same request identifier for safe retry. Planner validation and caught errors appear in red.

If a previous save appeared to disappear, open Documents > Weeks in the same program first; a saved plan may already be there. This update does not recover unsaved entries cleared by a previous reload, and does not alter or delete database data.

Validation: reproduced the old failure using a delayed folder read and the actual section-leave guard event. After the fix, saved folders become visible. Tests also cover save failure, retained inputs, red error, retry with the same request ID, preview timeout, and generation/download flow. No live database state was verified.
