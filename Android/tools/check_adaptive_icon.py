r"""检查自适应图标前景被裁切后的实际效果（模拟 Android 的裁切规则）。

Android 8+ 自适应图标：108dp 画布，系统只显示中间 72dp（66.7%），
并可能裁成圆、方、圆角方等形状。这里把 432px 前景按各种形状裁一遍，
拼成一张对照图，确认「忘川」二字与金圈不会被切到。
"""
import os
from PIL import Image, ImageDraw


# ---- 路径：全部按"本脚本所在位置"推算，克隆到任何目录下都能直接跑 ----
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

RES = os.path.join(_ROOT, 'app', 'src', 'main', 'res')
PREVIEW = os.path.join(_ROOT, 'docs', 'icons')
FG = os.path.join(RES, 'drawable-xxxhdpi', 'ic_launcher_foreground.png')
BG_COLOR = (158, 43, 37, 255)

fg = Image.open(FG).convert('RGBA')
n = fg.size[0]
body = Image.new('RGBA', (n, n), BG_COLOR)
full = Image.alpha_composite(body, fg)

# 安全区：中心 72/108
safe = int(n * 72 / 108)
off = (n - safe) // 2
crop = full.crop((off, off, off + safe, off + safe))


def shape_mask(size, kind):
    m = Image.new('L', (size, size), 0)
    d = ImageDraw.Draw(m)
    if kind == 'circle':
        d.ellipse([0, 0, size - 1, size - 1], fill=255)
    elif kind == 'rounded':
        d.rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * 0.22), fill=255)
    else:
        d.rectangle([0, 0, size - 1, size - 1], fill=255)
    return m


kinds = [('circle', '圆形裁切'), ('rounded', '圆角方形'), ('square', '全方形')]
S = 300
sheet = Image.new('RGB', (S * 3 + 80, S + 110), (247, 241, 227))
sd = ImageDraw.Draw(sheet)
from PIL import ImageFont
f = ImageFont.truetype(r'C:\Windows\Fonts\simhei.ttf', 22)

for i, (kind, label) in enumerate(kinds):
    tile = crop.resize((S, S), Image.LANCZOS)
    # 先按形状裁掉画布外区域（模拟系统裁切），再贴到宣纸底上
    masked = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    masked.paste(tile, (0, 0), shape_mask(S, kind))
    backdrop = Image.new('RGBA', (S, S), (247, 241, 227, 255))
    flat = Image.alpha_composite(backdrop, masked).convert('RGB')
    sheet.paste(flat, (20 + i * (S + 20), 60))
    sd.text((20 + i * (S + 20), 24), label, font=f, fill=(43, 33, 24))
    # 同时给出桌面小尺寸观感
    sheet.paste(flat.resize((72, 72), Image.LANCZOS), (20 + i * (S + 20) + S - 84, 60 + S - 84))

out = os.path.join(PREVIEW, '自适应图标裁切检查.png')
sheet.save(out)
print('saved', out)
print('前景尺寸', fg.size, '安全区裁切尺寸', crop.size)
