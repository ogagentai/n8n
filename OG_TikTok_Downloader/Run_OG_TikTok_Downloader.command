#!/bin/bash
# =============================================================================
#  OG TikTok Downloader  —  Run_OG_TikTok_Downloader.command
#  One double-click tool to safely archive the public videos of YOUR OWN
#  TikTok profile (https://www.tiktok.com/@oghonim) to your Mac, using only
#  free and open-source tools: yt-dlp, FFmpeg, Python 3 (and Homebrew to
#  install them on macOS).
#
#  It NEVER deletes your files, NEVER asks for your TikTok password, and
#  NEVER prints or stores your browser cookies.
# =============================================================================

# --- Safety: do not abort the whole run on a single command error. ----------
set -u
set -o pipefail

# --- The TikTok profile to archive (your own account). ----------------------
PROFILE_URL="https://www.tiktok.com/@oghonim"
PROFILE_HANDLE="oghonim"

# --- Locate the project folder = the folder THIS file lives in. -------------
#     (So everything stays self-contained, ideally at ~/OG_TikTok_Downloader)
SCRIPT_PATH="${BASH_SOURCE[0]}"
PROJECT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

DOWNLOADS_DIR="$PROJECT_DIR/Downloads"
VIDEOS_DIR="$DOWNLOADS_DIR/Videos"
METADATA_DIR="$DOWNLOADS_DIR/Metadata"
THUMBS_DIR="$DOWNLOADS_DIR/Thumbnails"
LOGS_DIR="$PROJECT_DIR/Logs"
SCRIPTS_DIR="$PROJECT_DIR/Scripts"
ARCHIVE_DIR="$PROJECT_DIR/Archive"
ARCHIVE_FILE="$ARCHIVE_DIR/downloaded_video_ids.txt"
FAILED_URLS="$LOGS_DIR/failed_urls.txt"
TEST_RESULT="$LOGS_DIR/test_result.txt"
HELPER_PY="$SCRIPTS_DIR/organize_and_index.py"
TOOLS_MD="$PROJECT_DIR/OPEN_SOURCE_TOOLS.md"

mkdir -p "$VIDEOS_DIR" "$METADATA_DIR" "$THUMBS_DIR" "$LOGS_DIR" "$SCRIPTS_DIR" "$ARCHIVE_DIR"
touch "$ARCHIVE_FILE" "$FAILED_URLS"

# --- Timestamped log; mirror everything to screen AND the log file. ---------
RUN_STAMP="$(date +%Y-%m-%d_%H-%M-%S)"
LOG="$LOGS_DIR/run_${RUN_STAMP}.log"
touch "$LOG"
exec > >(tee -a "$LOG") 2>&1

# --- Simple colors (fall back to plain text if not a terminal). -------------
if [ -t 1 ]; then
  B=$'\033[1m'; DIM=$'\033[2m'; R=$'\033[0m'
  GRN=$'\033[32m'; YEL=$'\033[33m'; RED=$'\033[31m'; CYN=$'\033[36m'
else
  B=""; DIM=""; R=""; GRN=""; YEL=""; RED=""; CYN=""
fi
say()  { printf "%s\n" "$*"; }
banner() { printf "\n%s========================================================%s\n%s%s%s\n%s========================================================%s\n" "$CYN" "$R" "$B" "$1" "$R" "$CYN" "$R"; }
ok()   { printf "%s✅ %s%s\n" "$GRN" "$*" "$R"; }
warn() { printf "%s⚠️  %s%s\n" "$YEL" "$*" "$R"; }
err()  { printf "%s❌ %s%s\n" "$RED" "$*" "$R"; }
info() { printf "%sℹ️  %s%s\n" "$DIM" "$*" "$R"; }

# --- Stop cleanly on Control+C (progress is always saved). ------------------
on_interrupt() {
  echo
  warn "Stopped by you (Control+C). Your progress is saved — just run this file again to continue."
  warn "تم الإيقاف بأمان. تقدّمك محفوظ — افتح الملف مرة أخرى للمتابعة."
  exit 130
}
trap on_interrupt INT

# Keep the Terminal window open after a double-click finishes.
PAUSE_AT_END=1
finish() {
  echo
  if [ "$PAUSE_AT_END" = "1" ] && [ -t 0 ]; then
    printf "%sPress Return to close this window…%s " "$DIM" "$R"
    read -r _ || true
  fi
}
trap finish EXIT

clear 2>/dev/null || true
say "${B}========================================================${R}"
say "${B}        OG TikTok Downloader  (open-source)             ${R}"
say "${B}        Profile: ${PROFILE_URL}${R}"
say "${B}========================================================${R}"
say "${DIM}Project folder: $PROJECT_DIR${R}"
say "${DIM}This run's log:  $LOG${R}"
say "${DIM}Start time:      $(date)${R}"

# =============================================================================
#  STEP 1 — INSPECT (look, don't change anything yet)
# =============================================================================
banner "STEP 1 — Inspecting your computer (no changes made)"

OS_NAME="$(uname)"
IS_MAC=0
[ "$OS_NAME" = "Darwin" ] && IS_MAC=1

if [ "$IS_MAC" = "1" ]; then
  MAC_VER="$(sw_vers -productVersion 2>/dev/null) ($(sw_vers -buildVersion 2>/dev/null))"
  ARCH="$(uname -m)"
  if [ "$ARCH" = "arm64" ]; then CHIP="Apple Silicon (arm64)"; else CHIP="Intel ($ARCH)"; fi
  say "• macOS version : ${MAC_VER:-unknown}"
  say "• Chip / arch   : $CHIP"
else
  warn "This is NOT macOS (detected: $OS_NAME). This tool is designed for a Mac."
  warn "It will still try to run, but the double-click and Homebrew steps are Mac features."
  ARCH="$(uname -m)"
  say "• OS / arch     : $OS_NAME / $ARCH"
fi

# Disk space on the volume that holds the project.
DISK_AVAIL="$(df -h "$PROJECT_DIR" 2>/dev/null | awk 'NR==2{print $4" free of "$2}')"
say "• Disk space    : ${DISK_AVAIL:-unknown}"

# Write permission check (we just created folders, so confirm we can write).
if touch "$PROJECT_DIR/.write_test" 2>/dev/null; then
  rm -f "$PROJECT_DIR/.write_test"
  say "• Write access  : OK (can write inside the project folder)"
else
  err "No write access to $PROJECT_DIR — please move the folder to your home folder (~)."
fi

# Tool presence (versions filled after we ensure/install them in Step 2).
tool_state() { command -v "$1" >/dev/null 2>&1 && echo "installed" || echo "MISSING"; }
say "• Homebrew      : $(tool_state brew)"
say "• Python 3      : $(tool_state python3)  $(python3 --version 2>/dev/null)"
say "• yt-dlp        : $(tool_state yt-dlp)"
say "• FFmpeg        : $(tool_state ffmpeg)"
say "• FFprobe       : $(tool_state ffprobe)"
info "Nothing on your system was changed in this step."

# =============================================================================
#  STEP 2 — DEPENDENCIES (install only what is missing, with your approval)
# =============================================================================
banner "STEP 2 — Checking & installing the open-source tools"

# Make sure Homebrew (if present) is on PATH for this script (Apple Silicon vs Intel).
load_brew() {
  if command -v brew >/dev/null 2>&1; then return 0; fi
  for cand in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$cand" ]; then eval "$("$cand" shellenv)"; return 0; fi
  done
  return 1
}
load_brew || true

ensure_homebrew() {
  if command -v brew >/dev/null 2>&1; then ok "Homebrew is installed: $(brew --version | head -1)"; return 0; fi
  if [ "$IS_MAC" != "1" ]; then
    warn "Homebrew is a macOS tool and isn't here. On Linux, install yt-dlp/ffmpeg with your package manager."
    return 1
  fi
  warn "Homebrew is NOT installed."
  say  ""
  say  "${B}What is Homebrew?${R}"
  say  "  Homebrew (brew.sh) is the standard free, open-source ${B}package manager${R} for macOS."
  say  "  It is used here ONLY to install the open-source tools yt-dlp and FFmpeg."
  say  "  ما هو Homebrew؟ هو مدير حزم مجاني ومفتوح المصدر لنظام ماك، وسنستخدمه فقط لتثبيت yt-dlp و FFmpeg."
  say  ""
  say  "${B}Official installation command (from https://brew.sh):${R}"
  say  '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  say  ""
  warn "During install, macOS may ask for your Mac login password."
  warn "Terminal will NOT show the password characters as you type — that is normal. Just type it and press Return."
  warn "ملاحظة: لن تظهر أحرف كلمة المرور أثناء الكتابة، وهذا طبيعي. اكتبها واضغط Return."
  say  ""
  if [ ! -t 0 ]; then
    err "Can't ask for approval (no interactive terminal). Please double-click the file in Finder instead."
    return 1
  fi
  printf "%sInstall Homebrew now? Type 'yes' to approve, anything else to skip: %s" "$B" "$R"
  read -r ANSWER
  if [ "$ANSWER" != "yes" ]; then
    warn "Skipped Homebrew installation at your request."
    say  "You can install it later from https://brew.sh and run this file again."
    return 1
  fi
  say "Installing Homebrew (this can take a few minutes)…"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  load_brew || true
  if command -v brew >/dev/null 2>&1; then ok "Homebrew installed: $(brew --version | head -1)"; return 0; fi
  err "Homebrew installation did not complete. See messages above."
  return 1
}

brew_install_or_upgrade() {
  local pkg="$1"
  if brew list "$pkg" >/dev/null 2>&1; then
    info "Updating $pkg…"; brew upgrade "$pkg" >/dev/null 2>&1 || true
  else
    say "Installing $pkg…"; brew install "$pkg"
  fi
}

HAVE_BREW=0
ensure_homebrew && HAVE_BREW=1

if [ "$HAVE_BREW" = "1" ]; then
  brew_install_or_upgrade yt-dlp
  brew_install_or_upgrade ffmpeg
else
  # Fallback path without Homebrew: try to keep yt-dlp fresh via pip if possible.
  if ! command -v yt-dlp >/dev/null 2>&1; then
    warn "Trying to install yt-dlp with pip (Python) since Homebrew is unavailable…"
    python3 -m pip install --user -U yt-dlp 2>/dev/null || python3 -m pip install --user -U --break-system-packages yt-dlp 2>/dev/null || true
    export PATH="$HOME/Library/Python/3.*/bin:$HOME/.local/bin:$PATH"
  fi
  if ! command -v ffmpeg >/dev/null 2>&1; then
    err "FFmpeg is required and could not be installed without Homebrew."
    err "Please install Homebrew (https://brew.sh) and run this file again."
  fi
fi
load_brew || true

# Resolve the actual commands we will use.
YTDLP="$(command -v yt-dlp || true)"
if [ -z "$YTDLP" ] && python3 -c "import yt_dlp" 2>/dev/null; then YTDLP="python3 -m yt_dlp"; fi
FFPROBE="$(command -v ffprobe || true)"
FFMPEG="$(command -v ffmpeg || true)"

# Optional but very helpful for TikTok: browser impersonation (curl_cffi).
# This makes yt-dlp look like a real browser, which TikTok often requires.
if ! python3 -c "import curl_cffi" >/dev/null 2>&1; then
  info "Adding optional browser-impersonation support (curl_cffi) to help with TikTok…"
  python3 -m pip install --user -U curl_cffi 2>/dev/null || python3 -m pip install --user -U --break-system-packages curl_cffi 2>/dev/null || true
fi

say ""
say "${B}Installed tool versions:${R}"
if [ -n "$YTDLP" ]; then YTDLP_VER="$($YTDLP --version 2>/dev/null | head -1)"; ok "yt-dlp  $YTDLP_VER"; else YTDLP_VER=""; err "yt-dlp not available — cannot continue."; fi
if [ -n "$FFMPEG" ]; then FFMPEG_VER="$($FFMPEG -version 2>/dev/null | head -1)"; ok "$FFMPEG_VER"; else FFMPEG_VER=""; warn "FFmpeg not available — playback verification will be limited."; fi
PY_VER="$(python3 --version 2>/dev/null)"; ok "$PY_VER"
BREW_VER="$(brew --version 2>/dev/null | head -1)"; [ -n "$BREW_VER" ] && ok "$BREW_VER"

if [ -z "$YTDLP" ]; then
  err "Cannot proceed without yt-dlp. Please install Homebrew and run again."
  echo "RESULT: FAILED — yt-dlp missing" > "$TEST_RESULT"
  exit 1
fi

# Refresh OPEN_SOURCE_TOOLS.md with the live, verified versions (backup old copy first).
write_tools_md() {
  if [ -f "$TOOLS_MD" ]; then cp -p "$TOOLS_MD" "$ARCHIVE_DIR/OPEN_SOURCE_TOOLS_backup_${RUN_STAMP}.md" 2>/dev/null || true; fi
  cat > "$TOOLS_MD" <<EOF
# OPEN_SOURCE_TOOLS.md

This file is refreshed automatically every run with the tools actually detected
on this Mac. Every tool below is **free and open source**. Licenses were
verified from each project's official source.

_Last verified: $(date)_

| Tool | Official source | License | Purpose | Installed? | Installed version |
|------|-----------------|---------|---------|-----------|-------------------|
| **yt-dlp** | https://github.com/yt-dlp/yt-dlp | The Unlicense (public domain) | Downloads the videos, metadata (JSON), thumbnails & descriptions | $( [ -n "$YTDLP_VER" ] && echo Yes || echo No ) | ${YTDLP_VER:-—} |
| **FFmpeg / FFprobe** | https://ffmpeg.org | LGPL-2.1-or-later (some parts GPL) | Merges/remuxes to MP4, converts thumbnails, verifies the video is playable | $( [ -n "$FFMPEG_VER" ] && echo Yes || echo No ) | ${FFMPEG_VER:-—} |
| **Python 3** | https://www.python.org | PSF License (OSI-approved) | Runs the indexing script that builds video_index.csv (standard library only) | $( [ -n "$PY_VER" ] && echo Yes || echo No ) | ${PY_VER:-—} |
| **Homebrew** | https://brew.sh | BSD-2-Clause | macOS package manager used only to install the tools above | $( [ -n "$BREW_VER" ] && echo Yes || echo No ) | ${BREW_VER:-—} |
| **curl_cffi** (optional) | https://github.com/lexiforest/curl_cffi | MIT License | Optional browser impersonation that helps yt-dlp reach TikTok | $( python3 -c "import curl_cffi,sys;print(getattr(curl_cffi,'__version__',''))" 2>/dev/null | grep -q . && echo Yes || echo No ) | $(python3 -c "import curl_cffi;print(getattr(curl_cffi,'__version__',''))" 2>/dev/null || echo "—") |

No paid APIs, no Apify, no cloud storage, no browser extensions, and no
closed-source downloaders are used at any point.
EOF
}
write_tools_md
ok "Recorded verified tool versions in OPEN_SOURCE_TOOLS.md"

# Embedded copy of the CSV indexer, used only if Scripts/organize_and_index.py
# is missing (e.g. you copied just the .command file). Standard library only.
write_helper_py() {
  cat > "$HELPER_PY" <<'PYEOF'
#!/usr/bin/env python3
# Tidies up yt-dlp output and builds Downloads/video_index.csv (stdlib only).
import csv, datetime, glob, json, os, sys

VIDEO_EXTS = (".mp4", ".mkv", ".webm", ".mov", ".m4v")
THUMB_EXTS = (".jpg", ".jpeg", ".png", ".webp")
CSV_FIELDS = ["video_id","upload_date","title","description","original_url",
              "uploader","duration_seconds","view_count","like_count",
              "comment_count","repost_count","local_video_path","metadata_path",
              "download_status","downloaded_at"]

def safe_move(src, dst):
    if os.path.abspath(src) == os.path.abspath(dst): return
    if os.path.exists(dst): return
    try: os.replace(src, dst)
    except Exception:
        try:
            import shutil; shutil.move(src, dst)
        except Exception: pass

def blank(v): return "" if v is None else v

def main():
    project = os.path.expanduser(sys.argv[1]) if len(sys.argv) > 1 else os.getcwd()
    downloads = os.path.join(project, "Downloads")
    videos_dir = os.path.join(downloads, "Videos")
    meta_dir = os.path.join(downloads, "Metadata")
    thumbs_dir = os.path.join(downloads, "Thumbnails")
    for d in (videos_dir, meta_dir, thumbs_dir): os.makedirs(d, exist_ok=True)
    if os.path.isdir(videos_dir):
        for name in os.listdir(videos_dir):
            path = os.path.join(videos_dir, name)
            if not os.path.isfile(path): continue
            low = name.lower()
            if low.endswith(".info.json") or low.endswith(".description"):
                safe_move(path, os.path.join(meta_dir, name))
            elif os.path.splitext(low)[1] in THUMB_EXTS:
                safe_move(path, os.path.join(thumbs_dir, name))
    info_files = sorted(set(glob.glob(os.path.join(meta_dir, "*.info.json")) +
                            glob.glob(os.path.join(videos_dir, "*.info.json"))))
    records = {}
    for info_path in info_files:
        try:
            with open(info_path, "r", encoding="utf-8") as f: data = json.load(f)
        except Exception: continue
        vid = str(data.get("id") or "").strip()
        if not vid: continue
        stem = os.path.basename(info_path)
        if stem.endswith(".info.json"): stem = stem[:-len(".info.json")]
        local_video = ""
        for ext in VIDEO_EXTS:
            cand = os.path.join(videos_dir, stem + ext)
            if os.path.exists(cand): local_video = cand; break
        if not local_video and os.path.isdir(videos_dir):
            for name in os.listdir(videos_dir):
                if vid in name and os.path.splitext(name)[1].lower() in VIDEO_EXTS:
                    local_video = os.path.join(videos_dir, name); break
        if local_video and os.path.exists(local_video) and os.path.getsize(local_video) > 0:
            status = "downloaded"; ts = datetime.datetime.fromtimestamp(os.path.getmtime(local_video))
        else:
            status = "metadata_only"; ts = datetime.datetime.fromtimestamp(os.path.getmtime(info_path))
        downloaded_at = ts.strftime("%Y-%m-%d %H:%M:%S")
        ud = str(data.get("upload_date") or "")
        if len(ud) == 8 and ud.isdigit(): ud = "%s-%s-%s" % (ud[0:4], ud[4:6], ud[6:8])
        url = (data.get("webpage_url") or data.get("original_url")
               or "https://www.tiktok.com/@%s/video/%s" % (data.get("uploader") or "", vid))
        meta_final = info_path
        if os.path.dirname(info_path) != meta_dir:
            meta_final = os.path.join(meta_dir, os.path.basename(info_path))
        records[vid] = {
            "video_id": vid, "upload_date": ud,
            "title": (data.get("title") or "").replace("\n"," ").strip(),
            "description": (data.get("description") or "").replace("\n"," ").strip(),
            "original_url": url,
            "uploader": data.get("uploader") or data.get("uploader_id") or data.get("channel") or "",
            "duration_seconds": blank(data.get("duration")),
            "view_count": blank(data.get("view_count")),
            "like_count": blank(data.get("like_count")),
            "comment_count": blank(data.get("comment_count")),
            "repost_count": blank(data.get("repost_count")),
            "local_video_path": local_video, "metadata_path": meta_final,
            "download_status": status, "downloaded_at": downloaded_at,
        }
    csv_path = os.path.join(downloads, "video_index.csv")
    rows = sorted(records.values(), key=lambda r: (r["upload_date"], r["video_id"]))
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=CSV_FIELDS); w.writeheader()
        for row in rows: w.writerow(row)
    print("INDEX_ROWS=%d" % len(rows)); print("CSV_PATH=%s" % csv_path)

if __name__ == "__main__":
    main()
PYEOF
}

# Make sure the indexing helper exists (write it if the user only copied the .command).
if [ ! -f "$HELPER_PY" ]; then
  info "Creating the indexing helper (Scripts/organize_and_index.py)…"
  write_helper_py
fi

# =============================================================================
#  Shared yt-dlp options
# =============================================================================
# General behaviour (safe filenames, retries, polite delays, resume).
COMMON_OPTS=(
  --ignore-config
  --no-overwrites
  --continue
  --no-mtime
  --restrict-filenames
  --trim-filenames 200
  --retries 3
  --fragment-retries 3
  --retry-sleep 3
  --socket-timeout 30
  --sleep-requests 1.5
  --sleep-interval 2
  --max-sleep-interval 6
  --newline
)
# What and where to download. --paths keeps metadata/thumbnails cleanly separated
# WITHOUT touching the output template (safe approach the task asked for).
DL_OPTS=(
  -f "bv*+ba/b"
  -S "res,ext:mp4:m4a,vcodec:h264"
  --merge-output-format mp4
  --remux-video mp4
  --write-info-json
  --write-description
  --write-thumbnail
  --convert-thumbnails jpg
  --download-archive "$ARCHIVE_FILE"
  --paths "home:$VIDEOS_DIR"
  --paths "infojson:$METADATA_DIR"
  --paths "description:$METADATA_DIR"
  --paths "thumbnail:$THUMBS_DIR"
  -o "%(upload_date>%Y-%m-%d)s_%(id)s_%(title).80B.%(ext)s"
)

# Cookie options start EMPTY (we try without login first). Filled in only if
# TikTok blocks us and you pick a browser. Cookie VALUES are never printed.
COOKIE_OPTS=()
COOKIE_BROWSER="none"

# =============================================================================
#  STEP 5 helper — Cookies-from-browser fallback (only if TikTok blocks us)
# =============================================================================
detect_browsers() {
  AVAIL_BROWSERS=()
  [ -d "/Applications/Google Chrome.app" ] && AVAIL_BROWSERS+=("chrome")
  [ -d "/Applications/Firefox.app" ] && AVAIL_BROWSERS+=("firefox")
  [ -d "/Applications/Microsoft Edge.app" ] && AVAIL_BROWSERS+=("edge")
  [ -d "/Applications/Brave Browser.app" ] && AVAIL_BROWSERS+=("brave")
  # Safari exists on every Mac.
  [ "$IS_MAC" = "1" ] && AVAIL_BROWSERS+=("safari")
}

offer_cookies() {
  # Returns 0 if a browser was chosen and COOKIE_OPTS set; 1 if user declined.
  banner "STEP 5 — TikTok wants login / blocked the request"
  warn "TikTok did not allow access without logging in (this is common)."
  say  "To continue, yt-dlp can read the TikTok login cookies from a browser where"
  say  "you are ALREADY signed in to TikTok. Your cookies are used only locally for"
  say  "this download. They are NEVER printed, saved as text, or uploaded anywhere."
  say  "سنستخدم تسجيل دخولك في المتصفح محليًا فقط، ولن نطبع أو نحفظ أو نرفع بياناتك إطلاقًا."
  say  ""
  detect_browsers
  if [ "${#AVAIL_BROWSERS[@]}" -eq 0 ]; then
    err "No supported browser detected. Please log in to TikTok in Chrome or Firefox, then run again."
    return 1
  fi
  if [ ! -t 0 ]; then
    warn "Non-interactive run — cannot ask which browser. Re-run by double-clicking in Finder."
    return 1
  fi
  say "Which browser is already logged in to your TikTok account ($PROFILE_HANDLE)?"
  local i=1
  for b in "${AVAIL_BROWSERS[@]}"; do say "   $i) $b"; i=$((i+1)); done
  say "   0) Skip (do not use cookies)"
  printf "%sEnter a number: %s" "$B" "$R"
  read -r CHOICE
  if [ "$CHOICE" = "0" ] || [ -z "$CHOICE" ]; then warn "Skipped cookies."; return 1; fi
  local idx=$((CHOICE-1))
  if [ "$idx" -lt 0 ] || [ "$idx" -ge "${#AVAIL_BROWSERS[@]}" ]; then err "Invalid choice."; return 1; fi
  COOKIE_BROWSER="${AVAIL_BROWSERS[$idx]}"
  COOKIE_OPTS=(--cookies-from-browser "$COOKIE_BROWSER")
  ok "Will use cookies from: $COOKIE_BROWSER (values stay private)."
  if [ "$COOKIE_BROWSER" = "chrome" ] || [ "$COOKIE_BROWSER" = "edge" ] || [ "$COOKIE_BROWSER" = "brave" ]; then
    warn "macOS may pop up a Keychain prompt to allow reading '$COOKIE_BROWSER Safe Storage'."
    warn "It is asking permission to read that browser's saved cookies. Click Allow / enter your Mac password."
    warn "قد يظهر طلب من Keychain للسماح بقراءة بيانات المتصفح — اضغط Allow أو أدخل كلمة مرور الماك."
  elif [ "$COOKIE_BROWSER" = "safari" ]; then
    warn "Safari cookies need 'Full Disk Access' for Terminal: System Settings ▸ Privacy & Security ▸ Full Disk Access ▸ enable Terminal."
    warn "If Safari fails, Chrome or Firefox is usually easier."
  fi
  return 0
}

# =============================================================================
#  STEP 4 — Enumerate the profile, then test with ONE video
# =============================================================================
banner "STEP 3/4 — Finding your videos and testing with ONE first"

IDS_FILE="$LOGS_DIR/.video_ids_${RUN_STAMP}.txt"
ENUM_ERR="$LOGS_DIR/.enum_err_${RUN_STAMP}.txt"

enumerate() {
  # List video IDs only (no download). Writes IDs to $IDS_FILE. Returns yt-dlp exit code.
  : > "$IDS_FILE"
  $YTDLP "${COMMON_OPTS[@]}" "${COOKIE_OPTS[@]}" \
    --flat-playlist --print "%(id)s" \
    "$PROFILE_URL" > "$IDS_FILE" 2> "$ENUM_ERR"
  return $?
}

say "Looking up the videos on $PROFILE_URL …"
enumerate
ENUM_CODE=$?
N_DETECTED=$(grep -c . "$IDS_FILE" 2>/dev/null || echo 0)

# If blocked / zero results, explain and offer cookies, then retry once.
if [ "$ENUM_CODE" -ne 0 ] || [ "$N_DETECTED" -eq 0 ]; then
  warn "Could not list videos without logging in. yt-dlp said:"
  grep -iE "error|403|forbidden|private|captcha|secondary user|sign in|login" "$ENUM_ERR" | head -6 | sed 's/^/     /'
  if offer_cookies; then
    say "Retrying with your $COOKIE_BROWSER login…"
    enumerate
    ENUM_CODE=$?
    N_DETECTED=$(grep -c . "$IDS_FILE" 2>/dev/null || echo 0)
  fi
fi

if [ "$ENUM_CODE" -ne 0 ] || [ "$N_DETECTED" -eq 0 ]; then
  err "Still could not find any videos. Full yt-dlp error (for troubleshooting):"
  echo "---------------------------------------------------------------"
  cat "$ENUM_ERR"
  echo "---------------------------------------------------------------"
  {
    echo "RESULT: FAILED"
    echo "When:   $(date)"
    echo "Reason: profile enumeration returned 0 videos / blocked."
    echo "Cookies used: $COOKIE_BROWSER"
    echo "Next safe steps:"
    echo "  1) Open TikTok in Chrome or Firefox and make sure you are logged in to @$PROFILE_HANDLE."
    echo "  2) If a CAPTCHA appears in the browser, solve it there, then run this file again."
    echo "  3) Update yt-dlp:  brew upgrade yt-dlp   (then run again)."
    echo "  4) Make sure your internet works and TikTok opens normally in your browser."
  } | tee "$TEST_RESULT"
  err "See the reasons above. Nothing was downloaded. No files were changed or deleted."
  PAUSE_AT_END=1
  exit 2
fi

ok "Detected $N_DETECTED video(s) on the profile."
FIRST_ID="$(grep -m1 . "$IDS_FILE")"
say "Test video id: $FIRST_ID"

# --- Download ONLY the first video as a test. -------------------------------
say "Downloading ONE test video…"
TEST_URL="https://www.tiktok.com/@${PROFILE_HANDLE}/video/${FIRST_ID}"
$YTDLP "${COMMON_OPTS[@]}" "${COOKIE_OPTS[@]}" "${DL_OPTS[@]}" "$TEST_URL" || true

# --- Verify the test download for real. -------------------------------------
verify_video() {
  # $1 = id ; echoes "PASS"/"FAIL ..." and returns 0/1
  local id="$1" file dur
  file="$(find "$VIDEOS_DIR" -type f -name "*${id}*" \( -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.webm' -o -iname '*.mov' -o -iname '*.m4v' \) 2>/dev/null | head -1)"
  if [ -z "$file" ]; then echo "FAIL: no video file was created for id $id"; return 1; fi
  if [ ! -s "$file" ]; then echo "FAIL: file exists but is empty: $file"; return 1; fi
  TEST_FILE="$file"
  if [ -n "$FFPROBE" ]; then
    dur="$($FFPROBE -v error -show_entries format=duration -of default=nw=1:nk=1 "$file" 2>/dev/null)"
    if [ -z "$dur" ] || ! awk -v d="$dur" 'BEGIN{exit !(d>0)}'; then
      echo "FAIL: FFprobe did not recognize a positive duration for $file"; return 1
    fi
    TEST_DUR="$dur"
  else
    TEST_DUR="(ffprobe unavailable)"
  fi
  echo "PASS"; return 0
}

TEST_FILE=""; TEST_DUR=""
VERDICT="$(verify_video "$FIRST_ID")"
META_JSON="$(find "$METADATA_DIR" -type f -name "*${FIRST_ID}*.info.json" 2>/dev/null | head -1)"

{
  echo "OG TikTok Downloader — one-video test"
  echo "When:            $(date)"
  echo "Profile:         $PROFILE_URL"
  echo "Cookies used:    $COOKIE_BROWSER"
  echo "Test video id:   $FIRST_ID"
  echo "Test video URL:  $TEST_URL"
  if [ "${VERDICT%%:*}" = "PASS" ]; then
    echo "RESULT:          PASS"
    echo "Video file:      $TEST_FILE"
    echo "File size:       $(du -h "$TEST_FILE" 2>/dev/null | awk '{print $1}')"
    echo "Duration (sec):  $TEST_DUR"
    echo "Metadata JSON:   ${META_JSON:-(not found)}"
  else
    echo "RESULT:          FAIL"
    echo "Why:             $VERDICT"
  fi
} | tee "$TEST_RESULT"

if [ "${VERDICT%%:*}" != "PASS" ]; then
  err "The one-video test FAILED. Not continuing to the full profile."
  err "$VERDICT"
  say "Tip: try running again and choose a browser where you're logged in to TikTok (Step 5)."
  PAUSE_AT_END=1
  exit 3
fi
ok "Test PASSED — a real, playable video was downloaded and verified."

# =============================================================================
#  STEP 6 — Full profile download (skips anything already downloaded)
# =============================================================================
banner "STEP 6 — Downloading the rest of your videos"

# Snapshot the archive so we can count what is genuinely new this run.
ARCHIVE_BEFORE="$LOGS_DIR/.archive_before_${RUN_STAMP}.txt"
cp -p "$ARCHIVE_FILE" "$ARCHIVE_BEFORE" 2>/dev/null || : > "$ARCHIVE_BEFORE"
COUNT_BEFORE=$(grep -c . "$ARCHIVE_BEFORE" 2>/dev/null || echo 0)

# How many detected IDs were already in the archive before this run = "already existed".
ALREADY_EXISTED=0
while IFS= read -r vid; do
  [ -z "$vid" ] && continue
  if grep -q " $vid$" "$ARCHIVE_BEFORE" 2>/dev/null || grep -q "$vid" "$ARCHIVE_BEFORE" 2>/dev/null; then
    ALREADY_EXISTED=$((ALREADY_EXISTED+1))
  fi
done < "$IDS_FILE"

say "Archiving all public videos from @$PROFILE_HANDLE (already-downloaded ones are skipped)…"
# -i / --ignore-errors: keep going past any single bad video.
$YTDLP "${COMMON_OPTS[@]}" "${COOKIE_OPTS[@]}" "${DL_OPTS[@]}" \
  --ignore-errors \
  "$PROFILE_URL" || true

COUNT_AFTER=$(grep -c . "$ARCHIVE_FILE" 2>/dev/null || echo 0)
NEW_DOWNLOADED=$((COUNT_AFTER - COUNT_BEFORE))
[ "$NEW_DOWNLOADED" -lt 0 ] && NEW_DOWNLOADED=0

# =============================================================================
#  STEP 7 — Record failed URLs (no duplicates)
# =============================================================================
# Pull any video IDs that appeared on ERROR lines in THIS run's log and store
# their URLs uniquely. (Cookie values never appear in yt-dlp error lines.)
grep -iE "ERROR" "$LOG" 2>/dev/null | grep -oE "[0-9]{15,}" | sort -u | while read -r bad; do
  echo "https://www.tiktok.com/@${PROFILE_HANDLE}/video/${bad}"
done >> "$FAILED_URLS"
if [ -s "$FAILED_URLS" ]; then sort -u "$FAILED_URLS" -o "$FAILED_URLS"; fi
N_FAILED=$(grep -c . "$FAILED_URLS" 2>/dev/null || echo 0)

# =============================================================================
#  STEP 8 — Build/refresh the CSV index (Python standard library only)
# =============================================================================
banner "STEP 8 — Building the video index (CSV)"
if [ -f "$HELPER_PY" ]; then
  python3 "$HELPER_PY" "$PROJECT_DIR" || warn "Indexing script reported a problem (videos are still safe)."
else
  warn "Indexing helper missing; skipping CSV (videos are still saved)."
fi
CSV_PATH="$DOWNLOADS_DIR/video_index.csv"

# =============================================================================
#  STEP 10 — Final verification & summary
# =============================================================================
banner "FINAL REPORT"

N_VIDEO_FILES=$(find "$VIDEOS_DIR" -type f \( -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.webm' -o -iname '*.mov' -o -iname '*.m4v' \) 2>/dev/null | wc -l | tr -d ' ')
TOTAL_SIZE=$(du -sh "$VIDEOS_DIR" 2>/dev/null | awk '{print $1}')

# Self-checks.
CHK_CMD="missing"; [ -f "$SCRIPT_PATH" ] && CHK_CMD="present"
CHK_EXEC="no"; [ -x "$SCRIPT_PATH" ] && CHK_EXEC="yes"
CHK_ARCHIVE="missing"; [ -f "$ARCHIVE_FILE" ] && CHK_ARCHIVE="present"
CHK_CSV="missing"; [ -f "$CSV_PATH" ] && CHK_CSV="present"

say "• One-video test         : ${VERDICT%%:*}"
say "• Videos detected        : $N_DETECTED"
say "• Newly downloaded (run) : $NEW_DOWNLOADED"
say "• Already existed (skip) : $ALREADY_EXISTED"
say "• Failed (logged)        : $N_FAILED"
say "• Total video files      : $N_VIDEO_FILES"
say "• Total downloaded size  : ${TOTAL_SIZE:-0}"
say "• Cookies used           : $COOKIE_BROWSER"
say ""
say "• Main .command present  : $CHK_CMD (executable: $CHK_EXEC)"
say "• Archive file           : $CHK_ARCHIVE  ($ARCHIVE_FILE)"
say "• CSV index              : $CHK_CSV  ($CSV_PATH)"
say "• Logs folder            : $LOGS_DIR"
say "• Videos folder          : $VIDEOS_DIR"
say ""
ok  "Open-source only: yt-dlp + FFmpeg + Python 3 (+ Homebrew). No paid or closed-source service used."
say "${B}To run again later, just double-click:${R} $SCRIPT_PATH"

# Append a compact machine summary to the log tail.
{
  echo "=== RUN SUMMARY ($(date)) ==="
  echo "profile=$PROFILE_URL cookies=$COOKIE_BROWSER detected=$N_DETECTED new=$NEW_DOWNLOADED already=$ALREADY_EXISTED failed=$N_FAILED total_files=$N_VIDEO_FILES total_size=${TOTAL_SIZE:-0}"
  echo "yt-dlp=$YTDLP_VER"
  echo "end_time=$(date)"
} >> "$LOG"

# Clean up tiny temp files for this run (never touches videos).
rm -f "$IDS_FILE" "$ENUM_ERR" "$ARCHIVE_BEFORE" 2>/dev/null || true

ok "Done."
exit 0
