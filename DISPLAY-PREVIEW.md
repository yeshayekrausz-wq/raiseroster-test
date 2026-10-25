# Motivation display — HTML design preview

Open motivation/projector/preview.html directly in Chrome or Edge. No installation, SQL, login or network connection is required. This is a standalone sample-data prototype, separate from the existing live projector. Nothing is redeemed or saved to the school database. Reload resets the sample settings, photos and redemptions.

- All classes: one child per class; single-class mode: one child on screen. Rotation interval is configurable.
- Green meter: all approved points; grey segment: current-week Hold only. Older held points are excluded.
- Visibility: approved points from already-due weeks divided by their cumulative target. No Hold points enter the threshold. For this prototype, the due-week target and current week are explicit sample controls; production must derive them from program data.
- Per-child automatic / always show / hide controls affect slideshow only. A hidden child may still scan when eligible by class schedule.
- Optional child photos and scan-session point totals. Photo picker is local-only; it never uploads.
- Scanner mode starts disabled. Settings > Scanner has sample codes and a sample-scan button. A keyboard-wedge scanner must send Enter. Scanning the same ID closes the session. Another child's ID cannot replace an active session. Duplicate and foreign-class cards are rejected without an Enter override. Inactivity closes after 15 seconds by default, adjustable.
- Optional receipt on same-ID close and separate optional receipt on timeout. Receipts open in a dialog, with a browser Print button; no silent printing. No receipt for an empty session. Changing settings or schedule closure ends the session without a receipt.
- Screen schedules use local computer timezone, support overnight windows, and turn the HTML screen black outside permitted hours. Class scanning windows apply only with scanner mode enabled; they use the schedule's selected weekdays. The simulation control allows testing boundaries without changing the computer clock.
- Full screen is user-initiated, hides the toolbar and pointer. F2 opens preview settings and restores the pointer; Esc exits browser fullscreen. This prototype is not a secure kiosk or a physical projector power controller.

Sample exercise: enable scanning, scan ID 1000, then reward 620001, then ID 1000 again. Sample reward barcode: 990000620001; sample student barcode: 120000001000. Receipt must first be enabled in Settings > Receipts.

Still to implement after visual approval: authenticated device-code pairing; server-enforced display-only permissions and class windows; real roster, photos, point data and redemption; derived due-week target; media/messages/birthdays/PowerPoint playlist; remote settings; silent receipt printing with supported hardware; installed kiosk shell and supported keyboard-only Task Manager recovery. The display must never receive broad school-admin credentials or rely on client-only checks for live redemption.

Tests: local Chromium checks layout, threshold exclusion and overrides, photo toggle, hidden-child scanning, no totals during scan, duplicate/foreign-class rejection, no Enter override, session switching, same-ID receipt, inactivity timeout, class window restriction, black screen and F2 recovery.

## Card layout revision

The Layout tab now lets you select the classes to display. Four classes use a 2×2 grid; eight use 4×2. Photo and name share one identity group, beside the green/grey meter. Rotation flips the outgoing card away and the new card into view; reduced-motion preferences skip the animation. Only the footer shows “Powered by YKONNECT”.

Settings > Text edits headings, captions, name/class templates and scan messages, with placeholder substitution. Font, scale, alignment, writing direction, heading color and clock visibility are configurable. Text is escaped rather than interpreted as HTML. Sample-data notices and attribution are retained. Settings remain page-local in this prototype and reset on reload.

Added browser checks: 2×2 equal-size layout, photo/name grouping, non-collapsed meters, edited heading, animation at rotation, and footer-only branding. Existing scanner, schedule and privacy checks still pass.

## On-screen designer revision

Click Design in the toolbar. The screen becomes an editable grid. Click an existing caption to type directly; click an empty grid cell or + Text box for a movable/resizable text box. Drag its Move handle or bottom-right corner. The toolbar controls left/center/right alignment, foreground/fill color, font, size, bold, page background and the selected class card's background. Clear fill removes a text box fill. Insert data adds a placeholder such as {name}, {class}, {approved}, {hold}, {goal} or {week}.

All classes, Single class and Scan screen have independent designs. Done returns to the display. Only design text, colors and geometry are saved in this browser's localStorage (not student records/photos); the status explicitly reports storage failures. Settings and redemptions remain sample-only. Authored display captions start blank. Names, classes and scores are data fields; operational scan errors still have default explanations. Footer attribution remains fixed, centered and outside the designer: Powered by YKONNECT. The physical off-schedule black screen hides the footer too.

The former Text settings tab is superseded by the direct on-screen editor. This is still an HTML prototype, not a server-synced design tool or secure kiosk. Editable school-provided content is inserted as text, not HTML. No live admin, database or device deployment changes.

Designer checks: blank captions, inline text and alignment, foreground/fill and card colors, draggable/resizable custom boxes, separate page designs, reload persistence, locked centered footer, and safe exit from scan-page design. Existing scanner/visibility/schedule tests also pass.
