# -*- coding: utf-8 -*-
r"""名士检索 v3.2：选项面板的**显示顺序**。

规则（v3.2）：朝代的选项按历史时间顺序从上到下，「梦」排最下；
其余需要选择的（爱好 / 社团 / 品级 / 职业 / 特技…）按拼音首字母 A~Z 从上到下；
手动输入的（名士名）不受影响。

做法：依次打开每个选项面板，把滚轮里的文字按 y 坐标读出来——
  a) 顶部几项必须等于期望列表的前几项；
  b) 把滚轮一路滑到底，最后一项必须等于期望列表的末项。
这样不用滚动全程也能确认"头对、尾对、中间没跑偏"（项数少时直接全量比对）。

用法：python tools\test_ms_options_order.py [设备] [标签]
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
OUT = os.path.join(_ROOT, '_analysis', 'ms_options_order_%s.txt') % TAG
os.makedirs(os.path.join(_ROOT, '_analysis'), exist_ok=True)

sys.path.insert(0, os.path.join(_ROOT, 'tools'))
import drive_app as d  # noqa: E402
d.DEV = DEV

# 期望顺序（独立于代码写死，代码改错了这里才报）
EXPECT = [
    # 朝代：历史时间顺序，梦最末
    ('朝代', ['先秦', '秦', '西楚', '汉', '三国', '晋', '南北朝', '唐',
             '五代十国', '宋', '辽', '元', '明', '清', '梦']),
    # 爱好：bo pin shang shi shu ya yan yi yue zhuang
    ('爱好', ['博文', '品茗', '赏玩', '食珍', '书画', '雅宴', '演武', '弈棋', '乐舞', '妆饰']),
    # 社团：bai jin qian rong tang tao wu wu yi
    ('社团', ['百家书院', '金戈馆', '千工苑', '容华社', '棠梨坊', '饕餮居', '无', '五湖商社', '逸趣社']),
    # 品阶：di tian xuan
    ('品阶', ['地', '天', '玄']),
]


def run(*a):
    return subprocess.run([ADB, '-s', DEV] + list(a), capture_output=True,
                          timeout=240).stdout.decode('utf-8', 'replace')


def sh(c):
    return run('shell', c)


def shot(name):
    sh('screencap -p /sdcard/_s.png')
    run('pull', '/sdcard/_s.png', os.path.join(SHOTS, '%s.png' % name))
    sh('rm /sdcard/_s.png')


def wheel_items(pool):
    """滚轮里当前可见的选项文字，按 y 从小到大"""
    out = []
    for n in d.nodes():
        t = n['text'].strip()
        if t in pool:
            out.append((n['center'][1], n['bounds'][0], t))
    out.sort()
    return [t for _, _, t in out]


def scroll_to_bottom(pool, limit=24):
    """在滚轮范围内一格一格往下滑，直到内容不再变化（= 到底）。

    坐标一律按 wheel 的实际 bounds 算 —— 平板（1600x2560）和 API29（1080x1920）
    的滚轮位置与手机不同，写死坐标会滑到空白处、一格都不动。
    """
    prev = None
    for _ in range(limit):
        wh, _cur, items = d.wheel_state()
        if not wh:
            return
        x1, y1, x2, y2 = wh['bounds']
        cx = (x1 + x2) // 2
        cy = (y1 + y2) // 2
        gaps = [items[i + 1][1] - items[i][1] for i in range(len(items) - 1)]
        item_h = min(gaps) if gaps else max(1, (y2 - y1) // 5)
        cur_items = [t for t, _ in items]
        if cur_items == prev:
            return                      # 滑不动了 → 到底
        prev = cur_items
        sh('input swipe %d %d %d %d 420' % (cx, cy + item_h, cx, cy - item_h))
        time.sleep(0.45)


lines = []
allok = True


def check(title, cond, detail=''):
    global allok
    allok = allok and bool(cond)
    lines.append('%-46s %s  %s' % (title, '✅' if cond else '❌', detail))
    print('   %-44s %s  %s' % (title, 'OK' if cond else 'FAIL', detail))


sh('am start -S -n ' + ACT)
time.sleep(6)
d.tap('名士检索', by='text', label='导航·名士')
time.sleep(2)

for name, expect in EXPECT:
    pool = set(expect)
    d.tap('^%s$' % name, by='text', label='打开「%s」面板' % name)
    time.sleep(2.0)
    got = wheel_items(pool)
    head_n = min(3, len(expect))
    check('%s · 顶部顺序' % name, got[:head_n] == expect[:head_n],
          '期望 %s / 实际 %s' % (expect[:head_n], got[:head_n]))
    if len(expect) <= 4:            # 项数少，一次就全看到了
        check('%s · 全量顺序' % name, got == expect, '期望 %s / 实际 %s' % (expect, got))
    # 一路滑到底看末项
    scroll_to_bottom(pool)
    time.sleep(1.0)
    got = wheel_items(pool)
    check('%s · 末项（滑到底）' % name, got[-1:] == expect[-1:],
          '期望末项 %s / 实际末尾 %s' % (expect[-1:], got[-3:]))
    shot('ms_order_%s_%s' % (TAG, name))
    # 滚轮面板没有"取消"键，按返回键关掉
    sh('input keyevent 4')
    time.sleep(1.2)

lines.append('')
lines.append('总体: %s' % ('✅ 朝代按时间序、其余按拼音序' if allok else '❌ 有顺序不符'))
print('总体:', 'OK' if allok else 'FAILED')
io.open(OUT, 'w', encoding='utf-8').write('\n'.join(lines))
print('written', OUT)
