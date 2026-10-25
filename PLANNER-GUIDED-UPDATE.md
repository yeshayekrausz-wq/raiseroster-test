# Planner guided steps — 1.15.4

Upload the motivation folder and sw.js to the same paths in GitHub. Do not upload the ZIP itself. Refresh the site with Ctrl+Shift+R after deployment.

Run Activate_Planner_Preview_Speed.txt in Supabase SQL Editor if you have not installed the preview speed update. Expected result: PLANNER_PREVIEW_SPEED_READY. This is the existing preview-only optimization, not a reset. Never paste HTML into SQL Editor.

Changes: step validation prevents advancing past incomplete goals, weeks, card quantities, percentages or classes. Changing week-building settings requires rebuilding the week list. Preview must complete before Review. The activity banner scrolls into view and stays visible. Preview waiting stops after 20 seconds, aborts the browser request and preserves entries; this does not guarantee server completion within 20 seconds. A late response cannot replace a subsequent preview. Card generation is separate and reports progress by week.

Goal labels explicitly refer to each child over the entire program. Combined totals refer only to selected classes; select every class for the school total. Review shows actual planned card points including rounding. Bonus rules default to points above the calculated value.

Validation: browser tests cover blocked steps, successful preview, timeout/abort, preserved inputs, retry, folder creation and card generation. Full app navigation integration passes. No live database or deployment was changed or tested.
