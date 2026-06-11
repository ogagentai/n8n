#!/bin/bash
# =============================================================================
#  Tiktok_Paste_Link_Download.command  —  أداة تحميل تيك توك
#  • الصق لينك فيديو واحد  → ينزّل الفيديو ده.
#  • الصق لينك البروفايل   → يعمل قائمة بكل فيديوهاتك وينزّلهم كلهم بالصوت.
#  أدوات مجانية مفتوحة المصدر فقط: yt-dlp + FFmpeg (+ curl_cffi لبصمة المتصفح).
#  ما بيمسحش أي ملف، وما بيطلبش باسورد تيك توك، وما بيطبعش أي كوكيز.
# =============================================================================
set -o pipefail   # من غير set -u عشان نتجنّب مشاكل bash 3.2 القديمة على الماك

if [ -t 1 ]; then B=$'\033[1m'; R=$'\033[0m'; G=$'\033[32m'; Y=$'\033[33m'; RED=$'\033[31m'; D=$'\033[2m'
else B=""; R=""; G=""; Y=""; RED=""; D=""; fi

OUT="$HOME/Desktop/TikTok_Videos"
mkdir -p "$OUT"
ERRLOG="$OUT/.last_error.txt"
SHEET="$OUT/all_video_links.txt"
ARCHIVE="$OUT/.downloaded_archive.txt"
BUILD="2026-06-11d (تحميل كل الفيديوهات + قائمة لينكات)"

trap 'echo; echo "${Y}تم الإيقاف. الفيديوهات المحمّلة محفوظة في $OUT${R}"; exit 0' INT
trap 'echo; if [ -t 0 ]; then printf "%sاضغط Return لقفل الويندو…%s " "$D" "$R"; read -r _ || true; fi' EXIT

clear 2>/dev/null || true
echo "${B}=================================================${R}"
echo "${B}        تحميل تيك توك — الصق اللينك وبس           ${R}"
echo "${B}=================================================${R}"
echo "${D}Build: $BUILD${R}"
echo "📁 الفيديوهات هتتحفظ في: ${B}$OUT${R}"
echo

# --- مسارات الأدوات -----------------------------------------------------------
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
for p in "$HOME"/Library/Python/3.*/bin; do [ -d "$p" ] && PATH="$p:$PATH"; done
export PATH
have() { command -v "$1" >/dev/null 2>&1; }

echo "${Y}بجهّز أدوات التحميل (أول مرة بس، ممكن تاخد دقيقة)…${R}"
python3 -m pip install --user -q -U "yt-dlp[default]" >/dev/null 2>&1 \
  || python3 -m pip install --user -q -U --break-system-packages "yt-dlp[default]" >/dev/null 2>&1 || true
for p in "$HOME"/Library/Python/3.*/bin; do [ -d "$p" ] && PATH="$p:$PATH"; done
export PATH
if ! have ffmpeg && have brew; then echo "${Y}بثبّت FFmpeg…${R}"; brew install ffmpeg >/dev/null 2>&1 || true; fi

# --- اختَر أفضل yt-dlp (يفضّل اللي بيدعم بصمة المتصفح) -------------------------
YTDLP=""; HAVE_IMP=0; CANDS=()
for p in "$HOME"/Library/Python/3.*/bin/yt-dlp "$HOME/.local/bin/yt-dlp"; do [ -x "$p" ] && CANDS+=("$p"); done
have yt-dlp && CANDS+=("$(command -v yt-dlp)")
python3 -c "import yt_dlp" >/dev/null 2>&1 && CANDS+=("python3 -m yt_dlp")
for c in "${CANDS[@]}"; do
  if $c --list-impersonate-targets 2>/dev/null | grep -qiE 'chrome|safari'; then YTDLP="$c"; HAVE_IMP=1; break; fi
done
if [ -z "$YTDLP" ] && [ ${#CANDS[@]} -gt 0 ]; then YTDLP="${CANDS[0]}"; fi
if [ -z "$YTDLP" ]; then echo "${RED}❌ مش قادر أثبّت yt-dlp.${R} ثبّت Homebrew من https://brew.sh وشغّل تاني."; exit 1; fi
echo "${G}✅ جاهز — yt-dlp $($YTDLP --version 2>/dev/null | head -1) | بصمة المتصفح: $([ "$HAVE_IMP" = 1 ] && echo "متاحة ✅" || echo "غير متاحة")${R}"

# خيارات التحميل المشتركة (الصيغة دي بتضمن الصوت جوه ملف واحد)
COMMON=(-f "best[acodec!=none][vcodec!=none]/bv*+ba/b"
        --merge-output-format mp4 --remux-video mp4
        --restrict-filenames --no-warnings
        --retries 3 --fragment-retries 3
        -o "$OUT/%(uploader)s_%(id)s.%(ext)s")

CHROME=0; FIREFOX=0
[ -d "/Applications/Google Chrome.app" ] && CHROME=1
[ -d "/Applications/Firefox.app" ] && FIREFOX=1

# --- مشغّل عام: يجرّب طرق الدخول بالترتيب ويقف عند أول نجاح (للفيديو الواحد) -----
#     "$@" = كل أوامر yt-dlp شاملة اللينك، بدون أوامر الدخول. الأخطاء تتسجّل في ERRLOG.
run_with_auth() {
  if [ "$HAVE_IMP" = 1 ] && [ "$CHROME" = 1 ]; then echo "${D}محاولة: Chrome + بصمة…${R}"; "$YTDLP" --impersonate chrome --cookies-from-browser chrome "$@" 2>"$ERRLOG" && return 0; fi
  if [ "$CHROME" = 1 ]; then echo "${D}محاولة: Chrome…${R}"; "$YTDLP" --cookies-from-browser chrome "$@" 2>"$ERRLOG" && return 0; fi
  if [ "$HAVE_IMP" = 1 ] && [ "$FIREFOX" = 1 ]; then echo "${D}محاولة: Firefox + بصمة…${R}"; "$YTDLP" --impersonate chrome --cookies-from-browser firefox "$@" 2>"$ERRLOG" && return 0; fi
  if [ "$FIREFOX" = 1 ]; then "$YTDLP" --cookies-from-browser firefox "$@" 2>"$ERRLOG" && return 0; fi
  if [ "$HAVE_IMP" = 1 ]; then "$YTDLP" --impersonate chrome "$@" 2>"$ERRLOG" && return 0; fi
  "$YTDLP" "$@" 2>"$ERRLOG" && return 0
  return 1
}

# --- تعداد فيديوهات البروفايل: يلاقي الطريقة الشغّالة ويحفظها في AUTH ----------
AUTH=()
_try_enum() { "$YTDLP" "$@" --flat-playlist --print "%(id)s" "$URL" 2>"$ERRLOG"; }
enumerate_profile() {
  local out=""
  if [ "$CHROME" = 1 ]; then
    if [ "$HAVE_IMP" = 1 ]; then out="$(_try_enum --impersonate chrome --cookies-from-browser chrome)"; [ -n "$out" ] && AUTH=(--impersonate chrome --cookies-from-browser chrome); fi
    if [ -z "$out" ]; then out="$(_try_enum --cookies-from-browser chrome)"; [ -n "$out" ] && AUTH=(--cookies-from-browser chrome); fi
  fi
  if [ -z "$out" ] && [ "$FIREFOX" = 1 ]; then
    if [ "$HAVE_IMP" = 1 ]; then out="$(_try_enum --impersonate chrome --cookies-from-browser firefox)"; [ -n "$out" ] && AUTH=(--impersonate chrome --cookies-from-browser firefox); fi
    if [ -z "$out" ]; then out="$(_try_enum --cookies-from-browser firefox)"; [ -n "$out" ] && AUTH=(--cookies-from-browser firefox); fi
  fi
  printf "%s" "$out"
  [ -n "$out" ]
}

# --- نوع اللينك: فيديو واحد ولا بروفايل ----------------------------------------
is_single() {
  case "$1" in
    *"/video/"*|*"/photo/"*|*vt.tiktok.com*|*vm.tiktok.com*) return 0 ;;
    *) return 1 ;;
  esac
}

download_single() {
  echo "${D}بنزّل الفيديو…${R}"
  run_with_auth "${COMMON[@]}" --no-playlist --force-overwrites "$URL"
}

download_profile() {
  echo "${D}بجمّع لينكات كل فيديوهاتك… (ممكن تاخد دقيقة)${R}"
  local ids; ids="$(enumerate_profile)"
  if [ -z "$ids" ]; then
    echo "${RED}❌ مقدرتش أجيب قائمة الفيديوهات. آخر سبب من yt-dlp:${R}"
    tail -n 4 "$ERRLOG" 2>/dev/null | sed 's/^/   /'
    echo "${Y}اتأكد إنك مسجّل دخول في Chrome بحسابك، وإن البروفايل بيفتح عادي في المتصفح.${R}"
    return 1
  fi
  local handle; handle="$(printf '%s' "$URL" | sed -n 's#.*tiktok\.com/@\([A-Za-z0-9._]*\).*#\1#p')"
  [ -z "$handle" ] && handle="oghonim"
  printf '%s\n' "$ids" | grep . | sed "s#^#https://www.tiktok.com/@$handle/video/#" > "$SHEET"
  local n; n=$(grep -c . "$SHEET" 2>/dev/null || echo 0)
  echo "${G}✅ لقيت $n فيديو. قائمة كل اللينكات اتحفظت في:${R}"
  echo "   ${B}$SHEET${R}"
  echo
  echo "${D}بنزّل دلوقتي كل الفيديوهات بالصوت (اللي اتنزّل قبل كده هيتسكيب تلقائياً)…${R}"
  echo "${D}تقدر توقف في أي وقت بـ Control+C، وتشغّل تاني يكمّل من حيث وقف.${R}"
  echo
  "$YTDLP" "${AUTH[@]}" "${COMMON[@]}" --download-archive "$ARCHIVE" --ignore-errors \
     --sleep-interval 2 --max-sleep-interval 5 --sleep-requests 1 "$URL"
  echo
  local got; got=$(ls "$OUT"/*.mp4 2>/dev/null | wc -l | tr -d ' ')
  echo "${G}✅ خلصنا! إجمالي ملفات الفيديو في الفولدر دلوقتي: $got${R}"
  return 0
}

# --- اللوب الرئيسي ------------------------------------------------------------
echo
echo "${D}الصق لينك فيديو (ينزّل الفيديو) أو لينك بروفايلك مثل https://www.tiktok.com/@oghonim (ينزّل الكل).${R}"
COUNT=0
while true; do
  echo
  printf "%sالصق اللينك واضغط Return  (أو اكتب q للخروج): %s" "$B" "$R"
  if ! read -r URL; then break; fi
  URL="$(printf "%s" "$URL" | tr -d '[:space:]')"
  [ -z "$URL" ] && continue
  case "$URL" in q|Q|quit|exit) break ;; esac
  case "$URL" in
    http*tiktok.com*|*vt.tiktok.com*|*vm.tiktok.com*) : ;;
    *) echo "${Y}⚠️  ده مش شكله لينك تيك توك.${R}"; continue ;;
  esac

  if is_single "$URL"; then
    if download_single; then
      COUNT=$((COUNT+1))
      NEWEST="$(ls -t "$OUT"/*.mp4 2>/dev/null | head -1)"
      echo "${G}✅ تم! الفيديو اتحفظ:${R} ${NEWEST:-$OUT}"
    else
      echo "${RED}❌ مانفعش. آخر سبب من yt-dlp:${R}"; tail -n 4 "$ERRLOG" 2>/dev/null | sed 's/^/   /'
      echo "${Y}   اتأكد إنك مسجّل دخول في Chrome، وإن اللينك بيفتح عادي في المتصفح.${R}"
    fi
  else
    download_profile || true
  fi
done

echo
echo "${B}خلصنا.${R}  📁 كل حاجة في: $OUT"
[ -f "$SHEET" ] && echo "📝 قائمة لينكاتك في: $SHEET"
exit 0
