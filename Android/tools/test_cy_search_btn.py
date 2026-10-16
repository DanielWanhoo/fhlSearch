# -*- coding: utf-8 -*-
r"""成语检索：底部"检索"键的显隐规则验证（第十一轮）。

规则：初始状态显示；**首次检索出结果后就自动收起**（此后要接着筛都用上方的"二次检索"）；
      "清空所有"、或"清空当前"退到最后一层之下（回到初始状态）时自动恢复；
      没命中的检索不算"有结果"，检索键保持显示，避免把用户卡住。

用法：python tools\test_cy_search_btn.py [设备]
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
ACT = 'com.wangchuan.fhlsearch/.MainActivity'
OUT = os.path.join(_ROOT, '_analysis', 'cy_search_btn_%s.txt') % DEV.replace('-', '_')

os.makedirs(os.path.join(_ROOT, '_analysis'), exist_ok=True)
sys.path.insert(0, os.path.join(_ROOT, 'tools'))
import drive_app as d  # noqa: E402
d.DEV = DEV

# 空格子在 uiautomator 里会把 hint 当 text 报出来，判空时要先滤掉
HINTS = ('拼音', '声调', '单字')


def run(*a):
    return subprocess.run([ADB, '-s', DEV] + list(a), capture_output=True,
                          timeout=240).stdout.decode('utf-8', 'replace')


def sh(c):
    return run('shell', c)


def set_cell(i, text, clear=0):
    """往第 i 格里写内容（可先退格若干次清空）"""
    d.tap('etCell', index=i, label='第 %d 格' % (i + 1))
    sh('input keyevent 123')                                  # 光标移到行尾
    if clear:
        sh('input keyevent ' + ' '.join(['67'] * clear))      # 退格
    if text:
        sh('input text "%s"' % text)
    time.sleep(0.8)
    d.hide_ime()


def state():
    """返回 (检索键是否可见, 上方按键文案, 结果标题, 四格输入内容)"""
    ns = d.nodes()
    search = any(n['id'].endswith('/btnSearch') for n in ns)
    acts = [n['text'] for n in ns
            if n['id'].endswith(('/btnClearAll', '/btnClearCurrent', '/btnSecondSearch')) and n['text']]
    cnt = (d.find('tvResultCount', ns) or {}).get('text', '—')
    cells = [('' if n['text'].strip() in HINTS else n['text'].strip())
             for n in ns if n['id'].endswith('/etCell')]
    return search, acts, cnt, cells


lines = []
allok = True


def check(title, expect_search, expect_acts=None, expect_count=None, expect_cells=None):
    global allok
    s, acts, cnt, cells = state()
    ok = (s == expect_search)
    if expect_acts is not None:
        ok = ok and (len(acts) == expect_acts)
    if expect_count is not None:
        ok = ok and (expect_count in cnt)
    if expect_cells is not None:
        ok = ok and (cells == expect_cells)
    allok = allok and ok
    lines.append('%-36s 检索键=%-4s 上方键=%-32s 结果=%-11s 输入=%s %s' % (
        title, '显示' if s else '隐藏', acts, cnt, cells, '✅' if ok else '❌'))
    print('   %-34s 检索键=%-4s 上方键=%-30s 结果=%-10s 输入=%s %s' % (
        title, '显示' if s else '隐藏', acts, cnt, cells, 'OK' if ok else 'FAIL'))
    return ok


sh('am start -S -n ' + ACT)
time.sleep(6)
d.tap('成语检索', by='text', label='导航·成语')
time.sleep(2)

check('① 初始状态', True, 0, None, ['', '', '', ''])

set_cell(0, 'an')
check('② 填了条件（还没检索）', True, 0, None, ['an', '', '', ''])

d.tap('btnSearch', label='检索'); time.sleep(2)
check('③ 首次检索后 → 自动收起', False, 3, '(53)', ['an', '', '', ''])

# 补第 2 格 → 点二次检索当场缩到 1 条（暗渡陈仓）；1 条时按需求不给"二次检索"
set_cell(1, 'du')
d.tap('二次检索', by='text', label='二次检索(执行)'); time.sleep(2)
check('④ 二次检索当场出结果', False, 2, '(1)', ['an', 'du', '', ''])

d.tap('^清空当前$', by='text', label='清空当前'); time.sleep(1.5)
check('⑤ 清空当前 → 退回上一层（53 条）', False, 3, '(53)', ['an', 'du', '', ''])

d.tap('^清空所有$', by='text', label='清空所有'); time.sleep(1.5)
check('⑥ 清空所有 → 回到初始状态并清空输入', True, 0, None, ['', '', '', ''])

# 「清空当前」退到最后一层之下也要恢复检索键（此时输入内容保留）
set_cell(0, 'an')
d.tap('btnSearch', label='检索'); time.sleep(2)
check('⑦ 再检索一次', False, 3, '(53)', ['an', '', '', ''])
d.tap('^清空当前$', by='text', label='清空当前'); time.sleep(1.5)
check('⑧ 清空当前退到最后一层之下 → 恢复', True, 0, None, ['an', '', '', ''])

# 没命中的检索：不该把检索键藏起来（否则用户没法改条件重搜）
set_cell(0, 'zzz', clear=6)
d.tap('btnSearch', label='检索(zzz)'); time.sleep(2)
check('⑨ 首次就没命中 → 检索键保持显示', True, 2, None, ['zzz', '', '', ''])

lines.append('')
lines.append('总体: %s' % ('✅ 显隐规则全部符合预期' if allok else '❌ 有不符合预期的状态'))
print('总体:', 'OK' if allok else 'FAILED')
io.open(OUT, 'w', encoding='utf-8').write('\n'.join(lines))
print('written', OUT)
