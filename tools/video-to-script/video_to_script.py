#!/usr/bin/env python3
"""
video_to_script — يحوّل أي فيديو (Instagram / TikTok / YouTube ...) لسكريبت مكتوب.

الخطوات:
  1) ينزّل الفيديو بـ yt-dlp
  2) يفرّغ الصوت بـ OpenAI Whisper
  3) (اختياري) يرتّب النص لسكريبت بموديل GPT

الاستخدام:
  export OPENAI_API_KEY=sk-...
  python3 video_to_script.py "https://www.instagram.com/reel/XXXX/"

الخيارات:
  --lang ar            لغة الفيديو (يحسّن الدقة) — افتراضي auto
  --model gpt-4o-mini  موديل ترتيب السكريبت
  --out script.md      مكان حفظ الناتج (افتراضي: بجانب المجلد الحالي)
  --transcript-only    التفريغ الخام بس من غير ترتيب
  --keep-video         ما يمسحش ملف الفيديو بعد الانتهاء
"""

import argparse
import json
import mimetypes
import os
import subprocess
import sys
import tempfile
import urllib.request
import uuid

OPENAI_BASE = "https://api.openai.com/v1"
WHISPER_LIMIT_MB = 25


def log(msg):
    print(f"\033[36m›\033[0m {msg}", file=sys.stderr)


def die(msg):
    print(f"\033[31m✗\033[0m {msg}", file=sys.stderr)
    sys.exit(1)


def ensure_yt_dlp():
    """يتأكد إن yt-dlp موجود، ولو مش موجود يسطّبه."""
    try:
        import yt_dlp  # noqa: F401
        return
    except ImportError:
        pass
    log("yt-dlp مش موجود — بسطّبه دلوقتي...")
    subprocess.run(
        [sys.executable, "-m", "pip", "install", "--quiet", "--user", "yt-dlp"],
        check=True,
    )
    import importlib
    import site
    importlib.reload(site)
    try:
        import yt_dlp  # noqa: F401
    except ImportError:
        die("فشل تسطيب yt-dlp. جرّب: pip install yt-dlp")


def download_video(url, workdir):
    """ينزّل الفيديو كملف واحد (من غير احتياج ffmpeg للدمج)."""
    ensure_yt_dlp()
    import yt_dlp

    out_tmpl = os.path.join(workdir, "video.%(ext)s")
    ydl_opts = {
        # single-file mp4 عشان ما نحتاجش ffmpeg للدمج
        "format": "best[ext=mp4]/best",
        "outtmpl": out_tmpl,
        "quiet": True,
        "no_warnings": True,
        "noprogress": True,
    }
    log(f"بنزّل الفيديو: {url}")
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(url, download=True)
        path = ydl.prepare_filename(info)
    if not os.path.exists(path):
        # fallback لو الامتداد اختلف
        cands = [os.path.join(workdir, f) for f in os.listdir(workdir)]
        cands = [c for c in cands if os.path.isfile(c)]
        if not cands:
            die("مالقيتش الفيديو بعد التنزيل.")
        path = max(cands, key=os.path.getsize)
    size_mb = os.path.getsize(path) / (1024 * 1024)
    log(f"اتنزّل: {os.path.basename(path)} ({size_mb:.1f}MB)")
    if size_mb > WHISPER_LIMIT_MB:
        log(
            f"⚠ الملف أكبر من {WHISPER_LIMIT_MB}MB (حد Whisper). "
            "ممكن التفريغ يفشل — قصّ الفيديو أو استخرج الصوت بـ ffmpeg الأول."
        )
    return path


def _multipart(fields, file_field, file_path):
    """يبني جسم multipart/form-data يدوياً (بدون مكتبات خارجية)."""
    boundary = uuid.uuid4().hex
    body = bytearray()
    for name, value in fields.items():
        body += f"--{boundary}\r\n".encode()
        body += f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode()
        body += f"{value}\r\n".encode()
    filename = os.path.basename(file_path)
    ctype = mimetypes.guess_type(filename)[0] or "application/octet-stream"
    with open(file_path, "rb") as f:
        data = f.read()
    body += f"--{boundary}\r\n".encode()
    body += (
        f'Content-Disposition: form-data; name="{file_field}"; '
        f'filename="{filename}"\r\n'
    ).encode()
    body += f"Content-Type: {ctype}\r\n\r\n".encode()
    body += data
    body += f"\r\n--{boundary}--\r\n".encode()
    return bytes(body), boundary


def transcribe(api_key, video_path, lang=None):
    fields = {"model": "whisper-1"}
    if lang:
        fields["language"] = lang
    body, boundary = _multipart(fields, "file", video_path)
    req = urllib.request.Request(
        f"{OPENAI_BASE}/audio/transcriptions",
        data=body,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": f"multipart/form-data; boundary={boundary}",
        },
    )
    log("بفرّغ الصوت بـ Whisper...")
    try:
        with urllib.request.urlopen(req, timeout=600) as resp:
            return json.loads(resp.read())["text"]
    except urllib.error.HTTPError as e:
        die(f"Whisper API رجّع خطأ {e.code}: {e.read().decode(errors='replace')}")


def make_script(api_key, transcript, model):
    system = (
        "أنت كاتب سكريبتات محترف. حوّل النص المفرّغ من فيديو إلى سكريبت مرتّب "
        "بنفس لغة النص. رتّبه كالتالي: عنوان/Hook مقترح، ثم النقاط الأساسية "
        "بشكل واضح، ثم خاتمة أو Call to action لو موجودة. صحّح أخطاء التفريغ "
        "البسيطة من غير تغيير المعنى."
    )
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": f"النص المفرّغ:\n\n{transcript}"},
        ],
    }
    req = urllib.request.Request(
        f"{OPENAI_BASE}/chat/completions",
        data=json.dumps(payload).encode(),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
    )
    log(f"برتّب السكريبت بـ {model}...")
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            return json.loads(resp.read())["choices"][0]["message"]["content"]
    except urllib.error.HTTPError as e:
        die(f"Chat API رجّع خطأ {e.code}: {e.read().decode(errors='replace')}")


def main():
    p = argparse.ArgumentParser(
        description="حوّل فيديو (Instagram/TikTok/YouTube) لسكريبت مكتوب"
    )
    p.add_argument("url", help="رابط الفيديو")
    p.add_argument("--lang", default=None, help="لغة الفيديو مثل ar / en")
    p.add_argument("--model", default="gpt-4o-mini", help="موديل ترتيب السكريبت")
    p.add_argument("--out", default=None, help="مكان حفظ الناتج (.md)")
    p.add_argument(
        "--transcript-only", action="store_true", help="التفريغ الخام فقط"
    )
    p.add_argument("--keep-video", action="store_true", help="ما تمسحش الفيديو")
    args = p.parse_args()

    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        die("لازم تظبط مفتاح OpenAI: export OPENAI_API_KEY=sk-...")

    workdir = tempfile.mkdtemp(prefix="v2s_")
    video_path = download_video(args.url, workdir)

    transcript = transcribe(api_key, video_path, args.lang)

    if args.transcript_only:
        result = transcript
    else:
        result = make_script(api_key, transcript, args.model)

    out_path = args.out or os.path.join(os.getcwd(), "script.md")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(result)

    if not args.keep_video:
        try:
            os.remove(video_path)
        except OSError:
            pass

    print("\n" + "=" * 60)
    print(result)
    print("=" * 60)
    log(f"اتحفظ في: {out_path}")


if __name__ == "__main__":
    main()
