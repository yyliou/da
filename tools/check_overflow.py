#!/usr/bin/env python3
"""檢查 Quarto reveal.js 講義是否有內容超出投影片邊界（「跑掉」）。

用法：
    pip install playwright
    playwright install chromium
    python tools/check_overflow.py            # 檢查全部 ch1-ch17 中英文版
    python tools/check_overflow.py 15         # 只檢查第 15 章
    python tools/check_overflow.py 13 17      # 檢查第 13-17 章

重要：本腳本會逐張「實際顯示」投影片後才量測。
不能用離線量測（把 section 設成 display:block 後量高度），因為 Quarto 的
r-stretch 會在投影片顯示時才把圖片縮放到剛好填滿剩餘空間；離線量測時圖片
維持原始大尺寸，會產生大量誤報（實測 ch9 誤報 18 張，實際 0 張）。

輸出說明：
  超出邊界  - 內容超過 700px，因為 scrollable:false 會被直接切掉，需要修
  壓到頁尾  - 內容落在 645-700px。含 r-stretch 圖片者屬正常（圖片本來就
              會填滿剩餘空間，多半停在 688px），不必理會
"""
import sys, os, json
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parent.parent

LIVE_JS = r"""
() => {
  const SC = Reveal.getScale();
  const cfg = Reveal.getConfig();
  const SH = cfg.height, SW = cfg.width;
  const s = document.querySelector('section.present:not(.stack)');
  if (!s) return null;
  const sr = s.getBoundingClientRect();
  let maxBottom = 0, worst = '', worstTxt = '';
  s.querySelectorAll('*').forEach(el => {
    if (!el.getClientRects().length) return;
    const cs = getComputedStyle(el);
    if (cs.position === 'fixed') return;
    if (el.closest('.footer, .slide-logo, .slide-number')) return;
    if (cs.visibility === 'hidden' || cs.display === 'none') return;
    const r = el.getBoundingClientRect();
    const bot = (r.bottom - sr.top) / SC;
    if (bot > maxBottom) {
      maxBottom = bot;
      worst = el.tagName.toLowerCase();
      worstTxt = (el.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 50);
    }
  });
  // 只計算「可見字元」的最右緣：pre-wrap 會讓換行處的空白懸在邊界外，
  // 那是看不見的，不該算成溢出
  let maxVis = 0;
  const w = document.createTreeWalker(s, NodeFilter.SHOW_TEXT);
  while (w.nextNode()) {
    const n = w.currentNode, t = n.textContent;
    for (let i = 0; i < t.length; i++) {
      if (/\s/.test(t[i])) continue;
      const rg = document.createRange(); rg.setStart(n, i); rg.setEnd(n, i + 1);
      const b = rg.getBoundingClientRect();
      if (b.width) maxVis = Math.max(maxVis, (b.right - sr.left) / SC);
    }
  }
  s.querySelectorAll('img').forEach(im => {
    const b = im.getBoundingClientRect();
    if (b.width) maxVis = Math.max(maxVis, (b.right - sr.left) / SC);
  });
  const h = s.querySelector('h1,h2,h3');
  let title = h ? h.textContent.trim() : '';
  if (!title) title = '(無標題) ' + s.textContent.trim().replace(/\s+/g, ' ').slice(0, 45);
  return {
    title: title.slice(0, 80),
    maxBottom: Math.round(maxBottom),
    overflowV: Math.round(maxBottom - SH),
    footerHit: Math.round(maxBottom - 645),
    overflowH: Math.round(maxVis - SW),
    worst, worstTxt,
    nImg: s.querySelectorAll('img').length,
  };
}
"""


def scan(pg, path):
    pg.goto("file://" + str(path), wait_until="load")
    try:
        pg.wait_for_function("() => window.Reveal && Reveal.isReady && Reveal.isReady()", timeout=20000)
    except Exception:
        pass
    pg.evaluate("""() => Promise.all([...document.images]
        .filter(i => !i.complete).map(i => new Promise(r => { i.onload = i.onerror = r; })))""")
    pg.wait_for_timeout(400)
    n = pg.evaluate("""() => [...document.querySelectorAll('.reveal .slides section')]
        .filter(s => !s.querySelector(':scope > section')).length""")
    out = []
    for i in range(n):
        pg.evaluate(f"""() => {{
            const all = [...document.querySelectorAll('.reveal .slides section')]
              .filter(s => !s.querySelector(':scope > section'));
            const ix = Reveal.getIndices(all[{i}]);
            Reveal.slide(ix.h, ix.v || 0); Reveal.layout();
        }}""")
        pg.wait_for_timeout(70)
        pg.evaluate("""() => { const s=document.querySelector('section.present:not(.stack)');
            if(s) s.querySelectorAll('.fragment').forEach(f=>f.classList.add('visible')); Reveal.layout(); }""")
        pg.wait_for_timeout(40)
        r = pg.evaluate(LIVE_JS)
        if r:
            r["i"] = i
            out.append(r)
    return out


def main():
    args = [int(a) for a in sys.argv[1:]]
    if not args:      lo, hi = 1, 17
    elif len(args) == 1: lo = hi = args[0]
    else:             lo, hi = args[0], args[1]

    targets = []
    for i in range(lo, hi + 1):
        for name in (f"ch{i}", f"ch{i}-zh"):
            p = ROOT / f"ch{i}" / f"{name}.html"
            if p.exists():
                targets.append((name, p))
    if not targets:
        print("找不到任何 .html，請先 quarto render")
        return 1

    problems, total = [], 0
    with sync_playwright() as p:
        b = p.chromium.launch()
        pg = b.new_page(viewport={"width": 1400, "height": 950})
        for name, path in targets:
            sl = scan(pg, path)
            total += len(sl)
            bad = [s for s in sl if s["overflowV"] > 0 or s["overflowH"] > 0]
            problems += [(name, s) for s in bad]
            flag = "  <<<" if bad else ""
            print(f"{name:>10}: {len(sl):>3} 張，問題 {len(bad):>2}{flag}", flush=True)
        b.close()

    print(f"\n{'='*58}\n共 {len(targets)} 份 / {total} 張投影片，發現 {len(problems)} 張有問題")
    if not problems:
        print("全部通過，沒有內容被切掉。")
        return 0
    print()
    for name, s in sorted(problems, key=lambda r: -r[1]["overflowV"]):
        kind = []
        if s["overflowV"] > 0: kind.append(f"垂直超出 {s['overflowV']}px")
        if s["overflowH"] > 0: kind.append(f"右緣超出 {s['overflowH']}px")
        print(f"  {name:>9} 第{s['i']+1:>2}張  {'、'.join(kind)}")
        print(f"            {s['title'][:60]}")
        print(f"            └ 被切元素 <{s['worst']}>: {s['worstTxt'][:55]}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
