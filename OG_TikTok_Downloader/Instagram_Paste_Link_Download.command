#!/bin/bash
# =============================================================================
#  Instagram_Paste_Link_Download.command  —  أداة تحميل إنستجرام
#  • الصق لينك بوست/ريل   → ينزّله.
#  • الصق لينك بروفايلك   → ينزّل كل البوستات (صور + فيديوهات + ريلز).
#  أداة مجانية مفتوحة المصدر: gallery-dl (رخصة GPL-2.0) + FFmpeg.
#  بتشتغل على جهازك، ما بتمسحش أي ملف، وما بتطلبش باسورد إنستجرام،
#  وبتقرأ تسجيل دخولك من المتصفح محلياً فقط (من غير ما تطبع أو ترفع أي بيانات).
# =============================================================================
set -o pipefail   # من غير set -u عشان التوافق مع bash 3.2 القديم على الماك

if [ -t 1 ]; then B=$'\033[1m'; R=$'\033[0m'; G=$'\033[32m'; Y=$'\033[33m'; RED=$'\033[31m'; D=$'\033[2m'
else B=""; R=""; G=""; Y=""; RED=""; D=""; fi

OUT="$HOME/Desktop/Instagram_Downloads"
mkdir -p "$OUT"
ARCHIVE="$OUT/.download_archive"
BUILD="2026-06-11a (Instagram / gallery-dl)"

trap 'echo; echo "${Y}تم الإيقاف. اللي اتحمّل محفوظ في $OUT${R}"; exit 0' INT
trap 'echo; if [ -t 0 ]; then printf "%sاضغط Return لقفل النافذة…%s " "$D" "$R"; read -r _ || true; fi' EXIT

clear 2>/dev/null || true
echo "${B}=================================================${R}"
echo "${B}      تحميل إنستجرام — الصق اللينك وبس            ${R}"
echo "${B}=================================================${R}"
echo "${D}Build: $BUILD${R}"
echo "📁 التحميلات هتتحفظ في: ${B}$OUT${R}"
echo

# --- مسارات الأدوات -----------------------------------------------------------
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
for p in "$HOME"/Library/Python/3.*/bin; do [ -d "$p" ] && PATH="$p:$PATH"; done
export PATH
have() { command -v "$1" >/dev/null 2>&1; }

# --- جهّز gallery-dl + FFmpeg --------------------------------------------------
echo "${Y}بجهّز أدوات التحميل (أول مرة بس، ممكن تاخد دقيقة)…${R}"
if ! have gallery-dl; then
  if have brew; then brew install gallery-dl >/dev/null 2>&1 || true; fi
fi
if ! have gallery-dl; then
  python3 -m pip install --user -q -U gallery-dl >/dev/null 2>&1 \
    || python3 -m pip install --user -q -U --break-system-packages gallery-dl >/dev/null 2>&1 || true
  for p in "$HOME"/Library/Python/3.*/bin; do [ -d "$p" ] && PATH="$p:$PATH"; done
  export PATH
fi
if ! have ffmpeg && have brew; then brew install ffmpeg >/dev/null 2>&1 || true; fi

# حدّد أمر gallery-dl
GDL=""
if have gallery-dl; then GDL="$(command -v gallery-dl)"
elif python3 -c "import gallery_dl" >/dev/null 2>&1; then GDL="python3 -m gallery_dl"
fi
if [ -z "$GDL" ]; then
  echo "${RED}❌ مش قادر أثبّت gallery-dl.${R} ثبّت Homebrew من https://brew.sh وشغّل تاني."
  exit 1
fi
echo "${G}✅ جاهز — gallery-dl $($GDL --version 2>/dev/null | head -1)${R}"

# --- المتصفح اللي هنقرأ منه تسجيل الدخول (إنستجرام بيحتاج تسجيل دخول) ----------
COOKIE_BROWSER=""
[ -d "/Applications/Google Chrome.app" ] && COOKIE_BROWSER="chrome"
[ -z "$COOKIE_BROWSER" ] && [ -d "/Applications/Firefox.app" ] && COOKIE_BROWSER="firefox"
[ -z "$COOKIE_BROWSER" ] && [ -d "/Applications/Safari.app" ] && COOKIE_BROWSER="safari"
if [ -z "$COOKIE_BROWSER" ]; then
  echo "${Y}⚠️  مفيش متصفح متعرّف عليه. إنستجرام بيحتاج تسجيل دخول — افتح Chrome وسجّل دخولك.${R}"
else
  echo "${G}✅ هستخدم تسجيل دخولك من: $COOKIE_BROWSER${R} ${D}(محلياً فقط، من غير طبع أو رفع)${R}"
  if [ "$COOKIE_BROWSER" = "chrome" ]; then
    echo "${D}   لو ظهر طلب Keychain اضغط Allow أو اكتب باسورد الماك.${R}"
  elif [ "$COOKIE_BROWSER" = "safari" ]; then
    echo "${D}   Safari محتاج Full Disk Access للـ Terminal (الأفضل تستخدم Chrome).${R}"
  fi
fi

# --- دالة التحميل (بتعرض التقدّم مباشرةً) --------------------------------------
run_dl() {
  local args=(-d "$OUT" --download-archive "$ARCHIVE" --write-metadata --no-mtime
              --sleep-request 2.0 --sleep 1.0)
  [ -n "$COOKIE_BROWSER" ] && args+=(--cookies-from-browser "$COOKIE_BROWSER")
  echo "${D}بنزّل… (تقدر توقف بـ Control+C وتكمّل بعدين)${R}"
  "$GDL" "${args[@]}" "$URL"
}

count_media() { find "$OUT" -type f ! -name '.*' ! -name '*.json' 2>/dev/null | wc -l | tr -d ' '; }

# --- اللوب الرئيسي ------------------------------------------------------------
echo
echo "${D}الصق لينك بروفايلك (ينزّل الكل) مثل https://www.instagram.com/oghonim/${R}"
echo "${D}أو لينك بوست/ريل واحد. الستوري كمان شغّالة: .../stories/USERNAME/${R}"
BEFORE=$(count_media)
while true; do
  echo
  printf "%sالصق لينك إنستجرام واضغط Return  (أو اكتب q للخروج): %s" "$B" "$R"
  if ! read -r URL; then break; fi
  URL="$(printf "%s" "$URL" | tr -d '[:space:]')"
  [ -z "$URL" ] && continue
  case "$URL" in q|Q|quit|exit) break ;; esac
  case "$URL" in
    *instagram.com/*) : ;;
    *) echo "${Y}⚠️  ده مش شكله لينك إنستجرام.${R}"; continue ;;
  esac

  if run_dl; then
    NOW=$(count_media); NEW=$((NOW-BEFORE)); [ "$NEW" -lt 0 ] && NEW=0; BEFORE=$NOW
    echo "${G}✅ تم! نزل دلوقتي $NEW ملف جديد. الإجمالي في الفولدر: $NOW${R}"
  else
    echo "${RED}❌ في مشكلة (غالباً محتاج تسجيل دخول، أو إنستجرام طلب تأكيد أمني).${R}"
    echo "${Y}   جرّب: افتح إنستجرام في Chrome وسجّل دخولك، ولو ظهر تأكيد أمني (challenge) حلّه في المتصفح، وبعدين شغّل ده تاني.${R}"
  fi
done

echo
echo "${B}خلصنا.${R}  📁 كل حاجة في: $OUT"
exit 0
