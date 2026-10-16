# 启动程序 -> 执行动作序列 -> 截图 -> 退出
#
# 用法:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools/shot.ps1 ^
#       -Exe <exe路径> -Out <png路径> [-WaitMs 2500] ^
#       -Script "click:200,300|type:du|paste:城春草木深|key:{ENTER}|wait:600"
#
# 动作:
#   click:X,Y      在窗口客户区坐标 (X,Y)（物理像素）点击左键
#   dblclick:X,Y   双击
#   type:TEXT      SendKeys 发送（仅 ASCII / 特殊键，如 {TAB} {ENTER}）
#   paste:TEXT     把 TEXT 放进剪贴板并 Ctrl+V（用来输入中文，绕过输入法）
#   key:XXX        SendKeys 发送一次
#   wait:MS        等待
#
# 抓图对象:
#   默认        主窗口（PrintWindow，最干净）
#   -Dialog     进程里最靠前的那个"小窗口"（弹窗，比 -FullScreen 精准）
#   -FullScreen 整个屏幕
#
# 注意: 本文件必须保存为 UTF-8 with BOM，否则 Windows PowerShell 5.1 会按 GBK 解码导致中文乱码。
param(
  [Parameter(Mandatory=$true)][string]$Exe,
  [Parameter(Mandatory=$true)][string]$Out,
  [int]$WaitMs = 2500,
  [string]$Script = "",
  [switch]$AppDebug,
  [string]$Size = "",
  [switch]$FullScreen,
  [switch]$Dialog,
  [switch]$KeepAlive
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

Add-Type -ReferencedAssemblies System.Drawing, System.Windows.Forms @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class Shot
{
    [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("shcore.dll")] static extern int SetProcessDpiAwareness(int v);
    [DllImport("user32.dll")] static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hh, bool repaint);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr p);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);

    delegate bool EnumProc(IntPtr h, IntPtr p);

    [StructLayout(LayoutKind.Sequential)]
    struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    struct POINT { public int X, Y; }

    const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    const uint MOUSEEVENTF_LEFTUP = 0x0004;
    const uint MOUSEEVENTF_WHEEL = 0x0800;

    // Host process must be DPI aware, otherwise GetWindowRect returns
    // virtualized (shrunk) coordinates and PrintWindow only grabs the top-left corner.
    public static string MakeAware()
    {
        try { SetProcessDpiAwareness(2); return "per-monitor"; } catch { }
        try { if (SetProcessDPIAware()) return "system"; } catch { }
        return "none";
    }

    public static string Focus(IntPtr h)
    {
        if (h == IntPtr.Zero) return "ERR:no handle";
        if (IsIconic(h)) ShowWindow(h, 9);
        SetForegroundWindow(h);
        System.Threading.Thread.Sleep(250);
        return "ok";
    }

    /// <summary>
    /// 在进程的所有可见顶层窗口里挑一个"小窗口"（弹窗）。
    /// 主窗口动辄两千多像素宽，弹窗不到它的一半，用宽度区分足够稳。
    /// </summary>
    public static IntPtr FindDialog(uint pid)
    {
        IntPtr best = IntPtr.Zero;
        int bestW = int.MaxValue;
        EnumWindows(delegate(IntPtr h, IntPtr p)
        {
            uint wp;
            GetWindowThreadProcessId(h, out wp);
            if (wp != pid || !IsWindowVisible(h)) return true;
            RECT r;
            if (!GetWindowRect(h, out r)) return true;
            int w = r.Right - r.Left, hh = r.Bottom - r.Top;
            if (w < 200 || hh < 150) return true;       // 工具提示、阴影之类的小窗口不要
            if (w < bestW) { bestW = w; best = h; }
            return true;
        }, IntPtr.Zero);
        return best;
    }

    /// <summary>在窗口客户区坐标 (cx,cy) 处点击</summary>
    public static string Click(IntPtr h, int cx, int cy, bool dbl)
    {
        POINT p = new POINT();
        p.X = cx; p.Y = cy;
        if (!ClientToScreen(h, ref p)) return "ERR:ClientToScreen";
        SetCursorPos(p.X, p.Y);
        System.Threading.Thread.Sleep(120);
        mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, IntPtr.Zero);
        System.Threading.Thread.Sleep(50);
        mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, IntPtr.Zero);
        if (dbl)
        {
            System.Threading.Thread.Sleep(90);
            mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, IntPtr.Zero);
            System.Threading.Thread.Sleep(50);
            mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, IntPtr.Zero);
        }
        System.Threading.Thread.Sleep(180);
        return "ok";
    }

    /// <summary>把鼠标移到窗口客户区 (cx,cy) 并滚动滚轮（notches 正=上滚 负=下滚）</summary>
    public static string WheelAt(IntPtr h, int cx, int cy, int notches)
    {
        POINT p = new POINT();
        p.X = cx; p.Y = cy;
        if (!ClientToScreen(h, ref p)) return "ERR:ClientToScreen";
        SetCursorPos(p.X, p.Y);
        System.Threading.Thread.Sleep(150);
        mouse_event(MOUSEEVENTF_WHEEL, 0, 0, (uint)(notches * 120), IntPtr.Zero);
        System.Threading.Thread.Sleep(200);
        return "ok";
    }

    /// <summary>按逻辑像素调整窗口客户区大小（内部按 DPI 换算），模拟用户拖动边框</summary>
    public static string ResizeClient(IntPtr h, int logicalW, int logicalH)
    {
        if (h == IntPtr.Zero) return "ERR:no handle";
        float scale = 1f;
        using (Graphics g = Graphics.FromHwnd(h)) scale = g.DpiX / 96f;
        int w = (int)Math.Round(logicalW * scale);
        int hh = (int)Math.Round(logicalH * scale);
        RECT r;
        GetWindowRect(h, out r);
        // 换算成整窗尺寸（把非客户区加回去）
        RECT c, w2;
        GetClientRect(h, out c);
        GetWindowRect(h, out w2);
        int border = (w2.Right - w2.Left) - c.Right;
        int title = (w2.Bottom - w2.Top) - c.Bottom;
        MoveWindow(h, r.Left, r.Top, w + border, hh + title, true);
        return "ok";
    }

    /// <summary>整屏截图（用于抓弹窗等不在主窗口里的内容）</summary>
    public static string CaptureScreen(string path)
    {
        Rectangle b = Screen.PrimaryScreen.Bounds;
        Bitmap bmp = new Bitmap(b.Width, b.Height, PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(bmp))
            g.CopyFromScreen(b.Left, b.Top, 0, 0, new Size(b.Width, b.Height));
        bmp.Save(path, ImageFormat.Png);
        bmp.Dispose();
        return "OK " + b.Width + "x" + b.Height + " (FullScreen)";
    }

    public static string Capture(IntPtr h, string path)
    {
        if (h == IntPtr.Zero) return "ERR:no handle";
        if (IsIconic(h)) ShowWindow(h, 9);
        SetForegroundWindow(h);
        System.Threading.Thread.Sleep(400);

        RECT r;
        if (!GetWindowRect(h, out r)) return "ERR:GetWindowRect failed";
        int w = r.Right - r.Left, hh = r.Bottom - r.Top;
        if (w <= 0 || hh <= 0) return "ERR:bad rect " + w + "x" + hh;

        Bitmap bmp = new Bitmap(w, hh, PixelFormat.Format32bppArgb);
        bool ok;
        using (Graphics g = Graphics.FromImage(bmp))
        {
            IntPtr hdc = g.GetHdc();
            ok = PrintWindow(h, hdc, 2);
            g.ReleaseHdc(hdc);
        }
        if (!ok)
        {
            using (Graphics g = Graphics.FromImage(bmp))
                g.CopyFromScreen(r.Left, r.Top, 0, 0, new Size(w, hh));
        }
        bmp.Save(path, ImageFormat.Png);
        bmp.Dispose();
        return "OK " + w + "x" + hh + (ok ? " (PrintWindow)" : " (CopyFromScreen)");
    }
}
"@

[void][Shot]::MakeAware()

if ($AppDebug -or $Size -ne "") {
  $argList = @()
  if ($AppDebug) { $argList += "--debug" }
  if ($Size -ne "") { $argList += "--size"; $argList += $Size }
  $proc = Start-Process -FilePath $Exe -ArgumentList $argList -PassThru
} else {
  $proc = Start-Process -FilePath $Exe -PassThru
}
try {
  Start-Sleep -Milliseconds $WaitMs
  $proc.Refresh()
  if ($proc.HasExited) { Write-Output "PROCESS EXITED EARLY code=$($proc.ExitCode)"; exit 1 }

  $h = $proc.MainWindowHandle
  if ($h -eq [IntPtr]::Zero) { Write-Output "NO MAIN WINDOW HANDLE"; exit 2 }

  [void][Shot]::Focus($h)

  $actions = @()
  if ($Script -ne "") { $actions = $Script.Split('|') }
  foreach ($a in $actions) {
    $a = $a.Trim()
    if ($a -eq "") { continue }
    $i = $a.IndexOf(':')
    if ($i -lt 0) { continue }
    $cmd = $a.Substring(0, $i).ToLower()
    $arg = $a.Substring($i + 1)
    switch ($cmd) {
      'click' {
        $xy = $arg.Split(',')
        [void][Shot]::Click($h, [int]$xy[0], [int]$xy[1], $false)
      }
      'dblclick' {
        $xy = $arg.Split(',')
        [void][Shot]::Click($h, [int]$xy[0], [int]$xy[1], $true)
      }
      'type' { [System.Windows.Forms.SendKeys]::SendWait($arg); Start-Sleep -Milliseconds 250 }
      'key'  { [System.Windows.Forms.SendKeys]::SendWait($arg); Start-Sleep -Milliseconds 350 }
      'paste' {
        # 剪贴板经常被别的进程短暂占用，Set-Clipboard 会抛 CLIPBRD_E_CANT_OPEN，重试几次
        $ok = $false
        for ($try = 0; $try -lt 10 -and -not $ok; $try++) {
          try { Set-Clipboard -Value $arg; $ok = $true }
          catch { Start-Sleep -Milliseconds 250 }
        }
        if (-not $ok) { Write-Output "剪贴板被占用，粘贴失败: $arg" }
        Start-Sleep -Milliseconds 150
        [System.Windows.Forms.SendKeys]::SendWait("^v")
        Start-Sleep -Milliseconds 450
      }
      'wheel' {
        # wheel:X,Y,±N  把鼠标移到 (X,Y) 再滚动 N 格（正=上滚，负=下滚）
        $p = $arg.Split(',')
        [void][Shot]::WheelAt($h, [int]$p[0], [int]$p[1], [int]$p[2])
        Start-Sleep -Milliseconds 400
      }
      'wait' { Start-Sleep -Milliseconds ([int]$arg) }
      'resize' {
        # resize:W,H  逻辑像素（内部按 DPI 换算），模拟用户拖动窗口边框
        $wh = $arg.Split(',')
        [void][Shot]::ResizeClient($h, [int]$wh[0], [int]$wh[1])
        Start-Sleep -Milliseconds 700
      }
      default { Write-Output "未知动作: $a" }
    }
  }

  $dir = Split-Path -Parent $Out
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  if ($Dialog) {
    # 弹窗是另一个顶层窗口，得重新找一次句柄（动作执行完弹窗才存在）
    $dh = [Shot]::FindDialog([uint32]$proc.Id)
    if ($dh -eq [IntPtr]::Zero) { Write-Output "找不到弹窗窗口"; exit 4 }
    $r = [Shot]::Capture($dh, $Out)
  } elseif ($FullScreen) {
    $r = [Shot]::CaptureScreen($Out)
  } else {
    $r = [Shot]::Capture($h, $Out)
  }
  Write-Output $r
  if ($r -like "ERR*") { exit 3 }
}
finally {
  if (-not $KeepAlive) {
    try { if (-not $proc.HasExited) { $proc.Kill() } } catch {}
  } else {
    Write-Output "PID=$($proc.Id)"
  }
}
