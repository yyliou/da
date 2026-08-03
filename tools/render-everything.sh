#!/bin/sh
# 一鍵重新渲染整個課程專案：
#   1. ch1–ch17 中英文講義（呼叫 tools/render-all.sh）
#   2. 課堂練習 da-ps/ex1–ex12
#   3. 課程網站 web/
#   4. 把網站輸出同步到 repo 根目錄（GitHub Pages 發佈位置）
#   5. 課綱 PDF（sylla/syllabus.Rmd）
#   6. 系統指南 PDF（prompt/da-system-guide.Rmd）
#
# 用法（在 da 資料夾下）：
#     sh tools/render-everything.sh            # 全部
#     sh tools/render-everything.sh 13 17      # 講義只渲染第 13–17 章，其餘照常
#
# 失敗不中斷，最後列出失敗清單並以非 0 結束；
# 每份的詳細訊息都寫到 tools/render-logs/。

set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 1
LOGDIR="$ROOT/tools/render-logs"
mkdir -p "$LOGDIR"

. "$ROOT/tools/find-tools.sh"
if [ -z "$QUARTO" ]; then
  echo "找不到 quarto 指令。"
  echo "  - 若 quarto 裝在 conda 環境中，請先 conda activate <環境名> 再執行"
  echo "  - 或安裝 Quarto：https://quarto.org/docs/get-started/"
  exit 1
fi
echo "Quarto：$QUARTO"
[ -n "$RSCRIPT" ] && echo "Rscript：${RSCRIPT}" || echo "Rscript：找不到（第 5、6 步會略過）"
[ -n "$PANDOC" ] && echo "pandoc：${PANDOC}" || echo "pandoc：找不到（PDF 會失敗）"
echo ""

FAIL=""

echo "===== 1/6 講義 ch1–ch17（中英文）====="
if [ $# -gt 0 ]; then
  sh tools/render-all.sh "$@" || FAIL="$FAIL render-all"
else
  sh tools/render-all.sh || FAIL="$FAIL render-all"
fi

echo ""
echo "===== 2/6 課堂練習 da-ps/ex1–ex12 ====="
for f in da-ps/ex*.qmd; do
  [ -e "$f" ] || { echo "  找不到 da-ps/ex*.qmd"; break; }
  b=$(basename "$f" .qmd)
  printf '  %-8s ' "$b"
  if "$QUARTO" render "$f" >"$LOGDIR/$b.log" 2>&1; then
    echo "✓"
  else
    echo "✗ 失敗 → tools/render-logs/$b.log"
    FAIL="$FAIL $b"
  fi
done

echo ""
echo "===== 3/6 課程網站 web/ ====="
( cd web && "$QUARTO" render ) >"$LOGDIR/web.log" 2>&1 \
  && echo "  ✓ 網站渲染完成" \
  || { echo "  ✗ 失敗 → tools/render-logs/web.log"; FAIL="$FAIL web"; }

echo ""
echo "===== 4/6 同步網站輸出到根目錄 ====="
# pCloud Drive 上直接 cp 覆蓋既有檔案，可能回報成功但內容沒有真的寫入，
# 因此一律「先刪除目的檔、再複製、最後用 cmp 驗證」。
sync_one() {
  _src=$1; _dst=$2
  rm -f "$_dst" 2>/dev/null
  cp "$_src" "$_dst" 2>/dev/null || return 1
  cmp -s "$_src" "$_dst"          # 內容真的一致才算成功
}
for f in web/*.html; do
  [ -e "$f" ] || { echo "  web/ 下沒有 .html，略過"; break; }
  b=$(basename "$f")
  if sync_one "$f" "./$b"; then
    echo "  ✓ $b"
  else
    echo "  ✗ $b 同步後內容仍不一致"
    FAIL="$FAIL sync:$b"
  fi
done
if [ -f web/search.json ]; then
  sync_one web/search.json ./search.json && echo "  ✓ search.json" \
    || { echo "  ✗ search.json"; FAIL="$FAIL sync:search.json"; }
fi
# 注意：pCloud Drive 的 FUSE 檔案系統不支援 rsync 的 rename 操作
# （會出現 "Socket is not connected"），因此一律用 cp 合併。
if [ -d web/site_libs ]; then
  mkdir -p site_libs
  if cp -R web/site_libs/. site_libs/; then
    echo "  ✓ site_libs/"
  else
    echo "  ✗ site_libs/ 複製失敗"
    FAIL="$FAIL sync:site_libs"
  fi
fi
if [ -d web/hex ]; then
  mkdir -p hex
  cp -f web/hex/*.svg hex/ && echo "  ✓ hex/" || FAIL="$FAIL sync:hex"
fi

echo ""
echo "===== 5/6 課綱 PDF ====="
if [ -z "$RSCRIPT" ]; then
  echo "  略過（找不到 Rscript）"
elif "$RSCRIPT" -e 'rmarkdown::render("sylla/syllabus.Rmd", quiet = TRUE)' >"$LOGDIR/syllabus.log" 2>&1; then
  echo "  ✓ sylla/syllabus.pdf"
else
  echo "  ✗ 失敗 → tools/render-logs/syllabus.log（檢查 rmarkdown / tinytex）"
  FAIL="$FAIL syllabus"
fi

echo ""
echo "===== 6/6 系統指南 PDF ====="
if [ -z "$RSCRIPT" ]; then
  echo "  略過（找不到 Rscript）"
elif "$RSCRIPT" -e 'rmarkdown::render("prompt/da-system-guide.Rmd", quiet = TRUE)' >"$LOGDIR/da-system-guide.log" 2>&1; then
  echo "  ✓ prompt/da-system-guide.pdf"
else
  echo "  ✗ 失敗 → tools/render-logs/da-system-guide.log"
  FAIL="$FAIL da-system-guide"
fi

echo ""
if [ -n "$FAIL" ]; then
  echo "完成，但以下項目失敗：$FAIL"
  echo "（細節見 tools/render-logs/）"
  exit 1
else
  echo "全部渲染完成。"
fi
