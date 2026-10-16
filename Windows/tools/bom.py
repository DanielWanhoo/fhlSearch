# -*- coding: utf-8 -*-
"""
给 Windows PowerShell 5.1 用的 .ps1 补 UTF-8 BOM。

Windows PowerShell 5.1 在没有 BOM 时按系统 ANSI 代码页（中文系统是 GBK）解码脚本，
脚本里的中文注释/字符串会乱码，甚至破坏语法。PowerShell 7+ 无此问题。

用法: python tools/bom.py <文件...>
"""
import sys, io, os

# 输出跟随系统编码（中文 Windows 的 cmd 是 GBK），只把编不出来的字符降级，避免抛异常。
# 需要强制 UTF-8 时，设环境变量 PYTHONIOENCODING=utf-8。
try:
    sys.stdout.reconfigure(errors='replace')
except Exception:
    pass
BOM = b'\xef\xbb\xbf'


def ensure(path):
    if not os.path.exists(path):
        print("  跳过（不存在）: " + path)
        return False
    with open(path, 'rb') as f:
        data = f.read()
    if data.startswith(BOM):
        print("  已含 BOM: " + path)
        return False
    # 确认是合法 UTF-8
    try:
        data.decode('utf-8')
    except UnicodeDecodeError as e:
        print("  !! 不是 UTF-8，无法安全加 BOM: %s (%s)" % (path, e))
        return False
    with open(path, 'wb') as f:
        f.write(BOM + data)
    print("  已补 BOM: %s (%d bytes)" % (path, len(data) + 3))
    return True


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    for p in sys.argv[1:]:
        ensure(p)
