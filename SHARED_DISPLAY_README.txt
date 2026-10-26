YKonnect — shared display design and celebrations

Install AFTER the Display Usability update (including Activate_Display_Controls.sql):
1. Upload this ZIP's folders to the same locations in GitHub.
2. Run the complete Activate_Shared_Display_Style.sql in Supabase SQL Editor.
3. Reload Motivation Admin. Open Display > Computers > a computer.

The “Shared design”, Appearance and “Shared greetings / מזל טוב” settings now apply to every connected computer in the SAME SCHOOL AND MOTIVATION PROGRAM, including computers added later.
The first save starts the shared design using the currently selected computer's design. Existing individual layouts are not deleted.
Click Save display settings to publish. Conflicting edits from another admin are rejected; reload before saving again.

Each computer keeps its own selected classes, layout mode (all/single), rotation, schedule, scanner settings, visibility overrides, power/background mode and image/video/PowerPoint-export playlist.

Birthdays:
- Enable Automatically show birthdays and choose Hebrew or Gregorian.
- Write your own greeting; use {name} and {class} for the child's information.
- Enter how many seconds each greeting stays and how long the normal display runs between greetings.
- Detection uses students in that display's selected classes. Students explicitly marked Hide are excluded. Birthday greetings do not require a points threshold.
- Gregorian mode uses the saved Gregorian birthday. February 29 appears March 1 in non-leap years.
- Hebrew mode uses the saved Hebrew birthday first. If it is blank, the Gregorian birthday is converted locally without a third-party request.
- Accepted examples: י״ד ניסן תשע״ג, 14 Nisan 5773, י״ד אדר א׳. Unreadable saved Hebrew dates are skipped, not silently replaced by a different birthday.
- Adar without a suffix uses Adar II in leap years; Adar I stays Adar I in leap years. Missing day 30 rolls to the next day after day 29. These follow birthday-anniversary conventions, not yahrzeit rules. Reference: https://hebcal.github.io/api/core/classes/HebrewCalendar.html
- The school timezone determines the civil date; greetings change at midnight, not sunset. Conversion from a Gregorian date assumes daytime birth. For a child born after sunset, correct the saved Hebrew birthday.

Other simchas:
- Click Add greeting, enter the text and choose From / Through dates (inclusive).
- These announcements are shared across the program's screens.
- Greetings take turns with the ordinary display and media; scanning interrupts them.
- They are suppressed in Black screen / Run in background modes.

No new EXE is required for this update when using the recent display player: its screen loads the updated website. If it is already running, restart it once after GitHub Pages updates so it loads the new renderer scripts.

SQL adds one private RLS-enabled table and authorized RPCs. It does not reset students, points, pairing codes or media. Run this SQL after earlier display migrations.

Tested: repeat-safe migration, authorization, shared design across two devices, independent rotation/media settings, stale-edit rejection, Gregorian and Hebrew birthdays, Hebrew punctuation/nikud, Adar leap cases, date-ranged messages, scanner interruption, off-screen suppression, and connected admin/designer regression tests. Physical device testing remains necessary.
