# -*- coding: utf-8 -*-
r"""诗词检索「图片识别」回归：把样例图片塞进手机，跑一遍识别，核对识别出来的 30 格。

做法（与真实流程一致）：
  1. 把图片 push 到本应用自己的外部目录（app-specific，不需要存储权限）；
  2. 发广播 com.wangchuan.fhlsearch.action.OCR_TEST（extra: path），
     它就是「相册识别」走的同一条路：读图 → 找字格 → ML Kit 识别 → 填格 → 自动检索；
  3. 从 logcat 抓「字格:」那几行，与 Windows 端同一批图片的识别结果对照。

用法：
    python tools\test_ocr.py [设备] [标签]

样例图放在 data\ocr\（自带 test\ 子目录也行，不放也能跑，只是没图可测）。
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
ACTION = PKG + '.action.OCR_TEST'
# 图片先推到 /data/local/tmp，再用 run-as 拷进应用私有目录：
# 应用没有存储权限，但读自己的私有目录不需要权限；DEBUG 包才允许 run-as。
TMP_DIR = '/data/local/tmp'
APP_DIR = '/data/data/%s/files/ocr' % PKG
OUT = os.path.join(_ROOT, '_analysis', 'ocr_%s.txt') % TAG

os.makedirs(os.path.join(_ROOT, '_analysis'), exist_ok=True)
sys.path.insert(0, os.path.join(_ROOT, 'tools'))
import drive_app as d  # noqa: E402
d.DEV = DEV

# Windows 端（Windows.Media.Ocr）对同一批样例图的识别结果，仅作对照参考
# 「？」= 那边没认出来，不代表本端也必须空着
REF = {
    'screenshot_20261019_094535_com.xingin.xhs_hos.jpg': [
        '深雨思不流湿', '鱼月明前处子', '春亭袖海云敬', '河池入衫故有', '床时山意浮游'],
    'screenshot_20261019_110313.jpg': [
        '深雨思不流湿', '鱼月明前处子', '春亭袖海云敬', '河池入衫故有', '床时山意浮游'],
    'IMG_10271.jpg': [
        '穷人日抵览行', '火万一树野书', '情故到鸟小至', '今家尽宿池项', '随落羽烧山水'],
    'IMG_10272.jpg': [
        '？青南不蒸困', '谁思穷共心泽', '床儿此梦沾见', '？？到气？最', '守区女河弄草'],
    'IMG_10273.jpg': [
        '元多平似？阔', '野婵楼？撷酒', '垂问千深采悬', '月愿把？娟里', '依知？？？时'],
    'screenshot_20261019_142235.png': [
        '更生杰千物最', '行鸟康东金吠', '柴可看鸣米处', '？水回佾到下', '菊笑因园国当'],
}


def run(*a, timeout=180):
    return subprocess.run([ADB, '-s', DEV] + list(a), capture_output=True,
                          timeout=timeout).stdout.decode('utf-8', 'replace')


def sh(c, timeout=180):
    return run('shell', c, timeout=timeout)


def logcat_clear():
    sh('logcat -c')


def grid_from_log():
    """从 logcat 里抓**最后一个**「字格:」块（5 行 × 6 字）。

    注意要取最后一个：logcat 的 -c 有时来不及清干净，取第一个会拿到上一张图的结果。
    """
    out = run('logcat', '-d', '-s', 'FhlOcr')
    blocks = []
    cur = []
    for ln in out.splitlines():
        if '字格' in ln:
            if cur:
                blocks.append(cur)
            cur = []
            continue
        m = re.search(r':\s*((?:[？\u4e00-\u9fff]\s+){5}[？\u4e00-\u9fff])', ln)
        if m:
            cur.append(m.group(1).replace(' ', ''))
        elif cur:
            blocks.append(cur)
            cur = []
    if cur:
        blocks.append(cur)
    for b in reversed(blocks):
        if len(b) == 5:
            return b
    return []


def count_final():
    """logcat 里 "最终" 出现的次数：用它判断"这一趟跑完了"，
    比 logcat -c 可靠（-c 在部分系统上清不干净，会让你读到上一张图的结果）"""
    out = run('logcat', '-d', '-s', 'FhlOcr')
    return out.count('最终')


def wait_result(timeout=15):
    """等界面出结果（匹配结果 N 或空态提示），返回 (标题, 空态文案, 命中行)"""
    deadline = time.time() + timeout
    cnt = empty = ''
    rows = []
    while time.time() < deadline:
        ns = d.nodes()
        cnt = (d.find('tvResultCount', ns) or {}).get('text', '')
        empty = (d.find('tvEmpty', ns) or {}).get('text', '')
        rows = [n['text'] for n in ns if n['id'].endswith('/tvText') and n['text']]
        if (cnt and cnt != '—') or empty:
            break
        time.sleep(1)
    return cnt or '—', empty, rows


def ocr_log():
    return run('logcat', '-d', '-s', 'FhlOcr')


def stats_line():
    """识别过程的统计行（每趟识别 / 拼板 / 最终）"""
    out = ocr_log()
    keep = [l.split('FhlOcr : ')[-1].strip() for l in out.splitlines()
            if any(k in l for k in ('趟', '拼板', '最终', '图片 ', '-> 5x6', '不是 5x6',
                                    '候选选区', '按题库'))]
    return keep


lines = []
allok = True


def w(s):
    lines.append(s)
    print(s)


def compare(name, grid):
    """与参考结果逐格比对，返回 (相同格数, 参考已知格数)"""
    ref = REF.get(name)
    if not ref:
        return None
    same = known = 0
    for r in range(5):
        for c in range(6):
            rch = ref[r][c]
            if rch == '？':
                continue
            known += 1
            if r < len(grid) and c < len(grid[r]) and grid[r][c] == rch:
                same += 1
    return same, known


def main():
    global allok
    w('== 设备 %s（%s）图片识别回归 ==' % (DEV, TAG))

    imgs = []
    for folder in (os.path.join(_ROOT, 'data', 'ocr', 'test'), os.path.join(_ROOT, 'data', 'ocr')):
        if not os.path.isdir(folder):
            continue
        for fn in sorted(os.listdir(folder)):
            p = os.path.join(folder, fn)
            if not os.path.isfile(p) or not fn.lower().endswith(('.jpg', '.png')):
                continue
            if fn in [x[0] for x in imgs]:
                continue
            imgs.append((fn, p))

    run('install', '-r', os.environ.get('FHL_APK')
        or os.path.join(_ROOT, 'app', 'build', 'outputs', 'apk', 'debug', 'app-debug.apk'))
    sh('am start -S -n ' + ACT)
    time.sleep(5)
    # 建目录要放在 install 之后：包还没装上去时 run-as 会失败，后面逐个 cp 就全是 ENOENT
    sh('run-as %s mkdir -p files/ocr' % PKG)
    d.tap('诗词检索', by='text', label='导航·诗词')
    time.sleep(1.5)

    found_poems = 0

    for fn, local in imgs:
        tmp = TMP_DIR + '/' + fn
        remote = APP_DIR + '/' + fn
        run('push', local, tmp)
        sh('run-as %s cp %s %s' % (PKG, tmp, remote))
        sh('rm -f ' + tmp)
        logcat_clear()
        before = count_final()
        sh('am broadcast -a %s --es path %s' % (ACTION, remote))
        # 等这一趟跑完（"最终 N / 30 格" 多出来一条），再解析字格
        grid = []
        for _ in range(90):
            time.sleep(1)
            if count_final() > before:
                time.sleep(1)
                grid = grid_from_log()
                break
        st = stats_line()
        w('')
        w('--- %s ---' % fn)
        for s in st:
            w('  · ' + s)
        if not grid or len(grid) != 5:
            allok = False
            w('  [X] 没拿到 5 行结果')
            continue
        for r in grid:
            w('  ' + ' '.join(r))
        cmp = compare(fn, grid)
        if cmp:
            same, known = cmp
            # 只作参考：Windows 那版自己也有错（有的图只认出 24 格），
            # 所以这里不参与判定，真正的验收是"填充格数"和"能不能直接出诗句"。
            w('  与 Windows 端对照：%d / %d 格一致（%.0f%%）（仅参考）'
              % (same, known, 100.0 * same / max(1, known)))
        filled = sum(1 for r in grid for ch in r if ch != '？')
        w('  识别填充：%d / 30 格' % filled)
        # 最小的样图只有 504×393（Windows 端那版也只认出 26 格），所以门槛放到 26
        if filled < 26:
            allok = False
            w('  [X] 填充格数偏少（%d < 26）' % filled)
        # 界面状态：字格里的字是自绘的（uiautomator 读不到），所以只看检索结果
        # —— 只要出结果/给出"未找到可组成的诗句"，就说明填格与自动检索都跑通了。
        cnt, empty, rows_hit = wait_result()
        w('  界面：结果=%s 空态=%s' % (cnt, (empty or '')[:20]))
        hit_count = bool(re.search(r'\(\d+\)', cnt)) or bool(rows_hit)
        if rows_hit:
            w('  命中诗句：' + '; '.join(rows_hit[:2]))
        if not hit_count and not empty:
            allok = False
            w('  [X] 界面既没出结果也没给提示（自动检索没跑）')
        if hit_count:
            found_poems += 1
        d.TAG = TAG
        d.shot('ocr_%s_%s' % (TAG, os.path.splitext(fn)[0][:24]))

    # 端到端指标：识别完能不能直接给出诗句（这才是用户真正要的）
    w('')
    w('识别后直接出诗句：%d / %d 张' % (found_poems, len(imgs)))
    if found_poems < len(imgs) - 1:
        allok = False
        w('  [X] 能出诗句的样图太少')

    w('')
    w('总体: %s' % ('✅ 全部通过' if allok else '❌ 有不符合预期的地方'))
    print('总体:', 'OK' if allok else 'FAILED')
    io.open(OUT, 'w', encoding='utf-8').write('\n'.join(lines))
    print('written', OUT)


if __name__ == '__main__':
    main()
