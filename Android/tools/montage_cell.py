# -*- coding: utf-8 -*-
r"""把拼板 PNG 里指定的格子打成 ASCII，看看送进 ML Kit 的实际图形。

用法：python tools\montage_cell.py <拼板.png> 12,13,14 [--size 34]
格子序号按行优先（0..29），与 PoemOcr 的 COLS=6/ROWS=5 一致。

拼板从哪来：给 App 发测试广播时带 `--ez dump true`，30 格的三趟拼板会存到
`files/ocr_dump/montage_{tight,soft,loose}.png`，再用 `tools\ocr_one.py --dump` 拉回本地。
这一步能回答"是字没认出来，还是我送进去的图本来就烂"。
"""
import sys

import numpy as np
from PIL import Image

COLS, ROWS, CELL, GAP = 6, 5, 240, 80
RAMP = ' .:-=+*#%@'


def main():
    path = sys.argv[1]
    idxs = [int(x) for x in sys.argv[2].split(',')]
    size = int(sys.argv[sys.argv.index('--size') + 1]) if '--size' in sys.argv else 34
    im = Image.open(path).convert('L')
    a = np.asarray(im, dtype=np.float32)
    print('%s  %dx%d' % (path, im.size[0], im.size[1]))
    for idx in idxs:
        rr, cc = divmod(idx, COLS)
        x0 = GAP + cc * (CELL + GAP)
        y0 = GAP + rr * (CELL + GAP)
        cell = a[y0:y0 + CELL, x0:x0 + CELL]
        dark = cell < 200
        if dark.any():
            ys, xs = np.where(dark)
            bx0, bx1, by0, by1 = xs.min(), xs.max(), ys.min(), ys.max()
        else:
            bx0 = bx1 = by0 = by1 = 0
        print('--- 格 #%d (行%d 列%d) 墨迹框 x%d..%d y%d..%d (%dx%d) 墨迹占比 %.2f'
              % (idx, rr, cc, bx0, bx1, by0, by1, bx1 - bx0 + 1, by1 - by0 + 1,
                 float(dark.mean())))
        small = np.asarray(Image.fromarray(cell.clip(0, 255).astype(np.uint8))
                           .resize((size, size), Image.BOX), dtype=np.float32) / 255.0
        for line in small:
            print('   ' + ''.join(RAMP[min(9, int((1.0 - v) * 9.999))] for v in line))


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    main()
