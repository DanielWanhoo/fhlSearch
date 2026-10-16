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
    /// 模块一：成语检索（山石雅集第 14 题）
    ///
    ///  - 拼音 / 声调 / 单字 三种模式，各 4 个输入框；拼音模糊，声调与单字精确；
    ///  - 层级检索：首次在全库筛，之后在上一层结果里筛；
    ///  - 结果里把用户填了内容的位次，在汉字 / 拼音 / 声调三处同时标绿；
    ///  - 按键规则：还没有上一批结果时给"检索"，有了上一批结果就给
    ///    "清空所有 / 清空当前 / 二次检索"（"检索"自动收起，清空回初始状态再恢复）。
    /// </summary>
    public class IdiomModule : ModuleBase
    {
        public override string ModuleName { get { return "成语检索"; } }
        public override string BigTitle { get { return "山石雅集第 14 题"; } }

        HeaderView _header;
        CardPanel _card;
        FSegTabs _tabs;
        readonly FInput[] _inputs = new FInput[4];
        FButton _btnSearch;
        FButton _btnClearAll, _btnClearCur, _btnSecond;
        ResultList _list;

        int _mode;                       // 0=拼音 1=声调 2=单字
        readonly Dictionary<int, string[]> _modeInputs = new Dictionary<int, string[]>();
        readonly List<List<Idiom>> _levels = new List<List<Idiom>>();
        /// <summary>与 _levels 一一对应：每一层当时用的 4 个格子内容</summary>
        readonly List<string[]> _levelCells = new List<string[]>();
        bool _narrowed;      // 右栏这批结果是不是「二次检索」筛出来的
        int _poolCount;      // 这次检索用到的范围条数（全库 or 上一批）

        int _searchCount;
        string _emptyText = "填写检索条件后点「检索」";

        public IdiomModule()
        {
            _header = new HeaderView();
            _header.Title = BigTitle;
            _header.Subtitle = "按拼音 / 声调 / 单字检索成语";
            Controls.Add(_header);

            _card = new CardPanel();
            Controls.Add(_card);

            _tabs = new FSegTabs();
            _tabs.SetItems(new string[] { "拼音", "声调", "单字" });
            _tabs.SelectedChanged += delegate { OnModeChanged(); };
            _card.Controls.Add(_tabs);

            for (int i = 0; i < 4; i++)
            {
                FInput f = new FInput();
                f.Hint = "拼音";
                f.MaxLen = 6;
                f.AllowIme = false;
                f.Filter = PinyinFilter;
                int idx = i;
                f.TextChanged += delegate { f.Invalid = false; };
                f.Submitted += delegate { DoSearch(); };
                _inputs[i] = f;
                _card.Controls.Add(f);
            }

            _btnSearch = new FButton();
            _btnSearch.Style = FButton.Kind.Primary;
            _btnSearch.Text = "检索";
            _btnSearch.Click += delegate { DoSearch(); };
            Controls.Add(_btnSearch);

            _btnClearAll = MakeAction("清空所有", FButton.Kind.Light, delegate { OnClearAll(); });
            _btnClearCur = MakeAction("清空当前", FButton.Kind.Light, delegate { OnClearCurrent(); });
            _btnSecond = MakeAction("二次检索", FButton.Kind.Primary, delegate { OnSecondSearch(); });

            _list = new ResultList();
            _rowH = CalcRowHeight();
            _list.RowHeight = delegate(int i, int w) { return _rowH; };
            _list.RowPaint = PaintRow;
            _list.EmptyPaint = PaintEmpty;
            Controls.Add(_list);

            _header.RightText = "检索 0 次";
            ApplyMode();
            ShowInitial("填写检索条件后点「检索」");
        }

        int _rowH;

        static int CalcRowHeight()
        {
            using (Graphics g = Graphics.FromHwnd(IntPtr.Zero))
            {
                int h = Ui.Px(Ui.GapM) * 2;
                h += Draw.Measure(g, "汉", Fonts.Of(Fonts.IdiomWord, true)).Height;
                h += Ui.Px(Ui.GapXs);
                h += Draw.Measure(g, "an", Fonts.BodyF()).Height;
                h += Ui.Px(2);
                h += Draw.Measure(g, "声调：4", Fonts.BodySF()).Height;
                return h;
            }
        }

        FButton MakeAction(string text, FButton.Kind kind, EventHandler h)
        {
            FButton b = new FButton();
            b.Style = kind;
            b.Text = text;
            b.AutoFit = true;
            b.Click += h;
            Controls.Add(b);
            return b;
        }

        public override void OnActivated()
        {
            Layout2();
            if (_inputs[0] != null) _inputs[0].FocusBox();
            Dbg.LogBounds("成语.列表", _list);
        }

        // ------------------------------------------------------------ 模式

        bool PinyinFilter(char c)
        {
            return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == 'v' || c == 'V' || c == '\'';
        }

        bool ToneFilter(char c) { return c >= '1' && c <= '4'; }

        bool CharFilter(char c)
        {
            return (c >= 0x4E00 && c <= 0x9FFF) || (c >= 0x3400 && c <= 0x4DBF);
        }

        void OnModeChanged()
        {
            _modeInputs[_mode] = CurrentCells();
            _mode = _tabs.Selected;
            ApplyMode();
        }

        void ApplyMode()
        {
            string[] saved;
            if (!_modeInputs.TryGetValue(_mode, out saved)) saved = new string[] { "", "", "", "" };
            string hint = _mode == 0 ? "拼音" : (_mode == 1 ? "声调" : "单字");
            for (int i = 0; i < 4; i++)
            {
                FInput f = _inputs[i];
                f.Hint = hint;
                f.MaxLen = _mode == 0 ? 6 : 1;
                f.AllowIme = _mode == 2;
                f.Filter = _mode == 0 ? (Func<char, bool>)PinyinFilter
                         : (_mode == 1 ? (Func<char, bool>)ToneFilter : (Func<char, bool>)CharFilter);
                f.Invalid = false;
                if (f.Text != saved[i]) f.Text = saved[i];
            }
            Dbg.Log("切换模式 -> " + hint);
        }

        string[] CurrentCells()
        {
            string[] a = new string[4];
            for (int i = 0; i < 4; i++) a[i] = (_inputs[i].Text ?? "").Trim();
            return a;
        }

        // ------------------------------------------------------------ 检索

        void DoSearch() { RunSearch(false); }

        /// <summary>
        /// 二次检索：**在上一次的检索结果里**按当前条件再检索一遍。
        /// 它和「检索」是一对动作按钮，区别只在"在哪个范围里找"：
        ///   检索     → 全部 319 条成语
        ///   二次检索 → 上一次的结果（也就是右栏现在显示的这批）
        /// </summary>
        void OnSecondSearch() { RunSearch(true); }

        void RunSearch(bool narrow)
        {
            string[] cells = CurrentCells();

            // 非法字符检查
            for (int i = 0; i < 4; i++)
            {
                if (cells[i].Length == 0) continue;
                bool bad = false;
                foreach (char c in cells[i])
                {
                    if (_mode == 0) { if (!PinyinFilter(c)) bad = true; }
                    else if (_mode == 1) { if (!ToneFilter(c)) bad = true; }
                    else { if (!CharFilter(c)) bad = true; }
                }
                if (bad)
                {
                    _inputs[i].Invalid = true;
                    _inputs[i].Invalidate();
                    Dbg.Log("非法字符: 第" + (i + 1) + "格 " + cells[i]);
                    return;
                }
            }

            // 单字模式：多输的只留第一个字
            if (_mode == 2)
            {
                for (int i = 0; i < 4; i++)
                    if (cells[i].Length > 1) { cells[i] = cells[i].Substring(0, 1); _inputs[i].Text = cells[i]; }
            }

            bool any = false;
            for (int i = 0; i < 4; i++) if (cells[i].Length > 0) any = true;
            if (!any) { Flash("请至少填写一个条件"); return; }

            if (narrow && _rows.Count == 0)
            {
                Flash("先点「检索」出结果，再用「二次检索」在上次结果里筛");
                return;
            }

            // 二次检索的范围 = 右栏现在显示的这批结果；检索 = 全库
            List<Idiom> pool = narrow ? _rows : null;
            int poolCount = narrow ? _rows.Count : Bank.Idioms.Count;

            bool[] hits = new bool[4];
            List<Idiom> res = new List<Idiom>();

            foreach (Idiom it in Bank.Idioms)
            {
                if (pool != null && !pool.Contains(it)) continue;
                bool ok = true;
                for (int i = 0; i < 4; i++)
                {
                    if (!Bank.IdiomHit(it, _mode, i, cells[i])) { ok = false; break; }
                }
                if (ok) res.Add(it);
            }

            for (int i = 0; i < 4; i++) hits[i] = cells[i].Length > 0;

            _searchCount++;
            _narrowed = narrow;
            _poolCount = poolCount;
            // 结果和范围都没变时不要再压一层，免得"清空当前"要点好几次
            if (!SameAs(pool, res)) { _levels.Add(res); _levelCells.Add(cells); }
            _modeInputs[_mode] = cells;

            _hit = hits;

            Dbg.Log(string.Format("{0} [{1}] {2}|{3}|{4}|{5} -> 在 {6} 条里筛出 {7} 条",
                narrow ? "二次检索" : "检索",
                _mode == 0 ? "拼音" : (_mode == 1 ? "声调" : "单字"),
                cells[0], cells[1], cells[2], cells[3], poolCount, res.Count));

            Render(res);
        }

        static bool SameAs(List<Idiom> a, List<Idiom> b)
        {
            if (ReferenceEquals(a, b)) return true;
            if (a == null || b == null || a.Count != b.Count) return false;
            for (int i = 0; i < a.Count; i++) if (!ReferenceEquals(a[i], b[i])) return false;
            return true;
        }

        bool[] _hit = new bool[4];
        string _flash = "";
        int _flashUntil;

        void Flash(string msg)
        {
            _flash = msg;
            _flashUntil = Environment.TickCount + 2600;
            Timer t = new Timer();
            t.Interval = 2600;
            t.Tick += delegate { t.Stop(); t.Dispose(); _flash = ""; Invalidate(); };
            t.Start();
            Invalidate();
        }

        void Render(List<Idiom> items)
        {
            _header.RightText = "检索 " + _searchCount + " 次";
            _rows = items;
            _list.Count = items.Count;

            if (items.Count == 0)
            {
                _emptyText = "未检索到对应结果";
                _tabs.Visible = true;
            }
            _list.SelectedIndex = -1;
            UpdateButtons(items.Count);
            Layout2();
            Invalidate();
        }

        List<Idiom> _rows = new List<Idiom>();

        void ShowInitial(string hint)
        {
            _emptyText = hint;
            _rows = new List<Idiom>();
            _list.Count = 0;
            UpdateButtons(-1);
            Layout2();
            Invalidate();
        }

        void UpdateButtons(int n)
        {
            bool show = n >= 0;        // 已经检索过，右栏进入"结果"状态
            bool hasPrev = n >= 1;     // 手上有一批结果可以拿来"二次检索"
            _btnClearAll.Visible = show;
            _btnClearCur.Visible = show;
            _btnSecond.Visible = hasPrev;
            // 「检索」和「二次检索」是一对：还没有上一批结果时可检索全库，
            // 有了上一批结果就让位给「二次检索」；清空回初始状态自动还回来。
            _btnSearch.Visible = !hasPrev;
        }

        void OnClearAll()
        {
            _searchCount = 0;
            _levels.Clear();
            _levelCells.Clear();
            _narrowed = false;
            _poolCount = 0;

            for (int i = 0; i < 4; i++) { _inputs[i].Text = ""; _inputs[i].Invalid = false; }
            _modeInputs.Clear();
            _tabs.Selected = 0;
            _mode = 0;
            ApplyMode();
            _hit = new bool[4];
            _header.RightText = "检索 0 次";
            ShowInitial("填写检索条件后点「检索」");
            Dbg.Log("清空所有检索");
        }

        void OnClearCurrent()
        {
            if (_levels.Count > 0) _levels.RemoveAt(_levels.Count - 1);
            if (_levelCells.Count > 0) _levelCells.RemoveAt(_levelCells.Count - 1);
            _narrowed = false;
            _poolCount = 0;

            if (_levels.Count == 0)
            {
                for (int i = 0; i < 4; i++) { _inputs[i].Text = ""; _inputs[i].Invalid = false; }
                _modeInputs[_mode] = new string[] { "", "", "", "" };
                _hit = new bool[4];
                ShowInitial("填写检索条件后点「检索」");
                return;
            }

            // 退回上一级：把"上一级当时用的条件"填回输入框，而不是一擦了之
            string[] cells = _levelCells[_levelCells.Count - 1];
            for (int i = 0; i < 4; i++) { _inputs[i].Text = cells[i]; _inputs[i].Invalid = false; }
            _modeInputs[_mode] = cells;
            for (int i = 0; i < 4; i++) _hit[i] = cells[i].Length > 0;

            List<Idiom> prev = _levels[_levels.Count - 1];
            _rows = prev;
            _list.Count = prev.Count;
            UpdateButtons(prev.Count);
            Layout2();
            Invalidate();
            Dbg.Log("清空当前 -> " + prev.Count + " 条，条件回到 " + string.Join("|", cells));
        }

        /// <summary>把焦点放到第一个空格子上，方便直接接着填</summary>
        void FocusFirstEmpty()
        {
            for (int i = 0; i < 4; i++)
                if ((_inputs[i].Text ?? "").Length == 0) { _inputs[i].FocusBox(); return; }
            if (_inputs[0] != null) _inputs[0].FocusBox();
        }

        public override void ResetAll() { OnClearAll(); }

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
            int W = Width, H = Height;
            Rectangle left, right;
            SplitPanes(W, H, 42, out left, out right);

            int gapM = Ui.Px(Ui.GapM), gapS = Ui.Px(Ui.GapS);

            // ---- 左：条件 ----
            int hy = 0;
            int hh = HeaderView.NeedHeight();
            _header.SetBounds(left.X, hy, left.Width, hh);

            int tabsH = Ui.Px(48);
            int inputH = Ui.Px(Ui.InputH);
            int cardY = hh;
            int cardH = gapM + tabsH + gapM + inputH + gapM;
            _card.SetBounds(left.X, cardY, left.Width, cardH);

            _tabs.SetBounds(gapM, gapM, left.Width - gapM * 2, tabsH);

            int inner = left.Width - gapM * 2;
            int ig = left.Width < Ui.Px(340) ? Ui.Px(6) : Ui.Px(10);   // 窄的时候把格间距收一收
            int each = (inner - ig * 3) / 4;
            if (each < Ui.Px(30)) each = Ui.Px(30);
            for (int i = 0; i < 4; i++)
                _inputs[i].SetBounds(gapM + i * (each + ig), gapM + tabsH + gapM, each, inputH);

            _btnSearch.SetBounds(left.X, cardY + cardH + gapM, left.Width, Ui.Px(Ui.BtnHLarge));

            // ---- 右：结果 ----
            // 二次检索藏起来时，剩下的两个清空键把整行铺满（否则右边空出一截）
            int nbtn = _btnSecond.Visible ? 3 : 2;
            int bw = (right.Width - gapS * (nbtn - 1)) / nbtn;
            int bh = Ui.Px(Ui.BtnHSmall);
            _btnClearAll.SetBounds(right.X, 0, bw, bh);
            _btnClearCur.SetBounds(_btnClearAll.Right + gapS, 0, bw, bh);
            _btnSecond.SetBounds(_btnClearCur.Right + gapS, 0, Math.Max(Ui.Px(20), right.Right - (_btnClearCur.Right + gapS)), bh);

            int titleH = TitleBarHeight();
            int listY = _btnClearAll.Visible ? bh + gapS + titleH + gapS : 0;
            _list.SetBounds(right.X, listY, right.Width, Math.Max(Ui.Px(40), right.Height - listY));
        }

        int TitleBarHeight()
        {
            using (Graphics g = Graphics.FromHwnd(IntPtr.Zero))
                return Draw.Measure(g, "匹配结果", Fonts.BodyF()).Height;
        }

        // ------------------------------------------------------------ 绘制右栏标题

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;

            Rectangle left, right;
            SplitPanes(Width, Height, 42, out left, out right);

            // 中间 1px 分隔线
            int gap = Ui.Px(Ui.PaneGap);
            Draw.VLine(g, left.Right + gap, 0, Height, Pal.Line);

            if (_btnClearAll.Visible)
            {
                int gapS = Ui.Px(Ui.GapS);
                int y = Ui.Px(Ui.BtnHSmall) + gapS;
                Font f = Fonts.BodyF();
                Font fb = Fonts.Of(Fonts.Body, true);
                string pre = "匹配结果";
                string cnt = "(" + _rows.Count + ")";
                Size ps = Draw.Measure(g, pre, f);
                Draw.Str(g, pre, f, Pal.Ink, right.X, y);
                Draw.Str(g, cnt, fb, Pal.Ink, right.X + ps.Width + Ui.Px(Ui.GapXs), y);

                if (_narrowed && _poolCount > 0)
                {
                    string bar = "在上一批 " + _poolCount + " 条中筛出 " + _rows.Count + " 条";
                    Font bf = Fonts.SubtitleF();
                    Size bs = Draw.Measure(g, bar, bf);
                    int padX = Ui.Px(Ui.GapS), padY = Ui.Px(Ui.GapXs);
                    Rectangle bg = new Rectangle(right.Right - bs.Width - padX * 2, y - padY,
                                                 bs.Width + padX * 2, bs.Height + padY * 2);
                    Draw.FillRound(g, bg, Ui.Px(Ui.RadiusS), Pal.GreenBg);
                    Draw.Str(g, bar, bf, Pal.GreenText, bg.X + padX, bg.Y + padY);
                }
            }

            if (_flash.Length > 0 && Environment.TickCount < _flashUntil)
            {
                // 轻提示（非法字符 / 请至少填写一个条件）
                Font f = Fonts.BodySF();
                Size s = Draw.Measure(g, _flash, f);
                int padX = Ui.Px(Ui.GapL), padY = Ui.Px(Ui.GapS);
                Rectangle box = new Rectangle(left.X + (left.Width - s.Width - padX * 2) / 2,
                                              Height - Ui.Px(70), s.Width + padX * 2, s.Height + padY * 2);
                Draw.FillRound(g, box, Ui.Pill(box.Height), Pal.Alpha(Pal.Ink, 235));
                Draw.Str(g, _flash, f, Pal.OnDark, box.X + padX, box.Y + padY);
            }
        }

        // ------------------------------------------------------------ 结果行

        void PaintRow(Graphics g, int index, Rectangle r, bool selected)
        {
            if (index < 0 || index >= _rows.Count) return;
            Idiom it = _rows[index];
            g.SmoothingMode = SmoothingMode.AntiAlias;

            // 卡片
            Draw.FillRound(g, r, Ui.Px(Ui.RadiusM), Pal.Card);
            Draw.StrokeRound(g, r, Ui.Px(Ui.RadiusM), selected ? Pal.VermLight : Pal.Line, 1f);
            if (selected)
            {
                // 选中的行左侧出现一条朱砂竖线
                int barW = Ui.Px(4);
                Rectangle bar = new Rectangle(r.X + Ui.Px(2), r.Y + Ui.Px(Ui.GapL), barW, r.Height - Ui.Px(Ui.GapL) * 2);
                Draw.FillRound(g, bar, barW / 2, Pal.Verm);
            }

            int x = r.X + Ui.Px(Ui.GapM);
            int y = r.Y + Ui.Px(Ui.GapM);
            int w = r.Width - Ui.Px(Ui.GapM) * 2;

            // ① 成语（命中位次标绿）
            Font wf = Fonts.Of(Fonts.IdiomWord, true);
            Seg[] chars = new Seg[4];
            for (int i = 0; i < 4; i++) chars[i] = new Seg(it.Zi[i].ToString(), _hit[i]);
            Draw.Segments(g, chars, wf, Pal.Ink, x, y, Ui.Px(2));
            y += Draw.Measure(g, "汉", wf).Height + Ui.Px(Ui.GapXs);

            // ② 带调拼音
            Font pf = Fonts.BodyF();
            Seg[] py = new Seg[4];
            for (int i = 0; i < 4; i++)
                py[i] = new Seg(PinyinTone.Mark(it.Py[i] + it.Tone[i]) + (i < 3 ? " " : ""), _hit[i]);
            Draw.Segments(g, py, pf, Pal.Verm, x, y, Ui.Px(2));
            y += Draw.Measure(g, "an", pf).Height + Ui.Px(2);

            // ③ 声调：数字
            Font tf = Fonts.BodySF();
            Seg[] tones = new Seg[8];
            tones[0] = new Seg("声调：", false);
            for (int i = 0; i < 4; i++)
            {
                tones[1 + i * 2] = new Seg(it.Tone[i].ToString(), _hit[i]);
                if (i < 3) tones[2 + i * 2] = new Seg(" ", false);
            }
            Draw.Segments(g, tones, tf, Pal.InkSub, x, y, Ui.Px(1));

            if (w < 1) return;
        }

        void PaintEmpty(Graphics g, Rectangle r)
        {
            Font f = Fonts.BodySF();
            Size s = Draw.Measure(g, _emptyText, f);
            Draw.Str(g, _emptyText, f, Pal.InkHint, r.X + (r.Width - s.Width) / 2, r.Y + Ui.Px(Ui.GapM));
        }
    }
}
