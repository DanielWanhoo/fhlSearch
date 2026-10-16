using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace FhlSearch.Theme
{
    /// <summary>
    /// 一个"面"：里面的控件圆角外面应该是这个颜色，而不是窗体那张宣纸渐变。
    /// 卡片实现了它，卡里的按钮 / 输入框 / 选项卡就会自动继承卡片色。
    /// </summary>
    public interface ISurface
    {
        Color SurfaceColor { get; }
    }

    /// <summary>
    /// 所有自绘控件的基类。背景统一画成"整个窗体那张宣纸渐变在本控件位置上的那一块"，
    /// 这样圆角卡片外面露出来的底色和窗体无缝衔接，不会出现色块接缝。
    ///
    /// 控件坐在卡片上时，背景必须是卡片色而不是宣纸色，否则圆角外面会露出一个
    /// **方块状的纸色残余**。这一点靠 ISurface 自动继承，不用每个控件手写。
    /// </summary>
    public class InkControl : Control
    {
        /// <summary>
        /// 圆角外面露出来的底色。null = 自动（有 ISurface 祖先就用它的面色，否则用宣纸渐变）；
        /// 也可以显式指定，用来覆盖自动判断。
        /// </summary>
        public Color? Behind = null;

        public InkControl()
        {
            SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint
                   | ControlStyles.ResizeRedraw | ControlStyles.UserPaint, true);
            DoubleBuffered = true;
            BackColor = Pal.PaperTop;
            Font = Fonts.BodyF();
            ForeColor = Pal.Ink;
        }

        /// <summary>沿父链找最近的一个"面"</summary>
        protected Color? InheritedSurface()
        {
            Control p = Parent;
            while (p != null)
            {
                ISurface s = p as ISurface;
                if (s != null) return s.SurfaceColor;
                p = p.Parent;
            }
            return null;
        }

        /// <summary>本控件圆角外面应该是什么颜色（null = 宣纸渐变）</summary>
        protected Color? Bg
        {
            get { return Behind ?? InheritedSurface(); }
        }

        /// <summary>
        /// 画本控件的底。**所有自绘控件都必须用它**，不要直接调 Paper.Paint ——
        /// 直接画宣纸会无视 Behind / ISurface，卡片里的控件四角就会露出方块状纸色残余。
        /// </summary>
        protected void PaintBg(Graphics g)
        {
            Color? bg = Bg;
            if (bg.HasValue)
            {
                using (SolidBrush b = new SolidBrush(bg.Value))
                    g.FillRectangle(b, ClientRectangle);
                return;
            }
            Paper.Paint(this, g);
        }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            PaintBg(e.Graphics);
        }
    }

    // ============================================================ 卡片

    /// <summary>圆角卡片：宣纸面 + 细边；卡里的控件会自动继承卡片色</summary>
    public class CardPanel : InkControl, ISurface
    {
        public Color Fill = Pal.Card;
        public Color LineColor = Pal.Line;
        public int Radius = Ui.RadiusM;

        public Color SurfaceColor { get { return Fill; } }

        public CardPanel()
        {
            SetStyle(ControlStyles.Selectable, false);
            TabStop = false;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            PaintBg(g);
            Draw.Card(g, new Rectangle(0, 0, Width, Height), Fill, LineColor, Ui.Px(Radius));
        }
    }

    /// <summary>宣纸渐变的"全局对齐"绘制：以顶层窗体为基准，子控件各画自己那一块。</summary>
    public static class Paper
    {
        public static void Paint(Control c, Graphics g)
        {
            int offY = 0;
            Control p = c;
            // 走到顶层窗体为止（窗体自身的 Top 是屏幕坐标，不能算进去）
            while (p != null && p.Parent != null) { offY += p.Top; p = p.Parent; }
            int formH = c.Height + offY;
            Control top = c.TopLevelControl;
            if (top != null && top.ClientSize.Height > formH) formH = top.ClientSize.Height;
            Draw.Paper(g, new Rectangle(0, -offY, Math.Max(1, c.Width), Math.Max(1, formH)));
        }
    }

    // ============================================================ 按钮

    /// <summary>朱砂主按钮 / 浅色按钮（胶囊形，与安卓版一致）</summary>
    public class FButton : InkControl
    {
        public enum Kind { Primary, Light, Ghost }

        Kind _kind = Kind.Primary;
        bool _hover, _down;

        public Kind Style { get { return _kind; } set { _kind = value; Invalidate(); } }

        /// <summary>结果区那排小按钮：文字过长时自动缩字号，保证一行放得下</summary>
        public bool AutoFit = false;

        public FButton()
        {
            SetStyle(ControlStyles.Selectable, false);
            TabStop = false;
        }

        protected override void OnMouseEnter(EventArgs e) { _hover = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { _hover = false; _down = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e) { _down = true; Invalidate(); base.OnMouseDown(e); }
        protected override void OnMouseUp(MouseEventArgs e) { _down = false; Invalidate(); base.OnMouseUp(e); }
        protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }
        /// <summary>
        /// 按钮被藏起来时把悬停 / 按下状态清掉。
        /// 鼠标正停在按钮上、这时程序把按钮隐藏（检索 / 二次检索互换），
        /// WM_MOUSELEAVE 不一定会送到，残留的悬停态会让它下一次出现时"自带高亮"。
        /// </summary>
        protected override void OnVisibleChanged(EventArgs e)
        {
            if (!Visible) { _hover = false; _down = false; }
            base.OnVisibleChanged(e);
        }
        protected override void OnTextChanged(EventArgs e) { Invalidate(); base.OnTextChanged(e); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            PaintBg(g);

            Rectangle r = new Rectangle(0, 0, Width, Height);
            int radius = Ui.Pill(Height);
            Color text;

            if (_kind == Kind.Ghost)
            {
                // 侧栏底部的小链接：平时只有灰字，鼠标移上去转朱砂
                string gs = Text ?? "";
                Font gf = Fonts.Of(11, false);
                Size gz = Draw.Measure(g, gs, gf);
                Draw.Str(g, gs, gf, _hover ? Pal.Verm : Pal.InkHint, (Width - gz.Width) / 2, (Height - gz.Height) / 2);
                return;
            }

            if (!Enabled)
            {
                Draw.FillRound(g, r, radius, _kind == Kind.Primary ? Pal.Disabled : Pal.BtnLight);
                if (_kind == Kind.Light) Draw.StrokeRound(g, r, radius, Pal.Line, 1f);
                text = _kind == Kind.Primary ? Pal.OnDark : Pal.Disabled;
            }
            else if (_kind == Kind.Primary)
            {
                Draw.FillRound(g, r, radius, _down ? Pal.VermPressed : (_hover ? Pal.VermLight : Pal.Verm));
                text = Pal.OnDark;
            }
            else
            {
                Draw.FillRound(g, r, radius, (_down || _hover) ? Pal.GoldTint : Pal.BtnLight);
                Draw.StrokeRound(g, r, radius, _hover ? Pal.GoldLight : Pal.LineStrong, 1f);
                text = Pal.Ink;
            }

            string s = Text ?? "";
            Font f = Fonts.BtnF();
            // 放不下就缩字号，但**不要把结果写回 AutoFit 字段**：控件刚建出来时宽度还是 0，
            // 第一次重绘就会把它永久置 true，之后窗口变窄再变宽字号也回不来。这里按当前宽度现算。
            if (AutoFit || Draw.Measure(g, s, f).Width > Width - Ui.Px(10))
                f = Draw.Fit(g, s, Fonts.Btn, true, Width - Ui.Px(10));

            Size sz = Draw.Measure(g, s, f);
            Draw.Str(g, s, f, text, (Width - sz.Width) / 2, (Height - sz.Height) / 2);
        }
    }

    // ============================================================ 输入框

    /// <summary>
    /// 宣纸内凹质感的输入框（对应 Material 的 OutlinedBox）：
    /// 空且没聚焦时占位符躺在正中；一旦聚焦或有内容，标签就浮到左上角、把边框顶出一个缺口。
    /// </summary>
    public class FInput : InkControl
    {
        TextBox _box;
        bool _focus;
        int _maxLen = 8;
        bool _ph;        // 现在框里显示的是占位符（不是用户输入的内容）
        bool _sup;       // 抑制 TextChanged 回调（占位符的写入不算用户输入）

        /// <summary>输入了非法字符（边框转朱砂）</summary>
        public bool Invalid;

        public TextBox Box { get { return _box; } }

        string _hint = "";

        /// <summary>占位 / 浮动标签文字</summary>
        public string Hint
        {
            get { return _hint; }
            set { _hint = value ?? ""; RefreshPh(); Invalidate(); }
        }

        /// <summary>允许输入的字符（返回 false 会被丢掉）</summary>
        public Func<char, bool> Filter;

        public int MaxLen
        {
            get { return _maxLen; }
            set { _maxLen = value < 0 ? 0 : value; ApplyMaxLen(); }
        }

        /// <summary>是否允许中文输入法（拼音/声调格要关掉）</summary>
        public bool AllowIme
        {
            get { return _box.ImeMode != ImeMode.Disable; }
            set { _box.ImeMode = value ? ImeMode.Inherit : ImeMode.Disable; }
        }

        public new event EventHandler TextChanged;
        public event EventHandler Submitted;

        public override string Text
        {
            get { return (_box == null || _ph) ? "" : _box.Text; }
            set
            {
                if (_box == null) return;
                string v = value ?? "";
                HidePh();
                if (_box.Text != v) _box.Text = v;
                RefreshPh();
            }
        }

        public FInput()
        {
            SetStyle(ControlStyles.Selectable, false);
            TabStop = false;

            _box = new TextBox();
            _box.BorderStyle = BorderStyle.None;
            _box.TextAlign = HorizontalAlignment.Center;
            _box.BackColor = Pal.InputFill;
            _box.ForeColor = Pal.Ink;
            _box.Font = Fonts.BodyF();
            _box.MaxLength = _maxLen;
            _box.ShortcutsEnabled = true;
            _box.TextChanged += delegate
            {
                if (!_sup)
                {
                    if (_ph) HidePh();          // 用户真的打字了，撤掉占位符
                    Invalidate();
                    EventHandler h = TextChanged;
                    if (h != null) h(this, EventArgs.Empty);
                }
            };
            _box.GotFocus += delegate { _focus = true; HidePh(); Place(); Invalidate(); };
            _box.LostFocus += delegate { _focus = false; RefreshPh(); Place(); Invalidate(); };
            _box.KeyDown += delegate (object s, KeyEventArgs e)
            {
                if (e.KeyCode == Keys.Enter)
                {
                    e.SuppressKeyPress = true;
                    e.Handled = true;
                    EventHandler h = Submitted;
                    if (h != null) h(this, EventArgs.Empty);
                }
            };
            _box.KeyPress += delegate (object s, KeyPressEventArgs e)
            {
                if (char.IsControl(e.KeyChar)) return;
                if (Filter != null && !Filter(e.KeyChar))
                {
                    e.Handled = true;
                    Invalid = true;
                    Invalidate();
                }
                else
                {
                    Invalid = false;
                    Invalidate();
                }
            };
            Controls.Add(_box);
        }

        // ------------------------------------------------------ 占位符

        /// <summary>
        /// 占位符直接写进真实 TextBox 里（居中、灰色），而不是由父控件画在背后 ——
        /// TextBox 是不透明窗口，画在背后会被它整个盖住。
        /// 只在「没聚焦且没内容」时显示，所以不会和输入法打架。
        /// </summary>
        void ShowPh()
        {
            if (_hint.Length == 0 || _ph || _box == null || _focus) return;
            _sup = true;
            _box.MaxLength = Math.Max(_maxLen, _hint.Length);
            _box.ForeColor = Pal.InkHint;
            _box.Font = PhFont();
            _box.Text = _hint;
            _ph = true;
            try { _box.SelectionStart = 0; } catch { }
            _sup = false;
        }

        void HidePh()
        {
            if (!_ph) return;
            _sup = true;
            _box.Text = "";
            _ph = false;
            _box.ForeColor = Pal.Ink;
            _box.Font = Fonts.BodyF();
            ApplyMaxLen();
            _sup = false;
        }

        void RefreshPh()
        {
            if (_box == null) return;
            if (_focus) { HidePh(); return; }
            if (!_ph && _box.TextLength == 0) ShowPh();
        }

        void ApplyMaxLen()
        {
            if (_box != null && !_ph) _box.MaxLength = _maxLen < 1 ? 1 : _maxLen;
        }

        /// <summary>框窄的时候占位符也缩一缩，别被切成两半</summary>
        Font PhFont()
        {
            Font f = Fonts.BodyF();
            int avail = Math.Max(Ui.Px(10), Width - Ui.Px(24));
            try
            {
                using (Graphics g = CreateGraphics())
                {
                    if (Draw.Measure(g, _hint, f).Width <= avail) return f;
                    return Draw.Fit(g, _hint, Fonts.Body, false, avail);
                }
            }
            catch { return f; }
        }

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            if (_box != null)
            {
                if (_ph) _box.Font = PhFont();
                Place();
            }
        }

        void Place()
        {
            int fh = _box.PreferredHeight;
            int y = (Height - fh) / 2;
            if (Floating) y += Ui.Px(5);
            if (y < 0) y = 0;
            _box.SetBounds(Ui.Px(12), y, Math.Max(Ui.Px(20), Width - Ui.Px(24)), fh);
        }

        bool Floating { get { return _focus || (!_ph && _box.TextLength > 0); } }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            PaintBg(g);

            Rectangle r = new Rectangle(0, 0, Width, Height);
            int radius = Ui.Px(Ui.RadiusM);
            Draw.FillRound(g, r, radius, Pal.InputFill);

            Color line = Invalid ? Pal.Error : (_focus ? Pal.Verm : Pal.LineStrong);
            Draw.StrokeRound(g, r, radius, line, (_focus || Invalid) ? Ui.Pf(2) : 1f);

            if (Hint.Length == 0) return;

            if (Floating)
            {
                Font lf = Draw.Fit(g, Hint, 11, false, Width - Ui.Px(20));
                Size sz = Draw.Measure(g, Hint, lf);
                Size bs = Draw.Measure(g, "汉", Fonts.BodyF());
                int lx = Ui.Px(12);
                int ly = (Height - bs.Height) / 2 - Ui.Px(12);
                if (ly < -sz.Height / 2) ly = -sz.Height / 2;

                // 把标签下面那截边框擦掉，做出 Material 的"缺口"效果
                Color bg = Bg ?? Pal.Card;
                using (SolidBrush b = new SolidBrush(bg))
                    g.FillRectangle(b, lx - Ui.Px(3), ly, sz.Width + Ui.Px(6), sz.Height);
                Draw.Str(g, Hint, lf, Invalid ? Pal.Error : (_focus ? Pal.Verm : Pal.InkHint), lx, ly);
            }
        }

        public void FocusBox() { try { _box.Focus(); } catch { } }

        /// <summary>点输入框的任意位置（包括边框内边距）都把光标送进文本框</summary>
        protected override void OnMouseDown(MouseEventArgs e)
        {
            FocusBox();
            base.OnMouseDown(e);
        }
    }

    // ============================================================ 选项卡

    /// <summary>模式选项卡（拼音 / 声调 / 单字）：等宽平分，选中项朱砂字 + 下方朱砂短横</summary>
    public class FSegTabs : InkControl
    {
        string[] _items = new string[0];
        int _sel;
        int _hoverIdx = -1;

        public event EventHandler SelectedChanged;

        public int Selected
        {
            get { return _sel; }
            set
            {
                if (value < 0 || value >= _items.Length || value == _sel) return;
                _sel = value;
                Invalidate();
                EventHandler h = SelectedChanged;
                if (h != null) h(this, EventArgs.Empty);
            }
        }

        public FSegTabs()
        {
            SetStyle(ControlStyles.Selectable, false);
            TabStop = false;
        }

        public void SetItems(string[] items)
        {
            _items = items ?? new string[0];
            if (_sel >= _items.Length) _sel = 0;
            Invalidate();
        }

        public string[] Items { get { return _items; } }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            int i = IndexAt(e.X);
            if (i != _hoverIdx) { _hoverIdx = i; Invalidate(); }
            base.OnMouseMove(e);
        }

        protected override void OnMouseLeave(EventArgs e) { _hoverIdx = -1; Invalidate(); base.OnMouseLeave(e); }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            int i = IndexAt(e.X);
            if (i >= 0) Selected = i;
            base.OnMouseDown(e);
        }

        int IndexAt(int x)
        {
            if (_items.Length == 0 || Width <= 0) return -1;
            int i = x * _items.Length / Width;
            if (i < 0) i = 0;
            if (i >= _items.Length) i = _items.Length - 1;
            return i;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            PaintBg(g);

            Rectangle r = new Rectangle(0, 0, Width, Height);
            int radius = Ui.Px(Ui.RadiusM);
            Draw.FillRound(g, r, radius, Pal.CardSoft);
            Draw.StrokeRound(g, r, radius, Pal.Line, 1f);

            if (_items.Length == 0) return;
            Font f = Fonts.BodySF();
            int tabW = Width / _items.Length;

            for (int i = 0; i < _items.Length; i++)
            {
                Rectangle tr = new Rectangle(i * tabW, 0, tabW, Height);
                bool sel = i == _sel;
                Color c = sel ? Pal.Verm : (i == _hoverIdx ? Pal.Ink : Pal.InkSub);
                Size sz = Draw.Measure(g, _items[i], f);
                Draw.Str(g, _items[i], f, c,
                         tr.X + (tr.Width - sz.Width) / 2,
                         tr.Y + (tr.Height - sz.Height) / 2 - Ui.Px(4));

                if (sel)
                {
                    int iw = Math.Max(Ui.Px(18), (int)(sz.Width * 0.78));
                    int ih = Math.Max(2, Ui.Px(3));
                    Draw.FillRound(g, new Rectangle(tr.X + (tr.Width - iw) / 2, Height - ih - Ui.Px(8), iw, ih),
                                   ih / 2, Pal.Verm);
                }
            }
        }
    }

    // ============================================================ 侧栏导航

    /// <summary>左侧 tab 栏：三项把整栏高度三等分，选中项是朱砂淡底圆角块</summary>
    public class RailNav : InkControl
    {
        public static readonly string[] Labels = { "成语检索", "诗词检索", "名士检索" };
        static readonly Draw.Icon[] Icons = { Draw.Icon.Book, Draw.Icon.Grid, Draw.Icon.Person };

        int _sel;
        int _hoverIdx = -1;

        /// <summary>底部要留给"使用说明 / 关于题库"的高度（像素），三个格子不会压到它们</summary>
        public int BottomReserve = 0;

        public event EventHandler SelectedChanged;

        public int Selected
        {
            get { return _sel; }
            set
            {
                if (value < 0 || value > 2 || value == _sel) return;
                _sel = value;
                Invalidate();
                EventHandler h = SelectedChanged;
                if (h != null) h(this, EventArgs.Empty);
            }
        }

        public RailNav()
        {
            SetStyle(ControlStyles.Selectable, false);
            TabStop = false;
        }

        int SlotH { get { return Math.Max(Ui.Px(48), (Height - Ui.Px(Ui.GapS) * 2 - BottomReserve) / 3); } }

        Rectangle ItemRect(int i)
        {
            int padV = Ui.Px(Ui.GapS), padH = Ui.Px(Ui.GapXs);
            int top = padV + i * SlotH;
            int h = SlotH - Ui.Px(Ui.GapXs);
            if (top + h > Height) h = Height - top;
            if (h < 1) h = 1;
            return new Rectangle(padH, top, Math.Max(1, Width - padH * 2), h);
        }

        int IndexAt(Point p)
        {
            for (int i = 0; i < 3; i++) if (ItemRect(i).Contains(p)) return i;
            return -1;
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            int i = IndexAt(e.Location);
            if (i != _hoverIdx) { _hoverIdx = i; Invalidate(); }
            base.OnMouseMove(e);
        }

        protected override void OnMouseLeave(EventArgs e) { _hoverIdx = -1; Invalidate(); base.OnMouseLeave(e); }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            int i = IndexAt(e.Location);
            if (i >= 0) Selected = i;
            base.OnMouseDown(e);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            PaintBg(g);

            Font lf = Fonts.Of(Fonts.RailLabel, false);
            int iconSz = Ui.Px(Ui.TabIcon);

            for (int i = 0; i < 3; i++)
            {
                Rectangle it = ItemRect(i);
                bool sel = i == _sel;

                if (sel) Draw.FillRound(g, it, Ui.Px(Ui.RadiusM), Pal.VermTint);
                else if (i == _hoverIdx) Draw.FillRound(g, it, Ui.Px(Ui.RadiusM), Pal.Alpha(Pal.GoldTint, 150));

                Size ls = Draw.Measure(g, Labels[i], lf);
                int contentH = iconSz + Ui.Px(Ui.GapXs) + ls.Height;
                int y = it.Y + (it.Height - contentH) / 2;

                Color c = sel ? Pal.Verm : Pal.InkSub;
                Draw.NavIcon(g, Icons[i], new Rectangle(it.X + (it.Width - iconSz) / 2, y, iconSz, iconSz), c);
                Draw.Str(g, Labels[i], lf, c, it.X + (it.Width - ls.Width) / 2, y + iconSz + Ui.Px(Ui.GapXs));
            }
        }
    }

    // ============================================================ 页头

    /// <summary>模块页头：朱砂竖条 + 大标题 + 右上角计数 + 副标题</summary>
    public class HeaderView : InkControl
    {
        string _title = "", _sub = "", _right = "";

        public string Title { get { return _title; } set { _title = value ?? ""; Invalidate(); } }
        public string Subtitle { get { return _sub; } set { _sub = value ?? ""; Invalidate(); } }
        public string RightText { get { return _right; } set { _right = value ?? ""; Invalidate(); } }

        public HeaderView()
        {
            SetStyle(ControlStyles.Selectable, false);
            TabStop = false;
        }

        /// <summary>页头需要的高度</summary>
        public static int NeedHeight()
        {
            return Ui.Px(Ui.GapL) + Ui.Px(26) + Ui.Px(Ui.GapXs) + LineH() + Ui.Px(Ui.GapXs);
        }

        static int LineH()
        {
            using (Graphics g = Graphics.FromHwnd(IntPtr.Zero))
                return Draw.Measure(g, "汉字", Fonts.SubtitleF()).Height;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            PaintBg(g);

            int top = Ui.Px(Ui.GapL);
            int barH = Ui.Px(26);
            Font tf = Fonts.TitleF();

            Draw.FillRound(g, new Rectangle(0, top, Ui.Px(4), barH), Ui.Px(2), Pal.Verm);

            Size ts = Draw.Measure(g, _title, tf);
            Draw.Str(g, _title, tf, Pal.Ink, Ui.Px(Ui.GapS), top + (barH - ts.Height) / 2);

            if (_right.Length > 0)
            {
                Font rf = Fonts.BodySF();
                Size rs = Draw.Measure(g, _right, rf);
                Draw.Str(g, _right, rf, Pal.InkSub, Width - rs.Width, top + (barH - rs.Height) / 2);
            }

            if (_sub.Length > 0)
            {
                Font sf = Fonts.SubtitleF();
                Draw.Str(g, _sub, sf, Pal.InkSub, 0, top + barH + Ui.Px(Ui.GapXs));
            }
        }
    }

    // ============================================================ 名士条件行

    /// <summary>名士检索的一个条件行：左＝条件名，右＝已选值（朱砂）/提示（灰） + 下箭头</summary>
    public class FModeRow : InkControl
    {
        bool _hover;

        public string Caption = "";
        public string Value = "";
        public string Placeholder = "选择";

        public FModeRow()
        {
            SetStyle(ControlStyles.Selectable, false);
            TabStop = false;
        }

        protected override void OnMouseEnter(EventArgs e) { _hover = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { _hover = false; Invalidate(); base.OnMouseLeave(e); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            PaintBg(g);
            PaintRow(g, new Rectangle(0, 0, Width, Height), Caption, Value, Placeholder, _hover);
        }

        /// <summary>画一行条件（列表里直接用这个方法，不必为每行创建一个控件）</summary>
        public static void PaintRow(Graphics g, Rectangle r, string caption, string value, string placeholder, bool hover)        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            int radius = Ui.Px(Ui.RadiusM);
            Draw.FillRound(g, r, radius, hover ? Pal.CardSoft : Pal.Card);
            Draw.StrokeRound(g, r, radius, hover ? Pal.GoldLight : Pal.LineStrong, 1f);

            Font nf = Fonts.BodyF();
            Size ns = Draw.Measure(g, caption, nf);
            Draw.Str(g, caption, nf, Pal.Ink, r.X + Ui.Px(Ui.GapL), r.Y + (r.Height - ns.Height) / 2);

            Font vf = Fonts.BodySF();
            bool has = !string.IsNullOrEmpty(value);
            string shown = has ? value : placeholder;
            Size vs = Draw.Measure(g, shown, vf);
            int chW = Ui.Px(10);
            int vx = r.Right - Ui.Px(Ui.GapM) - chW - Ui.Px(Ui.GapXs) - vs.Width;
            Draw.Str(g, shown, vf, has ? Pal.Verm : Pal.InkHint, vx, r.Y + (r.Height - vs.Height) / 2);

            Draw.Chevron(g, r.Right - Ui.Px(Ui.GapM) - chW / 2, r.Y + r.Height / 2, chW, Pal.InkHint);
        }
    }

    // ============================================================ 滚动列表

    /// <summary>
    /// 通用结果列表：行高/画法由外面给，自己负责滚动、选中、点击与细滚动条。
    /// 实现了 IWheelScrollable，所以鼠标停在上面就能滚（不需要先点一下）。
    /// </summary>
    public class ResultList : InkControl, IWheelScrollable
    {
        int _count;
        int _sel = -1;
        int _scroll;
        int _hoverIdx = -1;

        /// <summary>行间距（dp）</summary>
        public int GapAfterRow = Ui.GapM;

        /// <summary>给定可用宽度，返回第 i 行的高度</summary>
        public Func<int, int, int> RowHeight;

        /// <summary>画第 i 行</summary>
        public Action<Graphics, int, Rectangle, bool> RowPaint;

        /// <summary>没有结果时画空态提示</summary>
        public Action<Graphics, Rectangle> EmptyPaint;

        public event Action<int> RowClicked;
        public event Action<int> RowActivated;
        public event Action SelectionChanged;

        /// <summary>当前鼠标悬停的行（-1 表示没有）</summary>
        public int HoverIndex { get { return _hoverIdx; } }

        public ResultList()
        {
            SetStyle(ControlStyles.Selectable, true);
            TabStop = true;
        }

        public int Count
        {
            get { return _count; }
            set
            {
                _count = value;
                if (_sel >= _count) _sel = -1;
                _scroll = 0;
                Invalidate();
            }
        }

        public int SelectedIndex
        {
            get { return _sel; }
            set
            {
                int v = (value >= 0 && value < _count) ? value : -1;
                if (v == _sel) return;
                _sel = v;
                EnsureVisible(v);
                Invalidate();
                Action h = SelectionChanged;
                if (h != null) h();
            }
        }

        // ------------------------------------------------------ 布局

        int RowH(int i, int width)
        {
            if (RowHeight == null) return Ui.Px(56);
            int h = RowHeight(i, width);
            return h < 1 ? 1 : h;
        }

        int ContentH
        {
            get
            {
                int w = Width - Ui.Px(Ui.GapS) - Ui.Px(6);
                int h = 0;
                for (int i = 0; i < _count; i++) h += RowH(i, w) + Ui.Px(GapAfterRow);
                return h;
            }
        }

        int MaxScroll
        {
            get
            {
                int m = ContentH - Height + Ui.Px(Ui.GapS);
                return m < 0 ? 0 : m;
            }
        }

        Rectangle RectOf(int i)
        {
            int w = Width - Ui.Px(Ui.GapS) - Ui.Px(6);
            int y = -_scroll;
            for (int k = 0; k < i; k++) y += RowH(k, w) + Ui.Px(GapAfterRow);
            return new Rectangle(Ui.Px(2), y, w, RowH(i, w));
        }

        int IndexAt(Point p)
        {
            int w = Width - Ui.Px(Ui.GapS) - Ui.Px(6);
            int y = -_scroll;
            for (int i = 0; i < _count; i++)
            {
                int h = RowH(i, w);
                if (p.Y >= y && p.Y < y + h + Ui.Px(GapAfterRow) / 2) return i;
                y += h + Ui.Px(GapAfterRow);
            }
            return -1;
        }

        public void EnsureVisible(int i)
        {
            if (i < 0 || i >= _count) return;
            Rectangle r = RectOf(i);
            int dy = 0;
            if (r.Y < 0) dy = -r.Y - Ui.Px(Ui.GapS);
            else if (r.Bottom > Height) dy = Height - r.Bottom - Ui.Px(Ui.GapS);
            if (dy != 0) { _scroll += dy; Clamp(); Invalidate(); }
        }

        void Clamp()
        {
            int m = MaxScroll;
            if (_scroll < 0) _scroll = 0;
            if (_scroll > m) _scroll = m;
        }

        // ------------------------------------------------------ 滚轮

        public bool CanScroll { get { return MaxScroll > 0; } }

        public void WheelScroll(int delta)
        {
            if (delta == 0) return;
            _scroll -= delta / 120 * Ui.Px(56);
            Clamp();
            Invalidate();
        }

        protected override void OnMouseWheel(MouseEventArgs e)
        {
            WheelScroll(e.Delta);
            base.OnMouseWheel(e);
        }

        // ------------------------------------------------------ 鼠标 / 键盘

        protected override void OnMouseMove(MouseEventArgs e)
        {
            int i = IndexAt(e.Location);
            if (i != _hoverIdx) { _hoverIdx = i; Invalidate(); }
            base.OnMouseMove(e);
        }

        protected override void OnMouseLeave(EventArgs e) { _hoverIdx = -1; Invalidate(); base.OnMouseLeave(e); }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            Focus();
            int i = IndexAt(e.Location);
            if (i >= 0)
            {
                SelectedIndex = i;
                Action<int> h = RowClicked;
                if (h != null) h(i);
            }
            base.OnMouseDown(e);
        }

        protected override void OnMouseDoubleClick(MouseEventArgs e)
        {
            int i = IndexAt(e.Location);
            if (i >= 0)
            {
                Action<int> h = RowActivated;
                if (h != null) h(i);
            }
            base.OnMouseDoubleClick(e);
        }

        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            if (_count > 0)
            {
                if (keyData == Keys.Down)
                {
                    SelectedIndex = _sel < 0 ? 0 : Math.Min(_count - 1, _sel + 1);
                    return true;
                }
                if (keyData == Keys.Up)
                {
                    SelectedIndex = _sel <= 0 ? 0 : _sel - 1;
                    return true;
                }
                if (keyData == Keys.Enter && _sel >= 0)
                {
                    Action<int> h = RowActivated;
                    if (h != null) h(_sel);
                    return true;
                }
                if (keyData == Keys.PageDown)
                {
                    _scroll += Height / 2; Clamp(); Invalidate(); return true;
                }
                if (keyData == Keys.PageUp)
                {
                    _scroll -= Height / 2; Clamp(); Invalidate(); return true;
                }
            }
            return base.ProcessCmdKey(ref msg, keyData);
        }

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            Clamp();
        }

        // ------------------------------------------------------ 绘制

        protected override void OnPaint(PaintEventArgs e)
        {
            try { PaintCore(e.Graphics); }
            catch (Exception ex)
            {
                Dbg.Log("ResultList 绘制失败: " + ex);
                try
                {
                    e.Graphics.ResetClip();
                    Draw.Str(e.Graphics, "列表绘制失败：" + ex.Message, Fonts.BodySF(), Pal.Error, 4, 4);
                }
                catch { }
            }
        }

        void PaintCore(Graphics g)
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            PaintBg(g);

            if (_count == 0)
            {
                if (EmptyPaint != null) EmptyPaint(g, new Rectangle(0, Ui.Px(Ui.GapM), Width, Height - Ui.Px(Ui.GapM)));
                return;
            }

            Clamp();
            int w = Width - Ui.Px(Ui.GapS) - Ui.Px(6);
            int y = -_scroll;
            for (int i = 0; i < _count; i++)
            {
                int h = RowH(i, w);
                Rectangle r = new Rectangle(Ui.Px(2), y, w, h);
                if (r.Bottom >= 0 && r.Y <= Height && RowPaint != null)
                    RowPaint(g, i, r, i == _sel);
                y += h + Ui.Px(GapAfterRow);
            }

            // 细滚动条
            int ms = MaxScroll;
            if (ms > 0)
            {
                int trackH = Height - Ui.Px(Ui.GapS) * 2;
                int thumbH = Math.Max(Ui.Px(28), trackH * Height / Math.Max(1, ContentH));
                int thumbY = Ui.Px(Ui.GapS) + (trackH - thumbH) * _scroll / ms;
                Draw.FillRound(g, new Rectangle(Width - Ui.Px(4), thumbY, Ui.Px(3), thumbH),
                               Ui.Px(2), Pal.Alpha(Pal.Gold, 120));
            }
        }
    }
}
