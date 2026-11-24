# StreamFlix IPTV (SwiftUI Native)

تطبيق IPTV أصلي (Native SwiftUI) لأجهزة **iPhone و iPad و Mac و Apple TV**، مصمم بتجربة **Netflix** لحل كل مشاكل [Smarters Pro](https://apps.apple.com/us/app/smarters-pro/id6450746159):

## المميزات والحلول الهندسية
1. **تسجيل الدخول بـ Xtream Codes API (`Host` + `Username` + `Password`):** مع دعم تعدد البروفايلات ("Who's Watching?").
2. **تقليل الـ Buffering والتقطيع:**
   - ضبط `preferredForwardBufferDuration` بذكاء (15 ثانية للأفلام والمسلسلات، 3 ثوانٍ للبث المباشر لسرعة التنقل).
   - تفضيل روابط `.m3u8` (HLS) للبث المباشر لأنها أسرع وأكثر استقراراً على أجهزة Apple، مع إعادة اتصال تلقائي عند انقطاع البث.
3. **تقديم وتأخير فوري (Instant Seeking):**
   - استخدام **Debounced Scrubbing** (معاينة فورية للوقت + إرسال طلب Byte-Range واحد بعد استقرار الإصبع بـ 180ms) لمنع خنق سيرفر الـ IPTV.
   - أزرار ودبل تاب على اليمين واليسار للتقديم/التأخير `10s` فوراً.
4. **استكمال المشاهدة بدقة الثانية حتى بعد التوقف الطويل (Continue Watching & Pause Recovery):**
   - حفظ موضع المشاهدة تلقائياً كل 5 ثوانٍ، وعند الضغط على Pause، وعند الخروج للخلفية.
   - لو عملت Pause لمدة طويلة (مثلاً أكثر من دقيقتين) وسيرفر الـ IPTV قفل الاتصال، التطبيق بيعمل **إعادة اتصال صامتة** ويرجعك لنفس الثانية بالظبط (مع إرجاع ثانيتين للسياق).
5. **الحماية من النوم ("Are You Still Watching?"):**
   - إيقاف التشغيل التلقائي بعد حلقتين متتاليتين بدون تفاعل (قابل للتعديل من الإعدادات)، وعرض شاشة نتفليكس **"Are you still watching?"** مع عد تنازلي 60 ثانية يتوقف بعده تلقائياً لحفظ مكانك.
   - مؤقت نوم يدوي (15 / 30 / 45 / 60 دقيقة) داخل المشغل.

## طريقة التشغيل في Xcode
1. افتح **Xcode** واختر **File > New > Project > Multiplatform > App** باسم `StreamFlixIPTV`.
2. اسحب مجلد `StreamFlixCore` إلى المشروع في Xcode (أو أضفه من **File > Add Package Dependencies > Add Local...**).
3. استبدل ملفات التطبيق الافتراضية بملفات مجلد `StreamFlixApp/`.
4. في **Signing & Capabilities** أضف **Outgoing Connections (Client)** على macOS (و **App Transport Security > Allow Arbitrary Loads = YES** في `Info.plist` لأن معظم سيرفرات IPTV تعمل بـ `http://`).
5. شغّل التطبيق على الآيفون أو الآيباد أو الماك أو Apple TV.
