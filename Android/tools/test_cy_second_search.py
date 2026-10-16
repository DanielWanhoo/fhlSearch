# -*- coding: utf-8 -*-
r"""成语检索 · 二次检索的行为验证（新语义）。

期望的行为：
  1) 先检索出一批结果；
  2) 用户往输入框里补填新内容；
  3) **点"二次检索"当场就在上一次的结果里再筛一次并给出新结果**（不用再按"检索"）；
  4) 输入框内容全程保留；退回上一层时也保留，并恢复上一层的绿色标注。

预期值的来历：全库"第 2 格含 du"是 3 条（暗渡陈仓 / 多多益善 / 买椟还珠），
但在"第 1 格含 an"的 53 条结果里只有「暗渡陈仓」同时满足 → 二次检索正确结果是 1 条。

用法：python tools\test_cy_second_search.py [设备] [标签]
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
DEV = sys.argv[1] if len(sys.argv) > 1 else 'emulator-5554'
TAG = sys.argv[2] if len(sys.argv) > 2 else ''
ACT = 'com.wangchuan.fhlsearch/.MainActivity'
SHOTS = os.path.join(_ROOT, 'docs', 'shots')
os.makedirs(os.path.join(_ROOT, '_analysis'), exist_ok=True)
OUT = os.path.join(_ROOT, '_analysis', 'cy_second_search_%s.txt') % DEV.replace('-', '_')
SUF = TAG or DEV.replace('emulator-', 'emu')

sys.path.insert(0, os.path.join(_ROOT, 'tools'))
import drive_app as d  # noqa: E402
d.DEV = DEV


def run(*a):
    return subprocess.run([ADB, '-s', DEV] + list(a), capture_output=True,
                          timeout=240).stdout.decode('utf-8', 'replace')


def sh(c):
    return run('shell', c)


def cells_text():
    return [n['text'] for n in d.nodes() if n['id'].endswith('/etCell')][:4]


def count_text():
    return (d.find('tvResultCount', d.nodes()) or {}).get('text', '—')


def bar_text():
    return (d.find('tvSecondBar', d.nodes()) or {}).get('text', '—')


def words():
    return [n['text'] for n in d.nodes() if n['id'].endswith('/tvCyWord')]


def shot(name):
    sh('screencap -p /sdcard/_s.png')
    run('pull', '/sdcard/_s.png', os.path.join(SHOTS, '%s.png' % name))
    sh('rm /sdcard/_s.png')


lines = []
allok = True


def check(title, cond, detail=''):
    global allok
    allok = allok and bool(cond)
    lines.append('%-34s %s  %s' % (title, '✅' if cond else '❌', detail))
    print('   %-32s %s  %s' % (title, 'OK' if cond else 'FAIL', detail))


sh('am start -S -n ' + ACT)
time.sleep(6)
d.tap('成语检索', by='text', label='底部导航·成语检索')
time.sleep(2)

# ① 拼音第 1 格填 an，检索
d.tap('etCell', index=0, label='拼音第 1 格')
sh('input text "an"'); time.sleep(0.8)
d.hide_ime()
d.tap('btnSearch', label='检索')
time.sleep(2)
check('① 第 1 格 an → 检索', '(53)' in count_text(), count_text())
shot('cy_second_1_first_%s' % SUF)

# ② 补填第 2 格 du（此时先不点任何按钮）
d.tap('etCell', index=1, label='拼音第 2 格')
sh('input text "du"'); time.sleep(0.8)
d.hide_ime()
check('② 补填后两格都在', cells_text()[:2] == ['an', 'du'], '输入框=%s' % cells_text())

# ③ 直接点"二次检索"→ 当场在上一次结果里再筛
d.tap('二次检索', by='text', label='二次检索')
time.sleep(2)
check('③ 二次检索当场出结果 = 1', '(1)' in count_text(), count_text())
check('③ 首条 = 暗渡陈仓', words()[:1] == ['暗渡陈仓'], '首条=%s' % words()[:1])
check('③ 提示"上一次 53 条中筛出"', '53' in bar_text(), bar_text())
check('③ 输入框仍保留', cells_text()[:2] == ['an', 'du'], '输入框=%s' % cells_text())
shot('cy_second_2_narrowed_%s' % SUF)

# ④ 清空当前 → 退回上一层（53 条），输入框仍保留
d.tap('清空当前', by='text', label='清空当前')
time.sleep(1.5)
check('④ 退回上一层 = 53', '(53)' in count_text(), count_text())
check('④ 输入框仍保留', cells_text()[:2] == ['an', 'du'], '输入框=%s' % cells_text())
shot('cy_second_3_back_%s' % SUF)

# ⑤ 再补一格（第 3 格 chen）→ 再点二次检索，继续缩小
d.tap('etCell', index=2, label='拼音第 3 格')
sh('input text "chen"'); time.sleep(0.8)
d.hide_ime()
d.tap('二次检索', by='text', label='二次检索(再缩)')
time.sleep(2)
check('⑤ 再缩一次 = 1（暗渡陈仓）', '(1)' in count_text() and words()[:1] == ['暗渡陈仓'],
      '%s 首条=%s' % (count_text(), words()[:1]))

lines.append('')
lines.append('总体: %s' % ('✅ 通过' if allok else '❌ 有不符合预期的地方'))
print('总体:', 'OK' if allok else 'FAILED')
io.open(OUT, 'w', encoding='utf-8').write('\n'.join(lines))
print('written', OUT)
