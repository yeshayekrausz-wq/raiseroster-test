# YKonnect — Stage 1 (1.0.0)

Upload the complete contents of this folder to the existing HTTPS hosting location, preserving admin/, projector/ and superadmin/. Do not open index.html as a local file. No database migration is required.

Included: four platform install/help buttons, one root manifest and launcher, generated app icons, cached launcher, explicit offline fallback, conservative update lifecycle and retirement of the old projector cache. Admin and superadmin source are unchanged. No financial mutations, student records or API responses are cached. Offline data entry and synchronization are NOT implemented in this stage.

Release: upload all files together. Change VERSION in sw.js for each release that changes cached files, and update the displayed version in index.html. Serve sw.js with Cache-Control: no-cache (or equivalent revalidation). The browser downloads an update while online; activation waits until all controlled YKonnect windows/tabs close. No forced reload or skipWaiting on the root worker. Existing projector installations may need closing and reopening after their legacy worker retires. Existing projector-only shortcuts may remain separate; install the main app from the homepage.

Smoke check on the hosted site:
1. Open homepage in Chrome/Edge over HTTPS; use matching install button and confirm. Launch the installed icon: both Admin and Projector should appear.
2. On iPhone/iPad, follow Safari Share → Add to Home Screen; check icon and standalone launch.
3. Reopen once online to let the service worker control the page; go offline and reload homepage. Launcher should remain available. Admin/Projector should show the offline notice; no financial action should claim offline support.
4. Restore connectivity and reload; verify normal login and campaign behavior.
5. Deploy a version bump while a window is open: update notice should appear on the homepage; no automatic reload. Close ALL app and browser tabs for this site and reopen; confirm new version.

Next stage: scoped local database and download/read-only access, followed by queued idempotent money entries, server timestamps/versions and conflict handling. Requires inspection and changes to the Supabase schema/RPCs before offline writes can be enabled.
