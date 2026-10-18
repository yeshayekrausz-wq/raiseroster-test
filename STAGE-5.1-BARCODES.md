# YK Connect — Stage 5.1: קארטל־בארקאדס און שנעלע סקענס

## אינסטאלירן

דער אפדעיט גייט אויף דעם שוין אינסטאלירטן Stage 5.

1. עקסטרעקט דעם ZIP און אפלאוד דעם אינהאלט אין דעם GitHub־הויפט־פאלדער, מיט די זעלבע פאלדערס. די פיילס מיט די זעלבע נעמען ווערן דערהיינטיקט; אנדערע פיילס בלייבן.
2. עפנט `migrations/20261018_motivation_barcode_override.sql` אלס טעקסט. קאפירט דעם גאנצן אינהאלט אין Supabase → SQL Editor און דריקט Run. דער רעזולטאט דארף זיין `MOTIVATION_BARCODE_READY`. מען קען עס זיכער לויפן נאכאמאל. עס מעקט נישט אויס קיין קינדער, קארטלעך אדער פוינטס.
3. נאכדעם וואס GitHub Pages ענדיקט, פארמאכט די פראגראם־טעבס און עפנט נאכאמאל.

## וויאזוי עס ארבעט

- יעדער Student ID און reward card באקומט א Code 128 בארקאד, אויך אין Word, Excel און Print / Save PDF. די עקזיסטירנדע קארטל־קאודס בלייבן גילטיג: מען דארף נאר נאכאמאל פרינטן די קארטלעך צו באקומען די בארקאדס.
- ID־קארטלעך אנטהאלטן דעם קורצן תלמיד־נומער. ריווארד־קארטלעך אנטהאלטן דעם ריווארד־קאוד. נאר א ריווארד־קארטל לייגט צו פוינטס.
- עפנט דעם ריכטיגן תלמיד־פראפייל. דער סקענער דארף זיין אין keyboard/HID mode, מיט Code 128 enabled און Enter אלס suffix.
- מען קען סקענען אן קליקן אינעם פעלד, כל זמן דער פראפייל און בראוזער־פענסטער זענען אקטיוו. מען קען אויך טייפן דעם קאוד אינעם פעלד און דריקן Enter אדער Apply card.
- דער פעלד ווערט אויסגעליידיגט נאכן רעזולטאט, גרייט פארן נעקסטן קארטל. Add / subtract points בלייבט פאר מאנועלע פוינטס.
- א קארטל פון אן אנדער כתה עפנט א ווארענונג. Enter באשטעטיגט דעם איבעררייד; Esc זאגט אפ. די ערשטע Enter פונעם סקענער באשטעטיגט נישט דעם איבעררייד. דער לאג האלט דעם אדמין, תלמיד, אריגינעלן קארטל־כתה און דעם איבעררייד.
- א שוין באנוצטער קארטל קען נישט נאכאמאל געבן פוינטס. דער weekly cap, cards enabled און next-day reveal בלייבן אין קראפט, אויך ביים איבעררייד.
- ביים אפזאגן א כתה־ווארענונג בלייבט דער קארטל blocked ווי אינעם פריערדיגן סיסטעם. מען קען אים איבערקוקן און reopen אונטער Documents.
- ביי א פארלוירענער נעץ־ענטפער: לאז דעם תלמיד אפן און דריק Enter אינעם פעלד צו פרובירן דעם זעלבן request נאכאמאל. דאס גיט נישט קיין דאפלטע פוינטס. א pending request לאזט נישט איבערשפרינגען צו אן אנדער תלמיד.
- דאס איז פאר א USB/Bluetooth keyboard scanner. א קאמערא־סקענער און א Windows־גלאבאלער סקענער ווען דער בראוזער איז נישט אקטיוו זענען נישט אריינגערעכנט.

## דער ערשטער לייוו־טעסט

מאכט א קליינע טעסט־באצירקונג מיט א באשטימטן טעסט־תלמיד און טעסט־קארטלעך, כדי נישט אומזיסט צו טוישן אמת'ע תלמיד־פוינטס:

1. פרינט א קארטל. עפנט דעם טעסט־תלמיד; קליק אויפן פראפייל־קעפל און סקען. קאנטראליר די פוינטס און דעם תלמיד־לאג.
2. סקען זעלבן קארטל נאכאמאל: עס טאר נישט נאכאמאל צולייגן.
3. סקען א קארטל פון אן אנדער כתה: Esc טאר נישט צולייגן; אויף א פרישן אנדער־כתה קארטל, Enter דארף צולייגן מיטן איבעררייד אינעם לאג.
4. קאנטראליר דעם weekly cap און, אויב אנגעשטעלט, next-day reveal.
5. פרוביר דעם פיזישן סקענער אויף דיין דרוקער־פאפיר. די בארקאד־גרייס איז געשטעלט פאר לייענבארקייט; ביים פרינטן קלייב 100% / Actual size. ריווארד־קארטלעך ווערן יעצט געדרוקט איין קאלום ברייט.

## Validation / scope

Local database tests cover explicit override confirmation, prior mismatch requirement, repeat redemption denial, request idempotency, audit records, weekly caps, delayed reveal, and school/teacher/anonymous access boundaries, alongside prior Stage 4/5 tests. Browser tests cover focus-free scanner bursts, Enter/Escape override, repeat scans, unknown cards, delayed results, network response loss/retry, double submission and existing dashboard/export/settings flows.

Embedded barcode PNGs were independently decoded from their pixels using a separate Code 128 pattern reference, including checksum and quiet-zone checks. Word/Excel images were loaded with python-docx/openpyxl; PDF output was visually inspected. This does not replace a real scanner/printer test.

The deployed Stage 5 workspace source was verified through GitHub. No live school records were changed and no authenticated end-to-end test was run against the real school account. This release still needs the ZIP upload and SQL activation above.

Tests: `tests/motivation-barcode-db.mjs`, `tests/motivation-barcode-browser.cjs` (same PGlite/Playwright/Chromium environment variables as Stage 5).
