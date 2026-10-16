# -*- coding: utf-8 -*-
r"""诗词字格：选中框（selected）与输入焦点（focused）是否同步。

判定依据（uiautomator 节点属性）：
  格子外框 FrameLayout 的 selected="true" → 该格画着朱砂选中框
  格内隐藏 EditText 的 focused="true"    → 该格拿到了输入焦点（光标 + 输入法目标）
两者必须落在同一格，否则用方向键移动后打的字会跑到上一格。

用法：python tools\test_shici_focus.py [设备]
"""
import io
import os
import re
import subprocess
import sys
import time


# ---- 路径：全部按"本脚本所在位置"推算，克隆到任何目录下都能直接跑 ----
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SDK = os.path.join(os.environ.get('LOCALAPPDATA', ''), 'Android', 'Sdk')
ADB = os.path.join(SDK, 'platform-tools', 'adb.exe')
DEV = sys.argv[1] if len(sys.argv) > 1 else 'emulator-5556'
ACT = 'com.wangchuan.fhlsearch/.MainActivity'
OUT = os.path.join(_ROOT, '_analysis', 'shici_focus_%s.txt') % DEV.replace('-', '_')

os.makedirs(os.path.join(_ROOT, '_analysis'), exist_ok=True)
sys.path.insert(0, os.path.join(_ROOT, 'tools'))
import drive_app as d  # noqa: E402
d.DEV = DEV


def run(*a):
    return subprocess.run([ADB, '-s', DEV] + list(a), capture_output=True,
                          timeout=240).stdout.decode('utf-8', 'replace')


def sh(c):
    return run('shell', c)


def dump():
    xml = ''
    for _ in range(3):
        sh('uiautomator dump /sdcard/_f.xml')
        xml = run('shell', 'cat /sdcard/_f.xml')
        if '<hierarchy' in xml:
            break
        time.sleep(1)
    return xml


def snapshot(xml):
    """返回 (选中格 desc, 有焦点格 desc, 全部格子 desc 列表)"""
    frames, edits = [], []
    for m in re.finditer(r'<node\b[^>]*?(?:/>|>)', xml):
        n = m.group(0)
        b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
        if not b:
            continue
        cls = (re.search(r'class="([^"]*)"', n) or [None, ''])[1]
        cd = re.search(r'content-desc="([^"]*)"', n)
        bounds = tuple(map(int, b.groups()))
        if cd and re.match(r'^第\d+行第\d+列$', cd.group(1)):
            frames.append({'desc': cd.group(1), 'bounds': bounds,
                           'sel': 'selected="true"' in n})
        elif cls.endswith('EditText'):
            edits.append({'bounds': bounds, 'foc': 'focused="true"' in n})

    def owner(eb):
        for f in frames:
            if f['bounds'] == eb:            # 隐藏框与格子边界完全一致
                return f['desc']
        return None

    sel = [f['desc'] for f in frames if f['sel']]
    foc = [owner(e['bounds']) for e in edits if e['foc']]
    return (sel[0] if sel else None, foc[0] if foc else None, [f['desc'] for f in frames])


lines = []


def report(title, expect=None):
    sel, foc, allc = snapshot(dump())
    ok = sel is not None and sel == foc
    exp_ok = (expect is None) or (sel == expect)
    lines.append('--- %s ---' % title)
    lines.append('  选中框 : %s' % (sel or '（没有格子被选中）'))
    lines.append('  输入焦点: %s' % (foc or '（没有格子拿到焦点）'))
    lines.append('  同步? %s%s' % ('✅ 是' if ok else '❌ 否',
                                '' if exp_ok else '（预期应为 %s）' % expect))
    print('   %-24s 选中=%-8s 焦点=%-8s %s%s' % (
        title, sel or '-', foc or '-',
        'OK' if ok else 'MISMATCH',
        '' if exp_ok else '  预期=%s' % expect))
    return ok and exp_ok


sh('am start -S -n ' + ACT)
time.sleep(6)
d.tap('诗词检索', by='text', label='导航·诗词')
time.sleep(2)

ns = d.nodes()
g = d.find(r'/grid$', ns, by='id')
x1, y1, x2, y2 = g['bounds']
cw, chh = (x2 - x1) / 6.0, (y2 - y1) / 5.0


def tap_cell(row, col):
    sh('input tap %d %d' % (int(x1 + cw * (col + 0.5)), int(y1 + chh * (row + 0.5))))
    time.sleep(1.0)


allok = True
tap_cell(0, 0)
allok &= report('点击 第1行第1列', expect='第1行第1列')

sh('input keyevent 22'); time.sleep(0.7)   # →
allok &= report('按一次 →', expect='第1行第2列')

sh('input keyevent 22'); time.sleep(0.7)
allok &= report('再按一次 →', expect='第1行第3列')

sh('input keyevent 20'); time.sleep(0.7)   # ↓
allok &= report('按一次 ↓', expect='第2行第3列')

sh('input keyevent 21'); time.sleep(0.7)   # ←
allok &= report('按一次 ←', expect='第2行第2列')

sh('input keyevent 19'); time.sleep(0.7)   # ↑
allok &= report('按一次 ↑', expect='第1行第2列')

sh('input keyevent 61'); time.sleep(0.7)   # Tab
allok &= report('按一次 Tab', expect='第1行第3列')

# 最后一格后再按 → 应停在行末（不越界），且焦点仍同步
for _ in range(8):
    sh('input keyevent 22'); time.sleep(0.35)
allok &= report('连按 8 次 →（应停在第1行第6列）', expect='第1行第6列')

tap_cell(4, 5)
allok &= report('点击 第5行第6列', expect='第5行第6列')

lines.append('')
lines.append('总体: %s' % ('✅ 选中框与输入焦点始终同步' if allok else '❌ 存在不同步'))
print('总体:', 'OK' if allok else 'FAILED')
with io.open(OUT, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines))
print('written', OUT)
