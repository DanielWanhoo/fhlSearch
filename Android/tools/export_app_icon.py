# -*- coding: utf-8 -*-
r"""把应用图标导出成 PNG，统一放到工作区的「图标」目录。

产物（docs/icons\）：
  忘川检索_图标_1024.png            高清方图（圆印本体）
  忘川检索_图标_512.png             常用大图
  忘川检索_图标_256.png             中等
  忘川检索_图标_192.png             应用商店/预览常用尺寸
  忘川检索_图标_圆形_512.png         圆形裁切版
  忘川检索_自适应图标_合成_432.png    自适应图标合成效果（看得见的那部分）
  忘川检索_自适应图标_前景_432.png    自适应图标前景层（透明底 + 描金圈 + 忘川）
  忘川检索_自适应图标_背景_432.png    自适应图标背景层（朱砂渐变）
  忘川检索_单色图标_432.png          Android 13+ 主题化图标（白色剪影，透明底）
  图标尺寸一览.png                   48/72/96/144/192 各密度并排

绘制逻辑与 android 里的 mipmap 完全同源（直接复用 tools\gen_app_icon.py），
所以导出图和装机后看到的图标一致。
"""
import io
import os
import sys

from PIL import Image, ImageDraw, ImageFont


# ---- 路径：全部按"本脚本所在位置"推算，克隆到任何目录下都能直接跑 ----
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

sys.path.insert(0, os.path.join(_ROOT, 'tools'))
import gen_app_icon as g  # noqa: E402

OUT = os.path.join(_ROOT, 'docs', 'icons')


def gradient_square(size):
    """朱砂竖向渐变方块（自适应图标的背景层）"""
    ss = 4
    n = size * ss
    img = Image.new('RGBA', (n, n), g.VERM + (255,))
    d = ImageDraw.Draw(img)
    for i in range(n):
        t = i / n
        col = tuple(int(g.VERM[k] + (g.VERM_L[k] - g.VERM[k]) * t) for k in range(3))
        d.line([(0, i), (n, i)], fill=col + (255,), width=1)
    return img.resize((size, size), Image.LANCZOS)


def transparent_foreground(size):
    """自适应图标前景层：透明底 + 描金双圈 + 米白「忘川」（缩在安全区内）"""
    ss = 4
    n = size * ss
    img = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    r_ring = n * 0.265
    r_inner = n * 0.231
    d.ellipse([n / 2 - r_ring, n / 2 - r_ring, n / 2 + r_ring, n / 2 + r_ring],
              outline=g.GOLD + (235,), width=max(2, int(n * 0.016)))
    d.ellipse([n / 2 - r_inner, n / 2 - r_inner, n / 2 + r_inner, n / 2 + r_inner],
              outline=g.GOLD + (120,), width=max(1, int(n * 0.006)))

    f = ImageFont.truetype(g.KAI, int(n * 0.235))
    boxes = [d.textbbox((0, 0), ch, font=f) for ch in '忘川']
    hs = [b[3] - b[1] for b in boxes]
    gap = int(f.size * 0.05)
    y = n / 2 - (sum(hs) + gap) / 2
    for ch, b, h in zip('忘川', boxes, hs):
        w = b[2] - b[0]
        d.text((n / 2 - w / 2 - b[0], y - b[1]), ch, font=f, fill=g.PAPER + (255,))
        y += h + gap
    return img.resize((size, size), Image.LANCZOS)


def sheet():
    """各密度并排一览：48 / 72 / 96 / 144 / 192"""
    sizes = [48, 72, 96, 144, 192]
    pad, gap, label_h = 28, 26, 34
    W = pad * 2 + sum(sizes) + gap * (len(sizes) - 1)
    H = pad * 2 + max(sizes) + label_h
    im = Image.new('RGBA', (W, H), g.PAPER + (255,))
    d = ImageDraw.Draw(im)
    f = ImageFont.truetype(g.KAI, 20)
    x = pad
    for s in sizes:
        icon = g.draw_seal(s)
        im.paste(icon, (x, pad + (max(sizes) - s) // 2), icon)
        txt = '%d px' % s
        tw = d.textbbox((0, 0), txt, font=f)[2]
        d.text((x + s / 2 - tw / 2, pad + max(sizes) + 8), txt, font=f, fill=(107, 91, 75, 255))
        x += s + gap
    return im


def main():
    os.makedirs(OUT, exist_ok=True)
    written = []

    def save(img, name):
        p = os.path.join(OUT, name)
        img.save(p)
        written.append((name, os.path.getsize(p), img.size))

    # 常规方图
    for px in (1024, 512, 256, 192):
        save(g.draw_seal(px), '忘川检索_图标_%d.png' % px)

    # 圆形
    save(g.circular(g.draw_seal(512)), '忘川检索_图标_圆形_512.png')

    # 自适应图标：合成效果 / 前景 / 背景
    save(g.draw_seal(432, compact=True), '忘川检索_自适应图标_合成_432.png')
    save(transparent_foreground(432), '忘川检索_自适应图标_前景_432.png')
    save(gradient_square(432), '忘川检索_自适应图标_背景_432.png')

    # 主题化单色图标
    save(g.draw_mono(432), '忘川检索_单色图标_432.png')

    # 一览
    save(sheet(), '图标尺寸一览.png')

    lines = ['导出目录: %s' % OUT, '']
    for name, size_b, wh in written:
        lines.append('  %-40s %5dx%-5d %8.1f KB' % (name, wh[0], wh[1], size_b / 1024))
    report = '\n'.join(lines)
    io.open(os.path.join(OUT, '说明.txt'), 'w', encoding='utf-8').write(
        '忘川检索 · 应用图标（PNG 导出）\n'
        '================================\n\n'
        '图标方案：方案 C · 朱砂圆印（朱砂渐变圆底 + 描金双圈 + 米白「忘川」竖排，楷体）\n'
        '与安装包内使用的图标完全同源（同一份绘制代码 tools\\gen_app_icon.py）。\n\n'
        + report +
        '\n\n各文件用途：\n'
        '  图标_1024/512/256/192   —— 通用方图，发文章、做图、应用商店都能用\n'
        '  图标_圆形_512           —— 需要圆形头像/圆形图标时用\n'
        '  自适应图标_合成_432      —— Android 8+ 自适应图标实际显示的效果（中间 66.7% 是安全区）\n'
        '  自适应图标_前景_432      —— 前景层（透明底），可与任意背景合成\n'
        '  自适应图标_背景_432      —— 背景层（朱砂竖向渐变）\n'
        '  单色图标_432            —— Android 13+ 主题化图标用的白色剪影\n'
        '  图标尺寸一览            —— 48/72/96/144/192 各密度并排，看小尺寸下的清晰度\n'
    )
    print(report)
    print('\n说明.txt 已写入')


if __name__ == '__main__':
    main()
