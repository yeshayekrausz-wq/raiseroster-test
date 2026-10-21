YK Connect — Class sheet and profile layout

No SQL is needed. This update assumes the previous Hold Overview update is installed.
Extract the ZIP, upload motivation/ and sw.js to the GitHub repository root with their existing paths, and commit. After deployment, refresh with Ctrl+Shift+R.

The class sheet now places selection checkboxes next to names, followed by approved/held amounts and status toward the left. Hover highlights the pupil's row. Changing a checkbox highlights Save changes and shows an additional save bar. Changes are saved through the existing authorized database function.
Profile details are left-aligned: name/ID, class, phone numbers, address, teachers, then other saved details. Morning teachers precede afternoon teachers. The duplicate top approved/Hold summary is removed; the main points box remains. Pictures remain in their reserved panel.
No database data or card codes are changed by installing these files.

Tested locally in the browser: column ordering, save bar and persistence request, address display, morning/afternoon order, no duplicate summary, and existing flows. Not deployed to the live site.
