# -*- coding: utf-8 -*-
r"""生成「忘川检索」应用图标候选方案（预览用）。

输出到 docs\icons\ ：
  - candA_*.png ... 每个方案一张 512x512 预览
  - 图标方案对比.png  多尺寸对比总览（用于挑选）
"""
import os
from PIL import Image, ImageDraw, ImageFont


# ---- 路径：全部按"本脚本所在位置"推算，克隆到任何目录下都能直接跑 ----
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

OUT = os.path.join(_ROOT, 'docs', 'icons')
os.makedirs(OUT, exist_ok=True)

SS = 4               # 超采样倍数
BASE = 512           # 最终边长
C = BASE * SS

KAI = r'C:\Windows\Fonts\simkai.ttf'
LI = r'C:\Windows\Fonts\SIMLI.TTF'
HEI = r'C:\Windows\Fonts\simhei.ttf'

# 配色（沿用需求文档里的中国风色板）
PAPER = (247, 241, 227)
PAPER_D = (239, 228, 206)
VERM = (158, 43, 37)      # 朱砂 #9E2B25
VERM_L = (192, 57, 43)    # 高亮 #C0392B
GOLD = (176, 138, 62)     # 描金 #B08A3E
INK = (43, 33, 24)        # 墨色 #2B2118


def rounded_mask(size, radius, ss):
    m = Image.new('L', (size * ss, size * ss), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([0, 0, size * ss - 1, size * ss - 1], radius=radius * ss, fill=255)
    return m


def circle_mask(size, ss):
    m = Image.new('L', (size * ss, size * ss), 0)
    d = ImageDraw.Draw(m)
    d.ellipse([0, 0, size * ss - 1, size * ss - 1], fill=255)
    return m


def vtext(draw, chars, font, cx, cy, fill, gap_ratio=0.06):
    """竖排两字居中绘制。"""
    boxes = [draw.textbbox((0, 0), ch, font=font) for ch in chars]
    heights = [b[3] - b[1] for b in boxes]
    gap = int(font.size * gap_ratio)
    total = sum(heights) + gap * (len(chars) - 1)
    y = cy - total / 2
    for ch, b, h in zip(chars, boxes, heights):
        w = b[2] - b[0]
        draw.text((cx - w / 2 - b[0], y - b[1]), ch, font=font, fill=fill)
        y += h + gap


def vtext_gold_outline(draw, chars, font, cx, cy, fill, outline, width):
    """竖排两字，带描边（仿鎏金/描边印章效果）。"""
    boxes = [draw.textbbox((0, 0), ch, font=font, stroke_width=width) for ch in chars]
    heights = [b[3] - b[1] for b in boxes]
    gap = int(font.size * 0.06)
    total = sum(heights) + gap * (len(chars) - 1)
    y = cy - total / 2
    for ch, b, h in zip(chars, boxes, heights):
        w = b[2] - b[0]
        draw.text((cx - w / 2 - b[0] - width, y - b[1] - width), ch, font=font, fill=fill,
                  stroke_width=width, stroke_fill=outline)
        y += h + gap


def new_canvas(bg=(0, 0, 0, 0)):
    return Image.new('RGBA', (C, C), bg)


def save(img, name):
    out = img.resize((BASE, BASE), Image.LANCZOS)
    p = os.path.join(OUT, name)
    out.save(p)
    print('saved', p)
    return out


# ---------------------------------------------------------------- 方案 A
def cand_a():
    """朱砂方印 + 描金内框 + 米白「忘川」（阳文印章感）"""
    img = new_canvas((0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    body = Image.new('RGBA', (C, C), VERM + (255,))
    bd = ImageDraw.Draw(body)
    for i in range(C):                       # 竖向渐变，避免死板
        t = i / C
        col = tuple(int(VERM[k] + (VERM_L[k] - VERM[k]) * t) for k in range(3))
        bd.line([(0, i), (C, i)], fill=col + (255,), width=1)
    img.paste(body, (0, 0), rounded_mask(BASE, 88, SS))
    d = ImageDraw.Draw(img)
    m = int(C * 0.085)
    d.rounded_rectangle([m, m, C - m - 1, C - m - 1], radius=int(C * 0.045),
                        outline=GOLD + (235,), width=int(C * 0.016))
    f = ImageFont.truetype(KAI, int(C * 0.36))
    vtext(d, '忘川', f, C / 2, C / 2 + C * 0.005, PAPER + (255,))
    return save(img, 'candA_朱砂方印.png')


# ---------------------------------------------------------------- 方案 B
def cand_b():
    """米宣纸底 + 朱砂双线框 + 墨色「忘川」+ 角上小印"""
    img = new_canvas((0, 0, 0, 0))
    body = Image.new('RGBA', (C, C), PAPER + (255,))
    bd = ImageDraw.Draw(body)
    for i in range(C):
        t = i / C
        col = tuple(int(PAPER[k] + (PAPER_D[k] - PAPER[k]) * t) for k in range(3))
        bd.line([(0, i), (C, i)], fill=col + (255,), width=1)
    img.paste(body, (0, 0), rounded_mask(BASE, 88, SS))
    d = ImageDraw.Draw(img)
    o = int(C * 0.055)
    w = int(C * 0.020)
    d.rounded_rectangle([o, o, C - o - 1, C - o - 1], radius=int(C * 0.030),
                        outline=VERM + (255,), width=w)
    i2 = o + int(C * 0.017)
    d.rounded_rectangle([i2, i2, C - i2 - 1, C - i2 - 1], radius=int(C * 0.026),
                        outline=GOLD + (210,), width=max(2, int(C * 0.006)))
    f = ImageFont.truetype(KAI, int(C * 0.355))
    vtext(d, '忘川', f, C / 2, C / 2 - C * 0.01, INK + (255,))
    # 右下角小朱砂印
    s = int(C * 0.135)
    x0, y0 = int(C - o - C * 0.055 - s), int(C - o - C * 0.055 - s)
    d.rounded_rectangle([x0, y0, x0 + s, y0 + s], radius=int(C * 0.012), fill=VERM_L + (255,))
    fs = ImageFont.truetype(LI, int(s * 0.72))
    tb = d.textbbox((0, 0), '索', font=fs)
    d.text((x0 + s / 2 - (tb[2] - tb[0]) / 2 - tb[0], y0 + s / 2 - (tb[3] - tb[1]) / 2 - tb[1]),
           '索', font=fs, fill=PAPER + (255,))
    return save(img, 'candB_宣纸墨字.png')


# ---------------------------------------------------------------- 方案 C
def cand_c():
    """朱砂圆印 + 描金双圈 + 米白「忘川」（最像一枚印章）"""
    img = new_canvas((0, 0, 0, 0))
    body = Image.new('RGBA', (C, C), VERM + (255,))
    bd = ImageDraw.Draw(body)
    for i in range(C):
        t = i / C
        col = tuple(int(VERM[k] + (VERM_L[k] - VERM[k]) * t) for k in range(3))
        bd.line([(0, i), (C, i)], fill=col + (255,), width=1)
    img.paste(body, (0, 0), circle_mask(BASE, SS))
    d = ImageDraw.Draw(img)
    r1 = int(C * 0.415)
    d.ellipse([C / 2 - r1, C / 2 - r1, C / 2 + r1, C / 2 + r1],
              outline=GOLD + (235,), width=int(C * 0.020))
    r2 = int(C * 0.365)
    d.ellipse([C / 2 - r2, C / 2 - r2, C / 2 + r2, C / 2 + r2],
              outline=GOLD + (120,), width=max(2, int(C * 0.006)))
    f = ImageFont.truetype(KAI, int(C * 0.30))
    vtext(d, '忘川', f, C / 2, C / 2 + C * 0.004, PAPER + (255,))
    return save(img, 'candC_朱砂圆印.png')


# ---------------------------------------------------------------- 方案 D
def cand_d():
    """单字「忘」大字 + 朱砂方底 + 金边（小尺寸最清楚）"""
    img = new_canvas((0, 0, 0, 0))
    body = Image.new('RGBA', (C, C), VERM + (255,))
    bd = ImageDraw.Draw(body)
    for i in range(C):
        t = i / C
        col = tuple(int(VERM[k] + (VERM_L[k] - VERM[k]) * t) for k in range(3))
        bd.line([(0, i), (C, i)], fill=col + (255,), width=1)
    img.paste(body, (0, 0), rounded_mask(BASE, 88, SS))
    d = ImageDraw.Draw(img)
    m = int(C * 0.085)
    d.rounded_rectangle([m, m, C - m - 1, C - m - 1], radius=int(C * 0.045),
                        outline=GOLD + (235,), width=int(C * 0.016))
    f = ImageFont.truetype(KAI, int(C * 0.52))
    tb = d.textbbox((0, 0), '忘', font=f)
    d.text((C / 2 - (tb[2] - tb[0]) / 2 - tb[0], C / 2 - (tb[3] - tb[1]) / 2 - tb[1]),
           '忘', font=f, fill=PAPER + (255,))
    return save(img, 'candD_单字忘.png')


# ---------------------------------------------------------------- 对比总览
def montage(imgs):
    pad, gap = 28, 30
    row_h = 150
    W = pad * 2 + 512 + gap + 3 * 96 + gap * 3 + 300
    H = pad * 2 + row_h * len(imgs) + gap * (len(imgs) - 1)
    sheet = Image.new('RGB', (W, H), PAPER)
    d = ImageDraw.Draw(sheet)
    f_label = ImageFont.truetype(HEI, 26)
    f_small = ImageFont.truetype(HEI, 18)
    labels = ['方案 A · 朱砂方印', '方案 B · 宣纸墨字', '方案 C · 朱砂圆印', '方案 D · 单字「忘」']
    y = pad
    for img, lab in zip(imgs, labels):
        sheet.paste(img.resize((140, 140), Image.LANCZOS), (pad, y + 5), img.resize((140, 140), Image.LANCZOS))
        d.text((pad + 160, y + 34), lab, font=f_label, fill=INK)
        d.text((pad + 160, y + 74), '桌面显示尺寸预览 →', font=f_small, fill=(120, 105, 88))
        x = pad + 512 + gap
        for size in (144, 96, 72, 48):
            sheet.paste(img.resize((size, size), Image.LANCZOS), (x, y + (140 - size) // 2),
                        img.resize((size, size), Image.LANCZOS))
            x += size + gap
        d.line([(pad, y + row_h - 6), (W - pad, y + row_h - 6)], fill=GOLD, width=1)
        y += row_h + gap
    p = os.path.join(OUT, '图标方案对比.png')
    sheet.save(p)
    print('saved', p)
    return p


if __name__ == '__main__':
    imgs = [cand_a(), cand_b(), cand_c(), cand_d()]
    montage(imgs)
