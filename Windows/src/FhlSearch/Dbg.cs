using System;
using System.IO;
using System.Text;

namespace FhlSearch
{
    /// <summary>
    /// 开发用调试日志。默认关闭，只有带 --debug 启动时才会写文件，
    /// 正式版用户不会产生任何日志。
    /// </summary>
    public static class Dbg
    {
        public static bool On = false;
        static string _path;
        static readonly object _lock = new object();

        public static void Init(string exePath)
        {
            On = true;
            try
            {
                string dir = Path.GetDirectoryName(exePath);
                _path = Path.Combine(dir ?? ".", "忘川检索-debug.log");
                if (File.Exists(_path)) File.Delete(_path);
                Log("=== 忘川检索 调试日志 " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " ===");
                Log("CLR=" + Environment.Version + " 64bit=" + Environment.Is64BitProcess
                    + " OS=" + Environment.OSVersion.VersionString);
                Log("Ui.Scale=" + Theme.Ui.Scale);
            }
            catch { }
        }

        public static void Log(string msg)
        {
            if (!On) return;
            try
            {
                lock (_lock)
                {
                    File.AppendAllText(_path, DateTime.Now.ToString("HH:mm:ss.fff") + "  " + msg + "\r\n",
                        new UTF8Encoding(false));
                }
            }
            catch { }
        }

        /// <summary>
        /// 把控件在「主窗口客户区」里的坐标写进日志，方便自动化测试算出点击位置。
        /// </summary>
        public static void LogBounds(string tag, System.Windows.Forms.Control c)
        {
            if (!On || c == null) return;
            try
            {
                System.Windows.Forms.Form f = c.FindForm();
                if (f == null) { Log(tag + " (无父窗体)"); return; }
                System.Drawing.Point p = f.PointToClient(c.PointToScreen(System.Drawing.Point.Empty));
                Log(string.Format("{0}  客户区=({1},{2}) {3}x{4}  中心=({5},{6})",
                    tag, p.X, p.Y, c.Width, c.Height, p.X + c.Width / 2, p.Y + c.Height / 2));
            }
            catch { }
        }
    }
}
