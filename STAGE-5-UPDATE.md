# YK Connect — Motivation Stage 5

## אינסטאלירן

1. עקסטרעקט דעם ZIP. לייג דעם אינהאלט ארויף אין דעם עקזיסטירנדן GitHub repository, אינעם הויפט־פאלדער, מיט די זעלבע פאלדער־נעמען. למשל `motivation/admin/index.html` דארף בלייבן אין `motivation/admin/`. די פיילס מיט די זעלבע נעמען ווערן דערהיינטיקט. מעק נישט אויס אנדערע פיילס.
2. אין Supabase → SQL Editor עפנט א נייע Query. עפנט `migrations/Activate_Motivation_Stage5.sql` מיט א טעקסט־עדיטאר, קאפירט דעם גאנצן SQL־אינהאלט און דריקט Run. מען דארף נאר דעם איינעם אינסטאליר־פייל. דער רעזולטאט דארף זיין `MOTIVATION_STAGE5_READY`.
3. קיין HTML־פייל און קיין ZIP גייט נישט אריין אין SQL Editor. אויב עס הייבט זיך אן מיט `<!doctype html>`, איז עס דער אומריכטיגער פייל.
4. נאכדעם וואס GitHub Pages ענדיקט, פארמאך די אפענע פראגראם־טעבס און עפן דעם סייט נאכאמאל. קליק Motivation און דעם Dashboard.

דער ZIP איז צוגעגרייט און לאקאל געטעסטעט; ער איז נישט אויטאמאטיש ארויפגעשטעלט געווארן אויף GitHub אדער אינסטאלירט געווארן אין אייער Supabase.

## וואס איז דא

- א כתה עפנט איר אייגענע ליסטע; די אלגעמיינע תלמידים־ליסטע און כתה־קעסטלעך ווערן באהאלטן. „All classes“ גייט צוריק.
- עדיטן פער כתה: נאמען, געבורטס־דאטום, עברי־געבורטסטאג, אדרעס, נאטיצן, קלאס און די פינף געמיינזאמע פאון־פעלדער (main/home/father/mother/additional). „Add phone number“ עפנט נאך אן אומבאנוצטן פעלד.
- אפלאודן א תלמיד־בילד און קארטל/דאקומענט (PNG/JPG/WebP/PDF). בילדער און דאקומענטן ליגן אינעם פריוואטן סקול־באקעט; מען עפנט זיי פונעם תלמיד־פראפייל.
- אראפנעמען פון א כתה באזייטיקט נאר די איצטיגע כתה־צוטיילונג אין אלע פראגראמען. דער תלמיד און זיין היסטאריע בלייבן געהיטן אונטער Unassigned.
- קורצע, פעסטע תלמיד־נומערן פארן יוזער. די אינערליכע UUID ווערט נישט אויסגעדרוקט אויפן ID־קארטל.
- Documents → Card layout: שרייב די אייגענע שורות, אויסריכטונג און גרויסקייט. `{name}`, `{id}`, `{class}`, `{teacher}`, `{code}`, `{program}`, `{term}` ווערן אויטאמאטיש אויסגעפילט. קיין קארטל־טעקסט איז נישט פאראויס באשטימט. היט קודם דעם layout.
- Word `.docx` און Excel `.xlsx` זענען עכטע Office־פיילס. PDF ניצט Print / Save PDF אינעם בראוזער. די עקספארטן זענען טעקסט־קארטלעך; בילדער ווערן נישט אריינגעלייגט אין די Office־קארטלעך. Excel גיט א שורה פאר יעדן קארטל, מיט א קאלום פאר יעדע קארטל־שורה.
- Display און Phone האבן אויבערשטע אונטער־מעניוס און צוריק־לינקס. Phone → Freeze by class ערלויבט אויסצוקלייבן תלמידים פער כתה.
- נייער setup האט ליידיגע weekly cap, שעה'ן און slide durations. פריער געראטעוועטע סעטינגס ווערן נישט אויסגעמעקט. אויב אן אלטער cap איז שוין געהיטן געווארן, קען מען אים יעצט טוישן אדער אויסליידיגן ווען קארטלעך זענען אויסגעלאשן.
- דער timezone ווערט דערקענט פונעם קאמפיוטער/בראוזער ביים נייעם setup. דאס איז נישט א proxy/IP־לאקאציע. מען קען אים פאררעכטן אויב דער קאמפיוטער איז אנדערש ווי דער סקול.
- Teacher Portals: אדמין שטעלט צו א נאמען, email און כתה. דער מלמד נוצט דעם פארטעל־לינק און א באזונדערן באשטעטיגטן email־אקאונט. ער קען נאר לייענען זיין כתה און אירע פוינטס. מען קען דיסעיבלען דעם פארטעל. א סקול־אדמין־אקאונט ווערט נישט באנוצט אלס מלמד־אקאונט.
- Support שיקט פראגעס צום עקזיסטירנדן Super Admin inbox און ווייזט תשובות. Training איז ליידיג.
- קלענערע Dashboard־קעפל, באהאלטבארער לינקער מעניו, YK Connect אויבן און Powered by YK Connect אונטן. די פראגראם־אויסוואל שטייט נאר אינעם Dashboard.

## וואס דארף נאך א קומענדיגן שריט

דער אינסטאלירטער display-player, device-ID pairing און דאס לאקן דעם גאנצן קאמפיוטער זענען נאך נישט געבויט. „Computers“ זאגט דאס קלאר. די בראוזער־דיספלעי קען ווייזן דעם schedule/playlist, אבער קען נישט לאקן Windows אדער אויטאמאטיש אנצינדן דעם קאמפיוטער.

די hotline־פארבינדונג איז אויך נאך נישט דא: די פאון־רשות און freeze־ברירות ווערן געהיטן, אבער קאנטראלירן נאך נישט אמת'ע רופן. Training־ווידיא־אפלאוד קומט אין א קומענדיגן שריט; דער פלאץ בלייבט יעצט ליידיג ווי געבעטן.

Teacher signup נוצט אייער Supabase Auth. Email signup און email confirmation דארפן זיין ריכטיג קאנפיגורירט. Support נוצט די עקזיסטירנדע `support_threads` און `support_messages` טאבעלעס פון דעם פלאטפארם.

## Technical release notes

The cumulative `Activate_Motivation_Stage5.sql` installs missing Motivation stages in one transaction and safely skips complete existing stages. Partial installations fail with an explicit error. Shared school tables and Supabase Storage/Auth are prerequisites. The incremental usability migration is included for review; users should run the cumulative installer only.

Shared student writes use full-record optimistic concurrency checks, school authorization, transaction rollback and request idempotency. Short IDs are allocated under a school lock. Teacher access is a narrowly scoped security-definer RPC bound to a verified email, enabled portal and class; no organization membership is granted. Admin membership is rejected for teacher logins. Student attachments remain behind existing private school storage policies. Existing saved settings are preserved, because they may be intentional.

`admin/index.html` has one compatibility change: shared Campaign Admin resolves new private student-photo paths to temporary signed URLs for display. It does not persist those temporary URLs when unrelated student fields are saved.

Validation performed locally: Stage 4 regressions plus Stage 5 database tests; fresh and repeat cumulative installation; browser tests for class-only navigation, profile fields/uploads, short IDs/card layout, Word/Excel/PDF exports, settings navigation, phone freezes, support UI, teacher view and mobile layout. Word/Excel archives and XML were validated and opened with python-docx/openpyxl. PDF and desktop/mobile screenshots were inspected. Tests use controlled fixtures/mock browser services, not the live school database.

Test commands require PGLITE_MODULE; browser tests also require PLAYWRIGHT_MODULE and CHROMIUM_PATH:
- `node tests/motivation-usability-db.mjs`
- `node tests/motivation-usability-installer.mjs`
- `node tests/motivation-usability-browser.cjs`
