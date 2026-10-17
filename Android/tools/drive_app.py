# -*- coding: utf-8 -*-
r"""在已启动的模拟器上走一遍界面流程并抓图。

用法：
    python drive_app.py [设备序列号] [标签]
    python drive_app.py emulator-5554 phone
    python drive_app.py emulator-5556 tablet

设计要点：
  · 通过 uiautomator 的 resource-id / text 精确定位控件，不用硬编码坐标；
  · 每次点击前先收起软键盘（键盘会盖住底部导航，导致点击落空）；
  · 结束时检查 crash buffer，确认没有崩溃。
"""
import os
import re
import subprocess
import sys
import time


# ---- 路径：全部按"本脚本所在位置"推算，克隆到任何目录下都能直接跑 ----
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SDK = os.path.join(os.environ.get('LOCALAPPDATA', ''), 'Android', 'Sdk')
ADB = os.path.join(SDK, 'platform-tools', 'adb.exe')
# 默认装 debug 包；想验证正式包就设 FHL_APK 环境变量指向 dist\fhlSearch.apk
APK = os.environ.get('FHL_APK') or os.path.join(_ROOT, 'app', 'build', 'outputs', 'apk', 'debug', 'app-debug.apk')
SHOTS = os.path.join(_ROOT, 'docs', 'shots')
PKG = 'com.wangchuan.fhlsearch'
ACT = PKG + '/.MainActivity'

DEV = 'emulator-5554'
TAG = 'phone'


def run(*args, timeout=240):
    p = subprocess.run([ADB, '-s', DEV] + list(args), capture_output=True, timeout=timeout)
    return (p.stdout + p.stderr).decode('utf-8', 'replace')


def sh(cmd, timeout=240):
    return run('shell', cmd, timeout=timeout)


def wait(sec=1.0):
    time.sleep(sec)


def hide_ime():
    sh('input keyevent 111')      # ESC 收起输入法（不用 BACK，避免退出界面）
    wait(0.5)


def shot(name):
    os.makedirs(SHOTS, exist_ok=True)
    sh('screencap -p /sdcard/_s.png')
    run('pull', '/sdcard/_s.png', os.path.join(SHOTS, '%s_%s.png' % (TAG, name)))
    sh('rm /sdcard/_s.png')
    print('   截图 → %s_%s.png' % (TAG, name))


def nodes():
    xml = ''
    for _ in range(3):
        sh('uiautomator dump /sdcard/_ui.xml')
        xml = run('shell', 'cat /sdcard/_ui.xml')
        if '<hierarchy' in xml:
            break
        wait(1)
    out = []
    for m in re.finditer(r'<node\b[^>]*?(?:/>|>)', xml):
        n = m.group(0)
        rid = re.search(r'resource-id="([^"]*)"', n)
        txt = re.search(r'text="([^"]*)"', n)
        cls = re.search(r'class="([^"]*)"', n)
        b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
        if not b:
            continue
        x1, y1, x2, y2 = map(int, b.groups())
        out.append({
            'id': rid.group(1) if rid else '',
            'text': txt.group(1) if txt else '',
            'cls': cls.group(1) if cls else '',
            'bounds': (x1, y1, x2, y2),
            'center': ((x1 + x2) // 2, (y1 + y2) // 2),
        })
    return out


def find(pattern, ns=None, index=0, by='id'):
    ns = ns if ns is not None else nodes()
    hits = []
    for n in ns:
        hay = n['id'] if by == 'id' else n['text']
        if re.search(pattern, hay):
            hits.append(n)
    return hits[index] if len(hits) > index else None


def tap(pattern, index=0, by='id', label='', extra=None, hide_kb=True):
    # 关键：先收起输入法，再取控件坐标——否则键盘占位会让坐标整体偏移。
    # 例外：底部面板（BottomSheet）打开时不能按 ESC，否则会把面板一起关掉。
    if hide_kb:
        hide_ime()
    ns = nodes() if extra is None else extra
    n = find(pattern, ns, index=index, by=by)
    if not n:
        print('   ⚠ 找不到控件: %s' % pattern)
        return False
    sh('input tap %d %d' % n['center'])
    wait(1.0)
    print('   点击 %s' % (label or pattern))
    return True


def tap_cell(row, col):
    """按 6×5 网格点击诗词字格（按容器 bounds 换算）"""
    ns = nodes()
    g = find('ShiciGrid|/grid$', ns, by='id') or find('/grid', ns, by='id')
    if not g:
        print('   ⚠ 找不到字格容器')
        return False
    x1, y1, x2, y2 = g['bounds']
    cw = (x2 - x1) / 6.0
    chh = (y2 - y1) / 5.0
    cx = int(x1 + cw * (col + 0.5))
    cy = int(y1 + chh * (row + 0.5))
    sh('input tap %d %d' % (cx, cy))
    wait(0.5)
    return True


def wheel_state(ns=None):
    """返回 (滚轮控件, 正中那一项的文本, 可见项[(文本, 中线y)... 按 y 升序])"""
    ns = ns if ns is not None else nodes()
    wh = find(r'/wheel$', ns, by='id')
    if not wh:
        return None, None, []
    x1, y1, x2, y2 = wh['bounds']
    cy = (y1 + y2) // 2
    items = []
    for n in ns:
        if not n['text'] or n['cls'] != 'android.widget.TextView':
            continue
        ix1, iy1, ix2, iy2 = n['bounds']
        if ix1 >= x1 - 5 and ix2 <= x2 + 5 and iy2 > y1 - 5 and iy1 < y2 + 5:
            items.append(((iy1 + iy2) // 2, n['text']))
    items.sort()
    best = min(items, key=lambda t: abs(t[0] - cy))[1] if items else None
    return wh, best, [(t, y) for y, t in items]


# 各选项型条件的候选项顺序（与 MingshiFragment 里一致），用来算该往哪个方向滚
DYNASTY = ['汉', '明', '秦', '三国', '宋', '唐', '五代十国', '西楚', '晋', '先秦', '梦',
           '南北朝', '清', '元', '辽']
LOVE = ['博文', '乐舞', '品茗', '赏玩', '食珍', '书画', '雅宴', '演武', '弈棋', '妆饰']
CLUB = ['百家书院', '千工苑', '金戈馆', '容华社', '棠梨坊', '饕餮居', '五湖商社', '逸趣社', '无']
RANK = ['天', '地', '玄']


def wheel_pick(options, target, limit=14):
    """在已弹出的滚轮面板里滚到目标项（面板由调用方先点开）。

    策略：目标若已在可见项里就直接点它（滚轮支持点选，精确命中）；
    否则按「两格一步」滑动逼近——实测 2 倍格高 + 500ms 的慢滑没有惯性误差，
    而一步一格或快速滑动会因为惯性多走/少走，导致在两格之间来回振荡。
    """
    prev = None
    same_count = 0
    for _ in range(limit):
        ns = nodes()
        wh, cur, items = wheel_state(ns)
        if not wh:
            print('   ⚠ 找不到滚轮控件')
            return False
        if cur == target:
            print('   滚轮选中 %s' % target)
            return True
        # 目标已经露出来了 → 直接点它
        hit = [n for n in ns if n['text'] == target and n['cls'] == 'android.widget.TextView'
               and abs(n['center'][0] - (wh['bounds'][0] + wh['bounds'][2]) // 2) < 100]
        if hit:
            sh('input tap %d %d' % hit[0]['center'])
            wait(1.3)
            _, cur2, _ = wheel_state(nodes())
            if cur2 == target:
                print('   滚轮点选 %s' % target)
                return True
            cur = cur2
        try:
            delta = options.index(target) - options.index(cur)
        except ValueError:
            print('   ⚠ 滚轮里没有 %s（当前 %s）' % (target, cur))
            return False
        x1, y1, x2, y2 = wh['bounds']
        cx = (x1 + x2) // 2
        cy = (y1 + y2) // 2
        gaps = [items[i + 1][1] - items[i][1] for i in range(len(items) - 1)]
        item_h = min(gaps) if gaps else max(1, (y2 - y1) // 5)
        # 两格一步；只剩一格时用一格（慢速，尽量少误差）
        steps = 2 if abs(delta) >= 2 else 1
        dy = item_h * steps
        dur = 500 if steps == 2 else 620
        if delta > 0:
            sh('input swipe %d %d %d %d %d' % (cx, cy + dy, cx, cy - dy, dur))
        else:
            sh('input swipe %d %d %d %d %d' % (cx, cy - dy, cx, cy + dy, dur))
        wait(1.3)
        if cur == prev:
            same_count += 1
            if same_count >= 3:          # 卡住了：换成一格的小步再试
                same_count = 0
        else:
            same_count = 0
            prev = cur
    print('   ⚠ 滚轮没能滚到 %s' % target)
    return False


def pick_option(options, target):
    """在滚轮面板里滚到目标项并点「确定」"""
    wheel_pick(options, target)
    return tap('/btnWheelConfirm$', label='滚轮·确定', hide_kb=False)


def screen_size():
    out = sh('wm size')
    m = re.search(r'(\d+)x(\d+)', out)
    return (int(m.group(1)), int(m.group(2))) if m else (1080, 2400)


def scroll_page_back(times=3):
    """把页面内容往回拨（朝顶部方向），用于把已经滚出视野的条件行拉回来。

    横坐标取屏宽的 22%：手机上是整栏、平板上正好落在左栏（条件栏）里。
    """
    w, h = screen_size()
    x = int(w * 0.22)
    for _ in range(times):
        sh('input swipe %d %d %d %d 260' % (x, int(h * 0.32), x, int(h * 0.72)))
        wait(0.6)


def crashes():
    out = run('logcat', '-d', '-b', 'crash')
    return [l for l in out.splitlines() if 'FATAL EXCEPTION' in l or 'at com.wangchuan' in l]


def main():
    global DEV, TAG
    if len(sys.argv) > 1:
        DEV = sys.argv[1]
    if len(sys.argv) > 2:
        TAG = sys.argv[2]

    print('== 设备 %s （%s）==' % (DEV, TAG))
    print(' ', run('install', '-r', APK).strip().splitlines()[-1])
    sh('logcat -c')
    sh('am start -S -n ' + ACT)
    wait(6)

    # ---------------- 成语检索 ----------------
    print('→ 成语检索')
    shot('chengyu_init')
    tap('etCell', index=0, label='拼音第 1 格')
    sh('input text "an"'); wait(0.8)
    hide_ime()
    tap('btnSearch', label='检索')
    wait(2)
    ns = nodes()
    print('   结果:', (find('tvResultCount', ns) or {}).get('text', '—'))
    print('   按钮:', [n['text'] for n in ns if n['id'].endswith(('btnClearAll', 'btnClearCurrent', 'btnSecondSearch')) and n['text']])
    shot('chengyu_result')

    # 切到"声调"模式做二次检索
    tap('声调', by='text', label='声调选项卡')
    wait(1)
    shot('chengyu_tone_tab')

    # 题库修复回归：拼音第 1 格 gou → 应命中「狗急跳墙」（原题库误写作 go）
    # 注意：成语模块的第二次检索默认在"上一次结果"里筛，所以要先清空所有检索
    tap('拼音', by='text', label='拼音选项卡')
    wait(1)
    tap('^清空所有$', by='text', label='清空所有')
    wait(1)
    tap('etCell', index=0, label='拼音第 1 格')
    sh('input text "gou"'); wait(0.8)
    hide_ime()
    tap('btnSearch', label='检索(gou)')
    wait(2)
    ns = nodes()
    print('   gou 检索:', (find('tvResultCount', ns) or {}).get('text', '—'),
          [n['text'] for n in ns if n['id'].endswith('/tvCyWord')][:2])
    shot('chengyu_gou')

    # ---------------- 诗词检索 ----------------
    print('→ 诗词检索')
    tap('诗词检索', by='text', label='底部导航·诗词检索')
    wait(2)
    shot('shici_init')
    # 自动化注入示例字格（中文输入法难以通过 adb input text 模拟）
    sh('am broadcast -a com.wangchuan.fhlsearch.action.FILL_SHICI_TEST')
    wait(1)
    hide_ime()
    wait(0.5)
    shot('shici_filled')
    tap('btnSearch', label='开始检索')
    wait(2.5)
    ns = nodes()
    print('   结果:', (find('tvResultCount', ns) or {}).get('text', '—'))
    print('   命中行:', [n['text'] for n in ns if '·' in n['text']][:3])
    shot('shici_result')

    # ---------------- 名士检索 ----------------
    print('→ 名士检索')
    tap('名士检索', by='text', label='底部导航·名士检索')
    wait(2)
    shot('mingshi_init')
    tap('朝代', by='text', label='朝代条件行')
    wait(1.5)
    shot('mingshi_dynasty_sheet')
    pick_option(DYNASTY, '唐')
    shot('mingshi_dynasty_picked')
    tap('btnSearch', label='检索')
    wait(2)
    ns = nodes()
    print('   结果:', (find('tvResultCount', ns) or {}).get('text', '—'))
    print('   按钮:', [n['text'] for n in ns if n['id'].endswith(('btnClearAll', 'btnClearCurrent', 'btnSecondSearch')) and n['text']])
    shot('mingshi_result_tang')

    # 点结果第一行 → 名士详情
    first = None
    for n in ns:
        if n['id'].endswith('/tvMsName') and n['text']:
            first = n
            break
    if first and tap('/tvMsName$', label='结果第一行·%s' % first['text'], hide_kb=False):
        wait(2)
        nd = nodes()
        nm = find('/tvDetailName$', nd)
        hd = find('/tvDescHeader$', nd)
        print('   详情:', (nm or {}).get('text', '—'), '|', (hd or {}).get('text', '—'))
        shot('mingshi_detail')
        tap('/btnDetailClose$', label='详情·关闭', hide_kb=False)
        wait(1)

    # 二次检索：爱好 → 书画（新语义：挑完条件直接点"二次检索"当场出结果）
    scroll_page_back(3)          # 检索后页面已滚到结果处，先把条件行拨回来
    if tap('爱好', by='text', label='爱好条件行'):
        wait(1.5)
        pick_option(LOVE, '书画')
        tap('二次检索', by='text', label='二次检索(执行)')
        wait(2)
        ns = nodes()
        print('   结果:', (find('tvResultCount', ns) or {}).get('text', '—'))
        shot('mingshi_result_tang_shuhua')

    print('== 崩溃检查 ==')
    c = crashes()
    if c:
        print('  [X] 检测到崩溃：')
        for l in c[:12]:
            print('   ', l.strip())
    else:
        print('  [OK] 无崩溃')


if __name__ == '__main__':
    main()
