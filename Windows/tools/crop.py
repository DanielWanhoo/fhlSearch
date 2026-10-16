# -*- coding: utf-8 -*-
"""从截图里裁剪一块并放大，方便检查细节。用法: python tools/crop.py <png> <out> x y w h [zoom]"""
import sys, io
# 输出跟随系统编码（中文 Windows 的 cmd 是 GBK），只把编不出来的字符降级，避免抛异常。
# 需要强制 UTF-8 时，设环境变量 PYTHONIOENCODING=utf-8。
try:
    sys.stdout.reconfigure(errors='replace')
except Exception:
    pass
from PIL import Image

src, out = sys.argv[1], sys.argv[2]
x, y, w, h = (int(v) for v in sys.argv[3:7])
zoom = int(sys.argv[7]) if len(sys.argv) > 7 else 2
im = Image.open(src).convert("RGB")
box = im.crop((x, y, x + w, y + h))
box = box.resize((box.width * zoom, box.height * zoom), Image.LANCZOS)
box.save(out)
print(f"裁剪 ({x},{y},{w},{h}) 放大 {zoom}x -> {out}  {box.size}")
