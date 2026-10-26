# Update 1.1

For current behavior and upgrade steps, read DISPLAY-UPGRADE-START.txt. The original
setup notes below describe version 1.0; code expiration, hidden off-windows and
slideshow limitations there are superseded by version 1.1.

# Connected school display — installation

This update is built and tested locally. It has not been deployed to GitHub Pages,
Supabase, or GitHub Releases. Existing school records are not reset by this migration.

## 1. Website files

Extract YKONNECT_Display_Connected_Update.zip. Upload its CONTENTS to the root of
raiseroster-test, preserving the folders, replacing matching paths. Do not upload
the ZIP itself as the website and do not put another outer folder around its contents.
The package includes the complete tracked website, the Windows app source and the
release workflow. No node_modules or build output is included.

## 2. Supabase SQL

Open Activate_Display_Devices.sql as TEXT. Copy only its SQL into a NEW Supabase
SQL Editor query and run it. Success ends with DISPLAY_DEVICES_READY.
Do not paste an HTML page into SQL Editor. All new tables have RLS enabled and no
anonymous/direct table access. Admin RPCs require current school admin membership;
device RPCs require a random secret retained by the paired computer.
This is an additive migration; it does not reset children, cards, points, or logs.
It requires the existing Motivation + reward card + automatic planner migrations.

## 3. Student photographs

Deploy supabase/functions/display-photo/index.ts as an Edge Function named
`display-photo`, with JWT verification OFF. The function validates the device
capability itself. With Supabase CLI:

    supabase functions deploy display-photo --no-verify-jwt

The three standard Supabase environment secrets are already supplied by Supabase.
Do not copy the service-role key into the website or player. Without this function,
the display still runs, but private student photographs cannot load. The function
accepts only the school's student photo paths and PNG/JPG/WebP images up to 5 MB.

## 4. Windows app and public download

The supplied YKONNECT-Display-Setup.exe installs per Windows user and starts the
player. It is unsigned: no Windows code-signing certificate has been configured.
The EXE was packaged on Linux; actual installation, scanner hardware, startup,
printer output and update installation still need a Windows computer test.

Make sure `.github/workflows/display-release.yml` is included in GitHub. Under
Actions, open **Windows display player → Run workflow**. A successful run builds on
Windows and publishes the EXE, blockmap and latest.yml together as a GitHub Release.
A public repository's stable download URL then becomes:

https://github.com/yeshayekrausz-wq/raiseroster-test/releases/latest/download/YKONNECT-Display-Setup.exe

No website login is required to download. The URL is not active until the first
release exists. Subsequent pushes changing the player/display files trigger a new
version. The app checks every 30 minutes and installs downloaded updates outside
an active scan session. Version numbers use the workflow run number. Do not delete
or reuse published versions. GitHub Actions must be allowed to create releases.
Website rendering changes are included in that release trigger, causing clients
to restart with the updated page. Keep this release marked latest; unrelated future
releases in the same repository must preserve the display update assets/feed.

## 5. Connect the computer

1. Install and open the player on the display computer. It shows nine digits.
2. In Motivation Admin choose the program, then Display → Computers.
3. Enter those nine digits and a label such as “Main hallway”.
4. Open the computer's tile. Select a saved weekly plan and classes, configure
   layout, rotation, visibility, schedules and scanning, then Save display settings.
5. Choose Design to edit the screen. Its children/points are real preview data.
   Click Done in the designer, then Save display settings to send it to that device.
6. Check Turn on display and Save. The app reacts within the polling interval
   (normally five seconds). The player starts automatically when this Windows user
   signs in. It runs in the background while the display is off.

Browser test (after website deployment):
https://yeshayekrausz-wq.github.io/raiseroster-test/motivation/display/

Browser device secrets stay in that browser's local storage; clearing site data
requires pairing again. Windows device secrets use Windows encrypted storage.
Codes expire after 15 minutes, refresh automatically, and can be changed while
unpaired. For a connected computer, Disconnect in Admin first to revoke access
and issue a new pairing code. Do not share an unpaired code with another school.

## Behavior and boundaries

- One child per selected class, or one selected class on the whole display.
- Green: revealed approved points. Grey: held points from the current plan week
  only. Old held weeks do not show. Visibility uses approved points for completed
  plan weeks against the corresponding portion of the original target; current
  week points do not lift the threshold. Individual show/hide overrides are saved.
- Scan an ID anywhere without focusing an input. Scan rewards, then the same ID
  again to finish. Default inactivity is 15 seconds and is configurable. School,
  class, schedule, duplicate and card rules are checked in the database. There is
  no display override. On uncertain network results, scan the same card again to
  confirm the same request, avoiding double entry.
- Photos and scan totals are separately optional. Student phone/address details
  are not sent to display devices. Off/offline screens stop showing student data.
- Optional receipts use the Windows DEFAULT printer silently. Configure the
  receipt printer's roll size/defaults in Windows first. Browser receipt previews
  use the browser print dialog. Receipts show card count; entered card-point sum
  is optional and is not described as fully approved points.
- Fullscreen is a frameless, cursor-hidden kiosk window. Windows Task Manager
  recovery remains available. This is not an OS security lockdown; other Windows
  shortcuts may still work. Screen schedules turn the player view on/off, not the
  physical projector's power. Hardware power control needs projector integration.
- No author-written captions are filled in by default. Powered by YKONNECT remains
  centered at the bottom, outside editable boxes. Designs are stored per device.
- The current scope does not add media playlists to the new designer, ID-card
  photo exports, or the deferred planner/dashboard fixes in
  PENDING-MOTIVATION-REQUESTS.md.

## Verification

PGlite database tests cover repeat installation, RLS/direct-table denial, pairing,
consumed codes, school boundaries, revisions, real scan redemption, duplicate
protection, wrong-class denial, disabling and disconnecting. Browser tests cover
real roster rendering, visibility, global scanning, optional totals, remote off,
per-device settings, and saving designs from the embedded designer. Existing
standalone designer regression tests pass. No live school database was changed.

Renderer source: motivation/projector/preview.html plus
motivation/display/bridge.js. Regenerate connected HTML with:

    node scripts/build-display-renderer.mjs

Windows build on Windows:

    cd desktop/display
    npm ci
    npm run dist

The local cross-build used electron-builder's bundled NSIS UninstallerReader
(the same extraction path it uses on macOS) instead of Wine. The published GitHub
workflow performs a standard Windows build without that local adaptation.
