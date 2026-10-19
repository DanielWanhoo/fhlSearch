# -*- coding: utf-8 -*-
r"""字体缩放压力测试：把系统字号调大后走一遍，看布局会不会崩（折行/裁字/挤没）。

用法：python _analysis\font_scale_test.py 2.0
"""
import io
import os
import subprocess
import sys
import time


# ---- 路径：全部按"本脚本所在位置"推算，克隆到任何目录下都能直接跑 ----
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SDK = os.path.join(os.environ.get('LOCALAPPDATA', ''), 'Android', 'Sdk')
ADB = os.path.join(SDK, 'platform-tools', 'adb.exe')
DEV = 'emulator-5554'
APK = os.path.join(_ROOT, 'app', 'build', 'outputs', 'apk', 'debug', 'app-debug.apk')
SHOTS = os.path.join(_ROOT, '_analysis', 'crops')
ACT = 'com.wangchuan.fhlsearch/.MainActivity'
SCALE = sys.argv[1] if len(sys.argv) > 1 else '2.0'

os.makedirs(os.path.join(_ROOT, '_analysis'), exist_ok=True)
sys.path.insert(0, os.path.join(_ROOT, 'tools'))
import drive_app as d  # noqa: E402
d.DEV = DEV

OUT = os.path.join(_ROOT, '_analysis', 'font_scale_%s.txt') % SCALE
lines = []
def w(s=''):
    lines.append(s)

def run(*a):
    return subprocess.run([ADB, '-s', DEV] + list(a), capture_output=True,
                          timeout=240).stdout.decode('utf-8', 'replace')

def sh(c):
    return run('shell', c)

run('uninstall', 'com.wangchuan.fhlsearch')
print('   ', run('install', '-r', APK).strip().splitlines()[-1])
sh('settings put system font_scale %s' % SCALE)
time.sleep(1)
sh('am start -S -n ' + ACT)
time.sleep(6)

w('font_scale = %s' % SCALE)
w('')

IDS = ['btnSearch', 'tvResultCount', 'rvResult', 'layButtons', 'btnClearAll',
       'btnClearCurrent', 'btnSecondSearch', 'tvEmpty', 'grid', 'btnClear',
       'tvTitle', 'layModeList', 'result']

def dump(title):
    ns = d.nodes()
    w('--- %s ---' % title)
    for i in IDS:
        for n in [x for x in ns if x['id'].endswith('/' + i)]:
            x1, y1, x2, y2 = n['bounds']
            w('  %-18s y:%4d→%4d h=%3d  w=%4d  %s'
              % (i, y1, y2, y2 - y1, x2 - x1, (n['text'] or '')[:20]))
    w('')

dump('成语 初始')
d.tap('etCell', index=0, label='拼音第 1 格')
sh('input text "an"'); time.sleep(0.8)
d.hide_ime()
d.tap('btnSearch', label='检索'); time.sleep(2)
dump('成语 检索后')
sh('screencap -p /sdcard/_f.png')
run('pull', '/sdcard/_f.png', os.path.join(SHOTS, 'font%s_cy_bottom.png' % SCALE))
sh('rm /sdcard/_f.png')

d.tap('诗词检索', by='text', label='导航·诗词'); time.sleep(2)
dump('诗词')
d.tap('名士检索', by='text', label='导航·名士'); time.sleep(2)
d.tap('^朝代$', by='text', label='朝代'); time.sleep(2)
d.pick_option(d.DYNASTY, '唐')
d.tap('btnSearch', label='检索'); time.sleep(2)
dump('名士 检索后')
sh('screencap -p /sdcard/_f.png')
run('pull', '/sdcard/_f.png', os.path.join(SHOTS, 'font%s_ms_bottom.png' % SCALE))
sh('rm /sdcard/_f.png')

with io.open(OUT, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines))

# 复位字号
sh('settings put system font_scale 1.0')
print('written', OUT, '(font_scale 已复位为 1.0)')
