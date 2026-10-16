# -*- coding: utf-8 -*-
r"""在模拟器上跑一遍三大模块的检索，抓图并检查是否有崩溃。

用法：
    python verify_app.py                 # 默认 emulator-5554
    python verify_app.py emulator-5554
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
APK = os.path.join(_ROOT, 'app', 'build', 'outputs', 'apk', 'debug', 'app-debug.apk')
SHOTS = os.path.join(_ROOT, 'docs', 'shots')
PKG = 'com.wangchuan.fhlsearch'
ACT = PKG + '/.MainActivity'


def run(*args, timeout=180):
    p = subprocess.run([ADB, '-s', DEV] + list(args), capture_output=True, timeout=timeout)
    return p.returncode, p.stdout.decode('utf-8', 'replace'), p.stderr.decode('utf-8', 'replace')


def shell(cmd, timeout=180):
    return run('shell', cmd, timeout=timeout)


def shot(name):
    os.makedirs(SHOTS, exist_ok=True)
    shell('screencap -p /sdcard/_s.png')
    run('pull', '/sdcard/_s.png', os.path.join(SHOTS, name))
    shell('rm /sdcard/_s.png')
    print('  截图 →', name)


def ui_dump():
    """导出界面层级，便于按 id/文案定位控件。"""
    shell('uiautomator dump /sdcard/_ui.xml')
    p = subprocess.run([ADB, '-s', DEV, 'shell', 'cat', '/sdcard/_ui.xml'],
                       capture_output=True, timeout=120)
    return p.stdout.decode('utf-8', 'replace')


def find_bounds(xml, pattern):
    """按 text 或 resource-id 找控件的中心坐标。"""
    for m in re.finditer(r'<node[^>]*>', xml):
        node = m.group(0)
        text = re.search(r'text="([^"]*)"', node)
        rid = re.search(r'resource-id="([^"]*)"', node)
        hay = (text.group(1) if text else '') + '|' + (rid.group(1) if rid else '')
        if re.search(pattern, hay):
            b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', node)
            if b:
                x1, y1, x2, y2 = map(int, b.groups())
                if x2 > x1 and y2 > y1:
                    return (x1 + x2) // 2, (y1 + y2) // 2
    return None


def tap(x, y):
    shell('input tap %d %d' % (x, y))
    time.sleep(0.9)


def type_text(s):
    shell('input text "%s"' % s)
    time.sleep(0.6)


def crashes():
    _, out, _ = run('logcat', '-d', '-b', 'crash')
    return [l for l in out.splitlines() if 'FATAL' in l or PKG in l]


def main():
    print('== 安装 ==')
    rc, out, err = run('install', '-r', APK, timeout=300)
    print('  ', (out or err).strip().splitlines()[-1] if (out or err).strip() else rc)

    shell('logcat -c')
    shell('am start -S -n ' + ACT)
    time.sleep(6)

    steps = [
        ('01_chengyu_init', None),
        ('02_chengyu_pinyin_an', lambda: (tap(*find_bounds(ui_dump(), 'etCell')),
                                          type_text('an'),
                                          tap(*find_bounds(ui_dump(), 'btnSearch|检索')))),
        ('03_chengyu_result', None),
    ]
    for name, action in steps:
        if action:
            try:
                action()
            except TypeError:
                print('  ⚠ 未找到控件，跳过动作:', name)
        time.sleep(2)
        shot(name + '.png')

    print('== 崩溃检查 ==')
    c = crashes()
    if c:
        print('  ❌ 发现崩溃：')
        for l in c[:10]:
            print('   ', l)
    else:
        print('  ✅ 无崩溃')


if __name__ == '__main__':
    DEV = sys.argv[1] if len(sys.argv) > 1 else 'emulator-5554'
    main()
