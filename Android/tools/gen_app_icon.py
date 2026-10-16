r"""生成忘川检索的应用图标（方案 C · 朱砂圆印）。

按 Android 各密度直接绘制，不使用降采样，保证小尺寸下笔画清晰：
    mipmap-mdpi     48px
    mipmap-hdpi     72px
    mipmap-xhdpi    96px
    mipmap-xxhdpi   144px
    mipmap-xxxhdpi  192px
    drawable-xxxhdpi 432px  （自适应图标前景，安全区已留足）

同时输出 512px 预览到 docs\icons\app_icon_512.png。
"""
import os
from PIL import Image, ImageDraw, ImageFont


# ---- 路径：全部按"本脚本所在位置"推算，克隆到任何目录下都能直接跑 ----
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

RES = os.path.join(_ROOT, 'app', 'src', 'main', 'res')
PREVIEW = os.path.join(_ROOT, 'docs', 'icons')
KAI = r'C:\Windows\Fonts\simkai.ttf'

VERM = (158, 43, 37)
VERM_L = (192, 57, 43)
GOLD = (176, 138, 62)
PAPER = (247, 241, 227)


def draw_seal(size, compact=False):
    """绘制一枚朱砂圆印。

    compact=False：整张画布＝印章（用于 mipmap 老式图标，48~192px）。
    compact=True ：内容收缩到中心（用于自适应图标前景——系统只显示中间 66.7%，
                    并可能裁成圆形/圆角方形，所以金圈与文字都要留在安全区内）。
    """
    ss = 4
    n = size * ss
    img = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    if compact:
        # 自适应图标：画满朱砂底（背景层也是同色，接缝不可见）
        body = Image.new('RGBA', (n, n), VERM + (255,))
        bd = ImageDraw.Draw(body)
        for i in range(n):
            t = i / n
            col = tuple(int(VERM[k] + (VERM_L[k] - VERM[k]) * t) for k in range(3))
            bd.line([(0, i), (n, i)], fill=col + (255,), width=1)
        img.paste(body, (0, 0))
        d = ImageDraw.Draw(img)
        r_ring = n * 0.265          # 安全半径 0.333，留足边距
        r_inner = n * 0.231
        ring_w = max(2, int(n * 0.016))
        font_ratio = 0.235
    else:
        body = Image.new('RGBA', (n, n), VERM + (255,))
        bd = ImageDraw.Draw(body)
        for i in range(n):
            t = i / n
            col = tuple(int(VERM[k] + (VERM_L[k] - VERM[k]) * t) for k in range(3))
            bd.line([(0, i), (n, i)], fill=col + (255,), width=1)
        mask = Image.new('L', (n, n), 0)
        ImageDraw.Draw(mask).ellipse([0, 0, n - 1, n - 1], fill=255)
        img.paste(body, (0, 0), mask)
        d = ImageDraw.Draw(img)
        r_ring = n * 0.415
        r_inner = n * 0.362
        ring_w = max(2, int(n * 0.020))
        font_ratio = 0.30

    # 描金双圈
    d.ellipse([n / 2 - r_ring, n / 2 - r_ring, n / 2 + r_ring, n / 2 + r_ring],
              outline=GOLD + (235,), width=ring_w)
    d.ellipse([n / 2 - r_inner, n / 2 - r_inner, n / 2 + r_inner, n / 2 + r_inner],
              outline=GOLD + (120,), width=max(1, int(n * 0.006)))

    # 竖排「忘川」
    f = ImageFont.truetype(KAI, int(n * font_ratio))
    boxes = [d.textbbox((0, 0), ch, font=f) for ch in '忘川']
    hs = [b[3] - b[1] for b in boxes]
    gap = int(f.size * 0.05)
    total = sum(hs) + gap
    y = n / 2 - total / 2
    for ch, b, h in zip('忘川', boxes, hs):
        w = b[2] - b[0]
        d.text((n / 2 - w / 2 - b[0], y - b[1]), ch, font=f, fill=PAPER + (255,))
        y += h + gap

    return img.resize((size, size), Image.LANCZOS)


def circular(img):
    """把方形前景裁成圆形（mipmap 老式图标用）"""
    n = img.size[0]
    out = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    mask = Image.new('L', (n, n), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, n - 1, n - 1], fill=255)
    out.paste(img, (0, 0), mask)
    return out


def draw_mono(size):
    """主题化图标（Android 13+ 单色图标）：白色描金圈 + 竖排「忘川」剪影，透明底。
    系统只取 alpha 通道作为遮罩，所以画成纯白即可。"""
    ss = 4
    n = size * ss
    img = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r_ring = n * 0.265
    d.ellipse([n / 2 - r_ring, n / 2 - r_ring, n / 2 + r_ring, n / 2 + r_ring],
              outline=(255, 255, 255, 255), width=max(2, int(n * 0.016)))
    f = ImageFont.truetype(KAI, int(n * 0.235))
    boxes = [d.textbbox((0, 0), ch, font=f) for ch in '忘川']
    hs = [b[3] - b[1] for b in boxes]
    gap = int(f.size * 0.05)
    y = n / 2 - (sum(hs) + gap) / 2
    for ch, b, h in zip('忘川', boxes, hs):
        w = b[2] - b[0]
        d.text((n / 2 - w / 2 - b[0], y - b[1]), ch, font=f, fill=(255, 255, 255, 255))
        y += h + gap
    return img.resize((size, size), Image.LANCZOS)


def main():
    densities = {
        'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192,
    }
    for dens, px in densities.items():
        d = os.path.join(RES, 'mipmap-' + dens)
        os.makedirs(d, exist_ok=True)
        square = draw_seal(px)                    # 圆印本身：方图内是圆形印
        square.save(os.path.join(d, 'ic_launcher.png'))
        circular(square).save(os.path.join(d, 'ic_launcher_round.png'))
        print('mipmap-%-8s %3dpx' % (dens, px))

    # 自适应图标前景（432dp @ xxxhdpi = 432px；内容收缩到安全区内）
    # 同时按密度各出一张：xxxhdpi=432 / xxhdpi=288 / xhdpi=216（比例一致，系统按需取用）
    for dens, px in (('xxxhdpi', 432), ('xxhdpi', 288), ('xhdpi', 216)):
        fd = os.path.join(RES, 'drawable-' + dens)
        os.makedirs(fd, exist_ok=True)
        draw_seal(px, compact=True).save(os.path.join(fd, 'ic_launcher_foreground.png'))
        draw_mono(px).save(os.path.join(fd, 'ic_launcher_mono.png'))
        print('drawable-%-8s ic_launcher_foreground.png / ic_launcher_mono.png %dpx' % (dens, px))

    os.makedirs(PREVIEW, exist_ok=True)
    big = draw_seal(512)
    big.save(os.path.join(PREVIEW, 'app_icon_512.png'))
    big.resize((192, 192), Image.LANCZOS).save(os.path.join(PREVIEW, 'app_icon_192.png'))
    print('preview:', os.path.join(PREVIEW, 'app_icon_512.png'))


if __name__ == '__main__':
    main()
