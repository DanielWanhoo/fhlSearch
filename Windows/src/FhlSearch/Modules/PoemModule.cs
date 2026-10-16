using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using FhlSearch.Data;
using FhlSearch.Theme;

namespace FhlSearch.Modules
{
    /// <summary>
    /// 模块二：诗词检索（山石雅集第 15 题）
    ///
    ///  - 6 列 × 5 行 = 30 格，每格一个汉字；多输只取第一个；非汉字提示"非法字符"；
    ///  - 方向键移动选中格、朱砂方框标亮；点格子直接输入；
    ///  - 检索时从格中选 5 个字（顺序无关）与题库诗句匹配，命中格用绿框标亮并给序号；
    ///  - 结果附题目与作者；该模块没有层级检索，结果区不显示"二次检索"。
    /// </summary>
    public class PoemModule : ModuleBase
    {
        public override string ModuleName { get { return "诗词检索"; } }
        public override string BigTitle { get { return "山石雅集第 15 题"; } }

        const int Cols = 6, Rows = 5, Count = Cols * Rows;
        const int CellGap = 5;   // dp

        HeaderView _header;
        PoemGrid _grid;
        FButton _btnClear, _btnSearch;
        FButton _btnClearAll, _btnClearCur;
        ResultList _list;

        readonly TextBox[] _cells = new TextBox[Count];
        readonly char[] _chars = new char[Count];
        int _focus = 0;
        int _searchCount;
        bool _searched;
        int[] _hitCells = new int[0];
        List<Poem> _rows = new List<Poem>();
        Dictionary<Poem, int[]> _cellMap = new Dictionary<Poem, int[]>();
        int _rowH;
        int _lastWrapW = -1;
        List<string[]> _wrapped = new List<string[]>();
        string _flashText = "";
        int _flashUntil;

        public PoemModule()
        {
            _header = new HeaderView();
            _header.Title = BigTitle;
            _header.Subtitle = "在表格中填入汉字，检索蕴含的诗句";
            Controls.Add(_header);

            _grid = new PoemGrid(this);
            Controls.Add(_grid);
            BuildCells();

            _btnClear = MakeButton("清空", FButton.Kind.Light, delegate { ClearAll(); });
            _btnSearch = MakeButton("开始检索", FButton.Kind.Primary, delegate { DoSearch(); });

            _btnClearAll = MakeButton("清空所有", FButton.Kind.Light, delegate { ClearAll(); });
            _btnClearCur = MakeButton("清空当前", FButton.Kind.Light, delegate { ClearResultsOnly(); });

            _list = new ResultList();
            _list.GapAfterRow = Ui.GapS;
            _rowH = CalcRowHeight(1);
            _list.RowHeight = delegate(int i, int w) { return RowHeightAt(w, i); };
            _list.RowPaint = PaintRow;
            _list.EmptyPaint = PaintEmpty;
            _list.RowClicked += delegate(int i) { SelectHit(i); };
            _list.RowActivated += delegate(int i) { SelectHit(i); };
            Controls.Add(_list);

            _header.RightText = "检索 0 次";
            ShowInitial("在表格中填入汉字后点「开始检索」");
        }

        /// <summary>
        /// 建 30 个真正的 TextBox（中文输入法必须要有真实窗口才收得到），
        /// 边框、选中圈、命中标绿都由 PoemGrid 自己画，TextBox 只管显示那一个字。
        /// </summary>
        void BuildCells()
        {
            for (int i = 0; i < Count; i++)
            {
                if (_cells[i] != null) continue;
                TextBox tb = new TextBox();
                tb.BorderStyle = BorderStyle.None;
                tb.TextAlign = HorizontalAlignment.Center;
                tb.MaxLength = 1;
                tb.Font = Fonts.Of(Fonts.CellSize, false);
                tb.ForeColor = Pal.Ink;
                tb.BackColor = Pal.CardSoft;
                int idx = i;
                tb.TextChanged += delegate { OnCellEdited(idx, tb.Text); };
                tb.GotFocus += delegate { _focus = idx; _grid.Invalidate(); };
                tb.KeyDown += delegate (object s, KeyEventArgs e) { OnBoxKey(idx, e); };
                _cells[i] = tb;
            }
        }

        void OnBoxKey(int i, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Left) { MoveFocus(-1, 0); e.Handled = true; e.SuppressKeyPress = true; }
            else if (e.KeyCode == Keys.Right) { MoveFocus(1, 0); e.Handled = true; e.SuppressKeyPress = true; }
            else if (e.KeyCode == Keys.Up) { MoveFocus(0, -1); e.Handled = true; e.SuppressKeyPress = true; }
            else if (e.KeyCode == Keys.Down) { MoveFocus(0, 1); e.Handled = true; e.SuppressKeyPress = true; }
            else if (e.KeyCode == Keys.Enter) { DoSearch(); e.Handled = true; e.SuppressKeyPress = true; }
            else if (e.KeyCode == Keys.Back && _cells[i].TextLength == 0 && _chars[i] == '\0')
            {
                MoveFocus(-1, 0);
                e.Handled = true; e.SuppressKeyPress = true;
            }
        }

        FButton MakeButton(string t, FButton.Kind k, EventHandler h)
        {
            FButton b = new FButton();            b.Style = k;
            b.Text = t;
            b.AutoFit = true;
            b.Click += h;
            Controls.Add(b);
            return b;
        }

        public override void OnActivated()
        {
            Layout2();
            if (Focused == false && _cells[_focus] != null) _cells[_focus].Focus();
            Dbg.LogBounds("诗词.字格", _grid);
            Dbg.LogBounds("诗词.列表", _list);
        }

        // ------------------------------------------------------------ 字格

        public override void ResetAll() { ClearAll(); }

        char[] Chars { get { return _chars; } }

        void OnCellEdited(int i, string text)
        {
            // 只留第一个汉字
            string keep = "";
            if (!string.IsNullOrEmpty(text))
            {
                foreach (char c in text)
                {
                    if ((c >= 0x4E00 && c <= 0x9FFF) || (c >= 0x3400 && c <= 0x4DBF)) { keep = c.ToString(); break; }
                }
            }
            if (keep != text && _cells[i].Text != keep)
            {
                _cells[i].Text = keep;
                _cells[i].SelectionStart = keep.Length;
            }
            bool wasEmpty = _chars[i] == '\0';
            _chars[i] = keep.Length > 0 ? keep[0] : '\0';
            _grid.Invalidate();

            if (_searched) ClearResultsOnly();

            // 刚在空格里填了一个字 → 自动跳到下一格，连着打字不用一直点
            if (wasEmpty && keep.Length > 0) MoveFocus(1, 0);
        }

        void MoveFocus(int dc, int dr)
        {
            int c = _focus % Cols, r = _focus / Cols;
            c += dc; r += dr;
            if (c < 0) c = 0;
            if (c >= Cols) c = Cols - 1;
            if (r < 0) r = 0;
            if (r >= Rows) r = Rows - 1;
            SetFocusCell(r * Cols + c);
        }

        void SetFocusCell(int i)
        {
            if (i < 0 || i >= Count) return;
            _focus = i;
            try { _cells[i].Focus(); } catch { }
            _grid.Invalidate();
        }

        // ------------------------------------------------------------ 检索

        void DoSearch()
        {
            bool any = false;
            for (int i = 0; i < Count; i++) if (_chars[i] != '\0') any = true;
            if (!any) { Flash("请至少填写一个条件"); return; }

            _searched = true;
            _searchCount++;
            _header.RightText = "检索 " + _searchCount + " 次";

            List<Poem> hits = Bank.MatchPoems(_chars, out _cellMap);
            _rows = hits;
            _list.Count = hits.Count;
            _hitCells = new int[0];

            if (hits.Count == 0)
            {
                _grid.Invalidate();
                UpdateButtons(0);
                Layout2();
                Invalidate();
                Dbg.Log("诗词检索 -> 0 条");
                return;
            }

            _grid.Invalidate();
            UpdateButtons(hits.Count);
            Layout2();
            SelectHit(0);
            Dbg.Log("诗词检索 -> " + hits.Count + " 条");
        }

        void SelectHit(int i)
        {
            if (i < 0 || i >= _rows.Count) return;
            int[] cells;
            if (_cellMap.TryGetValue(_rows[i], out cells)) _hitCells = cells;
            else _hitCells = new int[0];
            _list.SelectedIndex = i;
            _grid.Invalidate();
        }

        void UpdateButtons(int n)
        {
            bool show = n >= 0;
            _btnClearAll.Visible = show;
            _btnClearCur.Visible = show;
        }

        void ShowInitial(string hint)
        {
            _flashText = "";
            _rows = new List<Poem>();
            _cellMap.Clear();
            _hitCells = new int[0];
            _list.Count = 0;
            _emptyText = hint;
            UpdateButtons(-1);
            Layout2();
            Invalidate();
            _grid.Invalidate();
        }

        string _emptyText = "在表格中填入汉字后点「开始检索」";

        /// <summary>清空全部：字格 + 结果 + 次数</summary>
        void ClearAll()
        {
            for (int i = 0; i < Count; i++)
            {
                _chars[i] = '\0';
                if (_cells[i] != null && _cells[i].Text.Length > 0) _cells[i].Text = "";
            }
            _searchCount = 0;
            _searched = false;
            _header.RightText = "检索 0 次";
            ShowInitial("在表格中填入汉字后点「开始检索」");
            SetFocusCell(0);
            Dbg.Log("诗词：清空");
        }

        /// <summary>只清结果与标亮，字格保留</summary>
        void ClearResultsOnly()
        {
            _searched = false;
            ShowInitial("在表格中填入汉字后点「开始检索」");
            Dbg.Log("诗词：清空当前（保留字格）");
        }

        void Flash(string msg)
        {
            _flashText = msg;
            _flashUntil = Environment.TickCount + 2600;
            Timer t = new Timer();
            t.Interval = 2600;
            t.Tick += delegate { t.Stop(); t.Dispose(); _flashText = ""; Invalidate(); };
            t.Start();
            Invalidate();
        }

        // ------------------------------------------------------------ 布局

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            Layout2();
        }

        bool _laying;

        void Layout2()
        {
            if (_laying || Width < 10 || Height < 10) return;
            _laying = true;
            try { LayoutCore(); }
            finally { _laying = false; }
        }

        void LayoutCore()
        {
            Rectangle left, right;
            SplitPanes(Width, Height, 44, out left, out right);

            int pad = Ui.Px(Ui.GapS);
            int gap = Ui.Px(Ui.GapS);

            int hh = HeaderView.NeedHeight();
            _header.SetBounds(left.X, 0, left.Width, hh);

            int btnH = Ui.Px(Ui.BtnH);
            int btnY = left.Bottom - btnH;

            // 字格：先按宽度算，再按可用高度收一收，保证 6×5 全部看得见
            int innerW = left.Width - pad * 2;
            int gapPx = Ui.Px(CellGap);
            int cellW = (innerW - gapPx * (Cols - 1)) / Cols;

            int availH = btnY - Ui.Px(Ui.GapM) - hh - pad * 2;
            int cellH = (availH - gapPx * (Rows - 1)) / Rows;

            int cell = Math.Min(cellW, cellH);
            int maxCell = Ui.Px(76);
            if (cell > maxCell) cell = maxCell;
            if (cell < Ui.Px(26)) cell = Ui.Px(26);

            int gridW = cell * Cols + gapPx * (Cols - 1);
            int gridH = cell * Rows + gapPx * (Rows - 1);
            int cardW = gridW + pad * 2;
            int cardX = left.X + (left.Width - cardW) / 2;

            _grid.SetBounds(cardX, hh, cardW, gridH + pad * 2);
            _grid.Configure(cell, gapPx, pad, _cells);

            // 清空 / 开始检索
            int bw1 = (left.Width - Ui.Px(Ui.GapS)) * 10 / 26;
            _btnClear.SetBounds(left.X, btnY, bw1, btnH);
            _btnSearch.SetBounds(_btnClear.Right + Ui.Px(Ui.GapS), btnY, left.Right - _btnClear.Right - Ui.Px(Ui.GapS), btnH);

            // 结果区
            int g = Ui.Px(Ui.GapS);
            int bw = (right.Width - g) / 2;
            int bh = Ui.Px(Ui.BtnHSmall);
            _btnClearAll.SetBounds(right.X, 0, bw, bh);
            _btnClearCur.SetBounds(_btnClearAll.Right + g, 0, right.Right - _btnClearAll.Right - g, bh);

            int listY = _btnClearAll.Visible ? bh + g + TitleBarHeight() + g : 0;
            _list.SetBounds(right.X, listY, right.Width, Math.Max(Ui.Px(40), right.Height - listY));
            _lastWrapW = -1;
        }

        int TitleBarHeight()
        {
            using (Graphics g = Graphics.FromHwnd(IntPtr.Zero))
                return Draw.Measure(g, "匹配结果", Fonts.BodyF()).Height;
        }

        // ------------------------------------------------------------ 绘制

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;

            Rectangle left, right;
            SplitPanes(Width, Height, 44, out left, out right);
            Draw.VLine(g, left.Right + Ui.Px(Ui.PaneGap), 0, Height, Pal.Line);

            if (_btnClearAll.Visible)
            {
                int y = Ui.Px(Ui.BtnHSmall) + Ui.Px(Ui.GapS);
                Font f = Fonts.BodyF();
                string pre = "匹配结果";
                Size ps = Draw.Measure(g, pre, f);
                Draw.Str(g, pre, f, Pal.Ink, right.X, y);
                Draw.Str(g, "(" + _rows.Count + ")", Fonts.Of(Fonts.Body, true), Pal.Ink, right.X + ps.Width + Ui.Px(Ui.GapXs), y);
            }

            if (_flashText.Length > 0 && Environment.TickCount < _flashUntil)
            {
                Font f = Fonts.BodySF();
                Size s = Draw.Measure(g, _flashText, f);
                int padX = Ui.Px(Ui.GapL), padY = Ui.Px(Ui.GapS);
                Rectangle box = new Rectangle(left.X + (left.Width - s.Width - padX * 2) / 2,
                                              Height - Ui.Px(70), s.Width + padX * 2, s.Height + padY * 2);
                Draw.FillRound(g, box, Ui.Pill(box.Height), Pal.Alpha(Pal.Ink, 235));
                Draw.Str(g, _flashText, f, Pal.OnDark, box.X + padX, box.Y + padY);
            }
        }

        // ------------------------------------------------------------ 结果行

        static int CalcRowHeight(int lines)
        {
            using (Graphics g = Graphics.FromHwnd(IntPtr.Zero))
                return Draw.Measure(g, "汉", Fonts.Of(Fonts.Result, false)).Height * lines
                     + Ui.Px(Ui.GapS) * 2 + (lines - 1) * Ui.Px(3);
        }

        int RowHeightAt(int width, int index)
        {
            EnsureWrap(width);
            int lines = 1;
            if (index >= 0 && index < _wrapped.Count) lines = Math.Max(1, _wrapped[index].Length);
            return CalcRowHeight(lines);
        }

        void EnsureWrap(int width)
        {
            if (width == _lastWrapW && _wrapped.Count == _rows.Count) return;
            _lastWrapW = width;
            _wrapped = new List<string[]>();
            using (Graphics g = Graphics.FromHwnd(IntPtr.Zero))
            {
                Font f = Fonts.Of(Fonts.Result, false);
                int avail = Math.Max(Ui.Px(60), width - Ui.Px(Ui.GapM) * 2);
                foreach (Poem p in _rows)
                {
                    List<string> ls = PersonInfoView.Wrap(g, Line(p), f, avail);
                    _wrapped.Add(ls.ToArray());
                }
            }
        }

        static string Line(Poem p)
        {
            return p.Verse + " · 《" + p.Title + "》 · " + p.Author;
        }

        void PaintRow(Graphics g, int index, Rectangle r, bool selected)
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            Draw.FillRound(g, r, Ui.Px(Ui.RadiusS), selected ? Pal.VermTint : Pal.CardSoft);
            Draw.StrokeRound(g, r, Ui.Px(Ui.RadiusS), selected ? Pal.VermLight : Pal.Line, 1f);

            Font f = Fonts.Of(Fonts.Result, false);
            int lh = Draw.Measure(g, "汉", f).Height;
            int y = r.Y + Ui.Px(Ui.GapS);
            string[] lines = (index < _wrapped.Count) ? _wrapped[index] : new string[] { "" };
            for (int i = 0; i < lines.Length; i++)
            {
                Draw.Str(g, lines[i], f, Pal.Ink, r.X + Ui.Px(Ui.GapM), y);
                y += lh + Ui.Px(3);
            }
        }

        void PaintEmpty(Graphics g, Rectangle r)
        {
            Font f = Fonts.BodySF();
            Size s = Draw.Measure(g, _emptyText, f);
            Draw.Str(g, _emptyText, f, Pal.InkHint, r.X + (r.Width - s.Width) / 2, r.Y + Ui.Px(Ui.GapM));
        }

        // ============================================================ 字格控件

        /// <summary>6×5 字格：格子是真正的 TextBox（中文输入法要用），边框与标亮由本控件画</summary>
        class PoemGrid : InkControl, ISurface
        {
            readonly PoemModule _owner;
            int _cell = 40, _gap = 5, _pad = 8;
            Rectangle[] _rects = new Rectangle[Count];

            public Color SurfaceColor { get { return Pal.Card; } }

            public PoemGrid(PoemModule owner)
            {
                _owner = owner;
            }

            /// <summary>由模块布局时调用，把 30 个 TextBox 摆好</summary>
            public void Configure(int cell, int gap, int pad, TextBox[] boxes)
            {
                _cell = cell; _gap = gap; _pad = pad;
                for (int r = 0; r < Rows; r++)
                    for (int c = 0; c < Cols; c++)
                    {
                        int i = r * Cols + c;
                        Rectangle box = new Rectangle(
                            pad + c * (cell + gap), pad + r * (cell + gap), cell, cell);
                        _rects[i] = box;

                        TextBox tb = boxes[i];
                        if (tb == null) continue;
                        if (tb.Parent != this) Controls.Add(tb);

                        // 格子小的时候字号跟着收一收，免得顶到边框
                        double fs = Math.Min(Fonts.CellSize, cell / (double)Ui.Scale * 0.55);
                        if (fs < 8) fs = 8;
                        Font nf = Fonts.Of(fs, false);
                        if (tb.Font != nf) tb.Font = nf;

                        // 单行 TextBox 的字是贴着**顶边**画的（它自己不会做垂直居中），
                        // 所以"字在格子里居中"要靠：把框的高设成 PreferredHeight、
                        // 再把这个框整体摆到格子的垂直中点。直接把框拉满整格，
                        // 字反而会浮在上半部分。
                        // 框只占中间一条，右上角也就腾出来给序号徽标了。
                        int fh = Math.Min(tb.PreferredHeight, box.Height);
                        int bw = Math.Max(Ui.Px(8), box.Width - Ui.Px(4));
                        tb.SetBounds(box.X + (box.Width - bw) / 2,
                                     box.Y + (box.Height - fh) / 2, bw, fh);
                    }
                Invalidate();
            }

            protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
            {
                if (keyData == Keys.Left) { _owner.MoveFocus(-1, 0); return true; }
                if (keyData == Keys.Right) { _owner.MoveFocus(1, 0); return true; }
                if (keyData == Keys.Up) { _owner.MoveFocus(0, -1); return true; }
                if (keyData == Keys.Down) { _owner.MoveFocus(0, 1); return true; }
                return base.ProcessCmdKey(ref msg, keyData);
            }

            protected override void OnMouseDown(MouseEventArgs e)
            {
                for (int i = 0; i < Count; i++)
                    if (_rects[i].Contains(e.Location)) { _owner.SetFocusCell(i); break; }
                base.OnMouseDown(e);
            }

            protected override void OnPaint(PaintEventArgs e)
            {
                Graphics g = e.Graphics;
                g.SmoothingMode = SmoothingMode.AntiAlias;
                Paper.Paint(this, g);

                // 卡片底
                Draw.Card(g, new Rectangle(0, 0, Width, Height), Pal.Card, Pal.Line);

                for (int i = 0; i < Count; i++)
                {
                    Rectangle r = _rects[i];
                    if (r.Width <= 0) continue;

                    bool hit = false;
                    int order = 0;
                    for (int k = 0; k < _owner._hitCells.Length; k++)
                        if (_owner._hitCells[k] == i) { hit = true; order = k + 1; break; }

                    bool cur = i == _owner._focus;

                    Color fill = hit ? Pal.GreenBg : Pal.CardSoft;
                    Color line = hit ? Pal.GreenLine : Pal.Line;
                    float lw = (hit || cur) ? Ui.Pf(1.6) : 1f;
                    if (cur && !hit) line = Pal.VermLight;

                    Draw.FillRound(g, r, Ui.Px(Ui.RadiusS), fill);
                    Draw.StrokeRound(g, r, Ui.Px(Ui.RadiusS), line, lw);

                    TextBox tb = _owner._cells[i];
                    if (tb != null) tb.BackColor = fill;

                    if (hit && order > 0) PaintBadge(g, r, order);
                }
            }

            /// <summary>命中格右上角的序号徽标（细绿圈 + 数字），说明这个字取自诗句的第几位</summary>
            static void PaintBadge(Graphics g, Rectangle cell, int order)
            {
                int d = Ui.Px(9);
                int cx = cell.Right - Ui.Px(7);
                int cy = cell.Y + Ui.Px(6);
                using (Pen p = new Pen(Pal.GreenLine, Ui.Pf(1.2)))
                    g.DrawEllipse(p, cx - d / 2f, cy - d / 2f, d, d);

                Font f = Fonts.Of(8, true);
                string s = order.ToString();
                Size sz = Draw.Measure(g, s, f);
                Draw.Str(g, s, f, Pal.GreenText, cx - sz.Width / 2, cy - sz.Height / 2);
            }
        }
    }
}
