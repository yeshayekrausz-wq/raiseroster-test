# YKonnect screen and printing update

## Installation — do these in order
1. Extract the ZIP and upload its folders/files into the existing GitHub repository root, replacing matching paths. Keep the folder structure. Commit to main.
2. Supabase SQL Editor: run the complete `Activate_Display_Media_Access.sql` file. It adds the missing function that allows a paired display to read only its own saved slideshow files. It does not delete student data or create new tables.
3. Supabase → Edge Functions → display-photo: deploy the included `supabase/functions/display-photo/index.ts`. Disable **Verify JWT with legacy secret** for this function. Its own paired-device verification remains enforced in SQL. GitHub upload alone does not deploy an Edge Function. CLI alternative: `supabase functions deploy display-photo --project-ref jqylxbqwznoohscjbxrx --no-verify-jwt`.
4. GitHub → Actions → Windows display player → Run workflow → main → Run workflow. Wait for green. The installed player needs the new release; refresh browser players and the admin with Ctrl+Shift+R.

## Changes
- Students columns fit the page width, with no inner table scrollbars. A long student list still uses normal page scrolling; hundreds of full records cannot be legibly shown at once.
- Upload image opens the file picker immediately and saves the picture to that student. Click an existing photo to replace it. Uploads run one at a time with progress/errors.
- Gregorian birthdays use MM/DD/YYYY in Motivation lists, profiles, bulk editors and Excel, and Campaign bulk date fields. Database values remain ISO dates. Hebrew birthdays retain their Hebrew format.
- Account icon above user name and verified school role. Click to upload your own profile picture or sign out. Photos are private school storage; user metadata stores the path.
- Fixed slideshow race: while a slow media URL is being resolved, the player no longer starts the same load again every 250 ms. Added the missing private-media authorization SQL. Media controls are visually grouped. Direct image/MP4/WebM links are supported; sharing/preview pages and native PPTX playback are not.
- Birthday greeting shows a large child photo if student photos are enabled and the image is available. Text wraps/fits without scrollbars. Photos use fixed slots so longer student names do not move the image. Missing photos show the first letter of the name.
- Designer: apply matching text-box settings to all class cards is enabled initially and has an explicit Apply selected box to all classes button. Settings remain editable individually by clearing the checkbox. Save display settings to publish.
- Cards: choose 2, 4, 6 or 8 per page and US Letter or A4. Print/PDF and Word use the selected layout and consistent headers. Print at 100%, with browser headers/footers off. The choice is in Documents beside the export controls.

## Verification
Browser checks cover table width, direct photo chooser, birthdays, invalid dates, profile-picture upload, private display images, delayed slideshow loading, birthday photo/no scrollbar, scans, and Letter PDF pagination. The SQL was executed twice and tested for valid paired access, wrong device secret, wrong/missing path and disabled display. JavaScript syntax checks passed.

Live deployment, the physical Windows machine, internet filtering and the actual printer have not been tested here. If the player still shows a photo/media error after installation, send the exact new error including HTTP status. This update does not change Campaign/Motivation polling intervals; that request remains deferred.
