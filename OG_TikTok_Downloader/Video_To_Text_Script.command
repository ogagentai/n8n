#!/bin/bash
# =============================================================================
#  Video_To_Text_Script.command  —  تفريغ كلام الفيديوهات لنص مكتوب (سكريبت)
#  بياخد فيديوهاتك المحمّلة ويطلّع لكل واحد ملف .txt فيه الكلام اللي اتقال.
#  أداة مجانية مفتوحة المصدر: faster-whisper (رخصة MIT) + Python — بتشتغل على جهازك.
#  ما بتمسحش أي ملف، وما بتطلبش أي باسورد أو إنترنت غير تحميل الموديل أول مرة.
# =============================================================================
set -o pipefail   # من غير set -u للتوافق مع bash 3.2 على الماك

if [ -t 1 ]; then B=$'\033[1m'; R=$'\033[0m'; G=$'\033[32m'; Y=$'\033[33m'; RED=$'\033[31m'; D=$'\033[2m'
else B=""; R=""; G=""; Y=""; RED=""; D=""; fi

# ✏️ الموديل: small = أسرع | medium = أدق للعربي | large-v3 = الأدق (أبطأ)
#    لو غيّرته وعايز تعيد التفريغ، امسح ملفات .txt القديمة من فولدر Video_Scripts.
WHISPER_MODEL="${WHISPER_MODEL:-small}"
WHISPER_LANG="${WHISPER_LANG:-}"     # سيبها فاضية = اكتشاف تلقائي، أو حط ar للعربي

OUT="$HOME/Desktop/Video_Scripts"
mkdir -p "$OUT"
HELPER="$OUT/.transcribe_videos.py"
BUILD="2026-06-11a (Video → Text / Whisper)"

trap 'echo; echo "${Y}تم الإيقاف. اللي اتفرّغ محفوظ في $OUT${R}"; exit 0' INT
trap 'echo; if [ -t 0 ]; then printf "%sاضغط Return لقفل النافذة…%s " "$D" "$R"; read -r _ || true; fi' EXIT

clear 2>/dev/null || true
echo "${B}=================================================${R}"
echo "${B}     تفريغ كلام الفيديوهات لنص مكتوب (سكريبت)      ${R}"
echo "${B}=================================================${R}"
echo "${D}Build: $BUILD | الموديل: $WHISPER_MODEL${R}"
echo "📝 النصوص هتتحفظ في: ${B}$OUT${R}"
echo

# --- مسارات الأدوات -----------------------------------------------------------
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
for p in "$HOME"/Library/Python/3.*/bin; do [ -d "$p" ] && PATH="$p:$PATH"; done
export PATH

if ! command -v python3 >/dev/null 2>&1; then
  echo "${RED}❌ Python 3 مش موجود.${R} ثبّت Homebrew من https://brew.sh وشغّل تاني."; exit 1
fi

echo "${Y}بجهّز أداة التفريغ (أول مرة بس، ممكن تاخد دقايق)…${R}"
if ! python3 -c "import faster_whisper" >/dev/null 2>&1; then
  python3 -m pip install --user -q -U faster-whisper >/dev/null 2>&1 \
    || python3 -m pip install --user -q -U --break-system-packages faster-whisper >/dev/null 2>&1 || true
fi
if ! python3 -c "import faster_whisper" >/dev/null 2>&1; then
  echo "${RED}❌ مقدرتش أثبّت faster-whisper.${R}"
  echo "   جرّب تكتب في التريمنال: python3 -m pip install --user faster-whisper"
  exit 1
fi
echo "${G}✅ جاهز.${R}"

# --- اكتب سكربت البايثون اللي بيعمل التفريغ -----------------------------------
cat > "$HELPER" <<'PYEOF'
#!/usr/bin/env python3
# بيدوّر على الفيديوهات ويطلّع .txt لكل واحد (faster-whisper). مكتبة قياسية + faster_whisper.
import os, sys
VIDEO_EXTS = (".mp4", ".mov", ".m4v", ".mkv", ".webm", ".avi", ".m4a", ".mp3", ".wav")

def find_videos(paths):
    vids = []
    for p in paths:
        p = os.path.expanduser(p)
        if os.path.isfile(p) and p.lower().endswith(VIDEO_EXTS):
            vids.append(p)
        elif os.path.isdir(p):
            for root, _, files in os.walk(p):
                for f in files:
                    if f.lower().endswith(VIDEO_EXTS) and not f.startswith("."):
                        vids.append(os.path.join(root, f))
    return sorted(set(vids))

def main():
    out_dir = os.path.expanduser(sys.argv[1])
    model_size = sys.argv[2]
    lang = sys.argv[3].strip() or None
    inputs = sys.argv[4:]
    os.makedirs(out_dir, exist_ok=True)

    vids = find_videos(inputs)
    if not vids:
        print("NO_VIDEOS"); return

    pending = []
    for v in vids:
        stem = os.path.splitext(os.path.basename(v))[0]
        out = os.path.join(out_dir, stem + ".txt")
        if os.path.exists(out) and os.path.getsize(out) > 0:
            continue
        pending.append((v, out))

    print("FOUND %d videos | %d need transcription | %d already done"
          % (len(vids), len(pending), len(vids) - len(pending)))
    if not pending:
        print("ALL_DONE"); return

    from faster_whisper import WhisperModel
    print("Loading model '%s' (first time downloads it once)…" % model_size)
    model = WhisperModel(model_size, device="cpu", compute_type="int8")

    def run(v, vad):
        segments, info = model.transcribe(v, language=lang, vad_filter=vad)
        lines = [s.text.strip() for s in segments if s.text.strip()]
        return lines, info

    done = 0
    for i, (v, out) in enumerate(pending, 1):
        name = os.path.basename(v)
        print("[%d/%d] %s …" % (i, len(pending), name))
        try:
            try:
                lines, info = run(v, True)
            except Exception:
                lines, info = run(v, False)
            with open(out, "w", encoding="utf-8") as f:
                f.write("\n".join(lines) + ("\n" if lines else ""))
            print("      OK -> %s  (lang=%s)" % (os.path.basename(out), getattr(info, "language", "?")))
            done += 1
        except Exception as e:
            print("      ERROR: %s" % e)
    print("DONE %d/%d" % (done, len(pending)))

if __name__ == "__main__":
    main()
PYEOF

# --- اللوب الرئيسي ------------------------------------------------------------
echo
echo "${D}اسحب فيديو أو فولدر هنا واضغط Return،${R}"
echo "${D}أو اضغط Return على طول علشان أفرّغ كل الفيديوهات في TikTok_Videos و Instagram_Downloads.${R}"
while true; do
  echo
  printf "%sالمدخل (اسحب هنا أو Return للكل، أو q للخروج): %s" "$B" "$R"
  if ! read -r INPUT; then break; fi
  case "$INPUT" in q|Q|quit|exit) break ;; esac

  if [ -z "$INPUT" ]; then
    INPUTS=("$HOME/Desktop/TikTok_Videos" "$HOME/Desktop/Instagram_Downloads")
  else
    # نظّف المسار من علامات التنصيص والباك-سلاش بتاعة السحب والإفلات
    INPUT="$(printf '%s' "$INPUT" | sed 's/\\ / /g')"
    INPUT="${INPUT%\"}"; INPUT="${INPUT#\"}"
    INPUT="${INPUT%\'}"; INPUT="${INPUT#\'}"
    INPUTS=("$INPUT")
  fi

  python3 "$HELPER" "$OUT" "$WHISPER_MODEL" "$WHISPER_LANG" "${INPUTS[@]}"
  echo "${G}✅ النصوص الجاهزة في: $OUT${R}"
done

echo
echo "${B}خلصنا.${R}  📝 كل النصوص في: $OUT"
exit 0
