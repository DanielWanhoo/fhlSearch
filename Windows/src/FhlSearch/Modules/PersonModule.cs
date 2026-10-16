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
    /// 模块三：名士检索（众里寻他）
    ///
    ///  - 九种检索模式；朝代 / 爱好 / 社团 / 品阶 用滚轮选择，其余 5 种用输入框模糊检索；
    ///  - 条件行显示已选值（朱砂），没选时显示"选择"/"输入"；
    ///  - 结果里显示名士名与摘要，标绿命中的条件；
    ///  - 还没有上一批结果时给"检索"，有了上一批结果就给
    ///    "清空所有 / 清空当前 / 二次检索"（"检索"自动收起，清空回初始状态再恢复）；
    ///  - 点结果里的任意一行 → 弹出该名士的详情；
    ///  - 检索次数计数，只有"清空所有"归零。
    /// </summary>
    public class PersonModule : ModuleBase
    {
        public override string ModuleName { get { return "名士检索"; } }
        public override string BigTitle { get { return "众里寻他"; } }

        /// <summary>一个检索条件</summary>
        class Cond
        {
            public PersonMode Mode;
            public string Name;
            public string Value = "";       // 空 = 未设置
            public bool IsOption;
        }

        static readonly PersonMode[] Modes = {
            PersonMode.Dynasty, PersonMode.Hobby, PersonMode.Club, PersonMode.Rank,
            PersonMode.Job, PersonMode.Meet, PersonMode.Origin, PersonMode.Skill, PersonMode.Desc
        };

        HeaderView _header;
        ResultList _modes;
        ResultList _list;
        FButton _btnSearch;
        FButton _btnClearAll, _btnClearCur, _btnSecond;

        readonly List<Cond> _conds = new List<Cond>();
        readonly List<List<Person>> _levels = new List<List<Person>>();
        /// <summary>与 _levels 一一对应：每一层当时的 9 个条件值</summary>
        readonly List<string[]> _levelConds = new List<string[]>();
        bool _narrowed;      // 右栏这批结果是不是「二次检索」筛出来的
        int _poolCount;      // 这次检索用到的范围条数（全库 or 上一批）
        int _searchCount;
        List<Person> _rows = new List<Person>();
        string _emptyText = "选择或输入检索条件后，结果将显示在这里；\r\n点结果中的任意一行，可查看该名士的全部描述";
        int _rowH;

        public PersonModule()
        {
            _header = new HeaderView();
            _header.Title = BigTitle;
            _header.Subtitle = "选择或输入条件检索名士，可多次叠加";
            Controls.Add(_header);

            BuildConds();

            _modes = new ResultList();
            _modes.GapAfterRow = Ui.GapS;
            _modes.Count = _conds.Count;
            _modes.RowHeight = delegate(int i, int w) { return Ui.Px(Ui.RowH); };
            _modes.RowPaint = PaintModeRow;
            _modes.RowClicked += delegate(int i) { OpenCond(i); };
            Controls.Add(_modes);

            _btnSearch = new FButton();
            _btnSearch.Style = FButton.Kind.Primary;
            _btnSearch.Text = "检索";
            _btnSearch.Click += delegate { DoSearch(); };
            Controls.Add(_btnSearch);

            _btnClearAll = MakeAction("清空所有", FButton.Kind.Light, delegate { OnClearAll(); });
            _btnClearCur = MakeAction("清空当前", FButton.Kind.Light, delegate { OnClearCurrent(); });
            _btnSecond = MakeAction("二次检索", FButton.Kind.Primary, delegate { OnSecondSearch(); });

            _list = new ResultList();
            _list.GapAfterRow = Ui.GapS;
            _rowH = CalcRowHeight();
            _list.RowHeight = delegate(int i, int w) { return _rowH; };
            _list.RowPaint = PaintPersonRow;
            _list.EmptyPaint = PaintEmpty;
            _list.RowClicked += delegate(int i) { OpenDetail(i); };
            _list.RowActivated += delegate(int i) { OpenDetail(i); };
            Controls.Add(_list);

            _header.RightText = "检索 0 次";
            ShowInitial();
        }

        FButton MakeAction(string t, FButton.Kind k, EventHandler h)
        {
            FButton b = new FButton();
            b.Style = k;
            b.Text = t;
            b.AutoFit = true;
            b.Click += h;
            Controls.Add(b);
            return b;
        }

        void BuildConds()
        {
            _conds.Clear();
            foreach (PersonMode m in Modes)
            {
                Cond c = new Cond();
                c.Mode = m;
                c.Name = Bank.ModeName(m);
                c.IsOption = Bank.IsMenuMode(m);
                _conds.Add(c);
            }
        }

        static int CalcRowHeight()
        {
            using (Graphics g = Graphics.FromHwnd(IntPtr.Zero))
                return Draw.Measure(g, "汉", Fonts.Of(Fonts.MsName, true)).Height + Ui.Px(Ui.GapS) * 2;
        }

        public override void OnActivated()
        {
            Layout2();
            Dbg.LogBounds("名士.条件列表", _modes);
            Dbg.LogBounds("名士.结果列表", _list);
        }

        public override void ResetAll() { OnClearAll(); }

        // ------------------------------------------------------------ 条件

        void OpenCond(int i)
        {
            if (i < 0 || i >= _conds.Count) return;
            Cond c = _conds[i];
            Form owner = FindForm();
            if (owner == null) return;

            bool cleared;
            if (c.IsOption)
            {
                string v = Dialogs.PickOption(owner, c.Name, OptionsOf(c.Mode), c.Value, out cleared);
                if (cleared) c.Value = "";
                else if (v != null) c.Value = v;
            }
            else
            {
                string v = Dialogs.AskText(owner, c.Name, HintOf(c.Mode), c.Value, out cleared);
                if (cleared) c.Value = "";
                else if (v != null) c.Value = v;
            }

            Dbg.Log("条件 " + c.Name + " = [" + c.Value + "]");
            _modes.Invalidate();
            Layout2();
            Invalidate();
        }

        static string[] OptionsOf(PersonMode m)
        {
            string[] a = Bank.OptionsOf(m);
            if (a != null && a.Length > 0) return a;
            switch (m)
            {
                case PersonMode.Dynasty: return new string[] { "汉", "明", "秦", "三国", "宋", "唐", "五代十国", "西楚", "晋", "先秦", "梦", "南北朝", "清", "元", "辽" };
                case PersonMode.Hobby: return new string[] { "博文", "乐舞", "品茗", "赏玩", "食珍", "书画", "雅宴", "演武", "弈棋", "妆饰" };
                case PersonMode.Club: return new string[] { "百家书院", "千工苑", "金戈馆", "容华社", "棠梨坊", "饕餮居", "五湖商社", "逸趣社", "无" };
                case PersonMode.Rank: return new string[] { "天", "地", "玄" };
            }
            return new string[0];
        }

        static string HintOf(PersonMode m)
        {
            string h = Bank.ModeHint(m);
            return string.IsNullOrEmpty(h) ? "在此输入检索内容" : h;
        }

        // ------------------------------------------------------------ 检索

        void DoSearch() { RunSearch(false); }

        /// <summary>
        /// 二次检索：**在上一次的检索结果里**按当前条件再筛一遍。
        /// 和「检索」是一对动作按钮，区别只在"在哪个范围里找"：
        ///   检索     → 全部 115 位名士
        ///   二次检索 → 上一次的结果（也就是右栏现在显示的这批）
        /// </summary>
        void OnSecondSearch() { RunSearch(true); }

        void RunSearch(bool narrow)
        {
            // 每次都是"按当前所有条件筛"，不做"哪些条件已经用过了"的记账 ——
            // 那样用户改一个旧条件重搜时会得到莫名其妙的结果（条件还留着，范围却已经缩过了）。
            List<Cond> use = new List<Cond>();
            foreach (Cond c in _conds) if (c.Value.Length > 0) use.Add(c);
            if (use.Count == 0) { _modes.Invalidate(); Flash("请至少选择一个条件"); return; }

            if (narrow && _rows.Count == 0)
            {
                Flash("先点「检索」出结果，再用「二次检索」在上次结果里筛");
                return;
            }

            List<Person> basePool = narrow ? _rows : Bank.People;
            List<Person> pool = basePool;
            foreach (Cond c in use)
            {
                List<Person> next = new List<Person>();
                foreach (Person p in pool) if (Bank.PersonHit(p, c.Mode, c.Value)) next.Add(p);
                pool = next;
            }

            _searchCount++;
            _narrowed = narrow;
            _poolCount = basePool.Count;
            // 结果和范围都没变时不要再压一层，免得"清空当前"要点好几次
            if (!SameAs(basePool, pool))
            {
                _levels.Add(pool);
                _levelConds.Add(Snapshot());
            }
            _header.RightText = "检索 " + _searchCount + " 次";

            Dbg.Log(string.Format("{0} {1} 个条件 -> 在 {2} 位里筛出 {3} 位",
                narrow ? "二次检索" : "名士检索", use.Count, basePool.Count, pool.Count));
            Render(pool);
        }

        /// <summary>把当前 9 个条件的值拍个快照（每一层存一份，退回上一级时还原）</summary>
        string[] Snapshot()
        {
            string[] a = new string[_conds.Count];
            for (int i = 0; i < _conds.Count; i++) a[i] = _conds[i].Value;
            return a;
        }

        void Restore(string[] snap)
        {
            if (snap == null) return;
            for (int i = 0; i < _conds.Count && i < snap.Length; i++) _conds[i].Value = snap[i];
        }

        static bool SameAs(List<Person> a, List<Person> b)
        {
            if (ReferenceEquals(a, b)) return true;
            if (a == null || b == null || a.Count != b.Count) return false;
            for (int i = 0; i < a.Count; i++) if (!ReferenceEquals(a[i], b[i])) return false;
            return true;
        }

        void Render(List<Person> pool)
        {
            _rows = pool;
            _list.Count = pool.Count;
            _list.SelectedIndex = -1;
            UpdateButtons(pool.Count);
            Layout2();
            Invalidate();
        }

        void ShowInitial()
        {
            _rows = new List<Person>();
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
            // 「检索」和「二次检索」是一对：还没有上一批结果时可检索全部名士，
            // 有了上一批结果就让位给「二次检索」；清空回初始状态自动还回来。
            _btnSearch.Visible = !hasPrev;
        }

        void OnClearAll()
        {
            _searchCount = 0;
            _levels.Clear();
            _levelConds.Clear();
            _narrowed = false;
            foreach (Cond c in _conds) c.Value = "";
            _header.RightText = "检索 0 次";
            ShowInitial();
            _modes.Invalidate();
            Dbg.Log("名士：清空所有");
        }

        void OnClearCurrent()
        {
            if (_levels.Count == 0) return;
            _levels.RemoveAt(_levels.Count - 1);
            if (_levelConds.Count > 0) _levelConds.RemoveAt(_levelConds.Count - 1);
            _narrowed = false;
            // 退回上一级：条件也跟着回到上一级的样子，界面和结果才对得上
            if (_levels.Count == 0)
            {
                foreach (Cond c in _conds) c.Value = "";
                ShowInitial();
            }
            else
            {
                Restore(_levelConds[_levelConds.Count - 1]);
                Render(_levels[_levels.Count - 1]);
            }
            _modes.Invalidate();
            Dbg.Log("名士：清空当前 -> " + _rows.Count + " 位");
        }

        string _flashText = "";
        int _flashUntil;

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

        void OpenDetail(int i)
        {
            if (i < 0 || i >= _rows.Count) return;
            Form owner = FindForm();
            if (owner == null) return;
            Dbg.Log("点击 名士检索 结果：" + _rows[i].Name);
            Dialogs.ShowPerson(owner, _rows, i);
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

            int hh = HeaderView.NeedHeight();
            _header.SetBounds(left.X, 0, left.Width, hh);

            int appliedH = AppliedHeight();
            int y = hh + appliedH;
            if (appliedH > 0) y += Ui.Px(Ui.GapXs);

            // 「检索」收起后会把这段高度还给条件列表，9 个条件少滚一点
            int searchH = _btnSearch.Visible ? Ui.Px(Ui.BtnHLarge) + Ui.Px(Ui.GapS) : 0;
            int modesH = Math.Max(Ui.Px(60), left.Bottom - y - searchH);
            _modes.SetBounds(left.X, y, left.Width, modesH);
            _modes.Visible = modesH > Ui.Px(20);

            _btnSearch.SetBounds(left.X, left.Bottom - Ui.Px(Ui.BtnHLarge), left.Width, Ui.Px(Ui.BtnHLarge));

            int g = Ui.Px(Ui.GapS);
            // 二次检索藏起来时，剩下的两个清空键把整行铺满（否则右边空出一截）
            int nbtn = _btnSecond.Visible ? 3 : 2;
            int bw = (right.Width - g * (nbtn - 1)) / nbtn;
            int bh = Ui.Px(Ui.BtnHSmall);
            _btnClearAll.SetBounds(right.X, 0, bw, bh);
            _btnClearCur.SetBounds(_btnClearAll.Right + g, 0, bw, bh);
            _btnSecond.SetBounds(_btnClearCur.Right + g, 0, Math.Max(Ui.Px(20), right.Right - (_btnClearCur.Right + g)), bh);

            int listY = _btnClearAll.Visible ? bh + g + TitleBarHeight() + g : 0;
            _list.SetBounds(right.X, listY, right.Width, Math.Max(Ui.Px(40), right.Height - listY));
        }

        int AppliedHeight()
        {
            bool any = false;
            foreach (Cond c in _conds) if (c.Value.Length > 0) any = true;
            if (!any) return 0;
            using (Graphics g = Graphics.FromHwnd(IntPtr.Zero))
                return Draw.Measure(g, "汉", Fonts.BodySF()).Height;
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

            // 已检索：条件名：值（值用朱砂）
            int hh = HeaderView.NeedHeight();
            int ah = AppliedHeight();
            if (ah > 0)
            {
                Font f = Fonts.BodySF();
                int x = left.X;
                int y = hh + Ui.Px(Ui.GapXs);
                Draw.Str(g, "已检索：", f, Pal.InkSub, x, y);
                x += Draw.Measure(g, "已检索：", f).Width;
                bool first = true;
                foreach (Cond c in _conds)
                {
                    if (c.Value.Length == 0) continue;
                    if (!first) { Draw.Str(g, "、", f, Pal.InkSub, x, y); x += Draw.Measure(g, "、", f).Width; }
                    first = false;
                    string lbl = c.Name + "：";
                    Draw.Str(g, lbl, f, Pal.InkSub, x, y);
                    x += Draw.Measure(g, lbl, f).Width;
                    Draw.Str(g, c.Value, f, Pal.Verm, x, y);
                    x += Draw.Measure(g, c.Value, f).Width;
                }
            }

            if (_btnClearAll.Visible)
            {
                int gg = Ui.Px(Ui.GapS);
                int y = Ui.Px(Ui.BtnHSmall) + gg;
                Font f = Fonts.BodyF();
                string pre = "匹配结果";
                Size ps = Draw.Measure(g, pre, f);
                Draw.Str(g, pre, f, Pal.Ink, right.X, y);
                Draw.Str(g, "(" + _rows.Count + ")", Fonts.Of(Fonts.Body, true), Pal.Ink, right.X + ps.Width + Ui.Px(Ui.GapXs), y);

                if (_narrowed && _poolCount > 0)
                {
                    string bar = "在上一批 " + _poolCount + " 位中筛出 " + _rows.Count + " 位";
                    Font bf = Fonts.SubtitleF();
                    Size bs = Draw.Measure(g, bar, bf);
                    int padX = Ui.Px(Ui.GapS), padY = Ui.Px(Ui.GapXs);
                    Rectangle bg = new Rectangle(right.Right - bs.Width - padX * 2, y - padY,
                                                 bs.Width + padX * 2, bs.Height + padY * 2);
                    Draw.FillRound(g, bg, Ui.Px(Ui.RadiusS), Pal.GreenBg);
                    Draw.Str(g, bar, bf, Pal.GreenText, bg.X + padX, bg.Y + padY);
                }
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

        void PaintModeRow(Graphics g, int index, Rectangle r, bool selected)
        {
            if (index < 0 || index >= _conds.Count) return;
            Cond c = _conds[index];
            bool hover = _modes.HoverIndex == index;
            FModeRow.PaintRow(g, r, c.Name, c.Value, c.IsOption ? "选择" : "输入", hover);
        }

        void PaintPersonRow(Graphics g, int index, Rectangle r, bool selected)
        {
            if (index < 0 || index >= _rows.Count) return;
            Person p = _rows[index];
            g.SmoothingMode = SmoothingMode.AntiAlias;

            Draw.FillRound(g, r, Ui.Px(Ui.RadiusS), selected ? Pal.VermTint : Pal.CardSoft);
            Draw.StrokeRound(g, r, Ui.Px(Ui.RadiusS), selected ? Pal.VermLight : Pal.Line, 1f);

            Font nf = Fonts.Of(Fonts.MsName, true);
            Size ns = Draw.Measure(g, p.Name, nf);
            Draw.Str(g, p.Name, nf, Pal.Ink, r.X + Ui.Px(Ui.GapM), r.Y + (r.Height - ns.Height) / 2);

            if (!string.IsNullOrEmpty(p.Dynasty))
            {
                Font df = Fonts.BodySF();
                string dt = "（" + p.Dynasty + "）";
                Size ds = Draw.Measure(g, dt, df);
                Draw.Str(g, dt, df, Pal.InkSub, r.Right - Ui.Px(Ui.GapM) - ds.Width, r.Y + (r.Height - ds.Height) / 2);
            }
        }

        void PaintEmpty(Graphics g, Rectangle r)
        {
            Font f = Fonts.BodySF();
            string[] lines = _emptyText.Replace("\r\n", "\n").Split('\n');
            int lh = Draw.Measure(g, "汉", f).Height + Ui.Px(4);
            int y = r.Y + Ui.Px(Ui.GapM);
            foreach (string s in lines)
            {
                Size sz = Draw.Measure(g, s, f);
                Draw.Str(g, s, f, Pal.InkHint, r.X + (r.Width - sz.Width) / 2, y);
                y += lh;
            }
        }
    }
}
