@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo ============================================================
echo         忘川检索 fhlSearch (Android) - 一键生成安装包
echo ============================================================
echo.

rem ---- 1. 定位 JDK（Android 构建需要 JDK 17 以上）----
rem   优先用环境变量 JAVA_HOME，其次找常见安装位置（含 Android Studio 自带的 JBR）。
set "JDK="
if defined JAVA_HOME if exist "%JAVA_HOME%\bin\java.exe" set "JDK=%JAVA_HOME%"
if not defined JDK if exist "%~dp0.tools\jdk21\bin\java.exe" set "JDK=%~dp0.tools\jdk21"
if not defined JDK if exist "C:\Program Files\Java\jdk-25\bin\java.exe" set "JDK=C:\Program Files\Java\jdk-25"
if not defined JDK if exist "C:\Program Files\Java\jdk-21\bin\java.exe" set "JDK=C:\Program Files\Java\jdk-21"
if not defined JDK if exist "C:\Program Files\Java\jdk-17\bin\java.exe" set "JDK=C:\Program Files\Java\jdk-17"
if not defined JDK if exist "C:\Program Files\Android\Android Studio\jbr\bin\java.exe" set "JDK=C:\Program Files\Android\Android Studio\jbr"
if not defined JDK (
    echo [错误] 没找到 JDK。请安装 JDK 17 或更高版本（或装 Android Studio，它自带 JBR）后重试。
    pause & exit /b 1
)
set "JAVA_HOME=%JDK%"
echo [1/4] 使用 JDK: %JAVA_HOME%

rem ---- 2. 把 data\ 里的三份 Excel 题库转成程序内嵌数据 ----
rem   没有 python、或 data\ 下没有题库文件时会自动跳过，直接沿用已生成的 JSON。
echo [2/4] 读取题库并生成内嵌数据 ...
set "PYTHONIOENCODING=utf-8"
where python >nul 2>nul
if errorlevel 1 (
    echo       [跳过] 本机没有 python，沿用 app\src\main\assets 里已生成的题库。
) else (
    python "tools\build_tiku.py"
    if errorlevel 1 (
        echo       [警告] 题库转换失败，继续用已生成的 JSON 编译。
    )
)

rem ---- 3. 编译 ----
echo [3/4] 正在编译（第一次要下载依赖，会比较慢，请耐心等待）...
call gradlew.bat :app:assembleRelease --console=plain
if errorlevel 1 (
    echo.
    echo [错误] 编译失败。请把上面的信息截图发给我。
    pause & exit /b 1
)

rem ---- 4. 收集产物 ----
echo [4/4] 正在整理安装包 ...
if not exist "dist" mkdir "dist"
set "APK=app\build\outputs\apk\release\app-release.apk"
if not exist "%APK%" set "APK=app\build\outputs\apk\release\app-release-unsigned.apk"
if not exist "%APK%" (
    echo [错误] 没找到编译产物。
    pause & exit /b 1
)
copy /y "%APK%" "dist\忘川检索.apk" >nul

echo.
echo ============================================================
echo   完成！安装包在这里：
echo   %~dp0dist\忘川检索.apk
echo.
echo   把它传到手机 / 平板上点一下即可安装（Android 10 及以上）。
echo   没有配置签名时产物是未签名的，装不上属正常，见 README 的"签名"一节。
echo ============================================================
echo.
pause
