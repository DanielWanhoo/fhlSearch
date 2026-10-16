using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace FhlSearch.Theme
{
    /// <summary>
    /// 能被滚轮滚动的自绘控件。实现这个接口后，只要鼠标停在它上面，
    /// 滚轮就会作用到它——不需要它先获得焦点。
    /// </summary>
    public interface IWheelScrollable
    {
        /// <summary>是否还有没显示出来的内容</summary>
        bool CanScroll { get; }
        /// <summary>滚动，delta 与 MouseEventArgs.Delta 同单位（一格 = 120）</summary>
        void WheelScroll(int delta);
    }

    /// <summary>
    /// 应用级滚轮路由器：把滚轮消息送给**光标底下**的可滚动控件。
    ///
    /// 为什么需要它：Windows 的 WM_MOUSEWHEEL 只发给**当前有焦点的窗口**，
    /// 然后由 .NET 沿着父链向上冒泡。于是出现这些情况全都滚不动：
    ///   * 焦点在侧栏按钮上，光标却停在选项卡上
    ///   * 焦点在结果列表里，光标停在左边的选项卡上
    /// 这不符合"滚轮滚光标下面的东西"这个所有人默认的直觉。
    ///
    /// 这里在消息进队列前拦一道：找出光标下的窗口，沿父链找 IWheelScrollable，
    /// 找到就滚它并吃掉消息；找不到就原样放行，不影响正常行为。
    /// </summary>
    public class WheelRouter : IMessageFilter
    {
        const int WM_MOUSEWHEEL = 0x020A;

        [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(POINT p);

        [StructLayout(LayoutKind.Sequential)]
        struct POINT { public int X, Y; }

        public bool PreFilterMessage(ref Message m)
        {
            if (m.Msg != WM_MOUSEWHEEL) return false;

            try
            {
                // WM_MOUSEWHEEL 的 lParam 是**屏幕坐标**
                int lp = unchecked((int)(long)m.LParam);
                POINT p = new POINT();
                p.X = unchecked((short)(lp & 0xFFFF));
                p.Y = unchecked((short)((lp >> 16) & 0xFFFF));

                IntPtr h = WindowFromPoint(p);
                if (h == IntPtr.Zero) return false;

                Control c = Control.FromHandle(h);
                if (c == null) return false;

                // 弹出模态对话框时主窗口是禁用的：这时候滚轮不该去滚背后那些列表
                Form f = c.FindForm();
                if (f != null && !f.Enabled) return false;

                while (c != null)
                {
                    IWheelScrollable ws = c as IWheelScrollable;
                    if (ws != null && ws.CanScroll)
                    {
                        int delta = unchecked((short)((long)m.WParam >> 16));
                        ws.WheelScroll(delta);
                        return true;   // 已处理，不再往下派发
                    }
                    c = c.Parent;
                }
            }
            catch { }
            return false;
        }
    }
}
