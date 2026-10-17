r"""生成「忘川检索」在 HarmonyOS 工程里使用的图标资源。

与 H:\workarea\fhlSearch\图标 那套导出图**同源**：同一组绘制参数
（朱砂竖向渐变 + 描金双圈 + 楷体竖排「忘川」），只是按 HarmonyOS 的形态与尺寸重画：

    AppScope/resources/base/media/foreground.png        512x512    分层图标·前景（内容收在安全区）
    AppScope/resources/base/media/background.png       1024x1024   分层图标·背景（朱砂渐变）
    entry/.../media/foreground.png                      512x512    同上（entry 模块自己也要一份）
    entry/.../media/background.png                     1024x1024
    entry/.../media/startIcon.png                      1024x1024   启动页图标：标准**圆角正方形**

用法：python scripts\gen_harmony_icons.py
"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP_MEDIA = os.path.join(ROOT, 'AppScope', 'resources', 'base', 'media')
ENTRY_MEDIA = os.path.join(ROOT, 'entry', 'src', 'main', 'resources', 'base', 'media')
KAI = r'C:\Windows\Fonts\simkai.ttf'

VERM = (158, 43, 37)      # 朱砂
VERM_L = (192, 57, 43)    # 朱砂（亮）
GOLD = (176, 138, 62)     # 描金
PAPER = (247, 241, 227)   # 米白

SS = 4                    # 4 倍超采样后缩回，保证小尺寸下笔画清晰


def _gradient(n):
    """朱砂竖向渐变底"""
    body = Image.new('RGBA', (n, n), VERM + (255,))
    bd = ImageDraw.Draw(body)
    for i in range(n):
        t = i / n
        col = tuple(int(VERM[k] + (VERM_L[k] - VERM[k]) * t) for k in range(3))
        bd.line([(0, i), (n, i)], fill=col + (255,), width=1)
    return body


def _text_vertical(d, n, ratio):
    """竖排「忘川」"""
    f = ImageFont.truetype(KAI, int(n * ratio))
    boxes = [d.textbbox((0, 0), ch, font=f) for ch in '忘川']
    hs = [b[3] - b[1] for b in boxes]
    gap = int(f.size * 0.05)
    y = n / 2 - (sum(hs) + gap) / 2
    for ch, b, h in zip('忘川', boxes, hs):
        w = b[2] - b[0]
        d.text((n / 2 - w / 2 - b[0], y - b[1]), ch, font=f, fill=PAPER + (255,))
        y += h + gap


def _rings(d, n, r_ring, r_inner, ring_w):
    """描金双圈"""
    d.ellipse([n / 2 - r_ring, n / 2 - r_ring, n / 2 + r_ring, n / 2 + r_ring],
              outline=GOLD + (235,), width=ring_w)
    d.ellipse([n / 2 - r_inner, n / 2 - r_inner, n / 2 + r_inner, n / 2 + r_inner],
              outline=GOLD + (120,), width=max(1, int(n * 0.006)))


def seal_layered_foreground(size):
    """分层图标前景：朱砂铺满（与背景层同色，接缝不可见），金圈与文字收在中心安全区内。"""
    n = size * SS
    img = _gradient(n)
    d = ImageDraw.Draw(img)
    _rings(d, n, n * 0.265, n * 0.231, max(2, int(n * 0.016)))
    _text_vertical(d, n, 0.235)
    return img.resize((size, size), Image.LANCZOS)


def seal_background(size):
    """分层图标背景：纯朱砂渐变"""
    n = size * SS
    return _gradient(n).resize((size, size), Image.LANCZOS)


def seal_rounded_square(size, radius_ratio=0.225):
    """标准圆角正方形图标：圆角方形朱砂底 + 描金双圈 + 竖排「忘川」。

    radius_ratio 0.225 ≈ 系统方图标的常规圆角比例（四角透明，浮在启动页底色上）。
    """
    n = size * SS
    img = _gradient(n)
    mask = Image.new('L', (n, n), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, n - 1, n - 1],
                                           radius=int(n * radius_ratio), fill=255)
    out = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    d = ImageDraw.Draw(out)
    _rings(d, n, n * 0.380, n * 0.330, max(2, int(n * 0.020)))
    _text_vertical(d, n, 0.280)
    return out.resize((size, size), Image.LANCZOS)


def main():
    targets = [
        (os.path.join(APP_MEDIA, 'foreground.png'), lambda: seal_layered_foreground(512)),
        (os.path.join(APP_MEDIA, 'background.png'), lambda: seal_background(1024)),
        (os.path.join(ENTRY_MEDIA, 'foreground.png'), lambda: seal_layered_foreground(512)),
        (os.path.join(ENTRY_MEDIA, 'background.png'), lambda: seal_background(1024)),
        (os.path.join(ENTRY_MEDIA, 'startIcon.png'), lambda: seal_rounded_square(1024)),
    ]
    for path, make in targets:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        img = make()
        img.save(path)
        print('%-70s %dx%d' % (path.replace(ROOT + os.sep, ''), img.size[0], img.size[1]))


if __name__ == '__main__':
    main()
