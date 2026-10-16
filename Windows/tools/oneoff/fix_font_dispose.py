# -*- coding: utf-8 -*-
"""
修一个系统性 bug：Fonts.* 返回的是**缓存中的共享 Font 实例**，
而调用处写成 `using (Font f = Fonts.Xxx(...))` 会在离开作用域时把它 Dispose 掉，
导致后续所有用到同一字体缓存的绘制抛 ArgumentException（参数无效）。

改法：去掉 using 包装，改为普通局部变量（缓存字体在全程序生命周期内不需要释放）。

【一次性脚本】v1.1 UI 重构期间跑过一次，问题已修完；留在这里只为记录当时的修法。
"""
import re, sys, io, os

# 输出跟随系统编码（中文 Windows 的 cmd 是 GBK），只把编不出来的字符降级，避免抛异常。
# 需要强制 UTF-8 时，设环境变量 PYTHONIOENCODING=utf-8。
try:
    sys.stdout.reconfigure(errors='replace')
except Exception:
    pass

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
                    "src", "FhlSearch")
# 匹配: using (Font name = Fonts.Any(...))   —— 允许括号内一层嵌套
PAT = re.compile(r'using \(Font (\w+) = (Fonts\.[A-Za-z0-9_]+\((?:[^()]|\([^()]*\))*\))\)')

total = 0
for dirpath, _, files in os.walk(ROOT):
    if '\\obj\\' in dirpath or '\\bin\\' in dirpath:
        continue
    for fn in files:
        if not fn.endswith('.cs'):
            continue
        p = os.path.join(dirpath, fn)
        with open(p, 'r', encoding='utf-8') as f:
            src = f.read()
        new, n = PAT.subn(lambda m: 'Font %s = %s;' % (m.group(1), m.group(2)), src)
        if n:
            # BOM 无关：Roslyn 对无 BOM 的 UTF-8 处理正确，保持原样写回
            with open(p, 'w', encoding='utf-8', newline='') as f:
                f.write(new)
            print(f"  {os.path.relpath(p, ROOT)}: 修复 {n} 处")
            total += n
print(f"\n合计修复 {total} 处")
