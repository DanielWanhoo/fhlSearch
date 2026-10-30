# -*- coding: utf-8 -*-
r"""成语检索 v3.2：三组同屏输入 + 手机端检索后自动折叠 + 「检索」键显隐。

v3.2 的规则：
  1) 声调 / 拼音 / 单字 三组**同屏常显**，每组 4 格（第 i 格＝成语第 i+1 个字）；
  2) 手机单栏：首次检索出结果后，条件区自动折叠成一行「检索条件」摘要，
     上方按键（清空所有 / 清空当前 / 二次检索）保留；点摘要可展开继续改，展开时摘要变「收起」；
  3) 第十一轮的规则照旧：「检索」键在出过结果后隐藏，清空到没有结果时恢复；
  4) 检索完成后输入内容保留；
  5) 结果逐字对齐：声调 / 拼音 / 单字 三行、靠左，同一列三行左边界一致。

预期条数的来历（全库 319 条，见 tools/compute_expected.py 同类算法）：
  声调第 1 位=4 → 84；拼音第 1 位含 an → 53；两者同时 → 14。

用法：python tools\test_cy_search_btn.py [设备] [标签]
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
TAG = sys.argv[2] if len(sys.argv) > 2 else DEV.replace('emulator-', 'emu')
ACT = 'com.wangchuan.fhlsearch/.MainActivity'
SHOTS = os.path.join(_ROOT, 'docs', 'shots')
OUT = os.path.join(_ROOT, '_analysis', 'cy_search_btn_%s.txt') % TAG

os.makedirs(os.path.join(_ROOT, '_analysis'), exist_ok=True)
sys.path.insert(0, os.path.join(_ROOT, 'tools'))
import drive_app as d  # noqa: E402
d.DEV = DEV

# 12 格的顺序：声调 0~3 → 拼音 4~7 → 单字 8~11
TONE = range(0, 4)
PINYIN = range(4, 8)
CHAR = range(8, 12)

# 空格子在 uiautomator 里会把 hint 当 text 报出来，判空时要先滤掉
HINTS = ('拼音', '声调', '字', '单字')


def run(*a):
    return subprocess.run([ADB, '-s', DEV] + list(a), capture_output=True,
                          timeout=240).stdout.decode('utf-8', 'replace')


def sh(c):
    return run('shell', c)


def cells():
    """返回 12 格的当前文本（hint 当空）"""
    return [('' if n['text'].strip() in HINTS else n['text'].strip())
            for n in d.nodes() if n['id'].endswith('/etCell')]


def by_kind(texts, idx):
    return [texts[i] for i in idx if i < len(texts)]


def set_cell(i, text, clear=0):
    d.tap('etCell', index=i, label='第 %d 格' % (i + 1))
    sh('input keyevent 123')
    if clear:
        sh('input keyevent ' + ' '.join(['67'] * clear))
    if text:
        sh('input text "%s"' % text)
    time.sleep(0.8)
    d.hide_ime()


def state():
    ns = d.nodes()
    search = any(n['id'].endswith('/btnSearch') for n in ns)
    acts = [n['text'] for n in ns
            if n['id'].endswith(('/btnClearAll', '/btnClearCurrent', '/btnSecondSearch')) and n['text']]
    summary = None
    for n in ns:
        if n['id'].endswith('/tvCondSummary'):
            summary = n['text']
    cnt = (d.find('tvResultCount', ns) or {}).get('text', '—')
    return search, acts, summary, cnt


lines = []
allok = True


def check(title, cond, detail=''):
    global allok
    allok = allok and bool(cond)
    lines.append('%-40s %s  %s' % (title, '✅' if cond else '❌', detail))
    print('   %-38s %s  %s' % (title, 'OK' if cond else 'FAIL', detail))


def shot(name):
    sh('screencap -p /sdcard/_s.png')
    run('pull', '/sdcard/_s.png', os.path.join(SHOTS, '%s.png' % name))
    sh('rm /sdcard/_s.png')


def expand_if_collapsed():
    """折叠时点摘要展开（GONE 的控件不会出现在 dump 里，所以看有没有 etCell）"""
    ns = d.nodes()
    if not any(n['id'].endswith('/etCell') for n in ns):
        d.tap('/layCondSummary$', label='展开修改')


def screen_width():
    m = re.search(r'(\d+)x(\d+)', sh('wm size') or '')
    return int(m.group(1)) if m else 0


# 平板（sw600dp 双栏）条件区常显、不折叠，摘要也不显示；手机单栏才折叠
WIDE = screen_width() >= 1200


sh('am start -S -n ' + ACT)
time.sleep(6)
d.tap('成语检索', by='text', label='导航·成语')
time.sleep(2)

# ① 初始：12 格同屏、检索键在、无摘要
c = cells()
s, acts, summary, cnt = state()
check('① 三组 12 格同屏常显', len(c) == 12, '实际 %d 格' % len(c))
check('① 无摘要、检索键显示、上方无按键', summary is None and s and len(acts) == 0,
      '摘要=%s 检索键=%s 上方键=%d' % (summary, s, len(acts)))

# ② 填拼音第 1 格 an（还没检索）
set_cell(4, 'an')
c = cells()
s, acts, summary, cnt = state()
check('② 填了条件还没检索 → 检索键仍显示', s and summary is None, '检索键=%s' % s)
check('② 内容落在拼音组第 1 格', by_kind(c, PINYIN)[0] == 'an', '拼音组=%s' % by_kind(c, PINYIN))
shot('cy_v32_1_filled_%s' % TAG)

# ③ 检索 → 53 条；手机端折叠
d.tap('btnSearch', label='检索')
time.sleep(2.5)
s, acts, summary, cnt = state()
check('③ 拼音 an → 53 条', '(53)' in cnt, cnt)
if WIDE:
    check('③ 平板双栏：条件区常显、不出摘要', summary is None and len(cells()) == 12,
          '摘要=%s 格数=%d' % (summary, len(cells())))
else:
    check('③ 出结果后折叠成摘要', summary is not None and '第 1 位' in (summary or '') and 'an' in (summary or ''),
          '摘要=%s' % summary)
check('③ 上方按键保留 3 个', len(acts) == 3, '%s' % acts)
check('③ 检索键隐藏（第十一轮规则）', not s, '检索键=%s' % s)
shot('cy_v32_2_collapsed_%s' % TAG)

# ④ 结果逐字对齐：同一列 声调/拼音/单字 的左边界一致
ns = d.nodes()
tones = [n for n in ns if n['id'].endswith('/tvTone')][:4]
pys = [n for n in ns if n['id'].endswith('/tvPinyin')][:4]
chars = [n for n in ns if n['id'].endswith('/tvChar')][:4]
texts = [n['text'] for n in chars]
aligned = len(tones) == len(pys) == len(chars) == 4 and all(
    abs(tones[i]['bounds'][0] - pys[i]['bounds'][0]) <= 3 and
    abs(pys[i]['bounds'][0] - chars[i]['bounds'][0]) <= 3 for i in range(4))
check('④ 首条 4 列 × 3 行齐备', len(tones) == 4 and len(texts) == 4,
      '声调=%d 拼音=%d 单字=%d 首条=%s' % (len(tones), len(pys), len(chars), ''.join(texts)))
check('④ 逐字左右对齐（同列左边界一致）', aligned,
      '声调x=%s 拼音x=%s 单字x=%s' % ([n['bounds'][0] for n in tones],
                                     [n['bounds'][0] for n in pys],
                                     [n['bounds'][0] for n in chars]))

# ⑤ 展开 → 输入内容还在
expand_if_collapsed()
time.sleep(1)
c = cells()
s, acts, summary, cnt = state()
check('⑤ 展开后输入内容保留', len(c) == 12 and by_kind(c, PINYIN)[0] == 'an',
      '拼音组=%s' % by_kind(c, PINYIN))
check('⑤ 展开状态下检索键仍隐藏', not s, '检索键=%s' % s)
shot('cy_v32_3_expanded_%s' % TAG)

# ⑥ 三组混合：声调第 1 位=4 + 拼音第 1 位=an → 14 条
d.tap('清空所有', by='text', label='清空所有')
time.sleep(1.5)
c = cells()
s, acts, summary, cnt = state()
check('⑥ 清空所有 → 回到初始且输入清空', summary is None and s and all(x == '' for x in c),
      '摘要=%s 检索键=%s 输入=%s' % (summary, s, c))

set_cell(0, '4')
set_cell(4, 'an')
d.tap('btnSearch', label='检索(声4+拼an)')
time.sleep(2.5)
s, acts, summary, cnt = state()
check('⑥ 声调 1 位=4 且 拼音 1 位=an → 14 条', '(14)' in cnt, cnt)
if WIDE:
    check('⑥ 平板：无摘要、输入仍在', summary is None and by_kind(cells(), TONE)[0] == '4',
          '摘要=%s' % summary)
else:
    check('⑥ 摘要同时列出声与拼', '声 4' in (summary or '') and '拼 an' in (summary or ''),
          '摘要=%s' % summary)
shot('cy_v32_4_mixed_%s' % TAG)

# ⑦ 没命中 → 不折叠、检索键保持显示（否则用户没法改条件重搜）
d.tap('清空所有', by='text', label='清空所有')
time.sleep(1.5)
set_cell(4, 'zzz')
d.tap('btnSearch', label='检索(zzz)')
time.sleep(2.5)
s, acts, summary, cnt = state()
check('⑦ 没命中 → 不折叠、检索键保持显示', s and summary is None, '检索键=%s 摘要=%s' % (s, summary))
shot('cy_v32_5_noresult_%s' % TAG)

lines.append('')
lines.append('总体: %s' % ('✅ 三组同屏 / 折叠展开 / 逐字对齐 / 内容保留 全部符合预期'
                        if allok else '❌ 有不符合预期的地方'))
print('总体:', 'OK' if allok else 'FAILED')
io.open(OUT, 'w', encoding='utf-8').write('\n'.join(lines))
print('written', OUT)
