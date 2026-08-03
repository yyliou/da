# 由其他腳本 source 進去：自動尋找 quarto、Rscript 與 pandoc
# 依序找：目前 PATH → Homebrew → 官方安裝位置 → RStudio 內建 → conda 環境
# 設定三個變數：QUARTO、RSCRIPT、PANDOC（找不到則為空字串）
# 另外會 export RSTUDIO_PANDOC，讓 rmarkdown::render() 找得到 pandoc。

_resolve_link() {
  # macOS 沒有 readlink -f，自己解析 symlink
  _t=$1
  _n=0
  while [ -L "$_t" ] && [ "$_n" -lt 20 ]; do
    _d=$(dirname "$_t")
    _l=$(readlink "$_t")
    case "$_l" in
      /*) _t=$_l ;;
      *)  _t="$_d/$_l" ;;
    esac
    _n=$((_n + 1))
  done
  echo "$_t"
}

_find_bin() {
  _name=$1
  if command -v "$_name" >/dev/null 2>&1; then
    command -v "$_name"
    return 0
  fi
  for _p in \
    "/opt/homebrew/bin/$_name" \
    "/usr/local/bin/$_name" \
    "/Applications/quarto/bin/$_name" \
    "/Applications/RStudio.app/Contents/Resources/app/quarto/bin/$_name" \
    "/Applications/RStudio.app/Contents/MacOS/quarto/bin/$_name" \
    "/Applications/RStudio.app/Contents/Resources/app/bin/$_name" \
    "/Library/Frameworks/R.framework/Resources/bin/$_name" \
    "$HOME/miniconda3/bin/$_name" \
    "$HOME/anaconda3/bin/$_name" \
    "$HOME/opt/miniconda3/bin/$_name" \
    "$HOME/opt/anaconda3/bin/$_name" \
    "/opt/miniconda3/bin/$_name" \
    "/opt/anaconda3/bin/$_name" \
    "$HOME"/miniconda3/envs/*/bin/"$_name" \
    "$HOME"/anaconda3/envs/*/bin/"$_name" \
    "$HOME"/opt/miniconda3/envs/*/bin/"$_name" \
    "$HOME"/opt/anaconda3/envs/*/bin/"$_name" \
    /opt/miniconda3/envs/*/bin/"$_name" \
    /opt/anaconda3/envs/*/bin/"$_name"
  do
    [ -x "$_p" ] && { echo "$_p"; return 0; }
  done
  return 1
}

QUARTO=$(_find_bin quarto || echo "")
RSCRIPT=$(_find_bin Rscript || echo "")
PANDOC=$(_find_bin pandoc || echo "")

# 找不到獨立的 pandoc 時，借用 Quarto 內建的那一份
if [ -z "$PANDOC" ] && [ -n "$QUARTO" ]; then
  _qdir=$(dirname "$(_resolve_link "$QUARTO")")
  for _p in \
    "$_qdir"/tools/*/pandoc \
    "$_qdir"/tools/pandoc \
    "$_qdir"/../tools/*/pandoc \
    "$_qdir"/../tools/pandoc \
    /Applications/quarto/bin/tools/*/pandoc \
    /Applications/quarto/bin/tools/pandoc
  do
    [ -x "$_p" ] && { PANDOC=$_p; break; }
  done
fi

# RStudio 內建的 pandoc（最後手段）
if [ -z "$PANDOC" ]; then
  for _p in \
    /Applications/RStudio.app/Contents/Resources/app/bin/pandoc/pandoc \
    /Applications/RStudio.app/Contents/MacOS/pandoc/pandoc
  do
    [ -x "$_p" ] && { PANDOC=$_p; break; }
  done
fi

# rmarkdown::render() 會讀這個環境變數
if [ -n "$PANDOC" ]; then
  RSTUDIO_PANDOC=$(dirname "$PANDOC")
  export RSTUDIO_PANDOC
fi
