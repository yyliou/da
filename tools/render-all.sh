#!/bin/sh
# 重新渲染全部 ch1–ch17 中英文講義
#
# 用法（在 da 資料夾下）：
#     sh tools/render-all.sh              # 全部 34 份
#     sh tools/render-all.sh 15           # 只渲染第 15 章（中英文）
#     sh tools/render-all.sh 13 17        # 渲染第 13–17 章
#
# 特性：
#   - 單一章節失敗不會中斷整批，最後會列出成功／失敗清單
#   - 每份的完整輸出寫到 tools/render-logs/<檔名>.log，失敗時可回頭查
#   - Quarto 需已安裝並在 PATH 中

set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LOGDIR="$ROOT/tools/render-logs"
mkdir -p "$LOGDIR"

LO=${1:-1}
HI=${2:-${1:-17}}

if ! command -v quarto >/dev/null 2>&1; then
  echo "找不到 quarto 指令。請先安裝 Quarto，或改用 RStudio 逐章 Render。"
  exit 1
fi

echo "Quarto 版本：$(quarto --version)"
echo "渲染範圍：第 $LO – $HI 章"
echo "紀錄位置：$LOGDIR"
echo ""

OK=""
FAIL=""
START=$(date +%s)

i=$LO
while [ "$i" -le "$HI" ]; do
  for suffix in "" "-zh"; do
    NAME="ch${i}${suffix}"
    FILE="$ROOT/ch${i}/${NAME}.qmd"
    [ -f "$FILE" ] || continue

    printf "  %-10s " "$NAME"
    T0=$(date +%s)
    if (cd "$ROOT/ch${i}" && quarto render "${NAME}.qmd") >"$LOGDIR/${NAME}.log" 2>&1; then
      T1=$(date +%s)
      echo "✓ 完成 ($((T1 - T0)) 秒)"
      OK="$OK $NAME"
    else
      T1=$(date +%s)
      echo "✗ 失敗 ($((T1 - T0)) 秒) → $LOGDIR/${NAME}.log"
      FAIL="$FAIL $NAME"
    fi
  done
  i=$((i + 1))
done

END=$(date +%s)
echo ""
echo "───────────────────────────────────────────"
echo "總耗時 $(((END - START) / 60)) 分 $(((END - START) % 60)) 秒"
echo "成功：$(echo $OK | wc -w | tr -d ' ') 份"
if [ -n "$FAIL" ]; then
  echo "失敗：$(echo $FAIL | wc -w | tr -d ' ') 份 →$FAIL"
  echo ""
  echo "各失敗檔的錯誤摘要："
  for f in $FAIL; do
    echo "  --- $f ---"
    grep -iE "^error|^!|could not find function|there is no package|cannot open" "$LOGDIR/${f}.log" | head -3 | sed 's/^/      /'
  done
  exit 1
fi
echo "全部成功。接著可執行：python tools/check_overflow.py"
