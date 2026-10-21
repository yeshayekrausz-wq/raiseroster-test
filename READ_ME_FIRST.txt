YK Connect — Reward Cards update

אינסטאלירן / INSTALL
1. עפנט Activate_Reward_Cards.txt אין Notepad. קאפירט דעם גאנצן טעקסט אין Supabase → SQL Editor → New query → Run. דער רעזולטאט דארף זיין MOTIVATION_REWARDS_READY.
   Open Activate_Reward_Cards.txt in a text editor. Paste all of it into Supabase SQL Editor and run. Expected result: MOTIVATION_REWARDS_READY. This requires your existing Stage 5 workspace. The update is one transaction and is safe to run again.
2. עקסטרעקט דעם ZIP. אין GitHub, אין דער הויפט פלאץ פון raiseroster-test, אפלאוד דעם motivation פאלדער און sw.js מיט די זעלבע פאלדער־סטרוקטור. די נייע פיילס ערזעצן די אלטע פיילס מיט די זעלבע נעמען. Commit changes.
   Extract the ZIP. Upload the motivation folder and sw.js to the repository root, preserving folders. Replace matching files and commit. Do not paste HTML or the ZIP into SQL Editor.
3. ווען GitHub Pages איז פארטיג, פארמאכט די אלטע טעבס און עפנט די וועבזייטל נאכאמאל. אויב נויטיג, Ctrl+Shift+R.
   After Pages deployment finishes, close old tabs and reopen; hard-refresh if needed.

וואס איז ניי / INCLUDED
• תלמיד ID: 4 ציפערן. נקודות קארטל: 5 ציפערן. באזונדערע 12־ציפעריגע בארקאודס פאר ביידע; קיין געדרוקטע נומער אונטערן בארקאוד.
  Student IDs: four digits. Reward manual/phone codes: five digits. Separate twelve-digit numeric scanner barcodes; no barcode caption.
• קארטלעך לויפן נישט אויס. די דאטומען באשטימען די רעכענונג־וואך. ביים שאפן סעלעקטירט מען אויך שול־טעג פאר באפרייען לויט טאג.
  Cards never expire. Dates identify the accounting period. Select school days when generating; cards are spread over those days within each teacher session. Old cards without an accounting period keep their previous full-credit behavior.
• מלמדים: גאנצער טאג, פארמיטאג אדער נאכמיטאג. אפילו איין גאנץ־טאג רבי באקומט צוויי באזונדערע באטשעס. פארמיטאג + נאכמיטאג מוז גלייך זיין דער סך־הכל פאר א קינד.
  Full-day assignments also produce separate AM/PM batches. AM + PM allocation must equal total cards per child. There are no prefilled allocations or point percentages.
• Select all פאר כתות. נקודות־פראצענטן ווערן צעטיילט באזונדער פאר יעדע כתה, צוזאמען איבער ביידע סדרים. די צעטיילונג פאר יעדע רבי ווערט צופעליג געמישט פון יענער כתה'ס סכום.
  Configure point values and percentages totaling 100. Each class receives its own exact total, randomly distributed between its teacher/session batches. Exact rounding rejects fractions; the other options assign largest remainders, with ties favoring lower or higher points.
• Eligibility אין דער זייט: אויסקלייבן וואך און כתה, ALL / לפנה״צ / אחה״צ. נאר איין קעסטל פאר א קינד; קיין קעסטל מיינט Hold. מען קען סעלעקטן די גאנצע כתה און אויסנעמען יחידים.
  IMPORTANT: new accounting periods start on Hold. Save the class sheet before normal use. Eligibility changes recalculate already redeemed points and control future redemptions. Changing a pupil's choice clears their individual overrides for that week.
• Unfreeze cards אינעם פראפייל: וואך, טאג, סדר אדער יחידישן קארטל; 100%, 50% אדער אייגענער פראצענט. עס שטעלט דעם סך־הכל באוויליגטע פראצענט; עס לייגט נישט נאכאמאל צו די זעלבע פוינטס.
  Unfreeze lists redeemed cards that are not fully authorized. Broad releases also cover later redemptions in that scope. More specific overrides take precedence until replaced by a new broader release. Partial points may have decimals. Manual points/exams are not held by this card sheet.
• סקענען א תלמיד־בארקאוד עפנט זיין פראפייל. סקענען א נקודות־בארקאוד אינעם אפענעם פראפייל קען ארבעטן אן קליקן אין פעלד. א צווייטע איינלייזונג ווערט נישט גערעכנט.
  Code 128 keyboard scanner with Enter suffix. Student barcode opens a profile globally; reward scanning applies to the open profile. Wrong-class cards require explicit override. Pending saves and dialogs block switching. Existing daily/weekly caps and reveal-next-day settings still apply. Telephone provider integration is still separate; these numeric codes are ready for manual/phone entry.
• דאונלאוד־קנעפלעך זענען העכער דער ליסטע. סעלעקטירט א Saved card order צו באקומען אלע קארטלעך פון דער באשטעלונג. All teachers / sessions איז דער נארמאלער אויסוואל; מען קען אויסקלייבן איין באטש פאר א איבערדרוק מיט די זעלבע קאודס.
  Choose a saved order to export every card, not only the recent 500. Each teacher/session starts a separate Word/print section. Word uses two columns with one card per cell. Excel has one row per card with named fields for mail merge and barcode images. PDF uses Print → Save PDF. Teacher cards are sorted by class, then teacher/session.
• Reset: Program Settings → Reset. אריינשרייבן RESET MOTIVATION און באשטעטיגן. עס מעקט פיזיש אלע Motivation קארטלעך, באשטעלונגען, פוינטס, Hold־באשלוסן און לאגס פאר דער שול. תלמידים, פראפיילס, IDs, כתות, מלמדים און סעטינגס בלייבן. Campaign דאטא בלייבט.
  Reset is permanent, school-wide across Motivation programs, and requires typed plus dialog confirmation. No reset was run on your live database by this update.

IMPORTANT LIMITS
Five-digit reward codes have a finite supply: 10000–99999 (90,000 codes per school). Used codes are never recycled, including after Reset, so an old printed card cannot redeem a new card by mistake. The application stops generation when that range is exhausted. Four-digit student IDs support 9,000 IDs per school. A larger live deployment will need a decision about code length before these ranges run out.
Old reward short codes are migrated; old long scanner codes remain accepted for compatibility. Reprint student IDs to use the new numeric student barcode.

VALIDATION
Tested locally: repeated full SQL activation, permissions, exact per-class distribution, AM/PM full-day split, old-period redemption, Hold and percentage recalculation, day/session/individual releases, reset behavior, browser keyboard scanning, eligibility UI, Word and Excel files. Physical scanner hardware and your live Supabase/GitHub Pages deployment were not tested or changed.
