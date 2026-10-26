YKonnect Display 1.2.0 — installation steps

1. GitHub: extract YKonnect_Display_Usability_Update.zip and upload its folders to the same locations in raiseroster-test. Include .github/workflows/display-release.yml (Windows may hide the .github folder).
2. Supabase SQL Editor: run Activate_Display_Controls.sql, then Activate_Display_Media_Repair.sql. These do not reset students, points, cards, pairing codes or stored media. The media repair replaces only the named media access policies and keeps the bucket private. Requires the earlier Display Devices and Display Upgrade SQL already installed.
3. On the display PC, install YKonnect-Display-1.2.0-Setup.exe. This is required for remote background mode. If the old damaged uninstaller still fails, use the earlier uninstaller repair first.
4. Public EXE download: GitHub currently has no published releases. Open https://github.com/yeshayekrausz-wq/raiseroster-test/actions and choose “Windows display player” > Run workflow > main. Wait for the build and Publish step to finish. This publishes the installer and update metadata. If the workflow is absent, check that .github/workflows/display-release.yml was uploaded. This cannot be completed by uploading source files alone.
5. Public download page: https://yeshayekrausz-wq.github.io/raiseroster-test/downloads/display/ . It does not require login and only offers an installer after a release exists. It shows an explanation instead of sending visitors to a missing file.

CHANGES
- Shift navigation ignores inputs, text areas, select controls and editable text in Motivation and Campaign Admin.
- Display computers: Show display / Black screen / Run in background. Background hides the Windows window but leaves the paired agent polling; Show display brings it back. Disconnect is separate. School schedules still apply when showing the display.
- Design: select a field, turn on “Apply style to all class cards / text boxes”. Colors, fonts and alignment apply to matching fields in other class cards; custom text boxes share style. Personal student text and box positions are preserved. Save display settings to publish.
- Print/PDF and Word: six cards per sheet (two columns, three rows), with teacher groups kept separate. A teacher’s final sheet can contain fewer than six cards. Excel remains one row per card for mail merge.
- Bulk edit: spreadsheet table above individual student editors. Paste phone numbers into the first Phone cell to fill downward; names into the first Name cell. Tab-separated data fills across. Existing details are not saved until Save. Oversized pastes are rejected before changing any cells. Bulk Add also supports direct cell paste.
- Private media bucket setup is repeat-safe, permits supported image/video/PDF files up to 25 MB, and limits access to the school’s admins. Network/filter failures now have actionable messages.

UPLOAD LIMITATION
The live failed upload was not reproduced with your signed-in account. The private Storage setup was tested, but an internet-filter or proxy blocking /storage/v1/ cannot be fixed by SQL. If uploading still fails, send the exact new error. Display playback also needs the previously supplied display-photo Edge Function deployed; that is separate from uploading.

VALIDATION
Automated checks cover background/resume, SQL authorization and scan blocking, private storage isolation, TSV paste and Shift inputs, missing/available release download states, 12 printed cards on 2 Letter pages, Word page/teacher grouping, and existing connected display/designer behavior. Windows installation and remote control on the physical display PC still need testing.
