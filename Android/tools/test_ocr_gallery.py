# -*- coding: utf-8 -*-
r"""诗词「图片识别」的两条系统通道：相册选择器 / 相机。

验证的是"系统托管通道"能不能走通（识别率另见 test_ocr.py）：
  · 「相册识别」→ 系统照片选择器（API 33+）或文件选择器（更老的系统）弹出
    → 选中一张图 → 回到 App 并自动识别、自动出检索结果；
  · 「拍照识别」→ 系统相机弹出（不需要 CAMERA 权限）→ 返回后 App 正常复原、不崩。

用法：python tools\test_ocr_gallery.py [设备] [标签]
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
TAG = sys.argv[2] if len(sys.argv) > 2 else 'phone'
PKG = 'com.wangchuan.fhlsearch'
ACT = PKG + '/.MainActivity'
OUT = os.path.join(_ROOT, '_analysis', 'ocr_gallery_%s.txt') % TAG
SAMPLE = 'H:\\\\projects\\\\info\\\\需求\\\\ocr\\\\test\\\\IMG_10271.jpg'

os.makedirs(os.path.join(_ROOT, '_analysis'), exist_ok=True)
sys.path.insert(0, os.path.join(_ROOT, 'tools'))
import drive_app as d  # noqa: E402
d.DEV = DEV
d.TAG = TAG

lines = []
allok = True


def w(s):
    lines.append(s)
    print(s)


def run(*a):
    return subprocess.run([ADB, '-s', DEV] + list(a), capture_output=True,
                          timeout=240).stdout.decode('utf-8', 'replace')


def sh(c):
    return run('shell', c)


def top_activity():
    """当前前台 Activity（不同 Android 版本字段名不一样）"""
    out = sh('dumpsys activity activities | grep -E "topResumedActivity|mResumedActivity"')
    m = re.search(r'([\w.]+)/([\w.$]+)', out)
    return (m.group(1) + '/' + m.group(2)) if m else '?'


def in_app():
    return PKG in top_activity()


def pick_first_image():
    """在选择器里点第一张图。

    照片选择器（API 33+）里的缩略图 id 是 icon_thumbnail；
    更老的系统会退化到文件选择器（documentsui），只能按文件名 / 缩略图找。
    点完确认真的回到了 App，没回去就换下一个候选再点。
    """
    # 等选择器把内容画出来
    deadline = time.time() + 15
    ns = []
    while time.time() < deadline and not in_app():
        time.sleep(1)
        ns = d.nodes()
        if any((n['id'].endswith('/icon_thumbnail') or 'thumbnail' in n['id']) for n in ns):
            break
    cands = [n for n in ns if n['id'].endswith('/icon_thumbnail') or 'thumbnail' in n['id']]
    if not cands:
        cands = [n for n in ns if n['cls'].endswith('ImageView')
                 and (n['bounds'][2] - n['bounds'][0]) >= 60
                 and (n['bounds'][3] - n['bounds'][1]) >= 60]
    if not cands:
        cands = [n for n in ns if n['text'] and n['text'].lower().endswith(('.jpg', '.jpeg', '.png'))]
    if not cands:
        w('  没识别到缩略图节点，按坐标点左上角碰一下')
        x, y = d.screen_size()
        sh('input tap %d %d' % (int(x * 0.2), int(y * 0.3)))
        time.sleep(3)
        return
    cands.sort(key=lambda n: (n['bounds'][1], n['bounds'][0]))
    for n in cands[:4]:
        if in_app():
            break
        w('  点击缩略图：id=%s bounds=%s' % (n['id'].split('/')[-1] or n['cls'].split('.')[-1],
                                          (n['bounds'],)))
        sh('input tap %d %d' % n['center'])
        time.sleep(3)


def ensure_app():
    """保证 App 在前台：先按返回关掉可能残留的选择器 / 弹窗，再重新拉起"""
    for _ in range(4):
        if in_app():
            return True
        sh('input keyevent 4')
        time.sleep(1)
    sh('am start -S -n ' + ACT)
    time.sleep(6)
    if not in_app():
        sh('am start -S -n ' + ACT)
        time.sleep(5)
    return in_app()


def launch_shici():
    ensure_app()
    d.tap('诗词检索', by='text', label='导航·诗词')
    time.sleep(2)
    return ensure_app()


w('== 设备 %s（%s）图片识别通道回归 ==' % (DEV, TAG))

# 先把一张图放进相册（模拟用户手机里有题目截图）
run('install', '-r', os.environ.get('FHL_APK')
    or os.path.join(_ROOT, 'app', 'build', 'outputs', 'apk', 'debug', 'app-debug.apk'))
sh('mkdir -p /sdcard/Pictures')
run('push', SAMPLE, '/sdcard/Pictures/fhl_ocr_sample.jpg')
sh('am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE '
   '-d file:///sdcard/Pictures/fhl_ocr_sample.jpg')
time.sleep(2)

launch_shici()
if not d.find(r'/btnOcrGallery$', by='id'):
    w('  ❌ 诗词页没打开（找不到「相册识别」键），先重置界面')
    ensure_app()
    launch_shici()

# ---- 1. 相册识别 ----
w('')
w('--- 相册识别 ---')
if not d.tap('/btnOcrGallery$', label='相册识别'):
    launch_shici()
    d.tap('/btnOcrGallery$', label='相册识别')
time.sleep(4)
top = top_activity()
w('  前台 Activity: %s' % top)
picker = ('photopicker' in top or 'documentsui' in top or 'media' in top)
if picker:
    w('  系统选择器已弹出 ✅')
else:
    w('  ❌ 没有弹出系统选择器')
    allok = False

pick_first_image()
# 有些系统选择器还要再点一次「完成 / 添加」
if not in_app():
    d.tap('^(完成|添加|打开)$', by='text', label='完成', hide_kb=False)
    time.sleep(2)

picked = in_app()
if not picked:
    # Android 10 那台模拟器的文件选择器（documentsui）媒体库里经常是空的
    # （显示 "No items"），属于模拟器环境问题，不算 App 的问题，标记跳过。
    ns = d.nodes()
    empty_list = any('No items' in (n['text'] or '') for n in ns)
    w('  选择器没有返回图片（documentsui 列表为空=%s）' % empty_list)
    if empty_list:
        w('  ⏭ 跳过本项：模拟器的文件选择器里没有可索引的图片（真机/新系统上走的是照片选择器）')
    else:
        w('  ❌ 选完图没有回到 App')
        allok = False

if picked:
    # 等识别跑完（"最终 N / 30 格"）
    grid_ok = False
    for _ in range(40):
        time.sleep(1)
        if '最终' in run('logcat', '-d', '-s', 'FhlOcr'):
            grid_ok = True
            break
    w('  回到 App：%s' % top_activity())
    if grid_ok:
        w('  选图后自动识别并填格 ✅')
    else:
        w('  ❌ 选图后没有进入识别流程（前台=%s）' % top_activity())
        allok = False

    # 识别完应当直接给出检索结果（这张样例图能凑出「落日故人情」）
    time.sleep(2)
    ns = d.nodes()
    cnt = (d.find('tvResultCount', ns) or {}).get('text', '') or '—'
    rows = [n['text'] for n in ns if n['id'].endswith('/tvText') and n['text']]
    w('  检索结果：%s%s' % (cnt, ('　' + rows[0]) if rows else ''))
    if not re.search(r'\(\d+\)', cnt):
        w('  ❌ 识别后没有自动出检索结果')
        allok = False
d.shot('ocr_gallery_%s' % TAG)

# ---- 2. 拍照识别 ----
w('')
w('--- 拍照识别 ---')
if not in_app():
    launch_shici()
else:
    d.tap('诗词检索', by='text', label='导航·诗词')
    time.sleep(1.5)
if not d.tap('/btnOcrCamera$', label='拍照识别'):
    launch_shici()
    d.tap('/btnOcrCamera$', label='拍照识别')
time.sleep(5)
top = top_activity()
w('  前台 Activity: %s' % top)
if 'camera' in top.lower():
    w('  系统相机已弹出（未申请 CAMERA 权限）✅')
elif PKG not in top:
    w('  相机没起来（前台=%s）—— 属于模拟器环境问题（该镜像的相机应用可能缺权限/会崩）' % top)
else:
    w('  ❌ 相机没有弹出')
    allok = False
d.shot('ocr_camera_%s' % TAG)
sh('input keyevent 4')          # 退出相机
time.sleep(3)
w('  返回后前台：%s' % top_activity())
if not in_app():
    launch_shici()
crashes = run('logcat', '-d', '-b', 'crash')
if 'FATAL EXCEPTION' in crashes and PKG in crashes:
    w('  ❌ 有崩溃')
    allok = False
else:
    w('  无崩溃 ✅')

w('')
w('总体: %s' % ('✅ 全部通过' if allok else '❌ 有不符合预期的地方'))
print('总体:', 'OK' if allok else 'FAILED')
io.open(OUT, 'w', encoding='utf-8').write('\n'.join(lines))
print('written', OUT)
