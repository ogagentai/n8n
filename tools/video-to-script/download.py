#!/usr/bin/env python3
"""
download — أداة تنزيل فيديوهات من الترمينال (Instagram / TikTok / YouTube ...).

الاستخدام:
  python3 download.py "https://www.instagram.com/reel/XXXX/"
  python3 download.py "<url>" -o downloads/          # مجلد الحفظ
  python3 download.py "<url>" --audio                # الصوت بس (mp3)
  python3 download.py "<url1>" "<url2>" "<url3>"     # أكتر من رابط

لو yt-dlp مش متسطّب، الأداة بتسطّبه لوحدها أول مرة.
"""

import argparse
import os
import subprocess
import sys


def log(msg):
    print(f"\033[36m›\033[0m {msg}", file=sys.stderr)


def die(msg):
    print(f"\033[31m✗\033[0m {msg}", file=sys.stderr)
    sys.exit(1)


def ensure_yt_dlp():
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
        die("فشل تسطيب yt-dlp. جرّب يدوي: pip install yt-dlp")


def download(url, outdir, audio_only, cookies_from):
    import yt_dlp

    os.makedirs(outdir, exist_ok=True)
    outtmpl = os.path.join(outdir, "%(uploader,id)s-%(id)s.%(ext)s")

    ydl_opts = {
        "outtmpl": outtmpl,
        "noprogress": False,
        "quiet": False,
        "no_warnings": True,
    }
    if audio_only:
        # استخراج صوت mp3 (بيحتاج ffmpeg)
        ydl_opts["format"] = "bestaudio/best"
        ydl_opts["postprocessors"] = [
            {
                "key": "FFmpegExtractAudio",
                "preferredcodec": "mp3",
                "preferredquality": "192",
            }
        ]
    else:
        # فيديو mp4 كملف واحد — من غير احتياج ffmpeg للدمج
        ydl_opts["format"] = "best[ext=mp4]/best"

    if cookies_from:
        ydl_opts["cookiesfrombrowser"] = (cookies_from,)

    log(f"بنزّل: {url}")
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(url, download=True)
        path = ydl.prepare_filename(info)
        if audio_only:
            path = os.path.splitext(path)[0] + ".mp3"

    if os.path.exists(path):
        size_mb = os.path.getsize(path) / (1024 * 1024)
        log(f"✓ اتحفظ: {path} ({size_mb:.1f}MB)")
        print(path)  # ناتج ينفع يتمرّر لأداة تانية
        return path
    log("✓ خلص (المسار اختلف؛ بص في مجلد الحفظ).")
    return None


def main():
    p = argparse.ArgumentParser(
        description="تنزيل فيديوهات من الترمينال (Instagram/TikTok/YouTube)"
    )
    p.add_argument("urls", nargs="+", help="رابط واحد أو أكتر")
    p.add_argument(
        "-o", "--outdir", default="downloads", help="مجلد الحفظ (افتراضي downloads/)"
    )
    p.add_argument(
        "--audio", action="store_true", help="نزّل الصوت بس كـ mp3 (يحتاج ffmpeg)"
    )
    p.add_argument(
        "--cookies-from",
        default=None,
        metavar="BROWSER",
        help="كوكيز من المتصفح للفيديوهات الخاصة (chrome/firefox/edge...)",
    )
    args = p.parse_args()

    ensure_yt_dlp()

    failures = 0
    for url in args.urls:
        try:
            download(url, args.outdir, args.audio, args.cookies_from)
        except Exception as e:  # noqa: BLE001
            failures += 1
            print(f"\033[31m✗\033[0m فشل تنزيل {url}: {e}", file=sys.stderr)

    if failures:
        sys.exit(1)


if __name__ == "__main__":
    main()
