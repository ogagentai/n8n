#!/bin/bash
# =============================================================================
#  Tiktok_Paste_Link_Download.command  —  أبسط أداة
#  دبل كليك ← الصق لينك فيديو تيك توك ← يتحمّل على الـ Desktop.
#  أدوات مجانية ومفتوحة المصدر فقط: yt-dlp + FFmpeg (+ Homebrew لتثبيتها).
#  ما بيمسحش أي ملف، وما بيطلبش باسورد تيك توك، وما بيطبعش أي كوكيز.
# =============================================================================
set -o pipefail

# ألوان بسيطة
if [ -t 1 ]; then B=$'\033[1m'; R=$'\033[0m'; G=$'\033[32m'; Y=$'\033[33m'; RED=$'\033[31m'; D=$'\033[2m'
else B=""; R=""; G=""; Y=""; RED=""; D=""; fi

OUT="$HOME/Desktop/TikTok_Videos"
mkdir -p "$OUT"

# اقفل بأمان واحفظ تقدّمك مع Control+C
trap 'echo; echo "${Y}تم الإيقاف. الفيديوهات اللي اتحمّلت محفوظة في $OUT${R}"; exit 0' INT
# سيب الويندو مفتوحة بعد ما يخلص الدبل كليك
trap 'echo; if [ -t 0 ]; then printf "%sاضغط Return لقفل الويندو…%s " "$D" "$R"; read -r _ || true; fi' EXIT

clear 2>/dev/null || true
echo "${B}=================================================${R}"
echo "${B}     تحميل فيديو تيك توك — الصق اللينك وبس        ${R}"
echo "${B}=================================================${R}"
echo "📁 الفيديوهات هتتحفظ في: ${B}$OUT${R}"
echo

# --- تأكد إن yt-dlp + ffmpeg موجودين، وثبّتهم لو ناقصين -------------------------
# ضيف أماكن Homebrew لمسار البحث (أبل سيليكون + إنتل) وأماكن بايثون.
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
for p in "$HOME"/Library/Python/3.*/bin; do [ -d "$p" ] && PATH="$p:$PATH"; done
export PATH

have() { command -v "$1" >/dev/null 2>&1; }

if ! have yt-dlp; then
  echo "${Y}بثبّت أداة التحميل yt-dlp (مرة واحدة بس)…${R}"
  if have brew; then
    brew install yt-dlp >/dev/null 2>&1 || true
  fi
  if ! have yt-dlp; then
    # خطة بديلة: تثبيت عن طريق بايثون (مجاني ومفتوح المصدر برضه)
    python3 -m pip install --user -U yt-dlp >/dev/null 2>&1 \
      || python3 -m pip install --user -U --break-system-packages yt-dlp >/dev/null 2>&1 || true
    for p in "$HOME"/Library/Python/3.*/bin; do [ -d "$p" ] && PATH="$p:$PATH"; done
    export PATH
  fi
fi

if ! have ffmpeg; then
  echo "${Y}بثبّت FFmpeg (مرة واحدة بس)…${R}"
  if have brew; then brew install ffmpeg >/dev/null 2>&1 || true; fi
fi

# حدّد أمر yt-dlp النهائي
YTDLP=""
if have yt-dlp; then YTDLP="$(command -v yt-dlp)"
elif python3 -c "import yt_dlp" >/dev/null 2>&1; then YTDLP="python3 -m yt_dlp"
fi

if [ -z "$YTDLP" ]; then
  echo "${RED}❌ مش قادر أثبّت yt-dlp تلقائياً.${R}"
  echo "الحل: ثبّت Homebrew من https://brew.sh وبعدين شغّل الملف ده تاني."
  exit 1
fi
echo "${G}✅ الأدوات جاهزة (yt-dlp $("$YTDLP" --version 2>/dev/null || $YTDLP --version 2>/dev/null))${R}"

# اختيار للـ impersonation لو متاح (بيساعد تيك توك)
IMP=""
if "$YTDLP" --list-impersonate-targets >/dev/null 2>&1; then IMP="--impersonate=chrome"; fi

# --- دالة تحميل فيديو واحد: تجرب من غير تسجيل دخول، وبعدين بكوكيز المتصفح --------
download_one() {
  local url="$1"
  local base=(-f "bv*+ba/b" --merge-output-format mp4 --remux-video mp4
              --no-playlist --restrict-filenames --no-warnings
              --retries 3 --fragment-retries 3
              -o "$OUT/%(uploader)s_%(id)s.%(ext)s")

  echo "${D}بحاول التحميل…${R}"
  "$YTDLP" ${IMP:+$IMP} "${base[@]}" "$url" && return 0

  # لو رفض من غير تسجيل دخول، نجرب كوكيز المتصفحات الموجودة (محلياً فقط، بدون طبع أي بيانات)
  if [ -d "/Applications/Google Chrome.app" ]; then
    echo "${Y}بحاول بتسجيل دخولك في Chrome (لو ظهر طلب Keychain اضغط Allow أو اكتب باسورد الماك)…${R}"
    "$YTDLP" ${IMP:+$IMP} --cookies-from-browser chrome "${base[@]}" "$url" && return 0
  fi
  if [ -d "/Applications/Firefox.app" ]; then
    echo "${Y}بحاول بتسجيل دخولك في Firefox…${R}"
    "$YTDLP" ${IMP:+$IMP} --cookies-from-browser firefox "${base[@]}" "$url" && return 0
  fi
  echo "${Y}بحاول بتسجيل دخول Safari (محتاج Full Disk Access للـ Terminal)…${R}"
  "$YTDLP" ${IMP:+$IMP} --cookies-from-browser safari "${base[@]}" "$url" && return 0

  return 1
}

# --- اللوب الرئيسي: الصق لينك ← يتحمّل ← الصق تاني -----------------------------
echo
echo "${D}نصيحة: لو فيه فيديو مارضيش يتحمّل، افتح تيك توك في Chrome أو Firefox وسجّل دخولك، وجرّب تاني.${R}"
COUNT=0
while true; do
  echo
  printf "%sالصق لينك فيديو تيك توك واضغط Return  (أو اكتب q للخروج): %s" "$B" "$R"
  if ! read -r URL; then break; fi
  # شيل أي مسافات
  URL="$(printf "%s" "$URL" | tr -d '[:space:]')"
  [ -z "$URL" ] && continue
  case "$URL" in
    q|Q|quit|exit) break ;;
  esac
  case "$URL" in
    http*tiktok.com*|*vt.tiktok.com*|*vm.tiktok.com*) : ;;
    *) echo "${Y}⚠️  ده مش شكله لينك تيك توك. الصق لينك زي: https://www.tiktok.com/@oghonim/video/123…${R}"; continue ;;
  esac

  if download_one "$URL"; then
    COUNT=$((COUNT+1))
    echo "${G}✅ تم! الفيديو رقم $COUNT اتحفظ في فولدر TikTok_Videos على الـ Desktop.${R}"
  else
    echo "${RED}❌ الفيديو ده مانفعش يتحمّل (غالباً محتاج تسجيل دخول أو اللينك مش متاح).${R}"
    echo "   جرّب: افتح تيك توك في Chrome، سجّل دخولك بحسابك، وبعدين الصق اللينك تاني."
  fi
done

echo
echo "${B}خلصنا. عدد الفيديوهات اللي اتحمّلت دلوقتي: $COUNT${R}"
echo "📁 كلها في: $OUT"
exit 0
