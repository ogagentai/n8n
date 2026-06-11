#!/bin/bash
# =============================================================================
#  Tiktok_Paste_Link_Download.command  —  أبسط أداة (نسخة مصلّحة)
#  دبل كليك ← الصق لينك فيديو تيك توك ← يتحمّل على الـ Desktop.
#  أدوات مجانية ومفتوحة المصدر فقط: yt-dlp + FFmpeg (+ curl_cffi لبصمة المتصفح).
#  ما بيمسحش أي ملف، وما بيطلبش باسورد تيك توك، وما بيطبعش أي كوكيز.
# =============================================================================
set -o pipefail   # ملاحظة: مفيش set -u عشان نتجنّب مشاكل bash 3.2 القديمة على الماك

# ألوان بسيطة
if [ -t 1 ]; then B=$'\033[1m'; R=$'\033[0m'; G=$'\033[32m'; Y=$'\033[33m'; RED=$'\033[31m'; D=$'\033[2m'
else B=""; R=""; G=""; Y=""; RED=""; D=""; fi

OUT="$HOME/Desktop/TikTok_Videos"
mkdir -p "$OUT"
ERRLOG="$OUT/.last_error.txt"
BUILD="2026-06-11c (audio fix)"

trap 'echo; echo "${Y}تم الإيقاف. الفيديوهات المحمّلة محفوظة في $OUT${R}"; exit 0' INT
trap 'echo; if [ -t 0 ]; then printf "%sاضغط Return لقفل الويندو…%s " "$D" "$R"; read -r _ || true; fi' EXIT

clear 2>/dev/null || true
echo "${B}=================================================${R}"
echo "${B}     تحميل فيديو تيك توك — الصق اللينك وبس        ${R}"
echo "${B}=================================================${R}"
echo "${D}Build: $BUILD${R}"
echo "📁 الفيديوهات هتتحفظ في: ${B}$OUT${R}"
echo

# --- مسارات الأدوات (Homebrew أبل سيليكون/إنتل + بايثون المستخدم) ---------------
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
for p in "$HOME"/Library/Python/3.*/bin; do [ -d "$p" ] && PATH="$p:$PATH"; done
export PATH
have() { command -v "$1" >/dev/null 2>&1; }

# --- جهّز نسخة yt-dlp بتدعم بصمة المتصفح (curl_cffi) — ده اللي تيك توك بيحتاجه ----
echo "${Y}بجهّز أدوات التحميل (أول مرة بس، ممكن تاخد دقيقة)…${R}"
python3 -m pip install --user -q -U "yt-dlp[default]" >/dev/null 2>&1 \
  || python3 -m pip install --user -q -U --break-system-packages "yt-dlp[default]" >/dev/null 2>&1 \
  || true
# حدّث المسار بعد التثبيت
for p in "$HOME"/Library/Python/3.*/bin; do [ -d "$p" ] && PATH="$p:$PATH"; done
export PATH

# FFmpeg لو ناقص (عن طريق Homebrew لو موجود)
if ! have ffmpeg && have brew; then
  echo "${Y}بثبّت FFmpeg…${R}"; brew install ffmpeg >/dev/null 2>&1 || true
fi

# --- اختَر أفضل yt-dlp: يفضّل اللي بيدعم بصمة المتصفح ---------------------------
YTDLP=""; HAVE_IMP=0
CANDS=()
for p in "$HOME"/Library/Python/3.*/bin/yt-dlp "$HOME/.local/bin/yt-dlp"; do [ -x "$p" ] && CANDS+=("$p"); done
have yt-dlp && CANDS+=("$(command -v yt-dlp)")
python3 -c "import yt_dlp" >/dev/null 2>&1 && CANDS+=("python3 -m yt_dlp")
for c in "${CANDS[@]}"; do
  if $c --list-impersonate-targets 2>/dev/null | grep -qiE 'chrome|safari'; then
    YTDLP="$c"; HAVE_IMP=1; break
  fi
done
# لو مفيش واحد بيدعم البصمة، استخدم أول واحد متاح
if [ -z "$YTDLP" ] && [ ${#CANDS[@]} -gt 0 ]; then YTDLP="${CANDS[0]}"; fi

if [ -z "$YTDLP" ]; then
  echo "${RED}❌ مش قادر أثبّت yt-dlp.${R} ثبّت Homebrew من https://brew.sh وشغّل الملف تاني."
  exit 1
fi
echo "${G}✅ الأدوات جاهزة — yt-dlp $($YTDLP --version 2>/dev/null | head -1) | بصمة المتصفح: $([ "$HAVE_IMP" = 1 ] && echo "متاحة ✅" || echo "غير متاحة")${R}"

# --- تحميل فيديو واحد: يجرّب أفضل الطرق بالترتيب، ويقف عند أول نجاح --------------
download_one() {
  local url="$1"
  local base=(-f "best[acodec!=none][vcodec!=none]/bv*+ba/b"
              --merge-output-format mp4 --remux-video mp4 --force-overwrites
              --no-playlist --restrict-filenames --no-warnings --no-progress
              --retries 3 --fragment-retries 3
              -o "$OUT/%(uploader)s_%(id)s.%(ext)s")
  local imp=()
  [ "$HAVE_IMP" = "1" ] && imp=(--impersonate chrome)
  local chrome=0 firefox=0
  [ -d "/Applications/Google Chrome.app" ] && chrome=1
  [ -d "/Applications/Firefox.app" ] && firefox=1

  # 1) الأفضل لتيك توك: بصمة المتصفح + تسجيل دخول Chrome
  if [ "$HAVE_IMP" = "1" ] && [ "$chrome" = "1" ]; then
    echo "${D}محاولة: Chrome + بصمة متصفح…${R}"
    "$YTDLP" "${imp[@]}" --cookies-from-browser chrome "${base[@]}" "$url" 2>"$ERRLOG" && return 0
  fi
  # 2) تسجيل دخول Chrome من غير بصمة
  if [ "$chrome" = "1" ]; then
    echo "${D}محاولة: Chrome login…${R}"
    "$YTDLP" --cookies-from-browser chrome "${base[@]}" "$url" 2>"$ERRLOG" && return 0
  fi
  # 3) بصمة + Firefox
  if [ "$HAVE_IMP" = "1" ] && [ "$firefox" = "1" ]; then
    echo "${D}محاولة: Firefox + بصمة متصفح…${R}"
    "$YTDLP" "${imp[@]}" --cookies-from-browser firefox "${base[@]}" "$url" 2>"$ERRLOG" && return 0
  fi
  # 4) Firefox login
  if [ "$firefox" = "1" ]; then
    "$YTDLP" --cookies-from-browser firefox "${base[@]}" "$url" 2>"$ERRLOG" && return 0
  fi
  # 5) بصمة من غير تسجيل دخول
  if [ "$HAVE_IMP" = "1" ]; then
    echo "${D}محاولة: بصمة متصفح بدون تسجيل دخول…${R}"
    "$YTDLP" "${imp[@]}" "${base[@]}" "$url" 2>"$ERRLOG" && return 0
  fi
  # 6) عادي
  "$YTDLP" "${base[@]}" "$url" 2>"$ERRLOG" && return 0
  return 1
}

# --- اللوب الرئيسي ------------------------------------------------------------
echo
COUNT=0
while true; do
  echo
  printf "%sالصق لينك فيديو تيك توك واضغط Return  (أو اكتب q للخروج): %s" "$B" "$R"
  if ! read -r URL; then break; fi
  URL="$(printf "%s" "$URL" | tr -d '[:space:]')"
  [ -z "$URL" ] && continue
  case "$URL" in q|Q|quit|exit) break ;; esac
  case "$URL" in
    http*tiktok.com*|*vt.tiktok.com*|*vm.tiktok.com*) : ;;
    *) echo "${Y}⚠️  ده مش شكله لينك تيك توك.${R}"; continue ;;
  esac

  if download_one "$URL"; then
    COUNT=$((COUNT+1))
    NEWEST="$(ls -t "$OUT"/*.mp4 2>/dev/null | head -1)"
    echo "${G}✅ تم! الفيديو رقم $COUNT اتحفظ:${R} ${NEWEST:-$OUT}"
  else
    echo "${RED}❌ الفيديو ده مانفعش يتحمّل. آخر سبب من yt-dlp:${R}"
    tail -n 4 "$ERRLOG" 2>/dev/null | sed 's/^/   /'
    echo "${Y}   جرّب: اتأكد إنك مسجّل دخول في Chrome بحسابك، وإن اللينك بيفتح عادي في المتصفح.${R}"
  fi
done

echo
echo "${B}خلصنا. عدد الفيديوهات اللي اتحمّلت دلوقتي: $COUNT${R}"
echo "📁 كلها في: $OUT"
exit 0
