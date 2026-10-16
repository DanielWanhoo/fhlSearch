# -*- coding: utf-8 -*-
"""测量截图中的关键边线位置，反推实际 DPI 缩放。

【一次性脚本】v1 界面（带回纹带 / 金线）时期用来量 DPI 的，v1.1 重构后界面里
已经没有回纹带和金线，这个脚本不再适用，留档而已。

用法: python tools/oneoff/measure_shot.py <截图.png>
"""
import sys, io, os
# 输出跟随系统编码（中文 Windows 的 cmd 是 GBK），只把编不出来的字符降级，避免抛异常。
# 需要强制 UTF-8 时，设环境变量 PYTHONIOENCODING=utf-8。
try:
    sys.stdout.reconfigure(errors='replace')
except Exception:
    pass
from PIL import Image

p = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "_dev", "shot01.png")
im = Image.open(p).convert("RGB")
W, H = im.size
print(f"截图尺寸: {W} x {H}")
px = im.load()

# 1) 找回纹带：一行里"金色像素"最多的 y
def is_gold(c):
    r, g, b = c
    return r > 140 and 100 < g < 215 and b < 150 and (r - b) > 40

best_y, best_n = 0, 0
for y in range(min(240, H)):
    n = sum(1 for x in range(0, W, 3) if is_gold(px[x, y]))
    if n > best_n:
        best_n, best_y = n, y
print(f"回纹带起始 y ≈ {best_y}  (金色像素 {best_n} 个/采样)")

# 2) 找侧栏右边线：在 y=300 这一行，从右往左... 改为从左往右找第一条竖直金线
def col_gold_ratio(x, y0, y1):
    n = 0
    for y in range(y0, y1):
        if is_gold(px[x, y]):
            n += 1
    return n / max(1, (y1 - y0))

y0, y1 = best_y + 40, min(H, best_y + 400)
cands = [(x, col_gold_ratio(x, y0, y1)) for x in range(0, min(600, W))]
cands = [c for c in cands if c[1] > 0.5]
print("竖向金线候选 x:", [c[0] for c in cands][:20])

# 3) 侧栏底色（比宣纸深）分界：找一行里颜色突变的 x
row = best_y + 200
prev = px[0, row]
print(f"\ny={row} 行，颜色突变的 x：")
for x in range(1, W):
    c = px[x, row]
    if abs(c[0]-prev[0]) + abs(c[1]-prev[1]) + abs(c[2]-prev[2]) > 26:
        print(f"   x={x:4d}  {prev} -> {c}")
    prev = c
