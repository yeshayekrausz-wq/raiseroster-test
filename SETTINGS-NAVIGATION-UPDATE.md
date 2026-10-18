# Program Settings — מסודר אין שטאפלען

## ארויפלייגן

1. עקסטרעקט `Motivation_Settings_Update.zip`. אפלאוד דעם אינהאלט אין GitHub מיט די זעלבע פאלדערס. דער ZIP אנטהאלט אלע יעצטיגע Motivation Admin־פיילס, כדי קיין נייע JavaScript־פייל זאל נישט פעלן.
2. אין Supabase SQL Editor לויפט דעם אינהאלט פון `migrations/20261018_motivation_settings_navigation.sql`. דער SQL איז אויך אין `Settings_Activate.txt`, צו קענען עפענען מיט Notepad. ביידע האבן גענוי דעם זעלבן SQL; מען לויפט נאר איינעם.
3. דער רעזולטאט דארף זיין `MOTIVATION_SETTINGS_READY`. דער אינסטאלירער פארלאנגט דעם שוין אינסטאלירטן Stage 5; מען קען אים לויפן נאכאמאל. ער אנטהאלט אויך דעם דערהיינטיקטן בארקאד־כתה־איבעררייד.
4. נאכן GitHub Pages־אפדעיט פארמאכט די פראגראם־טעבס און עפנט נאכאמאל. גיי אין Program Settings.

## דער נייער אויפשטעל

דער הויפט־בליק האט נאר די זעקס קנעפלעך, אין דעם סדר:

1. General — פראגראם־נאמען, זמן, דאטומען און ציל.
2. Conditions → Exams — די עקזיסטירנדע מקצועות, ציונים און פוינטס־רעגלען.
3. Cards — אנצינדן קארטלעך, next-day reveal און רבי־נעמען.
4. Limits — דער וועכנטליכער קארטל־לימיט.
5. Schedule → Week / Timezone — וואך־אנהייב און סקול־זייגער.
6. Scanning — סקענען אן פעלד־פאָקוס און אפציאנעלער באשטעטיגונג/טעות־סאונד.

יעדער נאַוויגאַציע־קנעפל האט איין ווארט מיט א קליינעם אייקאן. די קורצע ערקלערונג שטייט באזונדער אונטערן קנעפל. די פארבונדענע פייל־קעסטלעך אויבן זענען קליקבאר און ווייזן דעם איצטיגן פלאץ. Browser Back/Forward ארבעט צווישן די שטאפלען.

Phone Settings און Display Settings בלייבן אייגענע מעין־מעניוס און עפענען יעצט אויך מיט אונטער־קנעפלעך. Documents האלט די Card/Layout־אויסוואל און ווייזט דעם שטאפל אינעם breadcrumb. Teacher Portals בלייבט אין זיין אייגענעם פלאץ. דער גרויסער ברענד־קעפל אין Motivation Admin איז פארביטן מיטן קליינעם breadcrumb; דער Powered by YK Connect־פוס בלייבט.

## נייע פונקציעס

- דער סקול קען אויסקלייבן וועלכן טאג און שעה די וואך הייבט זיך אן. דאס ווערט געראטעוועט אינעם דאטאבעיס און קאנטראלירט דעם weekly cap ביי געווענליכע איינלייזונגען און כתה־איבערריידס.
- ביז מען היט אן אייגענע ברירה, בלייבט דער עקזיסטירנדער Monday 00:00־חשבון. די נייע פעלדער ווערן נישט אנגעפילט מיט ביישפילן.
- א טויש פונעם וואך־אנהייב קען גלייך טוישן וועלכע פריערדיגע איינלייזונגען ציילן אינעם איצטיגן לימיט. עס מעקט נישט אויס היסטאריע אדער פוינטס.
- Scanning־ברירות ווערן געהיטן פאר דעם בראוזער און סקול. מען קען אויסלעשן דעם אוטאמאטישן סקענער־איינגאנג אינעם גאנצן פראפייל און ווייטער נוצן דעם קאוד־פעלד.

## פארנעם פון דעם אפדעיט

דאס איז דער נייער מעניו־אויפשטעל מיט די עקזיסטירנדע ארבעטנדע סעטינגס, צוזאמען מיטן נייעם וואך־אנהייב און סקענער־ברירות. עס איז נישט א טענה אז יעדע פונקציע פון דער גאנצער פלאניר־ליסטע איז שוין געבויט. צווישן די קומענדיגע זאכן זענען יא/ניין־תנאים און קאמבינירטע תנאים, רענדאם קארטל־פארטיילונג, אויסלויף־דאטומען, טעגליכע לימיטס, אויסנאמען צום cap און מער דעטאלירטע רשות. די hotline־פארבינדונג און native display player זענען נאך נישט אקטיוו.

## Verification

Local PGlite tests cover custom boundaries (including before/at the chosen hour), daylight-saving changes, revisions/stale writes, invalid input, normal and override cap enforcement, and administrator/school isolation. Existing database regression cases also run.

Browser tests cover the six one-word categories in order, no editable fields at the settings root, nested breadcrumbs and Back, separated program/exam fields, week/timezone/limit/scanner saving, display/phone navigation, barcode redemption/override flows, exports and mobile overflow. Desktop, mobile and a nested Week page were visually inspected.

No live school data was changed and no GitHub deployment was performed by this release. Run the new SQL after uploading; avoid rerunning older incremental migrations afterward because they define the older week calculation.
