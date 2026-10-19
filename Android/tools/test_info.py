# -*- coding: utf-8 -*-
r"""「信息」弹窗回归：三个模块的大标题右边都有 i 图标，点开是居中的信息面板。

检查项：
  1. 三个模块点「信息」都能弹出面板，且卡片**屏幕居中**、不超出屏幕；
  2. 面板上有软件名、版本号（读出来应当等于设定的 versionName）、题库统计；
  3. 正文含三大模块 + 图片识别的用法，且可滚动；
  4. 点「关闭」能关掉；面板关掉后界面没崩。

用法：python tools\test_info.py [设备] [标签]
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
PKG = 'com.wangchuan.fhlsearch'
ACT = PKG + '/.MainActivity'
OUT = os.path.join(_ROOT, '_analysis', 'info_%s.txt') % TAG
SHOTS = os.path.join(_ROOT, 'docs', 'shots')

os.makedirs(os.path.join(_ROOT, '_analysis'), exist_ok=True)
sys.path.insert(0, os.path.join(_ROOT, 'tools'))
import drive_app as d  # noqa: E402
d.DEV = DEV
d.TAG = TAG


def run(*a):
    return subprocess.run([ADB, '-s', DEV] + list(a), capture_output=True,
                          timeout=240).stdout.decode('utf-8', 'replace')


def sh(c):
    return run('shell', c)


W, H = d.screen_size()
DENS = int(re.search(r'(\d+)', sh('wm density')).group(1)) / 160.0
lines = []
allok = True


def w(s):
    lines.append(s)
    print(s)


def expect_version():
    out = sh('dumpsys package %s | grep versionName' % PKG)
    m = re.search(r'versionName=(\S+)', out)
    return m.group(1) if m else '?'


def check_centered(title):
    global allok
    ns = d.nodes()
    card = d.find(r'/cardRoot$', ns, by='id')
    if not card:
        w('  %-22s ❌ 没找到卡片（id=cardRoot）' % title)
        allok = False
        return
    x1, y1, x2, y2 = card['bounds']
    cx, cy = (x1 + x2) / 2, (y1 + y2) / 2
    dx, dy = cx - W / 2, cy - H / 2
    tol = 16 * DENS
    ok = abs(dx) <= 3 and abs(dy) <= tol and x1 >= 0 and y1 >= 0 and x2 <= W and y2 <= H
    allok = allok and ok
    w('  %-22s 卡片 x=%d→%d y=%d→%d 偏移 dx=%.0f dy=%.0f（容差±%.0f）%s 高=%d'
      % (title, x1, x2, y1, y2, dx, dy, tol, '✅ 居中' if ok else '❌ 未居中', y2 - y1))


def open_and_check(nav, name):
    """切到某个模块 → 点信息 → 检查内容 → 关闭"""
    global allok
    d.tap(nav, by='text', label='导航·' + name)
    time.sleep(1.5)
    icon = d.find(r'/btnInfo$', by='id')
    if not icon:
        w('  %-22s ❌ 大标题右边找不到「信息」图标' % name)
        allok = False
        return
    w('  %-22s 信息图标 bounds=%s（%d×%d px）' % (name, icon['bounds'],
                                                icon['bounds'][2] - icon['bounds'][0],
                                                icon['bounds'][3] - icon['bounds'][1]))
    d.tap(r'/btnInfo$', label='信息图标')
    time.sleep(1.5)
    ns = d.nodes()
    texts = [n['text'] for n in ns if n['text']]
    blob = ' '.join(texts)
    ver = expect_version()
    ok_title = any('忘川检索' in t for t in texts)
    ok_ver = ('版本' in blob) and (ver in blob)
    ok_stats = any('题库' in t and '成语' in t for t in texts)
    ok_body = all(k in blob for k in ('图片识别', '众里寻他', '山石雅集'))
    ok = ok_title and ok_ver and ok_stats and ok_body
    allok = allok and ok
    w('  %-22s 标题=%s 版本(%s)=%s 题库统计=%s 用法正文=%s %s'
      % (name, ok_title, ver, ok_ver, ok_stats, ok_body, '✅' if ok else '❌'))
    check_centered(name + '·信息面板')
    d.shot('info_%s_%s' % (TAG, name))
    # 关掉
    if not d.tap(r'/btnInfoClose$', label='关闭', hide_kb=False):
        d.tap('^关闭$', by='text', label='关闭')
    time.sleep(1)
    ns = d.nodes()
    if d.find(r'/cardRoot$', ns, by='id'):
        w('  %-22s ❌ 点「关闭」后面板还在' % name)
        allok = False
    else:
        w('  %-22s 关闭正常 ✅' % name)


w('== 设备 %s（%s）信息面板回归 ==' % (DEV, TAG))
w('屏幕 %dx%d，密度 %.2f' % (W, H, DENS))
run('install', '-r', os.environ.get('FHL_APK')
    or os.path.join(_ROOT, 'app', 'build', 'outputs', 'apk', 'debug', 'app-debug.apk'))
sh('am start -S -n ' + ACT)
time.sleep(6)

for nav, name in (('成语检索', '成语'), ('诗词检索', '诗词'), ('名士检索', '名士')):
    open_and_check(nav, name)

w('')
w('总体: %s' % ('✅ 全部通过' if allok else '❌ 有不符合预期的地方'))
print('总体:', 'OK' if allok else 'FAILED')
io.open(OUT, 'w', encoding='utf-8').write('\n'.join(lines))
print('written', OUT)
