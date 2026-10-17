using System;
using System.IO;
using System.Text;
using System.Windows.Forms;
using FhlSearch.Theme;

namespace FhlSearch
{
    static class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            // 自测模式（开发用）：fhlSearch.exe --selftest 脚本.txt 输出.txt
            if (args != null && args.Length >= 3 && args[0] == "--selftest")
            {
                try { Environment.Exit(SelfTest.Run(args[1], args[2])); }
                catch (Exception ex) { Console.Error.WriteLine(ex); Environment.Exit(3); }
                return;
            }

            try
            {
                if (args != null)
                {
                    for (int i = 0; i < args.Length; i++)
                    {
                        if (args[i] == "--debug") Dbg.Init(Application.ExecutablePath);
                        else if (args[i] == "--size" && i + 1 < args.Length)
                        {
                            string[] wh = args[i + 1].Split('x', ',');
                            int ww, hh;
                            if (wh.Length == 2 && int.TryParse(wh[0], out ww) && int.TryParse(wh[1], out hh))
                            {
                                MainForm.ForceW = ww; MainForm.ForceH = hh;
                            }
                        }
                    }
                }

                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);

                // 滚轮跟着光标走：Windows 的 WM_MOUSEWHEEL 只发给**有焦点的**窗口，
                // 焦点不在选项卡 / 结果列表上时滚轮就会失效。这里按光标位置统一派发。
                Application.AddMessageFilter(new Theme.WheelRouter());

                // 未处理异常：给用户一个能看懂的提示，而不是崩溃对话框
                Application.ThreadException += delegate (object s, System.Threading.ThreadExceptionEventArgs e)
                {
                    ShowError(e.Exception);
                };
                AppDomain.CurrentDomain.UnhandledException += delegate (object s, UnhandledExceptionEventArgs e)
                {
                    ShowError(e.ExceptionObject as Exception);
                };

                Application.Run(new MainForm());
            }
            catch (Exception ex)
            {
                ShowError(ex);
            }
        }

        static void ShowError(Exception ex)
        {
            try
            {
                string detail = Describe(ex);
                WriteLog(detail);
                MessageBox.Show("忘川检索 遇到一个问题：\n\n" + (ex == null ? "未知错误" : ex.Message)
                    + "\n\n详细信息已写入日志：\n" + LogPath()
                    + "\n\n如果反复出现，请把日志反馈给作者。",
                    "忘川检索", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
            catch { }
        }

        static string Describe(Exception ex)
        {
            System.Text.StringBuilder sb = new System.Text.StringBuilder();
            sb.AppendLine("================ 忘川检索 错误日志 ================");
            sb.AppendLine("时间   : " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
            sb.AppendLine("系统   : " + Environment.OSVersion.VersionString);
            sb.AppendLine("CLR    : " + Environment.Version);
            sb.AppendLine("64 位  : " + Environment.Is64BitProcess);
            sb.AppendLine("程序   : " + Application.ExecutablePath);
            sb.AppendLine();
            int depth = 0;
            Exception e = ex;
            while (e != null && depth < 8)
            {
                sb.AppendLine("---- [" + depth + "] " + e.GetType().FullName + " ----");
                sb.AppendLine(e.Message);
                sb.AppendLine(e.StackTrace);
                sb.AppendLine();
                e = e.InnerException;
                depth++;
            }
            return sb.ToString();
        }

        public static string LogPath()
        {
            try
            {
                string dir = Path.GetDirectoryName(Application.ExecutablePath);
                if (!string.IsNullOrEmpty(dir)) return Path.Combine(dir, "忘川检索-error.log");
            }
            catch { }
            return Path.Combine(Path.GetTempPath(), "fhlsearch-error.log");
        }

        static void WriteLog(string text)
        {
            try { File.AppendAllText(LogPath(), text, new UTF8Encoding(false)); }
            catch { }
        }
    }
}
