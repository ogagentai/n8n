#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# organize_and_index.py
# Tidies up yt-dlp's output and builds Downloads/video_index.csv.
# Uses ONLY the Python standard library (no pandas, no third-party packages).
# It NEVER deletes a video and NEVER overwrites an existing file.
#
# Usage:  python3 organize_and_index.py /path/to/OG_TikTok_Downloader
# -----------------------------------------------------------------------------
import csv
import datetime
import glob
import json
import os
import sys

VIDEO_EXTS = (".mp4", ".mkv", ".webm", ".mov", ".m4v")
THUMB_EXTS = (".jpg", ".jpeg", ".png", ".webp")

CSV_FIELDS = [
    "video_id", "upload_date", "title", "description", "original_url",
    "uploader", "duration_seconds", "view_count", "like_count",
    "comment_count", "repost_count", "local_video_path", "metadata_path",
    "download_status", "downloaded_at",
]


def safe_move(src, dst):
    """Move src -> dst without ever overwriting an existing file."""
    if os.path.abspath(src) == os.path.abspath(dst):
        return
    if os.path.exists(dst):
        return  # keep what's already there; never overwrite
    try:
        os.replace(src, dst)
    except Exception:
        try:
            import shutil
            shutil.move(src, dst)
        except Exception:
            pass


def blank(v):
    """Return '' for missing values rather than inventing data."""
    return "" if v is None else v


def main():
    project = os.path.expanduser(sys.argv[1]) if len(sys.argv) > 1 else os.getcwd()
    downloads = os.path.join(project, "Downloads")
    videos_dir = os.path.join(downloads, "Videos")
    meta_dir = os.path.join(downloads, "Metadata")
    thumbs_dir = os.path.join(downloads, "Thumbnails")
    for d in (videos_dir, meta_dir, thumbs_dir):
        os.makedirs(d, exist_ok=True)

    # Safety net: if any metadata/thumbnail landed next to the videos, file them away.
    if os.path.isdir(videos_dir):
        for name in os.listdir(videos_dir):
            path = os.path.join(videos_dir, name)
            if not os.path.isfile(path):
                continue
            low = name.lower()
            if low.endswith(".info.json") or low.endswith(".description"):
                safe_move(path, os.path.join(meta_dir, name))
            elif os.path.splitext(low)[1] in THUMB_EXTS:
                safe_move(path, os.path.join(thumbs_dir, name))

    # Gather every metadata file (now mostly under Metadata/).
    info_files = sorted(set(
        glob.glob(os.path.join(meta_dir, "*.info.json")) +
        glob.glob(os.path.join(videos_dir, "*.info.json"))
    ))

    records = {}
    for info_path in info_files:
        try:
            with open(info_path, "r", encoding="utf-8") as f:
                data = json.load(f)
        except Exception:
            continue
        vid = str(data.get("id") or "").strip()
        if not vid:
            continue

        stem = os.path.basename(info_path)
        if stem.endswith(".info.json"):
            stem = stem[: -len(".info.json")]

        # Find the matching video file (same stem first, then by id).
        local_video = ""
        for ext in VIDEO_EXTS:
            cand = os.path.join(videos_dir, stem + ext)
            if os.path.exists(cand):
                local_video = cand
                break
        if not local_video and os.path.isdir(videos_dir):
            for name in os.listdir(videos_dir):
                if vid in name and os.path.splitext(name)[1].lower() in VIDEO_EXTS:
                    local_video = os.path.join(videos_dir, name)
                    break

        if local_video and os.path.exists(local_video) and os.path.getsize(local_video) > 0:
            status = "downloaded"
            ts = datetime.datetime.fromtimestamp(os.path.getmtime(local_video))
        else:
            status = "metadata_only"
            ts = datetime.datetime.fromtimestamp(os.path.getmtime(info_path))
        downloaded_at = ts.strftime("%Y-%m-%d %H:%M:%S")

        # Normalise upload date YYYYMMDD -> YYYY-MM-DD.
        ud = str(data.get("upload_date") or "")
        if len(ud) == 8 and ud.isdigit():
            ud = "%s-%s-%s" % (ud[0:4], ud[4:6], ud[6:8])

        url = (data.get("webpage_url") or data.get("original_url")
               or "https://www.tiktok.com/@%s/video/%s" % (data.get("uploader") or "", vid))

        meta_final = info_path
        if os.path.dirname(info_path) != meta_dir:
            meta_final = os.path.join(meta_dir, os.path.basename(info_path))

        records[vid] = {
            "video_id": vid,
            "upload_date": ud,
            "title": (data.get("title") or "").replace("\n", " ").strip(),
            "description": (data.get("description") or "").replace("\n", " ").strip(),
            "original_url": url,
            "uploader": data.get("uploader") or data.get("uploader_id") or data.get("channel") or "",
            "duration_seconds": blank(data.get("duration")),
            "view_count": blank(data.get("view_count")),
            "like_count": blank(data.get("like_count")),
            "comment_count": blank(data.get("comment_count")),
            "repost_count": blank(data.get("repost_count")),
            "local_video_path": local_video,
            "metadata_path": meta_final,
            "download_status": status,
            "downloaded_at": downloaded_at,
        }

    csv_path = os.path.join(downloads, "video_index.csv")
    rows = sorted(records.values(), key=lambda r: (r["upload_date"], r["video_id"]))
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=CSV_FIELDS)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)

    print("INDEX_ROWS=%d" % len(rows))
    print("CSV_PATH=%s" % csv_path)


if __name__ == "__main__":
    main()
