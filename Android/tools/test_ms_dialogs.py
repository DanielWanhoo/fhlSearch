# -*- coding: utf-8 -*-
r"""名士检索：三个窗口是否都在屏幕正中。

窗口：
  · 滚轮选择（朝代/爱好/社团/品阶）→ OptionSheetFragment
  · 输入条件（职业/生逢/出身/技能/其他描述）→ InputSheetFragment
  · 名士详情（点结果弹出）→ MingshiDetailSheetFragment

判定：卡片根节点（id=cardRoot）的中心与屏幕中心之差。
带输入法的输入面板会被系统上抬以避开键盘，那种情况只校验"水平居中 + 完全在屏幕内"。

用法：python _analysis\test_ms_dialogs.py [设备]
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
DEV = sys.argv[1] if len(sys.argv) > 1 else 'emulator-5554'
TAG = sys.argv[2] if len(sys.argv) > 2 else 'phone'
ACT = 'com.wangchuan.fhlsearch/.MainActivity'
SHOTS = os.path.join(_ROOT, 'docs', 'shots')
OUT = os.path.join(_ROOT, '_analysis', 'ms_dialogs_%s.txt') % DEV.replace('-', '_')

os.makedirs(os.path.join(_ROOT, '_analysis'), exist_ok=True)
sys.path.insert(0, os.path.join(_ROOT, 'tools'))
import drive_app as d  # noqa: E402
d.DEV = DEV


def run(*a):
    return subprocess.run([ADB, '-s', DEV] + list(a), capture_output=True,
                          timeout=240).stdout.decode('utf-8', 'replace')


def sh(c):
    return run('shell', c)


def shot(name):
    sh('screencap -p /sdcard/_dlg.png')
    run('pull', '/sdcard/_dlg.png', os.path.join(SHOTS, '%s_%s.png' % (TAG, name)))
    sh('rm /sdcard/_dlg.png')


W, H = d.screen_size()
DENS = int(re.search(r'(\d+)', d.sh('wm density')).group(1)) / 160.0
lines = []
allok = True


def check(title, allow_ime_shift=False):
    """检查当前屏幕上的卡片是否居中"""
    global allok
    ns = d.nodes()
    card = d.find(r'/cardRoot$', ns, by='id')
    if not card:
        lines.append('%-26s ❌ 没找到卡片（id=cardRoot）' % title)
        print('   %-24s ❌ 没找到卡片' % title)
        allok = False
        return
    x1, y1, x2, y2 = card['bounds']
    cx, cy = (x1 + x2) / 2, (y1 + y2) / 2
    dx, dy = cx - W / 2, cy - H / 2
    okx = abs(dx) <= 3
    # 浮窗是在"状态栏以内的可用区域"居中的：不同 Android 版本/密度下
    # 会有最多半个状态栏（约 12dp，取 16dp 留四舍五入余量）的垂直偏差，肉眼不可见。
    tol = 16 * DENS
    oky = abs(dy) <= tol if not allow_ime_shift else True
    onscreen = x1 >= 0 and y1 >= 0 and x2 <= W and y2 <= H
    ok = okx and oky and onscreen
    allok = allok and ok
    lines.append('%-26s 卡片 x=%d→%d y=%d→%d  中心偏移 dx=%.0f dy=%.0f (容差±%.0f)  %s' % (
        title, x1, x2, y1, y2, dx, dy, tol,
        ('✅ 居中' if ok else '❌ 未居中') + ('' if oky else '（垂直允许被键盘上抬）')))
    print('   %-24s dx=%6.1f dy=%6.1f (容差±%.0f)  卡片高=%d  %s' % (
        title, dx, dy, tol, y2 - y1, 'OK' if ok else ('OK(键盘上抬)' if (okx and onscreen) else 'FAIL')))


sh('am start -S -n ' + ACT)
time.sleep(6)
d.tap('名士检索', by='text', label='导航·名士')
time.sleep(2)
lines.append('屏幕 %dx%d' % (W, H))

# ① 滚轮窗口
d.tap('^朝代$', by='text', label='朝代'); time.sleep(1.5)
shot('dlg_wheel')
check('① 滚轮窗口（朝代）')
d.tap('/btnWheelConfirm$', label='确定', hide_kb=False); time.sleep(1.2)

# ② 输入窗口（会唤起键盘）
d.tap('^职业$', by='text', label='职业'); time.sleep(2)
shot('dlg_input')
check('② 输入窗口（职业，带键盘）', allow_ime_shift=True)
# 关掉：点清除该条件（顺便验证回传）
d.tap('/btnClearMode$', label='清除该条件', hide_kb=False); time.sleep(1.2)

# ③ 详情窗口
d.tap('btnSearch', label='检索'); time.sleep(2)
ns = d.nodes()
first = None
for n in ns:
    if n['id'].endswith('/tvMsName') and n['text']:
        first = n
        break
if first:
    d.tap('/tvMsName$', label='结果第一行', hide_kb=False); time.sleep(1.8)
    shot('dlg_detail')
    check('③ 详情窗口')
    d.tap('/btnDetailClose$', label='关闭', hide_kb=False); time.sleep(1)
else:
    lines.append('③ 详情窗口：没找到结果行')
    allok = False

lines.append('')
lines.append('总体: %s' % ('✅ 三个窗口都居中' if allok else '❌ 有窗口没居中'))
print('总体:', 'OK' if allok else 'FAILED')
io.open(OUT, 'w', encoding='utf-8').write('\n'.join(lines))
print('written', OUT)
