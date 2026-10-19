# -*- coding: utf-8 -*-
r"""量手机端布局：把关键控件的真实 bounds 打出来，用于定位空白/裁切问题。

用法：python _analysis\measure_phone.py [设备序列号]
"""
import io
import os
import sys


# ---- 路径：全部按"本脚本所在位置"推算，克隆到任何目录下都能直接跑 ----
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

os.makedirs(os.path.join(_ROOT, '_analysis'), exist_ok=True)
sys.path.insert(0, os.path.join(_ROOT, 'tools'))
import drive_app as d  # noqa: E402

d.DEV = sys.argv[1] if len(sys.argv) > 1 else 'emulator-5554'
OUT = os.path.join(_ROOT, '_analysis', 'measure_phone.txt')

lines = []
def w(s=''):
    lines.append(s)

W, H = d.screen_size()
dens = d.sh('wm density')
w('设备 %s  屏幕 %dx%d  %s' % (d.DEV, W, H, dens.strip()))
w('')

IDS = ['btnSearch', 'tvResultCount', 'rvResult', 'layButtons', 'layStatus', 'tvEmpty',
       'btnClearAll', 'btnClearCurrent', 'btnSecondSearch', 'tvSecondBar', 'layInputs',
       'header', 'tvTitle', 'tvSubtitle', 'tabMode', 'result', 'grid', 'layDpad',
       'btnClear', 'layModeList', 'tvCount']

def dump(title, ns=None):
    ns = ns if ns is not None else d.nodes()
    w('--- %s ---' % title)
    for i in IDS:
        hits = [n for n in ns if n['id'].endswith('/' + i) or n['id'].endswith(':' + i)]
        for n in hits:
            x1, y1, x2, y2 = n['bounds']
            txt = (n['text'] or '')[:22]
            w('  %-18s y:%4d→%4d  h=%3d  x:%4d→%4d  w=%4d  %s'
              % (i, y1, y2, y2 - y1, x1, x2, x2 - x1, txt))
    w('')

d.sh('am start -S -n ' + d.ACT)
d.wait(6)

# ---------- 成语：初始态 + 检索后 ----------
w('===== 成语检索 =====')
dump('初始态')
d.tap('etCell', index=0, label='拼音第 1 格')
d.sh('input text "an"'); d.wait(0.8)
d.hide_ime()
d.tap('btnSearch', label='检索'); d.wait(2)
dump('检索后（53 条）')

# 底部导航条的真实位置（用来判断是否压住按钮）
ns = d.nodes()
navs = [n for n in ns if n['id'].endswith('/bottomNav')]
if navs:
    x1, y1, x2, y2 = navs[0]['bounds']
    w('  bottomNav          y:%4d→%4d  h=%3d' % (y1, y2, y2 - y1))
w('')

# ---------- 诗词 ----------
w('===== 诗词检索 =====')
d.tap('诗词检索', by='text', label='导航·诗词'); d.wait(2)
d.sh('am broadcast -a com.wangchuan.fhlsearch.action.FILL_SHICI_TEST'); d.wait(1)
d.hide_ime(); d.wait(0.5)
dump('填入字格后')
d.tap('btnSearch', label='开始检索'); d.wait(2)
dump('检索后')
w('')

# ---------- 名士 ----------
w('===== 名士检索 =====')
d.tap('名士检索', by='text', label='导航·名士'); d.wait(2)
dump('初始态（9 个条件）')
d.tap('朝代', by='text', label='朝代'); d.wait(1.5)
d.tap_chip('唐', fallback_row=0, fallback_col=5)
d.tap('btnSearch', label='检索'); d.wait(2)
dump('检索后（23 位）')

with io.open(OUT, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines))
print('written', OUT)
