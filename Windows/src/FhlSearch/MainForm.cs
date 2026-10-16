using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using FhlSearch.Data;
using FhlSearch.Modules;
using FhlSearch.Theme;

namespace FhlSearch
{
    /// <summary>三大模块的统一接口</summary>
    public abstract class ModuleBase : UserControl
    {
        public abstract string ModuleName { get; }   // 成语检索
        public abstract string BigTitle { get; }     // 山石雅集第 14 题

        /// <summary>清空所有检索</summary>
        public abstract void ResetAll();

        /// <summary>等到本模块被激活时调用（用于首次布局）</summary>
        public virtual void OnActivated() { }

        /// <summary>
        /// 把一个矩形按百分比切成左右两栏，中间留出 1px 分隔线与两侧 pane_gap 的空白。
        /// 与安卓版平板布局一致（成语 42/58，诗词与名士 44/56）。
        /// </summary>
        protected static void SplitPanes(int w, int h, int leftPct, out Rectangle left, out Rectangle right)
        {
            // 与安卓版的权重写法等价：先扣掉中间的固定部分（左右各 pane_gap + 1px 分隔线），
            // 剩下的宽度再按 42/58 或 44/56 分。
            int gap = Ui.Px(Ui.PaneGap);
            int fixedPart = gap * 2 + 1;
            int rest = w - fixedPart;
            if (rest < 2) rest = 2;
            int lw = rest * leftPct / 100;
            int rw = rest - lw;
            if (rw < 1) rw = 1;
            left = new Rectangle(0, 0, lw, h);
            right = new Rectangle(lw + fixedPart, 0, rw, h);
        }

        protected ModuleBase()
        {
            SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint
                   | ControlStyles.ResizeRedraw | ControlStyles.UserPaint, true);
            DoubleBuffered = true;
            BackColor = Pal.PaperTop;
            ForeColor = Pal.Ink;
            Font = Fonts.BodyF();
        }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            Paper.Paint(this, e.Graphics);
        }
    }

    public class MainForm : Form
    {
        readonly ModuleBase[] _modules = new ModuleBase[3];
        int _current = -1;
        bool _built;

        RailNav _rail;
        FButton _btnHelp, _btnAbout;

        /// <summary>调试用：命令行 --size W,H 强制指定初始客户区大小（逻辑像素）</summary>
        public static int ForceW = 0, ForceH = 0;

        public MainForm()
        {
            Text = "忘川检索";
            StartPosition = FormStartPosition.CenterScreen;
            Font = Fonts.BodyF();
            BackColor = Pal.PaperTop;
            ForeColor = Pal.Ink;

            // ResizeRedraw 必须开：否则缩放窗口时 WinForms 只重画"新露出来"的那条区域，
            // 右对齐的文字会在每个中间宽度各画一份且旧的擦不掉，看起来就是一串字符残影。
            SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint
                   | ControlStyles.ResizeRedraw | ControlStyles.UserPaint, true);
            DoubleBuffered = true;

            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }

            ApplyInitialSize();
            Bank.Load();

            // ---- 左侧 tab 栏 ----
            _rail = new RailNav();
            _rail.SelectedChanged += delegate { SelectModule(_rail.Selected); };
            Controls.Add(_rail);

            // ---- 侧栏底部的两个小链接 ----
            _btnHelp = MakeLink("使用说明");
            _btnHelp.Click += delegate { Dialogs.Help(this); };
            _btnAbout = MakeLink("关于题库");
            _btnAbout.Click += delegate { Dialogs.About(this); };

            // ---- 三个模块 ----
            try { _modules[0] = new Modules.IdiomModule(); }
            catch (Exception ex) { Dbg.Log("IdiomModule 构造失败: " + ex); throw; }
            try { _modules[1] = new Modules.PoemModule(); }
            catch (Exception ex) { Dbg.Log("PoemModule 构造失败: " + ex); throw; }
            try { _modules[2] = new Modules.PersonModule(); }
            catch (Exception ex) { Dbg.Log("PersonModule 构造失败: " + ex); throw; }

            for (int i = 0; i < 3; i++)
            {
                ModuleBase m = _modules[i];
                m.Visible = false;
                Controls.Add(m);
                m.BringToFront();
            }
            _rail.BringToFront();
            _btnHelp.BringToFront();
            _btnAbout.BringToFront();

            if (Bank.LoadError != null)
                MessageBox.Show("题库读取失败：\n" + Bank.LoadError, "忘川检索",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);

            _built = true;
            Layout2();
            SelectModule(0);
        }

        FButton MakeLink(string text)
        {
            FButton b = new FButton();
            b.Style = FButton.Kind.Ghost;
            b.Text = text;
            Controls.Add(b);
            return b;
        }

        // ------------------------------------------------------------ 尺寸

        /// <summary>
        /// 初始窗口大小：默认 1180×760（逻辑像素），若屏幕放不下就按工作区收缩，
        /// 避免在 1366×768 @150% 这类小屏上窗口超出屏幕。
        /// </summary>
        void ApplyInitialSize()
        {
            int w = Ui.Px(ForceW > 0 ? ForceW : 1180);
            int h = Ui.Px(ForceH > 0 ? ForceH : 760);
            Rectangle wa;
            try { wa = Screen.PrimaryScreen.WorkingArea; }
            catch { wa = new Rectangle(0, 0, Ui.Px(1024), Ui.Px(720)); }

            int maxW = wa.Width - Ui.Px(24);
            int maxH = wa.Height - Ui.Px(24);
            if (maxW < Ui.Px(640)) maxW = wa.Width;
            if (maxH < Ui.Px(480)) maxH = wa.Height;
            if (w > maxW) w = maxW;
            if (h > maxH) h = maxH;
            if (w < Ui.Px(760)) w = Ui.Px(760);
            if (h < Ui.Px(520)) h = Ui.Px(520);

            ClientSize = new Size(w, h);

            int mw = Ui.Px(760), mh = Ui.Px(520);
            if (mw > wa.Width) mw = Math.Max(Ui.Px(400), wa.Width - Ui.Px(20));
            if (mh > wa.Height) mh = Math.Max(Ui.Px(320), wa.Height - Ui.Px(20));
            MinimumSize = new Size(mw, mh);
        }

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            Layout2();
            Invalidate();
        }

        void Layout2()
        {
            if (!_built || _rail == null) return;
            int W = ClientSize.Width, H = ClientSize.Height;
            int railW = Ui.Px(Ui.RailW);

            int linkH = Ui.Px(22);
            int linkY = H - Ui.Px(Ui.GapS) - linkH * 2 - Ui.Px(Ui.GapXs);
            _rail.BottomReserve = H - linkY + Ui.Px(Ui.GapXs);
            _rail.SetBounds(0, 0, railW, H);

            _btnHelp.SetBounds(Ui.Px(Ui.GapXs), linkY, railW - Ui.Px(Ui.GapXs) * 2, linkH);
            _btnAbout.SetBounds(Ui.Px(Ui.GapXs), linkY + linkH, railW - Ui.Px(Ui.GapXs) * 2, linkH);

            // 内容区：栏宽 + 1px 分隔线 + 内容（左右 16dp、上下 8dp 内边距）
            int cx = railW + 1 + Ui.Px(Ui.ScreenPad);
            int cw = W - cx - Ui.Px(Ui.ScreenPad);
            int cy = Ui.Px(Ui.GapS);
            int ch = H - Ui.Px(Ui.GapS) * 2;
            if (cw < Ui.Px(120)) cw = Ui.Px(120);
            if (ch < Ui.Px(120)) ch = Ui.Px(120);

            for (int i = 0; i < 3; i++)
                if (_modules[i] != null) _modules[i].SetBounds(cx, cy, cw, ch);
        }

        void SelectModule(int i)
        {
            if (i == _current) return;
            _current = i;
            for (int k = 0; k < 3; k++)
                if (_modules[k] != null) _modules[k].Visible = k == i;
            if (_modules[i] != null)
            {
                _modules[i].BringToFront();
                _modules[i].OnActivated();
            }
            // 侧栏要重新提到最前，否则会被刚显示的模块盖住
            _rail.BringToFront();
            _btnHelp.BringToFront();
            _btnAbout.BringToFront();
            Invalidate();
        }

        // ------------------------------------------------------------ 绘制

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            // 用 ClientRectangle 而不是 e.ClipRectangle：让渐变始终以整个窗体为基准，
            // 子控件再调 Paper.Paint 时拿到的就是同一张底，接缝处不会错位。
            Draw.Paper(e.Graphics, ClientRectangle);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            int W = ClientSize.Width, H = ClientSize.Height;
            int railW = Ui.Px(Ui.RailW);

            // 侧栏与内容之间的一条细分隔线
            Draw.VLine(g, railW, 0, H, Pal.Line);
        }
    }
}
