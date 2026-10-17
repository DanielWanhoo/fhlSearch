# -*- coding: utf-8 -*-
"""
打包发布：生成 dist\\fhlSearch.exe、dist\\使用说明.txt，以及项目根目录的 重新生成题库.bat。

编码约定（很重要，和 Windows 兼容性直接相关）：
  * .bat  -> **GBK / cp936**。cmd.exe 按系统 OEM 代码页读取批处理，中文系统上是 936，
             存成 UTF-8 会让中文提示全变乱码（Win7 上尤其明显）。
  * .txt  -> **UTF-8 with BOM**。Win7 的记事本不带 BOM 时会当 ANSI 解，中文会乱码。

用法: python tools/make_dist.py
"""
import sys, io, os, shutil, subprocess, datetime

# 输出跟随系统编码（中文 Windows 的 cmd 是 GBK），只把编不出来的字符降级，避免抛异常。
# 需要强制 UTF-8 时，设环境变量 PYTHONIOENCODING=utf-8。
try:
    sys.stdout.reconfigure(errors='replace')
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # 项目根目录
EXE_SRC = os.path.join(ROOT, r"src\FhlSearch\bin\Release\fhlSearch.exe")
DIST = os.path.join(ROOT, "dist")
DOC_SRC = os.path.join(ROOT, r"docs\使用说明.md")
BAT_OUT = os.path.join(ROOT, "重新生成题库.bat")

BAT = r"""@echo off
chcp 936 >nul
setlocal
cd /d "%~dp0"

echo ============================================================
echo    忘川检索 fhlSearch  -  重新生成题库并打包
echo ============================================================
echo.
echo 用途：改完题库 Excel 后双击本文件，
echo       就会自动重新生成内嵌题库并编译出新的 exe。
echo       题库目录默认是项目里的 data\ （可用 bank_src.txt 换到别处）。
echo.

where python >nul 2>nul
if errorlevel 1 (
    echo [错误] 没有找到 python 命令。
    echo        请先安装 Python 3，安装时勾选 "Add Python to PATH"。
    echo.
    pause
    exit /b 1
)

where dotnet >nul 2>nul
if errorlevel 1 (
    echo [错误] 没有找到 dotnet 命令，需要 .NET SDK 8 或更高版本。
    echo.
    pause
    exit /b 1
)

echo [1/4] 从 Excel 题库生成内嵌数据 ...
python "tools\build_data.py"
if errorlevel 1 (
    echo.
    echo [失败] 题库转换出错，请检查上面的提示。
    pause
    exit /b 1
)

echo.
echo [2/4] 编译程序 ...
dotnet build "src\FhlSearch\FhlSearch.csproj" -c Release --nologo -v q
if errorlevel 1 (
    echo.
    echo [失败] 编译出错，请检查上面的提示。
    pause
    exit /b 1
)

echo.
echo [3/4] 打包到 dist ...
python "tools\make_dist.py"
if errorlevel 1 (
    echo.
    echo [失败] 打包出错。
    pause
    exit /b 1
)

echo.
echo [4/4] 全部完成！
echo.
echo    新程序位置:  %cd%\dist\fhlSearch.exe
echo.
pause
"""


def write_gbk(path, text):
    with open(path, "wb") as f:
        f.write(text.replace("\n", "\r\n").encode("gbk", errors="replace"))
    print("  已写出 (GBK)     : %s  (%d bytes)" % (path, os.path.getsize(path)))


def write_utf8_bom(path, text):
    with open(path, "wb") as f:
        f.write(b"\xef\xbb\xbf")
        f.write(text.replace("\n", "\r\n").encode("utf-8"))
    print("  已写出 (UTF8+BOM): %s  (%d bytes)" % (path, os.path.getsize(path)))


def main():
    print("=" * 70)
    print("打包 忘川检索")
    print("=" * 70)

    if not os.path.exists(EXE_SRC):
        print("找不到编译产物: " + EXE_SRC)
        print("请先运行: dotnet build src\\FhlSearch\\FhlSearch.csproj -c Release")
        return 2

    if not os.path.isdir(DIST):
        os.makedirs(DIST)

    # 1) exe
    dst_exe = os.path.join(DIST, "fhlSearch.exe")
    shutil.copy2(EXE_SRC, dst_exe)
    print("  已复制 exe       : %s  (%d bytes)" % (dst_exe, os.path.getsize(dst_exe)))

    # 2) 使用说明
    if os.path.exists(DOC_SRC):
        with open(DOC_SRC, encoding="utf-8") as f:
            doc = f.read()
        doc = doc.replace("\n---\n", "\n" + "-" * 60 + "\n")
        doc = doc.replace("## ", "■ ").replace("# ", "")
        doc = doc.replace("**", "").replace("| ", "  ").replace(" |", "  ")
        doc = doc.replace("`", "")
        head = ("忘川检索 fhlSearch 使用说明\n"
                "打包时间: %s\n" % datetime.datetime.now().strftime("%Y-%m-%d %H:%M"))
        write_utf8_bom(os.path.join(DIST, "使用说明.txt"), head + "\n" + doc)

    # 3) 重新生成题库.bat
    write_gbk(BAT_OUT, BAT)

    print()
    print("dist 目录内容:")
    for n in sorted(os.listdir(DIST)):
        p = os.path.join(DIST, n)
        print("  %-24s %10d bytes" % (n, os.path.getsize(p)))

    # 4) 自检：exe 里确实带着题库资源
    size = os.path.getsize(dst_exe)
    print()
    print("exe 大小: %d bytes (%.0f KB)" % (size, size / 1024.0))
    if size < 100 * 1024:
        print("  !! 警告: exe 偏小，内嵌题库可能没进去")
        return 3
    print("  OK: 大小正常（内嵌题库约 55 KB）")
    print("=" * 70)
    return 0


if __name__ == "__main__":
    sys.exit(main())
