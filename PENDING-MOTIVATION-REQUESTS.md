# Deferred user requests — October 25, 2026

Do not implement these as part of the first display HTML prototype.

- Remove the visible “20 seconds limit” wording from loading messages. User asked to remove the text; do not silently interpret as removing all network deadlines.
- Dashboard Approved / Hold summary becomes a drill-down control: class, week, redeemed cards with student/status, and unredeemed cards. Unredeemed cards have class/teacher ownership, not known student ownership unless assigned beforehand.
- Planner blank time defaults to 12:00 AM.
- “Choose release” is a disabled placeholder, never an actionable selection.
- Exclude individual dates within each week; reduce cards and increase per-card value to preserve the weekly target. Need explicit per-day/session allocation rule before implementing rounding.
- Place Select all checkbox directly beside its label; avoid full-width checkbox inputs.
- Add spacing between saved-plan action buttons and week cards.
- Include child photo in ID-card exports: Word, Excel and PDF, as an embedded image rather than only a link.

Display requirements confirmed:
- All-class mode shows one child per class and rotates; single-class mode one child in large view.
- Optional photos in both modes and optional totals when scanning.
- Green all approved; grey only current-week Hold. Older Hold is not displayed.
- Visibility threshold counts approved points only from weeks already due for approval, against their cumulative expected target; manual always-show/hide overrides.
- Scan ID anywhere, then reward cards, with no override at the public display. Same ID finishes and optionally prints; inactivity 15 seconds configurable. Receipt-on-timeout is a separate user setting.
- Schedule screen on/off and per-class scan hours only when scanning mode is enabled.
- First standalone HTML for visual review; EXE/device-code pairing afterward. Installed app should have no normal window controls/cursor, use fullscreen, and preserve keyboard-only Task Manager recovery; browser prototype cannot enforce OS lockdown.
