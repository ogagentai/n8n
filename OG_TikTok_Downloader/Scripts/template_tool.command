#!/bin/bash
# =============================================================================
#  template_tool.command  —  قالب جاهز لأي أداة جديدة (دبل كليك للتشغيل)
#  انسخ الملف ده، غيّر الاسم، واملا الجزء المعلّم بـ "✏️ عدّل هنا".
#  بيشتغل على الماك، بأدوات مفتوحة المصدر، وبيسيب نافذة التيرمنال مفتوحة في الآخر.
# =============================================================================
set -o pipefail   # من غير set -u عشان التوافق مع bash 3.2 القديم بتاع الماك

# ---- ألوان بسيطة ------------------------------------------------------------
if [ -t 1 ]; then B=$'\033[1m'; R=$'\033[0m'; G=$'\033[32m'; Y=$'\033[33m'; RED=$'\033[31m'; D=$'\033[2m'
else B=""; R=""; G=""; Y=""; RED=""; D=""; fi

# ---- ✏️ عدّل هنا: اسم الأداة ومكان حفظ النتايج -------------------------------
TOOL_NAME="أداة جديدة"
OUT="$HOME/Desktop/My_Tool_Output"     # فولدر النتايج (اتغيّر حسب الأداة)
mkdir -p "$OUT"

# ---- يسيب النافذة مفتوحة ويقف بأمان مع Control+C ------------------------------
trap 'echo; echo "${Y}تم الإيقاف. النتايج محفوظة في $OUT${R}"; exit 0' INT
trap 'echo; if [ -t 0 ]; then printf "%sاضغط Return لقفل النافذة…%s " "$D" "$R"; read -r _ || true; fi' EXIT

clear 2>/dev/null || true
echo "${B}========================================${R}"
echo "${B}   $TOOL_NAME${R}"
echo "${B}========================================${R}"
echo "📁 النتايج هتتحفظ في: ${B}$OUT${R}"
echo

# ---- مسارات الأدوات (Homebrew + بايثون المستخدم) -----------------------------
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
for p in "$HOME"/Library/Python/3.*/bin; do [ -d "$p" ] && PATH="$p:$PATH"; done
export PATH
have() { command -v "$1" >/dev/null 2>&1; }

# دالة بتتأكد إن أداة موجودة، وتثبّتها لو ناقصة (brew أولاً)
ensure_tool() {            # ensure_tool <command> <brew-formula>
  local cmd="$1" formula="$2"
  have "$cmd" && return 0
  echo "${Y}بثبّت $formula (مرة واحدة)…${R}"
  if have brew; then brew install "$formula" >/dev/null 2>&1 || true; fi
  have "$cmd"
}

# ---- ✏️ عدّل هنا: تأكد من الأدوات اللي محتاجها أداتك --------------------------
# أمثلة:
# ensure_tool yt-dlp yt-dlp
# ensure_tool ffmpeg ffmpeg
# (yt-dlp بصمة المتصفح: python3 -m pip install --user "yt-dlp[default]")

# ---- ✏️ عدّل هنا: ده قلب الأداة — اللي بتعمله فعلاً --------------------------
do_work() {
  local input="$1"
  echo "${D}بشتغل على: $input${R}"

  # مثال يوضّح الفكرة (بدّله بالأمر الحقيقي):
  #   ffmpeg -i "$input" "$OUT/output.mp3"
  #   yt-dlp -o "$OUT/%(title)s.%(ext)s" "$input"
  echo "(هنا بيتحط الأمر الحقيقي بتاع الأداة)"

  # رجّع 0 لو نجح، أو 1 لو فشل
  return 0
}

# ---- اللوب الرئيسي: اسأل المستخدم، اشتغل، كرّر -------------------------------
echo "${G}✅ جاهز.${R}"
while true; do
  echo
  printf "%sاكتب/الصق المدخل واضغط Return  (أو اكتب q للخروج): %s" "$B" "$R"
  if ! read -r INPUT; then break; fi
  [ -z "$INPUT" ] && continue
  case "$INPUT" in q|Q|quit|exit) break ;; esac

  if do_work "$INPUT"; then
    echo "${G}✅ تم! النتيجة في: $OUT${R}"
  else
    echo "${RED}❌ في مشكلة. جرّب تاني أو ابعتلي صورة الشاشة.${R}"
  fi
done

echo
echo "${B}خلصنا.${R}  📁 النتايج في: $OUT"
exit 0
