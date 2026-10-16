# -*- coding: utf-8 -*-
r"""清除 Android 资源文件里的 UTF-8 BOM。

背景：用 PowerShell 的 Set-Content -Encoding UTF8 改写 XML 会写入 BOM（EF BB BF），
      aapt2 解析带 BOM 的布局会报 'Cannot read field "elmName" because "root" is null'。
      本脚本把所有 res 下的 XML/文本资源的 BOM 去掉，并报告修改了哪些文件。

用法：python strip_bom.py [目录]
"""
import os
import sys


# ---- 路径：全部按"本脚本所在位置"推算，克隆到任何目录下都能直接跑 ----
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

BOM = b'\xef\xbb\xbf'
TARGETS = ('.xml', '.txt', '.json')


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else \
        os.path.join(_ROOT, 'app', 'src', 'main')
    fixed = []
    for dirpath, _, files in os.walk(root):
        for fn in files:
            if not fn.lower().endswith(TARGETS):
                continue
            p = os.path.join(dirpath, fn)
            with open(p, 'rb') as f:
                data = f.read()
            if data.startswith(BOM):
                with open(p, 'wb') as f:
                    f.write(data[len(BOM):])
                fixed.append(os.path.relpath(p, root))
    if fixed:
        print('已清除 BOM 的文件（%d 个）：' % len(fixed))
        for f in fixed:
            print('  -', f)
    else:
        print('没有发现带 BOM 的文件')
    return 0


if __name__ == '__main__':
    sys.exit(main())
