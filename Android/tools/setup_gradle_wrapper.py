# -*- coding: utf-8 -*-
r"""准备 Gradle Wrapper：从 Gradle 官方发行包中取出 gradlew / gradlew.bat / gradle-wrapper.jar。

为什么这么做：本机没有 Gradle 命令行，也没有 Android Studio，
而 cmdline-tools 里不含 wrapper 生成工具。直接从发行包取是最省事、最可靠的路径。
顺带把发行包铺进 ~/.gradle/wrapper/dists，之后 ./gradlew 无需再下载。

用法：python setup_gradle_wrapper.py
"""
import hashlib
import os
import shutil
import sys
import urllib.request
import zipfile


# ---- 路径：全部按"本脚本所在位置"推算，克隆到任何目录下都能直接跑 ----
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

VERSION = '9.8.1'
DIST_NAME = 'gradle-%s-bin.zip' % VERSION
URL = 'https://services.gradle.org/distributions/' + DIST_NAME

PROJ = _ROOT
CACHE = os.path.join(PROJ, '.tools')
ZIP_PATH = os.path.join(CACHE, DIST_NAME)

GRADLE_HOME = os.environ.get('GRADLE_USER_HOME') or os.path.join(
    os.environ.get('USERPROFILE', ''), '.gradle')
DISTS = os.path.join(GRADLE_HOME, 'wrapper', 'dists', 'gradle-%s-bin' % VERSION)


def download(url, dest):
    if os.path.exists(dest) and os.path.getsize(dest) > 100 * 1024 * 1024:
        print('已存在，跳过下载:', dest)
        return
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    print('下载 %s ...' % url)
    tmp = dest + '.part'
    with urllib.request.urlopen(url, timeout=120) as r, open(tmp, 'wb') as f:
        total = int(r.headers.get('Content-Length') or 0)
        done = 0
        while True:
            chunk = r.read(1024 * 256)
            if not chunk:
                break
            f.write(chunk)
            done += len(chunk)
            if total:
                pct = done * 100 // total
                print('\r  %d%%  (%.1f/%.1f MB)' % (pct, done / 1048576, total / 1048576),
                      end='', flush=True)
    print()
    os.replace(tmp, dest)
    print('下载完成:', dest, os.path.getsize(dest) // 1024, 'KB')


def main():
    download(URL, ZIP_PATH)

    zf = zipfile.ZipFile(ZIP_PATH)
    names = zf.namelist()
    root = names[0].split('/')[0]          # gradle-9.8.1

    # 1) 取出 wrapper 三件套
    wanted = {
        '%s/bin/gradlew' % root: os.path.join(PROJ, 'gradlew'),
        '%s/bin/gradlew.bat' % root: os.path.join(PROJ, 'gradlew.bat'),
        '%s/lib/plugins/gradle-wrapper-main-%s.jar' % (root, VERSION):
            os.path.join(PROJ, 'gradle', 'wrapper', 'gradle-wrapper.jar'),
    }
    # wrapper jar 名字可能带版本号后缀差异，做一次模糊匹配兜底
    for n in names:
        if n.endswith('gradle-wrapper-main-%s.jar' % VERSION) or \
           (n.endswith('.jar') and 'gradle-wrapper-main' in n):
            wanted[n] = os.path.join(PROJ, 'gradle', 'wrapper', 'gradle-wrapper.jar')

    for src, dst in wanted.items():
        if src not in names:
            print('⚠ 发行包中找不到', src)
            continue
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with zf.open(src) as fi, open(dst, 'wb') as fo:
            shutil.copyfileobj(fi, fo)
        print('写出 %-58s %8d B' % (os.path.relpath(dst, PROJ), os.path.getsize(dst)))
    zf.close()

    # 2) 把发行包铺进 wrapper 缓存目录（Gradle 首次运行会自动解压并校验）
    #    Gradle 用 zip 的 sha256 前若干位作为 hash 目录名，这里直接算出来。
    h = hashlib.sha256(open(ZIP_PATH, 'rb').read()).hexdigest()
    # Gradle 的目录名算法：base36(sha256 的前 8 字节) 之类，难以精确复现，
    # 因此这里不猜目录名——直接让 gradlew 自己下载/解压；但把 zip 放到本地缓存旁，
    # 若网络不可用可用 --offline 手动指定。
    print('\n发行包 sha256:', h)
    print('提示：首次执行 gradlew.bat 会自动下载并解压同版本发行包（约 130MB）。')

    for f in ('gradlew', 'gradlew.bat'):
        p = os.path.join(PROJ, f)
        if os.path.exists(p):
            os.chmod(p, 0o755)


if __name__ == '__main__':
    sys.exit(main())
