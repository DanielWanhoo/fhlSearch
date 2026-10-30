# -*- coding: utf-8 -*-
r"""成语检索 · 二次检索（层级）与输入内容保留 —— v3.2 版。

v3.2 起三组输入同屏常显（声调 0~3 / 拼音 4~7 / 单字 8~11 格），
手机端出结果后条件区会自动折叠，要继续改就得先点摘要展开。

期望的行为：
  1) 先检索出一批结果；
  2) 展开条件区、往输入框里补填新内容；
  3) 点"二次检索"**当场**在上一次的结果里再筛一次（不用再按"检索"）；
  4) 输入内容全程保留；退回上一层时也保留，并恢复上一层的绿色标注；
  5) 每出一轮新结果，条件区重新折叠、结果让位。

预期值的来历：全库"第 2 格含 du"3 条（暗渡陈仓 / 多多益善 / 买椟还珠），
在"第 1 格含 an"的 53 条里只有「暗渡陈仓」→ 二次检索 1 条；再补第 3 格 chen 仍是这 1 条。

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
TAG = sys.argv[2] if len(sys.argv) > 2 else DEV.replace('emulator-', 'emu')
ACT = 'com.wangchuan.fhlsearch/.MainActivity'
SHOTS = os.path.join(_ROOT, 'docs', 'shots')
OUT = os.path.join(_ROOT, '_analysis', 'cy_second_search_%s.txt') % TAG

os.makedirs(os.path.join(_ROOT, '_analysis'), exist_ok=True)
sys.path.insert(0, os.path.join(_ROOT, 'tools'))
import drive_app as d  # noqa: E402
d.DEV = DEV

PINYIN = range(4, 8)
HINTS = ('拼音', '声调', '字', '单字')


def screen_width():
    out = run('shell', 'wm', 'size')
    for tok in out.replace('\r', ' ').split():
        if 'x' in tok and tok.replace('x', '').isdigit():
            return int(tok.split('x')[0])
    return 1080


def run(*a):
    return subprocess.run([ADB, '-s', DEV] + list(a), capture_output=True,
                          timeout=240).stdout.decode('utf-8', 'replace')


def sh(c):
    return run('shell', c)


def pinyin_cells():
    """拼音组 4 格的内容"""
    c = [('' if n['text'].strip() in HINTS else n['text'].strip())
         for n in d.nodes() if n['id'].endswith('/etCell')]
    return [c[i] for i in PINYIN if i < len(c)]


def count_text():
    return (d.find('tvResultCount', d.nodes()) or {}).get('text', '—')


def bar_text():
    return (d.find('tvSecondBar', d.nodes()) or {}).get('text', '—')


def words():
    """结果首条成语：每列一个 tvChar，4 个字拼起来"""
    chars = [n['text'] for n in d.nodes() if n['id'].endswith('/tvChar')]
    return [''.join(chars[i:i + 4]) for i in range(0, min(len(chars), 8), 4)]


def expand():
    """折叠时点摘要展开，等输入框回来"""
    if not any(n['id'].endswith('/etCell') for n in d.nodes()):
        d.tap('/layCondSummary$', label='展开修改')
        time.sleep(1.2)


def collapsed():
    return not any(n['id'].endswith('/etCell') for n in d.nodes())


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


WIDE = screen_width() >= 1200      # 平板双栏（条件区常显，不折叠）
sh('am start -S -n ' + ACT)
time.sleep(6)
d.tap('成语检索', by='text', label='底部导航·成语检索')
time.sleep(2)

# ① 拼音第 1 格填 an，检索
d.tap('etCell', index=4, label='拼音第 1 格')
sh('input text "an"')
time.sleep(0.8)
d.hide_ime()
d.tap('btnSearch', label='检索')
time.sleep(2.5)
check('① 拼音 1 位 an → 53 条', '(53)' in count_text(), count_text())
if WIDE:
    check('① 平板双栏：条件区常显（不折叠）', not collapsed(), '折叠=%s' % collapsed())
else:
    check('① 出结果后条件区折叠', collapsed(), '折叠=%s' % collapsed())
shot('cy_second_1_first_%s' % TAG)

# ② 展开后补填第 2 格 du（此时先不点任何按钮）
expand()
d.tap('etCell', index=5, label='拼音第 2 格')
sh('input text "du"')
time.sleep(0.8)
d.hide_ime()
check('② 补填后两格都在', pinyin_cells()[:2] == ['an', 'du'], '拼音组=%s' % pinyin_cells())

# ③ 直接点"二次检索"→ 当场在上一次结果里再筛
d.tap('二次检索', by='text', label='二次检索')
time.sleep(2.5)
check('③ 二次检索当场出结果 = 1', '(1)' in count_text(), count_text())
check('③ 首条 = 暗渡陈仓', words()[:1] == ['暗渡陈仓'], '首条=%s' % words()[:1])
check('③ 提示"上一次 53 条中筛出"', '53' in bar_text(), bar_text())
if WIDE:
    check('③ 平板双栏：条件区仍常显', not collapsed(), '折叠=%s' % collapsed())
else:
    check('③ 新一轮结果后重新折叠', collapsed(), '折叠=%s' % collapsed())
shot('cy_second_2_narrowed_%s' % TAG)

expand()
check('③ 展开后输入框仍保留', pinyin_cells()[:2] == ['an', 'du'], '拼音组=%s' % pinyin_cells())

# ④ 清空当前 → 退回上一层（53 条），输入框仍保留
d.tap('清空当前', by='text', label='清空当前')
time.sleep(1.8)
check('④ 退回上一层 = 53', '(53)' in count_text(), count_text())
expand()
check('④ 退回后输入框仍保留', pinyin_cells()[:2] == ['an', 'du'], '拼音组=%s' % pinyin_cells())
shot('cy_second_3_back_%s' % TAG)

# ⑤ 再补一格（第 3 格 chen）→ 再点二次检索，仍然只有 1 条
d.tap('etCell', index=6, label='拼音第 3 格')
sh('input text "chen"')
time.sleep(0.8)
d.hide_ime()
d.tap('二次检索', by='text', label='二次检索(再缩)')
time.sleep(2.5)
check('⑤ 再缩一次 = 1（暗渡陈仓）', '(1)' in count_text() and words()[:1] == ['暗渡陈仓'],
      '%s 首条=%s' % (count_text(), words()[:1]))

lines.append('')
lines.append('总体: %s' % ('✅ 通过' if allok else '❌ 有不符合预期的地方'))
print('总体:', 'OK' if allok else 'FAILED')
io.open(OUT, 'w', encoding='utf-8').write('\n'.join(lines))
print('written', OUT)
