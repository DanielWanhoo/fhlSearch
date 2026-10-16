# -*- coding: utf-8 -*-
"""
生成程序图标：朱砂方印（圆角正方形）+ 描金双框 + 竖排「忘川」（楷体·阴文）。

与《忘川检索》安卓版图标同一套美术：
    朱砂竖向渐变 #9E2B25 → #C0392B ／ 描金 #B08A3E ／ 米白 #F7F1E3 ／ 楷体 simkai
区别只有外形：安卓是朱砂圆印，Windows 这边用圆角正方形（桌面图标的常规形状）。

每个尺寸都按 4 倍超采样单独绘制，保证 16/24/32 px 下笔画依然清晰。

用法: python tools/make_icon.py

输出：
    src/FhlSearch/Resources/app.ico     多尺寸 ICO（16/24/32/48/64/128/256）
    _dev/icon_preview.png              尺寸一览，用于肉眼检查
"""
import sys, os

try:
    sys.stdout.reconfigure(errors='replace')
except Exception:
    pass

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # 项目根目录
OUT = os.path.join(ROOT, r"src\FhlSearch\Resources\app.ico")
PREVIEW = os.path.join(ROOT, r"_dev\icon_preview.png")

KAI = r"C:\Windows\Fonts\simkai.ttf"

VERM = (158, 43, 37)     # #9E2B25
VERM_L = (192, 57, 43)   # #C0392B
GOLD = (176, 138, 62)    # #B08A3E
PAPER = (247, 241, 227)  # #F7F1E3

# 圆角正方形印记的各段比例（相对边长）
R_BODY = 0.205   # 外轮廓圆角
INSET_F = 0.085  # 描金外框距边
R_FRAME = 0.135  # 描金外框圆角
W_FRAME = 0.022  # 描金外框线宽
INSET_I = 0.126  # 内细线距边
R_INNER = 0.108  # 内细线圆角
FONT_RATIO = 0.30

ICO_SIZES = [256, 128, 64, 48, 32, 24, 16]


def _font(size):
    return ImageFont.truetype(KAI, size)


def draw_seal(size):
    """画一枚朱砂方印，返回 size×size 的 RGBA 图。"""
    ss = 4
    n = size * ss
    img = Image.new('RGBA', (n, n), (0, 0, 0, 0))

    # ① 朱砂底：竖向渐变，裁成圆角正方形
    body = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    bd = ImageDraw.Draw(body)
    for i in range(n):
        t = i / max(1, n - 1)
        col = tuple(int(VERM[k] + (VERM_L[k] - VERM[k]) * t) for k in range(3)) + (255,)
        bd.line([(0, i), (n, i)], fill=col, width=1)
    mask = Image.new('L', (n, n), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, n - 1, n - 1], radius=int(n * R_BODY), fill=255)
    img.paste(body, (0, 0), mask)

    d = ImageDraw.Draw(img)

    # ② 描金双框
    f0, f1 = int(n * INSET_F), n - 1 - int(n * INSET_F)
    d.rounded_rectangle([f0, f0, f1, f1], radius=int(n * R_FRAME),
                        outline=GOLD + (235,), width=max(2, int(n * W_FRAME)))
    i0, i1 = int(n * INSET_I), n - 1 - int(n * INSET_I)
    d.rounded_rectangle([i0, i0, i1, i1], radius=int(n * R_INNER),
                        outline=GOLD + (120,), width=max(1, int(n * 0.007)))

    # ③ 竖排「忘川」（阴文：米白）
    f = _font(int(n * FONT_RATIO))
    boxes = [d.textbbox((0, 0), ch, font=f) for ch in '忘川']
    hs = [b[3] - b[1] for b in boxes]
    gap = int(f.size * 0.05)
    y = n / 2 - (sum(hs) + gap) / 2
    for ch, b, h in zip('忘川', boxes, hs):
        w = b[2] - b[0]
        d.text((n / 2 - w / 2 - b[0], y - b[1]), ch, font=f, fill=PAPER + (255,))
        y += h + gap

    return img.resize((size, size), Image.LANCZOS)


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    os.makedirs(os.path.dirname(PREVIEW), exist_ok=True)

    # 大尺寸再降采样会糊掉小图，所以每个尺寸都单独绘制
    frames = {s: draw_seal(s) for s in ICO_SIZES}
    frames[256].save(OUT, format="ICO",
                     sizes=[(s, s) for s in ICO_SIZES])
    print("图标已生成:", OUT, os.path.getsize(OUT), "bytes")
    print("包含尺寸:", ICO_SIZES)

    # 尺寸一览：1:1 摆放，方便看小尺寸清晰度
    strip = [256, 128, 64, 48, 32, 24, 16]
    pad = 24
    W = sum(strip) + pad * (len(strip) + 1)
    H = 256 + pad * 2
    sheet = Image.new("RGBA", (W, H), (247, 241, 227, 255))
    x = pad
    for s in strip:
        sheet.paste(frames[s], (x, pad), frames[s])
        x += s + pad
    sheet.save(PREVIEW)
    print("预览图:", PREVIEW)


if __name__ == "__main__":
    main()
