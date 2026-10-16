# -*- coding: utf-8 -*-
"""对比 C# 自测输出与 Python 参考实现输出。

用法: python tools/diff_check.py [Python输出] [C#输出]
默认读写项目根目录下的 _dev\\out_python.txt 与 _dev\\out_csharp.txt。
"""
import sys, io, os

# 输出跟随系统编码（中文 Windows 的 cmd 是 GBK），只把编不出来的字符降级，避免抛异常。
# 需要强制 UTF-8 时，设环境变量 PYTHONIOENCODING=utf-8。
try:
    sys.stdout.reconfigure(errors='replace')
except Exception:
    pass

_DEV = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "_dev")
A = sys.argv[1] if len(sys.argv) > 1 else os.path.join(_DEV, "out_python.txt")
B = sys.argv[2] if len(sys.argv) > 2 else os.path.join(_DEV, "out_csharp.txt")


def load(p):
    d = {}
    order = []
    with open(p, encoding='utf-8') as f:
        for ln in f:
            ln = ln.rstrip('\n')
            if not ln or ln.startswith('#'):
                continue
            parts = ln.split('\t')
            key = parts[0]
            val = parts[1] if len(parts) > 1 else ''
            rest = parts[2] if len(parts) > 2 else ''
            d[key] = (val, rest)
            order.append(key)
    return d, order


da, oa = load(A)
db, ob = load(B)

print(f"Python 参考: {len(da)} 条")
print(f"C#  自测   : {len(db)} 条")

allkeys = []
for k in oa:
    if k not in allkeys:
        allkeys.append(k)
for k in ob:
    if k not in allkeys:
        allkeys.append(k)

onlyA = [k for k in da if k not in db]
onlyB = [k for k in db if k not in da]
if onlyA:
    print(f"\n仅 Python 有 {len(onlyA)} 条: {onlyA[:5]}")
if onlyB:
    print(f"\n仅 C# 有 {len(onlyB)} 条: {onlyB[:5]}")

diff = 0
order_only = 0
for k in allkeys:
    a = da.get(k)
    b = db.get(k)
    if a is None or b is None:
        continue
    if a[0] != b[0]:
        diff += 1
        print(f"\n❌ 条数不一致: {k}  Python={a[0]}  C#={b[0]}")
        continue
    sa = sorted(x for x in a[1].split('|') if x)
    sb = sorted(x for x in b[1].split('|') if x)
    if sa != sb:
        diff += 1
        if diff <= 12:
            print(f"\n❌ 内容不一致: {k}  ({a[0]} 条)")
            only_a = [x for x in sa if x not in sb]
            only_b = [x for x in sb if x not in sa]
            if only_a:
                print(f"   仅 Python: {only_a[:10]}")
            if only_b:
                print(f"   仅 C#    : {only_b[:10]}")
    elif a[1] != b[1]:
        order_only += 1

print("\n" + "=" * 70)
if diff == 0:
    print(f"✅ 内容全部一致：{len(allkeys)} 条查询，两套实现检索结果完全相同")
    print(f"   （其中 {order_only} 条仅展示顺序不同：程序按拼音升序排列，参考实现按题库原序）")
else:
    print(f"❌ 有 {diff} 条内容不一致（共 {len(allkeys)} 条）")
print("=" * 70)
