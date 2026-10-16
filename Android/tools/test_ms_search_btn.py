# -*- coding: utf-8 -*-
r"""名士检索：底部"检索"键的显隐规则验证。

规则：初始状态显示；**首次检索出结果后就自动收起**（此后都走上方的"二次检索"，
      条件改来改去也不再把它放回来）；"清空所有"或"清空当前"退到最后一层之下
      （回到初始状态）时自动恢复。

用法：python tools\test_ms_search_btn.py [设备]
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
OUT = os.path.join(_ROOT, '_analysis', 'ms_search_btn_%s.txt') % DEV.replace('-', '_')

os.makedirs(os.path.join(_ROOT, '_analysis'), exist_ok=True)
sys.path.insert(0, os.path.join(_ROOT, 'tools'))
import drive_app as d  # noqa: E402
d.DEV = DEV


def run(*a):
    return subprocess.run([ADB, '-s', DEV] + list(a), capture_output=True,
                          timeout=240).stdout.decode('utf-8', 'replace')


def sh(c):
    return run('shell', c)


def state():
    """返回 (检索键是否可见, 上方三个键是否可见, 结果标题)"""
    ns = d.nodes()
    search = any(n['id'].endswith('/btnSearch') for n in ns)
    acts = [n['text'] for n in ns
            if n['id'].endswith(('/btnClearAll', '/btnClearCurrent', '/btnSecondSearch')) and n['text']]
    cnt = (d.find('tvResultCount', ns) or {}).get('text', '—')
    return search, acts, cnt


lines = []
allok = True


def check(title, expect_search, expect_acts=None, expect_count=None):
    global allok
    s, acts, cnt = state()
    ok = (s == expect_search)
    if expect_acts is not None:
        ok = ok and (len(acts) == expect_acts)
    if expect_count is not None:
        ok = ok and (expect_count in cnt)
    allok = allok and ok
    lines.append('%-32s 检索键=%-4s 上方键=%-34s 结果=%-12s %s' % (
        title, '显示' if s else '隐藏', acts, cnt, '✅' if ok else '❌'))
    print('   %-30s 检索键=%-4s 上方键=%-32s 结果=%-12s %s' % (
        title, '显示' if s else '隐藏', acts, cnt, 'OK' if ok else 'FAIL'))
    return ok


sh('am start -S -n ' + ACT)
time.sleep(6)
d.tap('名士检索', by='text', label='导航·名士')
time.sleep(2)

check('① 初始状态', True, 0)

d.tap('^朝代$', by='text', label='朝代'); time.sleep(1.5)
d.pick_option(d.DYNASTY, '唐')
check('② 选了条件（还没检索）', True, 0)

d.tap('btnSearch', label='检索'); time.sleep(2)
check('③ 首次检索后 → 自动收起', False, 3, '(23)')

d.tap('二次检索', by='text', label='二次检索'); time.sleep(1.5)
check('④ 没挑新条件就点二次检索', False, 3)

d.tap('^爱好$', by='text', label='爱好'); time.sleep(1.5)
d.pick_option(d.LOVE, '书画')
check('⑤ 二次检索里挑了条件 → 仍不收放', False, 3)

# 语义：点"二次检索"当场就在上一次结果里再筛（唐 23 位 + 爱好书画 = 2 位）
d.tap('二次检索', by='text', label='二次检索(执行)'); time.sleep(2)
check('⑥ 二次检索当场出结果', False, 3, '(2)')

d.tap('^清空当前$', by='text', label='清空当前'); time.sleep(1.5)
check('⑦ 清空当前 → 退回上一层（唐 23）', False, 3, '(23)')

d.tap('^清空当前$', by='text', label='清空当前'); time.sleep(1.5)
check('⑧ 再清空当前 → 回到初始状态', True, 0)

# 小屏（API 29）上"清空当前"后页面可能还停在结果那一屏，条件行在视野外 →
# 先拨回条件区再挑，否则会点空（这一步点空过，属于脚本问题，不是程序问题）
if not d.find('^朝代$', by='text'):
    d.scroll_page_back(3)
d.tap('^朝代$', by='text', label='朝代'); time.sleep(1.5)
d.pick_option(d.DYNASTY, '辽')          # 辽 = 0 位，用来验证"没命中不会被藏键卡住"
d.tap('btnSearch', label='检索(辽)'); time.sleep(2)
check('⑨ 首次就没命中 → 检索键保持显示', True, 2)

d.tap('^清空所有$', by='text', label='清空所有'); time.sleep(1.5)
check('⑩ 清空所有 → 恢复', True, 0)

lines.append('')
lines.append('总体: %s' % ('✅ 显隐规则全部符合预期' if allok else '❌ 有不符合预期的状态'))
print('总体:', 'OK' if allok else 'FAILED')
io.open(OUT, 'w', encoding='utf-8').write('\n'.join(lines))
print('written', OUT)
