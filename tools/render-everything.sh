#!/bin/sh
# 一鍵重新渲染整個課程專案：
#   1. ch1–ch17 中英文講義（呼叫 tools/render-all.sh）
#   2. 課堂練習 da-ps/ex1–ex12
#   3. 課程網站 web/
#   4. 把網站輸出同步到 repo 根目錄（GitHub Pages 發佈位置）
#   5. 課綱 PDF（sylla/syllabus.Rmd，需要 R + rmarkdown）
#
# 用法（在 da 資料夾下）：
#     sh tools/render-everything.sh            # 全部
#     sh tools/render-everything.sh 13 17      # 講義只渲染第 13–17 章，其餘照常

set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

FAIL=""

echo "===== 1/5 講義 ch1–ch17（中英文）====="
sh tools/render-all.sh "$@" || FAIL="$FAIL render-all"

echo ""
echo "===== 2/5 課堂練習 da-ps/ex1–ex12 ====="
for f in da-ps/ex*.qmd; do
  echo "--- quarto render $f"
  quarto render "$f" >/dev/null 2>&1 || { echo "    FAILED: $f"; FAIL="$FAIL $f"; }
done

echo ""
echo "===== 3/5 課程網站 web/ ====="
( cd web && quarto render ) || FAIL="$FAIL web"

echo ""
echo "===== 4/5 同步網站輸出到根目錄 ====="
for f in index prob r slide sylla; do
  cp "web/$f.html" "./$f.html" && echo "  synced $f.html"
done
[ -f web/search.json ] && cp web/search.json ./search.json
if [ -d web/site_libs ]; then
  rsync -a --delete web/site_libs/ site_libs/ && echo "  synced site_libs/"
fi
mkdir -p hex && cp -f web/hex/da.svg hex/da.svg 2>/dev/null

echo ""
echo "===== 5/5 課綱 PDF ====="
Rscript -e 'rmarkdown::render("sylla/syllabus.Rmd")' \
  || { echo "  syllabus PDF 渲染失敗（檢查 R / rmarkdown / tinytex）"; FAIL="$FAIL syllabus"; }

echo ""
if [ -n "$FAIL" ]; then
  echo "完成，但以下項目失敗：$FAIL"
  echo "（講義失敗細節見 tools/render-logs/）"
  exit 1
else
  echo "全部渲染完成。"
fi
