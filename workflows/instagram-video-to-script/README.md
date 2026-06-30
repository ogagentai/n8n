# Instagram Video → Script (تحويل فيديو إنستجرام لسكريبت)

Workflow جاهز لـ n8n بياخد رابط فيديو إنستجرام (Reel أو Post) ويحوّله لسكريبت مكتوب
ومرتّب باستخدام تفريغ صوتي (Whisper) + موديل لغوي.

## الفكرة باختصار

```
Form (رابط إنستجرام)
   → Get Direct Video URL   (HTTP: API بينزّل/يحلّ رابط الفيديو المباشر)
   → Extract Video URL      (Code: يطلع الرابط المباشر من رد الـ API)
   → Download Video         (HTTP: ينزّل الفيديو كـ binary)
   → Transcribe (Whisper)   (OpenAI: يفرّغ الصوت لنص)
   → Generate Script        (OpenAI: يرتّب النص لسكريبت)
```

## التشغيل خطوة بخطوة

1. **استورد الـ workflow**: من n8n افتح *Workflows → Import from File* واختار
   `instagram-video-to-script.json`.

2. **حساب OpenAI**: افتح node `Transcribe (Whisper)` واعمل/اختار
   *OpenAI API credential* (نفس الـ credential هيتستخدم في `Generate Script`).
   - لو الفيديو عربي: افتح *Options* في node التفريغ وضيف `Language = ar` لدقة أعلى.

3. **خدمة تنزيل إنستجرام** (node `Get Direct Video URL`):
   إنستجرام مفيهوش API رسمي مجاني للتنزيل، فعندك اختيارين:

   ### الاختيار (أ) — RapidAPI (شغّال على n8n Cloud والسيرفر)
   - اشترك في أي *Instagram downloader* على RapidAPI (مثلاً
     `instagram-scraper-api2`).
   - في الـ node اعمل *Header Auth credential*:
     - Name: `x-rapidapi-key`
     - Value: مفتاح RapidAPI بتاعك
   - عدّل الـ `url` و الـ `x-rapidapi-host` لو استخدمت API مختلف.
   - الـ `Extract Video URL` بيدوّر أوتوماتيك على الرابط المباشر في رد الـ API
     (حقول زي `video_url`, `download_url`, `play`...). لو الـ API بتاعك بيرجّع
     شكل مختلف، افتح node `Extract Video URL` وزوّد اسم الحقل في `candidateKeys`.

   ### الاختيار (ب) — yt-dlp (مجاني، n8n self-hosted بس)
   لو عندك n8n على سيرفرك وفيه `yt-dlp` متسطّب، تقدر تستبدل أول 3 nodes
   (`Get Direct Video URL` + `Extract Video URL` + `Download Video`) بـ:
   - **Execute Command** node:
     ```
     yt-dlp -o "/tmp/ig_video.mp4" "{{ $json['Instagram URL'] }}"
     ```
   - **Read/Write Files from Disk** node (operation: Read) على المسار `/tmp/ig_video.mp4`
     عشان يطلّع الفيديو كـ binary باسم `data`.
   - بعدها وصّل على node `Transcribe (Whisper)` عادي.

4. **شغّل**: اضغط *Test workflow* أو افتح رابط الفورم، الصق رابط الإنستجرام،
   والسكريبت النهائي هيظهر في node `Generate Script` (حقل `message.content`).

## ملاحظات

- Whisper بيقبل ملفات `mp4` مباشرة ويستخرج الصوت لوحده، فمش محتاج تحويل ffmpeg.
- لو الفيديو طويل جداً (أكبر من 25MB حد Whisper)، محتاج تقص الصوت الأول
  (مثلاً بـ ffmpeg عبر Execute Command) قبل التفريغ.
- تقدر تغيّر الموديل في `Generate Script` (مثلاً `gpt-4o`) أو تعدّل الـ system prompt
  حسب شكل السكريبت اللي عايزه.

## نفس الحاجة لـ TikTok / يوتيوب

نفس البنية بالظبط بتشتغل لأي منصة. غيّر بس طريقة التنزيل في أول node:
الاختيار (ب) بـ `yt-dlp` بيدعم TikTok ويوتيوب وإنستجرام بنفس الأمر من غير أي تعديل تاني.
