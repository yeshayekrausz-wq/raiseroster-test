# Students and display update

## Install
1. Extract the ZIP. Upload its contents to the repository root, preserving folder names. Replace matching files. Commit to main.
2. No new SQL is required for this update. Do not paste HTML or JavaScript into the SQL editor.
3. Supabase Dashboard → Edge Functions → display-photo: deploy the included `supabase/functions/display-photo/index.ts`. In this function's settings disable **Verify JWT with legacy secret**. The function verifies the paired device secret through database RPCs; storage remains private. GitHub upload alone does not deploy an Edge Function.
   CLI alternative from repository root: `supabase functions deploy display-photo --project-ref jqylxbqwznoohscjbxrx --no-verify-jwt`.
4. GitHub → Actions → Windows display player → Run workflow → main → Run workflow. Wait for a successful release. Installed players need that new version; browser players only need reload.
5. Reload the admin with Ctrl+Shift+R. Open Students after Dashboard.

This update assumes the previously installed Display Devices, Controls, Media Repair and Shared Display Style SQL migrations. Do not rerun older migrations over newer ones.

## What changed
- Students table after Dashboard: class order, details, Hebrew/Gregorian birthdays, all saved phones, approved/held points, per-column filters, edit and upload image action. Excel exports the filtered list, preserves IDs/phones as text, freezes headings and includes Excel filters. Photo binaries are not included in this roster export.
- Student photos are resized to at most 1600 pixels and converted to JPEG before upload. JPG/PNG/WebP source pictures up to 80 MB are supported; this does not bypass internet filters or denied storage permissions.
- Display accepts existing HTTPS student photo sources as well as private storage photos; failed private photos retry no more than once a minute and report an error. Missing photos use a neutral silhouette instead of the last letter of the child's name.
- Slideshow reports failed media links instead of silently hiding them; videos retry muted when automatic sound playback is blocked. Use direct HTTPS image/MP4/WebM URLs, not a Drive preview page or a PPTX file. Export PowerPoint as MP4 or slide images first.
- Scanner accepts Enter or Tab terminators. Browser scanning errors show the server message. Live scanning operates in the paired player, not the Shared design editor. Class rules and duplicate protection remain server enforced.
- Temporary test-student button under Teacher Portals creates a separate real TEST student with your home number and class. It does not grant an admin/teacher login. Real redemptions affect points; use the Phone Settings simulator for tests that must not affect points. Remove its class assignment when finished.
- All Programs moved below Training; sign-out and notifications in the Motivation top bar. Footer: Powered by YKonnect.
- ID cards grouped by class. Print/PDF and Word card pages reserve consistent header space, with six fixed-size cards per full page. Print at 100% scale, A4, with browser headers/footers disabled. Printer feed tolerances still apply.

## Verification and limits
Automated browser checks passed for full admin navigation, student filtering/edit selection, class ordering, Excel export, image resizing, private display images, URL slideshow, and Enter/Tab scan sessions with mocked backend responses. Excel opened with openpyxl. JavaScript syntax and patch whitespace checks passed.
No deployment to GitHub, Supabase, or a Windows device was performed from this workspace. Existing school-specific Storage/Edge Function/network failures require verification after deployment. This package does not claim that the root cause on the physical display has been confirmed.
