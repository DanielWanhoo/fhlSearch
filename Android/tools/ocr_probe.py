# -*- coding: utf-8 -*-
r"""在电脑上复现 PoemOcr 的取格几何，先把"图难在哪"量出来（**不跑 OCR**，秒级）。

图片识别出问题时，第一件事是分清"格子切歪了"还是"字认错了"：
这个脚本只算几何，不碰 ML Kit，所以在电脑上跑，不用装机、不用等识别。

用法：
    python tools\ocr_probe.py <图片> [--art 格子序号,格子序号] [--montage 输出.png]

输出：
  * 图片尺寸 / 是否按 EXIF 旋转
  * 面板检测结果、整图与面板各自的切格结果（行带 / 列带 / 每格尺寸）
  * 倾斜估计（-8..8 度，暗像素投影最锐的角度）
  * 每格墨迹占比、极性、对比度（能看出"这格几乎没字"还是"字被切掉一半"）
  * 可选：把某几格打成 ASCII 点阵，肉眼核对切格正不正

配套脚本：
    tools\ocr_one.py       —— 在手机上真跑一遍并拉回拼板 PNG
    tools\montage_cell.py  —— 看拼板里某一格到底长什么样（送进 ML Kit 的图形）
"""
import io
import os
import sys

import numpy as np
from PIL import Image, ImageOps

COLS, ROWS = 6, 5
MAX_SIDE = 2200


# ------------------------------------------------------------------ 基础
def load(path, max_side=MAX_SIDE):
    im = Image.open(path)
    im = ImageOps.exif_transpose(im)
    im = im.convert('L')
    w, h = im.size
    if max(w, h) > max_side:
        k = max_side / max(w, h)
        nw, nh = max(1, round(w * k)), max(1, round(h * k))
        im = im.resize((nw, nh), Image.BILINEAR)
        return np.asarray(im, dtype=np.float32), True
    return np.asarray(im, dtype=np.float32), False


def otsu(a):
    a = a.astype(np.int32).clip(0, 255)
    hist = np.bincount(a.ravel(), minlength=256).astype(np.float64)
    n = hist.sum()
    if n == 0:
        return 120
    om = (np.arange(256) * hist).sum() / n
    wB = np.cumsum(hist)
    sumB = np.cumsum(np.arange(256) * hist)
    wF = n - wB
    mB = np.divide(sumB, wB, out=np.zeros(256), where=wB > 0)
    mF = np.divide(om - sumB, wF, out=np.zeros(256), where=wF > 0)
    between = wB * wF * (mB - mF) ** 2
    return int(np.argmax(between))


def bands(proj, thresh, min_len):
    out = []
    st = -1
    for i, v in enumerate(proj):
        if v > thresh:
            if st < 0:
                st = i
        elif st >= 0:
            if i - st >= min_len:
                out.append((st, i - 1))
            st = -1
    if st >= 0 and len(proj) - st >= min_len:
        out.append((st, len(proj) - 1))
    return out


def longest_band(frac, thresh, min_len):
    out = bands(frac, thresh, min_len)
    if not out:
        return None
    return max(out, key=lambda b: b[1] - b[0])


def find_panel(g):
    h, w = g.shape
    rl = (g > 195).sum(axis=1) / w
    b = longest_band(rl, 0.45, max(50, h // 12))
    if b is None:
        return None
    y0, y1 = b
    cl = (g[y0:y1 + 1] > 195).sum(axis=0) / (y1 - y0 + 1)
    cb = longest_band(cl, 0.45, max(50, w // 12))
    if cb is None:
        return None
    return (cb[0], y0, cb[1], y1)


def pick_best(lst, need):
    if len(lst) > need:
        lst = sorted(sorted(lst, key=lambda b: -(b[1] - b[0]))[:need])
    return sorted(lst, key=lambda b: b[0])


def find_grid(g, box):
    x0, y0, x1, y1 = box
    reg = g[y0:y1 + 1, x0:x1 + 1]
    pw, ph = reg.shape[1], reg.shape[0]
    if pw < 30 or ph < 30:
        return None
    thr = max(60, min(180, otsu(reg)))
    dark = reg < thr
    row_proj = dark.sum(axis=1)
    col_proj = dark.sum(axis=0)
    rb = pick_best(bands(row_proj, max(2, pw // 400), max(8, ph // 40)), ROWS)
    cb = pick_best(bands(col_proj, max(2, ph // 400), max(8, pw // 40)), COLS)
    return dict(thr=thr, rows=[(a + y0, b + y0) for a, b in rb],
                cols=[(a + x0, b + x0) for a, b in cb],
                rows_raw=len(rb), cols_raw=len(cb),
                rows_all=len(bands(row_proj, max(2, pw // 400), max(8, ph // 40))),
                cols_all=len(bands(col_proj, max(2, ph // 400), max(8, pw // 40))))


def skew_estimate(g, box, span=8.0, step=0.5):
    """在 box 内按角度旋转，取"行投影峰谷比"最大的角度（正数=图需逆时针转）"""
    x0, y0, x1, y1 = box
    reg = g[y0:y1 + 1, x0:x1 + 1]
    thr = max(60, min(180, otsu(reg)))
    dark = (reg < thr).astype(np.float32)
    h, w = dark.shape
    best, best_score = 0.0, -1.0
    scores = []
    for ang in np.arange(-span, span + 1e-9, step):
        # 用 PIL 旋转（扩展画布），再算行投影的方差（字行越分开方差越大）
        im = Image.fromarray((dark * 255).astype(np.uint8))
        r = im.rotate(ang, resample=Image.BILINEAR, expand=True, fillcolor=0)
        a = np.asarray(r, dtype=np.float32) / 255.0
        proj = a.sum(axis=1)
        score = float(np.var(proj))
        scores.append((ang, score))
        if score > best_score:
            best_score, best = score, ang
    return best, scores


def cell_stats(g, rows, cols):
    out = []
    for r, (ry0, ry1) in enumerate(rows):
        line = []
        for c, (cx0, cx1) in enumerate(cols):
            cell = g[max(0, ry0 - 4):ry1 + 5, max(0, cx0 - 4):cx1 + 5]
            n = cell.size
            p2, p50, p98 = (np.percentile(cell, q) for q in (2, 50, 98))
            bg = p50
            dark_glyph = (bg - p2) >= (p98 - bg)
            ink_lo = bg - p98 if dark_glyph else p2 - bg
            ink_hi = bg - p2 if dark_glyph else p98 - bg
            span = max(1e-6, ink_hi - ink_lo)
            raw = (bg - cell) if dark_glyph else (cell - bg)
            a = np.clip((raw - ink_lo) / span, 0, 1)
            ink = float((a > 0.35).mean())
            line.append(dict(w=cx1 - cx0 + 1, h=ry1 - ry0 + 1, p2=int(p2),
                             p50=int(p50), p98=int(p98), dark=dark_glyph,
                             span=int(ink_hi - ink_lo), ink=round(ink, 3),
                             px=n))
        out.append(line)
    return out


def cell_art(g, ry, cx, size=28):
    y0, y1 = ry
    x0, x1 = cx
    cell = g[max(0, y0 - 4):y1 + 5, max(0, x0 - 4):x1 + 5]
    p2, p50, p98 = (np.percentile(cell, q) for q in (2, 50, 98))
    bg = p50
    dark_glyph = (bg - p2) >= (p98 - bg)
    ink_lo = bg - p98 if dark_glyph else p2 - bg
    ink_hi = bg - p2 if dark_glyph else p98 - bg
    span = max(1e-6, ink_hi - ink_lo)
    raw = (bg - cell) if dark_glyph else (cell - bg)
    a = np.clip((raw - ink_lo) / span, 0, 1)
    img = Image.fromarray((a * 255).astype(np.uint8)).resize((size, size), Image.BILINEAR)
    ap = np.asarray(img, dtype=np.float32) / 255.0
    chars = ' .:-=+*#%@'
    lines = []
    for row in ap:
        lines.append(''.join(chars[min(9, int(v * 9.999))] for v in row))
    return lines


def main():
    path = sys.argv[1]
    art = None
    montage = None
    if '--art' in sys.argv:
        art = [int(x) for x in sys.argv[sys.argv.index('--art') + 1].split(',')]
    if '--montage' in sys.argv:
        montage = sys.argv[sys.argv.index('--montage') + 1]

    g, scaled = load(path)
    h, w = g.shape
    print('图片 %dx%d%s' % (w, h, '（已缩到 2200）' if scaled else ''))
    panel = find_panel(g)
    print('面板:', panel)

    cands = []
    if panel and panel != (0, 0, w - 1, h - 1):
        cands.append(('面板', panel))
    cands.append(('整图', (0, 0, w - 1, h - 1)))

    chosen = None
    for name, box in cands:
        r = find_grid(g, box)
        size = '%dx%d' % (box[2] - box[0] + 1, box[3] - box[1] + 1)
        if r is None:
            print('%s %s -> 区域太小' % (name, size))
            continue
        ok = len(r['rows']) == ROWS and len(r['cols']) == COLS
        print('%s %s -> %s  (otsu=%d, 行 %d/%d, 列 %d/%d)'
              % (name, size, '5x6' if ok else '不是 5x6', r['thr'],
                 len(r['rows']), r['rows_all'], len(r['cols']), r['cols_all']))
        if not ok:
            print('    行带:', r['rows'])
            print('    列带:', r['cols'])
        if ok and chosen is None:
            chosen = (name, box, r)
    if chosen is None:
        print('没切出 5x6，后面跳过')
        return
    name, box, r = chosen
    print('采用:', name)
    print('行带:', r['rows'])
    print('列带:', r['cols'])

    ang, scores = skew_estimate(g, box)
    top = sorted(scores, key=lambda t: -t[1])[:5]
    print('倾斜估计: %.1f 度  前五: %s'
          % (ang, ', '.join('%.1f:%.0f' % t for t in top)))

    st = cell_stats(g, r['rows'], r['cols'])
    print('每格 (宽×高 墨迹占比 p2/50/98 span 深字?):')
    for i, line in enumerate(st):
        cells = ['%dx%d %.2f %d/%d/%d %d%s' % (c['w'], c['h'], c['ink'], c['p2'],
                                              c['p50'], c['p98'], c['span'],
                                              'D' if c['dark'] else 'L')
                 for c in line]
        print('  行%d %s' % (i, ' | '.join(cells)))

    if montage:
        # 复现拼板，方便和手机端 dump 的对比
        M, GAP = 240, 80
        sheet = Image.new('L', (COLS * M + (COLS + 1) * GAP,
                                ROWS * M + (ROWS + 1) * GAP), 255)
        pil = Image.fromarray(g.clip(0, 255).astype(np.uint8))
        for rr, (ry0, ry1) in enumerate(r['rows']):
            for cc, (cx0, cx1) in enumerate(r['cols']):
                cell = g[max(0, ry0 - 4):ry1 + 5, max(0, cx0 - 4):cx1 + 5]
                p2, p50, p98 = (np.percentile(cell, q) for q in (2, 50, 98))
                bg = p50
                dark_glyph = (bg - p2) >= (p98 - bg)
                ink_lo = bg - p98 if dark_glyph else p2 - bg
                ink_hi = bg - p2 if dark_glyph else p98 - bg
                span = max(1e-6, ink_hi - ink_lo)
                raw = (bg - cell) if dark_glyph else (cell - bg)
                a = np.clip((raw - ink_lo) / span, 0, 1)
                small = Image.fromarray(((1 - a) * 255).astype(np.uint8))
                k = M / max(small.size)
                small = small.resize((max(1, round(small.width * k)),
                                      max(1, round(small.height * k))), Image.BILINEAR)
                dx = GAP + cc * (M + GAP) + (M - small.width) // 2
                dy = GAP + rr * (M + GAP) + (M - small.height) // 2
                sheet.paste(small, (dx, dy))
        sheet.save(montage)
        print('拼板已存:', montage)

    if art:
        for idx in art:
            rr, cc = divmod(idx, COLS)
            print('--- 格 #%d (行%d 列%d) %s' % (idx, rr, cc,
                                                art_header(st, rr, cc)))
            for ln in cell_art(g, r['rows'][rr], r['cols'][cc]):
                print('   ' + ln)


def art_header(st, rr, cc):
    c = st[rr][cc]
    return '%dx%d ink=%.2f p2/50/98=%d/%d/%d' % (c['w'], c['h'], c['ink'], c['p2'],
                                                 c['p50'], c['p98'])


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    main()
