New plan navigation fix

Upload motivation/admin/planner.js and sw.js to the same paths in GitHub. This is a small patch; keep the other existing files. No SQL required. After deployment refresh with Ctrl+Shift+R.

The planner previously began its database load before the main router checked whether it could leave Documents. The busy-state guard then cancelled that same transition. Loading now starts only after navigation is accepted. Reproduced with delayed database responses; the regression and card planning browser flow pass.
