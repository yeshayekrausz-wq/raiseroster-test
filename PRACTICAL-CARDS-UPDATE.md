# Practical Motivation cards

## ארויפלייגן

1. Open `Activate_Practical_Cards.txt` in Notepad. Copy its SQL into Supabase SQL Editor and Run. Final result: `MOTIVATION_PRACTICAL_READY`.
2. Extract `YK_Practical_Cards_Update.zip` and upload its contents to the existing GitHub root, preserving folders. The SQL includes previous settings/week, barcode override and card-policy updates; Stage 5 must already be installed. Do not run older migrations after it.
3. Reload Motivation and click Refresh students. Print new ID cards: existing IDs below 1000 are reassigned. Valid existing four-digit IDs are preserved. Internal student UUIDs, points and history stay unchanged.

## דער סדר פונעם באניץ

- Teacher Portals → Add teacher: name, class, Full day / Morning / Afternoon. Email is optional for card preparation; a verified email is required for the existing read-only portal login.
- Each class has either one active full-day teacher, or one active morning teacher and one active afternoon teacher. Edit existing assignments to choose a session. Disable an old assignment before replacing it when necessary.
- Documents → Student ID cards: ready-made name, four-digit ID, class, saved phone and Code 128 barcode. If home phone is present, it is used first; otherwise main, father or mother phone. No saved phone is fabricated.
- Scan a newly printed student ID anywhere in the active Motivation Admin browser page to open the student. Scanner must use keyboard mode with Enter. A pending redemption or busy edit must finish first; unsaved dialog edits require confirmation before switching. This is not an operating-system background listener and is not installed in Campaign Admin.
- Documents → Generate reward cards: choose inclusive from/through dates, classes, total per child, morning/afternoon split where needed, and points per card. All numeric inputs start blank. Full-day teachers receive the total; split-teacher amounts must add to the total.
- Preview shows teacher, class, student count, per-child count and total. Generate creates separate teacher batches. A changed roster/teacher assignment requires another preview.
- Saved card order loads all cards in that order (not only the most recent 500). Choose a teacher batch for print/PDF, Word or Excel. The simple reward layout includes class, teacher, card number, dates and barcode. Existing custom reward lines remain supported, with required identification appended.
- Rewards are class/teacher batches, not individually preassigned cards. The recipient is assigned on redemption. Per-student daily/weekly caps remain in effect. Creating ten cards per student does not silently change those caps.
- Enter the printed reward number manually in the student's reward field, or scan the reward barcode. IDs use a distinct school-specific barcode prefix to avoid confusing student IDs with reward numbers or another school's students.

## Date rules and limits

From starts at midnight in the saved school timezone; Through includes that whole day. Expiry occurs at the next midnight. The chosen range overrides the general expiry-days rule for these dated orders. Existing cards are not backdated or rewritten. Normal redemption and class overrides enforce both start and expiry. The UI does not schedule automatic future printing.

Four-digit IDs range from 1000–9999 and are unique per school. IDs are retained for archived students; exhausting the range gives an explicit error. Orders support up to 20,000 cards and up to 100 selected classes; split allocations apply to the selected split classes for that order. Use separate orders for different allocations. Repeating the same generation request does not duplicate cards; deliberately making a new order for the same dates creates an additional order.

## Verification

PGlite tests exercise repeat installation, stable four-digit IDs, tenant/role isolation, teacher conflicts, exact full/split quantities, invalid date/count inputs, stale previews, retry idempotency, validity enforcement, manual card numbers, and complete retrieval of more than 500 cards. Existing database regressions also run.

Playwright tests with mocked Supabase exercise basic ID printing, scanning from Reports and from a student profile, school mismatch rejection, optional-email teachers, empty numeric fields, order preview/generation, teacher batch selection, printing all cards and Word/Excel exports. A live school database, production deployment and physical scanner have not been tested or changed.
