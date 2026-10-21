YK Connect — Class sheet, Unfreeze and student profile update

INSTALL
Requires the previous Random Cards update.
1. Open Activate_Class_Unfreeze.txt in a text editor and run the complete SQL in Supabase SQL Editor. Expected result: MOTIVATION_CLASS_UNFREEZE_READY.
2. Extract the ZIP and upload motivation/ and sw.js to the repository root, preserving the folder structure. Commit changes.
3. After deployment, reopen the website; Ctrl+Shift+R if needed.
Do not paste HTML or the ZIP into SQL Editor. This installer does not change any card codes and does not reset data.

CHANGES
• Eligibility is one vertical class sheet, one pupil per row, with compact ALL / morning / afternoon checkboxes. Thirty pupils fit in the tested 1440×1000 desktop viewport; smaller displays may require scrolling.
• Unfreeze class: choose a week and class, then confirm. Releases both sessions to 100% for current members of that class.
• Unfreeze school: choose a week, then confirm. Releases both sessions to 100% across the school for that week's Motivation program.
• Both actions replace individual restrictions and partial releases within that selected week. Already redeemed card points are recalculated without adding duplicate ledger entries, and future redemptions follow the new eligibility. Other weeks/programs and manual/exam points are unchanged. These actions do not delete cards.
• Student details now appear directly below the name. Active class teachers appear as מלמד {name}, with morning/afternoon labels where applicable.
• The old Student details side box is reserved for the student's picture. The shortcut instructions and Open Campaign Admin link are removed from the profile. The address is hidden from this profile view; its saved database value and Edit Profile field remain. Other saved details and file attachments appear under the name.
• Student IDs, reward codes and barcodes are unchanged. No card reprint is required for this update.

אינסטאלירן דעם נייעם SQL־טעקסט אין Supabase און אפלאוד די וועב־פיילס אין GitHub.
אנפריזן א כתה אדער חדר גייט אויף דער אויסגעקליבענער וואך, ביידע סדרים, 100%.
די כתה־ליסטע איז צוריק איין שטייענדיגע ליסטע. די תלמיד־פרטים און מלמדים שטייען אונטערן נאמען; דער זייטיגער קעסטל איז פארן בילד.
קיין נייע קארטל־קאודס ווערן נישט באשאפן דורך דעם אפדעיט.

VALIDATION
Local database tests cover class/school releases, unchanged totals on repeated release, stale revision protection and school/role isolation, alongside previous reward, reset and bulk-add regressions. Browser tests cover both release buttons, thirty-row vertical sheet, profile layout/teacher names, and prior workflows. No live database actions or deployment were performed.
