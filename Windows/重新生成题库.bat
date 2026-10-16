@echo off
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
echo    新程序位置:  %cd%\dist\忘川检索.exe
echo.
pause
