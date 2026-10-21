YK Connect — Random codes and roster update

INSTALL / אינסטאלירן
This is an update to the previous MOTIVATION_REWARDS_READY version.
1. Run the complete Activate_Random_Cards.txt in Supabase SQL Editor. Result: MOTIVATION_RANDOM_CODES_READY.
2. Extract the ZIP. Upload the motivation folder and sw.js at the GitHub repository root, preserving their folder paths. Commit changes.
3. After deployment, reopen the website and use Ctrl+Shift+R if needed.
Do not paste HTML into SQL Editor. Use this new SQL file; do not rerun the earlier five-digit installer after this upgrade.

דער SQL איז פאר די פריערדיגע Rewards ווערסיע וואס איז שוין אינסטאלירט. קאפירט דעם נייעם SQL־טעקסט אין Supabase, און אפלאוד די וועב־פיילס אין GitHub מיט די זעלבע פאלדערס.

CHANGES / טוישונגען
• School days removed from card generation. New cards belong to an accounting week and morning/afternoon session, with no invented day assignment. Old cards with assigned days can still be filtered by those days when unfreezing.
• Reward manual codes are now SIX random numeric digits (100000–999999). Student IDs remain four digits; scanner barcodes remain twelve digits. Each school's code ledger prevents duplicate codes and survives test resets so old codes are never reused. Randomness uses PostgreSQL's cryptographic UUID generator, with rejection sampling. This makes codes nonsequential; it does not replace authenticated access, duplicate-redemption checks, or protections needed in a future public phone service.
• Existing five-digit reward codes are replaced with random six-digit codes. Reprint reward cards from the saved orders. Existing twelve-digit barcodes remain unchanged. No points or student profiles are deleted by this upgrade.
• Main-menu section re-entry opens its initial view. Documents closes the generation panel and clears its selected order/filter; Dashboard returns to the class overview; Eligibility returns to week/class selection; Reports clears filters. Saved data stays saved. Unsaved class sheets and open generation/settings forms prompt before leaving; unresolved requests must finish or retry.
• Hold Shift from any main page to show the student navigator centered on screen. Up/down chooses a student, left/right changes class, releasing Shift opens the profile. Esc cancels. Capital-letter typing is preserved. Editing/confirmation dialogs and pending card operations block profile switching.
• Search results show the student's short ID and registered phone numbers alongside the name. Profiles display saved address, English/Hebrew birth dates, notes and phone numbers, plus existing pictures and attachments.
• Dashboard → Bulk add students: choose a class, enter full-field rows or paste tab-separated Excel data. Column order is shown above the paste box. Dates use YYYY-MM-DD. Up to 200 pupils save in one transaction: invalid rows or duplicate names in the same class prevent the entire batch from saving. Retrying an unchanged request does not create duplicates. Photos and attachments continue to be uploaded through Edit Profile / Edit this class after creation.
• Eligibility uses a compact multi-column class sheet. A 30-pupil class was tested at a 1440×1000 desktop viewport without scrolling the pupil list; smaller screens or bigger classes may still require scrolling.
• Hold whole school applies to the selected accounting week and active Motivation program, after explicit confirmation. It clears individual releases for that week, places every student on Hold, and recalculates already redeemed card points. Other weeks/programs and manual/exam points are unchanged. It does not delete cards. Use the class sheet or Unfreeze to authorize points afterward.

וויכטיג: די אלטע 5־ציפעריגע נקודות־קאודס ווערן געטוישט. דרוקט איבער די נקודות־קארטלעך. די 12־ציפעריגע בארקאודס בלייבן די זעלבע.
Hold whole school גייט נאר אויף דער אויסגעקליבענער וואך אינעם אקטיוון פראגראם; עס מעקט נישט קיין קארטלעך.

TESTING
Local database suite: repeated migration, five-to-six digit upgrade with stable barcodes, random unique allocations, no date assignment, reset non-reuse, full-school Hold and stale-revision protection, full-field bulk add, rollback on invalid/duplicate rows, permissions and retry safety, plus prior rewards tests.
Local browser suite: centered global Shift navigation, scanner behavior, phone search with IDs, full profile details, bulk-add UI, fresh section entry, class-sheet choices, school Hold, exports and reset flow. No live database reset or GitHub deployment was performed.
