# -*- coding: utf-8 -*-
r"""调试单张图片的识别过程：把图丢进手机跑一遍，然后只看「这一次」的日志。

和 test_ocr.py 的区别：那个是**回归**（一次跑 6 张、核对填充格数），
这个是**单张排查**（跑一张、打全过程日志、可选把拼板 PNG 拉回来）。

用法：
    python tools\ocr_one.py [设备] [图片路径] [--dump]

    --dump   连拼板一起拉回来（紧 / 柔 / 宽三趟，存到 _analysis\ocr_dump\）

看什么：
    1. `面板/整图 ... -> 5x6（点阵；行距 X，列距 Y）`  —— 走的哪条切格路径
    2. `拼板(紧) ... 30 / 30 格取到了墨迹；跳过 1,2:纯色`  —— 哪几格没取到字、为什么
    3. `第1趟（紧）认到 27 / 30`  —— 三趟各认到多少（两趟一致就只跑两趟）
    4. `字格:` 后面就是最终 30 格
    5. 界面若出现 `按题库补全：…`，说明是靠"按题库对一遍"救回来的

注意：
  * 只有 **debuggable 包** 才能用 `run-as` 往应用私有目录塞图；
    装的是正式包时请改用 `python tools\test_ocr_gallery.py`（走系统相册通道）。
  * 样例图放在哪都行，路径直接传进来；仓库里的 `data\ocr\test\` 也有默认值可试。
"""
import io
import os
import subprocess
import sys
import time

SDK = os.path.join(os.environ.get('LOCALAPPDATA', ''), 'Android', 'Sdk')
ADB = os.path.join(SDK, 'platform-tools', 'adb.exe')
DEV = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith('-') else 'emulator-5554'
DUMP = '--dump' in sys.argv
PKG = 'com.wangchuan.fhlsearch'
ACT = PKG + '/.MainActivity'

# 项目根目录（脚本在 tools\ 下）：拼板输出、样例图目录都按它推算，克隆到哪都能跑
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.makedirs(os.path.join(_ROOT, '_analysis'), exist_ok=True)
OUTDIR = os.path.join(_ROOT, '_analysis', 'ocr_dump')

# 没给图片路径时，从 data\ocr\test\ 里挑第一张（发布副本的约定位置）
_args = [a for a in sys.argv[2:] if not a.startswith('-')]
IMG = _args[0] if _args else ''
if not IMG:
    _dir = os.path.join(_ROOT, 'data', 'ocr', 'test')
    if os.path.isdir(_dir):
        _jpgs = sorted(f for f in os.listdir(_dir) if f.lower().endswith(('.jpg', '.png')))
        if _jpgs:
            IMG = os.path.join(_dir, _jpgs[0])
if not IMG or not os.path.isfile(IMG):
    print('用法：python tools\\ocr_one.py [设备] <本地图片路径> [--dump]')
    print('（没找到样例图；把带 6×5 字格的截图路径传进来即可）')
    raise SystemExit(2)

sys.path.insert(0, os.path.join(_ROOT, 'tools'))
import drive_app as d  # noqa: E402

d.DEV = DEV


def run(*a, timeout=180):
    return subprocess.run([ADB, '-s', DEV] + list(a), capture_output=True,
                          timeout=timeout).stdout.decode('utf-8', 'replace')


def run_bytes(*a, timeout=180):
    """取二进制输出（exec-out 不会被换行符转义搞坏 PNG）"""
    return subprocess.run([ADB, '-s', DEV] + list(a), capture_output=True,
                          timeout=timeout).stdout


def sh(c, timeout=180):
    return run('shell', c, timeout=timeout)


name = os.path.basename(IMG)
remote = '/data/data/%s/files/ocr/%s' % (PKG, name)

print('设备 %s   图片 %s%s' % (DEV, IMG, '   （连拼板一起拉回）' if DUMP else ''))
d.sh('am start -S -n %s' % ACT)
d.wait(6)
d.tap('诗词检索', by='text', label='导航·诗词')
d.wait(1.5)

run('push', IMG, '/data/local/tmp/_ocr.jpg')
sh('run-as %s mkdir -p files/ocr' % PKG)
sh('run-as %s cp /data/local/tmp/_ocr.jpg %s' % (PKG, remote))
sh('rm -f /data/local/tmp/_ocr.jpg')
if DUMP:
    sh('run-as %s mkdir -p files/ocr_dump' % PKG)
    sh('run-as %s rm -f files/ocr_dump/montage_tight.png '
       'files/ocr_dump/montage_soft.png files/ocr_dump/montage_loose.png' % PKG)
sh('logcat -c')
extra = ' --ez dump true' if DUMP else ''
print(sh('am broadcast -a %s.action.OCR_TEST --es path %s%s' % (PKG, remote, extra)).strip())

# 等到这一趟真的跑完（日志里出现「最终 N / 30 格」），最多等 90 秒
def finals():
    return run('logcat', '-d', '-s', 'FhlOcr').count('最终')


before = finals()
for _ in range(90):
    time.sleep(1)
    if finals() > before:
        time.sleep(1)
        break

print('=================== 日志 ===================')
print(sh('logcat', '-d', '-s', 'FhlOcr'))

if DUMP:
    os.makedirs(OUTDIR, exist_ok=True)
    pulled = []
    for fn in ('montage_tight.png', 'montage_soft.png', 'montage_loose.png'):
        data = run_bytes('exec-out', 'run-as', PKG, 'cat', 'files/ocr_dump/' + fn)
        if len(data) > 8 and data[:4] == b'\x89PNG':
            dst = os.path.join(OUTDIR, fn)
            io.open(dst, 'wb').write(data)
            pulled.append(dst)
    if pulled:
        print('=================== 拼板 ===================')
        for p in pulled:
            print('  ', p)
        print('  看图：python tools\\montage_cell.py <上面的 png> 0,1,2')
    else:
        print('[!] 没拉到拼板：确认装的是 debuggable 包，且广播带了 --ez dump true')
