using System;
using System.Collections.Generic;
using System.Drawing;
using System.Text;
using System.Windows.Forms;
using FhlSearch.Data;
using FhlSearch.Theme;

namespace FhlSearch.Modules
{
    /// <summary>
    /// 程序里的所有弹窗。
    ///
    /// 全部是**标准 Windows 对话框**：固定的窗口边框 + 标题栏 + 关闭按钮，
    /// 用 ShowDialog 做真正的模态，可以用鼠标拖动、Esc / Alt+F4 关闭，
    /// 不会盖住整个主窗口，也没有"点卡片外面关闭"那种移动端做法。
    ///
    /// 里面用的是原生 WinForms 控件（ListBox / TextBox / Button），
    /// 只把底色换成程序自己的配色，所以既像 Windows 对话框，又和主界面同源。
    /// </summary>
    public static class Dialogs
    {
        /// <summary>
        /// 对话框统一用的字体。**必须走 Fonts.Of（dp 单位、随 DPI 缩放）**：
        /// SystemFonts.MessageBoxFont 是像素单位的字体，在 200% 缩放下不会跟着放大，
        /// 字会小得看不清。14dp 约等于 Windows 对话框的 10.5pt，略大一点更好认。
        /// </summary>
        public static Font UiFont { get { return Fonts.Of(14, false); } }

        // ======================================================== 入口

        /// <summary>
        /// 列表选择。返回选中的值；cleared = 用户点了"清除该条件"；
        /// 两者都不成立（点了取消或直接关窗）时返回 null。
        /// </summary>
        public static string PickOption(Form owner, string caption, string[] options, string current, out bool cleared)
        {
            cleared = false;
            using (OptionDialog dlg = new OptionDialog(caption, options, current))
            {
                if (owner != null) dlg.ShowDialog(owner); else dlg.ShowDialog();
                cleared = dlg.Cleared;
                return dlg.Result;
            }
        }

        public static string AskText(Form owner, string caption, string hint, string current, out bool cleared)
        {
            cleared = false;
            using (InputDialog dlg = new InputDialog(caption, hint, current))
            {
                if (owner != null) dlg.ShowDialog(owner); else dlg.ShowDialog();
                cleared = dlg.Cleared;
                return dlg.Result;
            }
        }

        public static void ShowPerson(Form owner, List<Person> list, int index)
        {
            using (PersonDialog dlg = new PersonDialog(list, index))
            {
                if (owner != null) dlg.ShowDialog(owner); else dlg.ShowDialog();
            }
        }

        public static void Help(Form owner)
        {
            string s =
                "【三大模块】\r\n" +
                "左侧栏切换：成语检索 / 诗词检索 / 名士检索\r\n\r\n" +
                "【成语检索 · 山石雅集第 14 题】\r\n" +
                "拼音：填英文字母，支持完整拼音或声母、韵母（模糊匹配）\r\n" +
                "声调：填 1 / 2 / 3 / 4\r\n" +
                "单字：填一个汉字\r\n" +
                "留空的格子表示该位置不限\r\n" +
                "结果里标绿的，就是你填了条件的那几位\r\n\r\n" +
                "【诗词检索 · 山石雅集第 15 题】\r\n" +
                "在 6×5 的字格里每格填一个汉字\r\n" +
                "方向键移动格子，朱砂方框是当前格\r\n" +
                "点「开始检索」后，程序找出能由格中字拼出的诗句\r\n" +
                "点结果里的某一条，字格上会绿框标出用的是哪几格\r\n\r\n" +
                "【诗词检索 · 从图片识别】\r\n" +
                "点「从图片识别」，选一张题目截图，程序会自动找出 6×5 字格、\r\n" +
                "认出 30 个汉字填进去，并直接开始检索 —— 不用一个个敲字。\r\n" +
                "用的是 Windows 自带的文字识别，需要 Windows 10 (1809) 及以上，\r\n" +
                "且系统装了简体中文 OCR 组件（中文版 Win10/11 一般自带）。\r\n" +
                "Win7 / 8.1 上用不了这条功能，其余功能不受影响，汉字仍可手动输入。\r\n" +
                "\r\n" +
                "截图建议（照做识别率最高，点下方「查看截图样例」可看一张理想输入）：\r\n" +
                "· 6×5 字格要完整，连边框一起截；周围多截点界面没关系，会自动裁\r\n" +
                "· 上下有黑边、带手机状态栏都没影响，会自动裁掉\r\n" +
                "· 别用缩略图：图片长边建议 800 像素以上，单字实际低于 40 像素会明显变差\r\n" +
                "· 微信 / QQ 转发过的图会被压糊，尽量用原图\r\n" +
                "· 深色格子配浅色字也能认（会按每格自己的底色判深浅）\r\n" +
                "· 能截图就别拍屏：反光、角度太斜都会掉识别率\r\n" +
                "\r\n" +
                "认错了怎么办：格子里的字本来就是可以改的 ——\r\n" +
                "直接改掉认错的那个字，再点「开始检索」即可。\r\n" +
                "若提示「拼不出题库里的诗句」，多半也是个别字认错，对着截图改一下就行。\r\n\r\n" +
                "【名士检索 · 众里寻他】\r\n" +
                "点条件行选值：朝代 / 爱好 / 社团 / 品阶 弹出列表选择，其余是输入\r\n" +
                "选好的条件显示在标题下方「已检索：」那一行，可以叠加\r\n" +
                "结果多于一条时可以做二次检索，逐层缩小范围\r\n" +
                "点结果里的任意一行，弹出该名士的全部信息\r\n" +
                "「检索 N 次」只在点「清空所有」时归零\r\n\r\n" +
                "【快捷键】\r\n" +
                "Enter   执行检索 / 确认对话框\r\n" +
                "Esc     关闭对话框\r\n" +
                "方向键  移动选择（诗词字格、结果列表、列表选项）\r\n" +
                "滚轮    光标停在哪个可滚动区域上就滚哪个\r\n\r\n" +
                "【运行环境】\r\n" +
                "本程序为绿色免安装单文件，不写注册表。\r\n" +
                "支持 Windows 7 SP1 及以上；Win7 需已安装 .NET Framework 4.0 或更高。\r\n" +
                "Windows on Arm（骁龙本 / Arm 平板）：Windows 11 Arm 版可以直接运行\r\n" +
                "（原生 Arm64 或系统自动仿真）；Windows 10 Arm 版不保证。\r\n" +
                "程序是纯 .NET 程序，exe 里不含任何 x86 / x64 机器码，与 CPU 架构无关。";
            using (TextDialog dlg = new TextDialog("使用说明", s, 720, 620, "查看截图样例",
                       delegate { Sample(owner); }))
            {
                if (owner != null) dlg.ShowDialog(owner); else dlg.ShowDialog();
            }
        }

        /// <summary>把打包进程序里的那张"理想输入截图"显示出来</summary>
        public static void Sample(Form owner)
        {
            using (SampleDialog dlg = new SampleDialog())
            {
                if (owner != null) dlg.ShowDialog(owner); else dlg.ShowDialog();
            }
        }

        public static void About(Form owner)
        {
            StringBuilder sb = new StringBuilder();
            sb.AppendLine("题库统计");
            sb.AppendLine("──────────────────────────────");
            sb.AppendLine("  成语检索     " + Bank.Idioms.Count + " 条");
            sb.AppendLine("  诗词检索     " + Bank.Poems.Count + " 条");
            sb.AppendLine("  名士检索     " + Bank.People.Count + " 位");
            sb.AppendLine();
            sb.AppendLine("题库来源");
            sb.AppendLine("──────────────────────────────");
            sb.AppendLine("  题库来源于微博蓝在寻（原整理者）");
            foreach (string s in Bank.SourceInfo)
            {
                // 分隔符说明、文件生成提示这类是给开发者看的，不往用户面前摆
                if (s.IndexOf("分隔符") >= 0) continue;
                if (s.IndexOf("请勿手改") >= 0) continue;
                // 来源行形如「成语题库: 成语检索.xlsx  (39351 bytes, 修改于 …)」，
                // 只留文件名那一段，不然弹窗里换行换得乱七八糟
                string line = s;
                int k = line.IndexOf("  (");
                if (k > 0) line = line.Substring(0, k);
                sb.AppendLine("  " + line);
            }
            sb.AppendLine("  内嵌生成于 " + Bank.GenTime);
            sb.AppendLine();
            sb.AppendLine("版权说明");
            sb.AppendLine("──────────────────────────────");
            sb.AppendLine("  《忘川风华录》相关知识内容版权归网易所有。");
            sb.AppendLine("  本程序为非商业同人工具，仅供个人学习交流，");
            sb.AppendLine("  不含任何游戏美术、音频、立绘等资源。");
            sb.AppendLine("  如权利人认为有不妥，请联系作者删除。");
            sb.AppendLine();
            sb.AppendLine("忘川检索 · fhlSearch  v" + Versions());
            sb.AppendLine("程序与题库全部离线运行，不联网、不写注册表。");
            Text(owner, "关于题库", sb.ToString(), 580, 520);
        }

        /// <summary>程序版本号，直接从程序集读，省得改了 csproj 忘了改这里</summary>
        static string Versions()
        {
            try
            {
                Version v = System.Reflection.Assembly.GetExecutingAssembly().GetName().Version;
                return v.Major + "." + v.Minor + "." + v.Build;
            }
            catch { return "1.1.0"; }
        }

        /// <summary>
        /// 统一换行：StringBuilder.AppendLine() 出来的是 \r\n，
        /// 若直接 .Replace("\n", "\r\n") 会变成 \r\r\n —— 多行 TextBox 会把 \r 也当换行，
        /// 于是每行之间都空出一行。这里先把 \r\n、\r 都归一成 \n，再统一成 \r\n。
        /// </summary>
        internal static string CrLf(string s)
        {
            if (string.IsNullOrEmpty(s)) return "";
            return s.Replace("\r\n", "\n").Replace('\r', '\n').Replace("\n", "\r\n");
        }

        public static void Text(Form owner, string title, string body, int w, int h)
        {
            h = FitHeight(owner, body, w, h);
            using (TextDialog dlg = new TextDialog(title, body, w, h))
            {
                if (owner != null) dlg.ShowDialog(owner); else dlg.ShowDialog();
            }
        }

        /// <summary>
        /// 按正文实际需要的高度把对话框撑够，省得"关于题库"多写两行就冒滚动条。
        /// 只在不够时加高，且不超父窗口的 85%（再高就还是让它滚）。
        /// 注意单位：MeasureText 量出来的是物理像素，h 是逻辑像素，比较前要换算。
        /// </summary>
        static int FitHeight(Form owner, string body, int w, int h)
        {
            try
            {
                int innerW = Ui.Px(w - 28) - SystemInformation.VerticalScrollBarWidth - Ui.Px(6);
                if (innerW < Ui.Px(80)) return h;
                Size sz = TextRenderer.MeasureText(
                    CrLf(body), UiFont,
                    new Size(innerW, int.MaxValue),
                    TextFormatFlags.WordBreak | TextFormatFlags.NoPadding);
                int needPx = sz.Height + Ui.Px(14 + 30 + 14 + 8);
                if (needPx <= Ui.Px(h)) return h;
                int capPx = owner != null && owner.ClientSize.Height > 0
                    ? owner.ClientSize.Height * 85 / 100
                    : needPx;
                int outH = Math.Max(h, (int)Math.Ceiling(Math.Min(needPx, capPx) / (double)Ui.Scale));
                Dbg.Log(string.Format("弹窗高度 {0}: 文本{1}px 需要{2}px 上限{3}px -> {4}dp (原 {5}dp)",
                    w, sz.Height, needPx, capPx, outH, h));
                return outH;
            }
            catch { return h; }
        }
    }

    // ============================================================ 对话框基类

    /// <summary>
    /// 标准 Windows 对话框的公共部分：固定边框 + 标题栏 + 关闭按钮，
    /// 居中于父窗口，不进任务栏，Esc 关闭。
    /// </summary>
    public class FhlDialog : Form
    {
        public FhlDialog(string title, int w, int h)
        {
            Text = title;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            StartPosition = FormStartPosition.CenterParent;
            MinimizeBox = false;
            MaximizeBox = false;
            ShowInTaskbar = false;
            ShowIcon = false;
            AutoScaleMode = AutoScaleMode.None;
            Font = Dialogs.UiFont;
            ForeColor = Pal.Ink;
            BackColor = Pal.Card;
            ClientSize = Ui.Sz(w, h);
        }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            using (SolidBrush b = new SolidBrush(Pal.Card))
                e.Graphics.FillRectangle(b, ClientRectangle);
        }

        /// <summary>标准尺寸的按钮（位置由 PlaceButtons 统一排）</summary>
        protected Button MakeButton(string text, EventHandler onClick)
        {
            Button b = new Button();
            b.Text = text;
            b.Font = Dialogs.UiFont;
            b.FlatStyle = FlatStyle.System;
            b.SetBounds(0, 0, Ui.Px(80), Ui.Px(30));
            if (onClick != null) b.Click += onClick;
            Controls.Add(b);
            return b;
        }

        /// <summary>
        /// 把一排按钮**从右往左**排好（Windows 对话框的习惯：主要按钮在最右下角），
        /// 宽度按文字实测宽度算，中英文混排也不会被切掉。
        /// </summary>
        protected void PlaceButtons(int dialogW, int y, params Button[] bs)
        {
            int gap = Ui.Px(8);
            int right = Ui.Px(dialogW - 14);
            using (Graphics g = CreateGraphics())
            {
                for (int i = bs.Length - 1; i >= 0; i--)
                {
                    Button b = bs[i];
                    int w = Math.Max(Ui.Px(78), Draw.Measure(g, b.Text, b.Font).Width + Ui.Px(30));
                    b.SetBounds(right - w, Ui.Px(y), w, Ui.Px(30));
                    right -= w + gap;
                }
            }
        }

        /// <summary>说明性小字</summary>
        protected Label MakeLabel(string text, int x, int y, int w, int h)
        {
            Label l = new Label();
            l.Text = text;
            l.Font = Dialogs.UiFont;
            l.ForeColor = Pal.InkSub;
            l.AutoSize = false;
            l.SetBounds(Ui.Px(x), Ui.Px(y), Ui.Px(w), Ui.Px(h));
            Controls.Add(l);
            return l;
        }
    }

    // ============================================================ 选项型条件

    /// <summary>朝代 / 爱好 / 社团 / 品阶：标准列表选择对话框</summary>
    class OptionDialog : FhlDialog
    {
        public string Result = null;
        public bool Cleared = false;

        readonly ListBox _list;

        public OptionDialog(string caption, string[] options, string current)
            : base("选择" + caption, 340, 452)
        {
            MakeLabel("请选择「" + caption + "」（也可以直接双击某一项）：", 14, 12, 312, 20);

            _list = new ListBox();
            _list.DrawMode = DrawMode.OwnerDrawFixed;
            _list.BorderStyle = BorderStyle.FixedSingle;
            _list.BackColor = Pal.CardSoft;
            _list.ForeColor = Pal.Ink;
            _list.Font = Dialogs.UiFont;
            _list.ItemHeight = Ui.Px(26);
            _list.IntegralHeight = false;
            _list.SetBounds(Ui.Px(14), Ui.Px(38), Ui.Px(312), Ui.Px(348));
            _list.DrawItem += OnDrawItem;
            _list.DoubleClick += delegate { Accept(); };
            if (options != null) foreach (string o in options) _list.Items.Add(o);
            Controls.Add(_list);

            Button ok = MakeButton("确定", delegate { Accept(); });
            Button clr = MakeButton("清除该条件", delegate
            {
                Result = null; Cleared = true; DialogResult = DialogResult.OK; Close();
            });
            Button cancel = MakeButton("取消", delegate
            {
                Result = null; Cleared = false; DialogResult = DialogResult.Cancel; Close();
            });
            PlaceButtons(340, 452 - 14 - 30, cancel, clr, ok);

            AcceptButton = ok;
            CancelButton = cancel;

            int idx = 0;
            if (options != null && !string.IsNullOrEmpty(current))
                for (int i = 0; i < options.Length; i++) if (options[i] == current) { idx = i; break; }
            if (_list.Items.Count > 0) _list.SelectedIndex = idx;
        }

        void Accept()
        {
            if (_list.SelectedIndex < 0) return;
            Result = Convert.ToString(_list.SelectedItem);
            Cleared = false;
            DialogResult = DialogResult.OK;
            Close();
        }

        void OnDrawItem(object sender, DrawItemEventArgs e)
        {
            if (e.Index < 0) return;
            bool sel = (e.State & DrawItemState.Selected) != 0;
            Rectangle r = e.Bounds;
            using (SolidBrush b = new SolidBrush(sel ? Pal.VermTint : Pal.CardSoft))
                e.Graphics.FillRectangle(b, r);
            if (sel)
                using (Pen p = new Pen(Pal.Verm))
                    e.Graphics.DrawRectangle(p, r.X, r.Y, r.Width - 1, r.Height - 1);
            TextRenderer.DrawText(e.Graphics, Convert.ToString(_list.Items[e.Index]), _list.Font,
                new Rectangle(r.X + Ui.Px(8), r.Y, r.Width - Ui.Px(12), r.Height),
                sel ? Pal.Verm : Pal.Ink,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
        }
    }

    // ============================================================ 输入型条件

    /// <summary>职业 / 生逢 / 出身 / 技能 / 其他描述：标准输入对话框</summary>
    class InputDialog : FhlDialog
    {
        public string Result = null;
        public bool Cleared = false;

        readonly TextBox _box;

        public InputDialog(string caption, string hint, string current)
            : base(caption, 460, 226)
        {
            MakeLabel(hint, 14, 14, 432, 20);

            _box = new TextBox();
            _box.Font = Dialogs.UiFont;
            _box.BorderStyle = BorderStyle.FixedSingle;
            _box.BackColor = Pal.CardSoft;
            _box.ForeColor = Pal.Ink;
            _box.SetBounds(Ui.Px(14), Ui.Px(40), Ui.Px(432), Ui.Px(28));
            _box.Text = current ?? "";
            Controls.Add(_box);

            MakeLabel("匹配时会忽略标点和空格", 14, 76, 432, 20);

            Button ok = MakeButton("确定", delegate { Accept(); });
            Button clr = MakeButton("清除该条件", delegate
            {
                Result = null; Cleared = true; DialogResult = DialogResult.OK; Close();
            });
            Button cancel = MakeButton("取消", delegate
            {
                Result = null; Cleared = false; DialogResult = DialogResult.Cancel; Close();
            });
            PlaceButtons(460, 226 - 14 - 30, cancel, clr, ok);

            AcceptButton = ok;
            CancelButton = cancel;
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            try { _box.Focus(); _box.SelectAll(); } catch { }
        }

        void Accept()
        {
            Result = (_box.Text ?? "").Trim();
            Cleared = false;
            DialogResult = DialogResult.OK;
            Close();
        }
    }

    // ============================================================ 名士详情

    /// <summary>名士详情：标准只读文本框 + 翻页 / 复制按钮</summary>
    class PersonDialog : FhlDialog
    {
        readonly List<Person> _list;
        int _idx;
        readonly TextBox _body;

        public PersonDialog(List<Person> list, int index)
            : base("名士详情", 580, 540)
        {
            _list = list ?? new List<Person>();
            _idx = index;

            _body = new TextBox();
            _body.Multiline = true;
            _body.ReadOnly = true;
            _body.ScrollBars = ScrollBars.Vertical;
            _body.WordWrap = true;
            _body.BorderStyle = BorderStyle.FixedSingle;
            _body.BackColor = Pal.CardSoft;
            _body.ForeColor = Pal.Ink;
            _body.Font = Dialogs.UiFont;
            _body.SetBounds(Ui.Px(14), Ui.Px(14), Ui.Px(552), Ui.Px(446));
            Controls.Add(_body);

            Button close = MakeButton("关闭", delegate { Close(); });
            Button copyAll = MakeButton("复制信息", delegate { Copy(true); });
            Button copyName = MakeButton("复制名字", delegate { Copy(false); });
            Button next = MakeButton("下一位", delegate { Step(1); });
            Button prev = MakeButton("上一位", delegate { Step(-1); });
            PlaceButtons(580, 540 - 14 - 30, prev, next, copyName, copyAll, close);

            CancelButton = close;
            ShowPerson();
        }

        Person Cur
        {
            get
            {
                if (_list.Count == 0) return null;
                if (_idx < 0) _idx = 0;
                if (_idx >= _list.Count) _idx = _list.Count - 1;
                return _list[_idx];
            }
        }

        void ShowPerson()
        {
            Person p = Cur;
            Text = p == null ? "名士详情" : ("名士详情 — " + p.Display);
            _body.Text = PersonInfoView.ToText(p).Replace("\n", "\r\n");
            _body.SelectionStart = 0;
            _body.SelectionLength = 0;
        }

        void Step(int d)
        {
            if (_list.Count == 0) return;
            _idx += d;
            if (_idx < 0) _idx = _list.Count - 1;
            if (_idx >= _list.Count) _idx = 0;
            ShowPerson();
        }

        void Copy(bool all)
        {
            Person p = Cur;
            if (p == null) return;
            try { Clipboard.SetText(all ? PersonInfoView.ToText(p) : p.Name); }
            catch { }
        }
    }

    // ============================================================ 纯文本

    /// <summary>使用说明 / 关于题库：标准只读文本框；可额外挂一个按钮（如「查看截图样例」）</summary>
    class TextDialog : FhlDialog
    {
        public TextDialog(string title, string body, int w, int h)
            : this(title, body, w, h, null, null)
        {
        }

        public TextDialog(string title, string body, int w, int h, string extraText, EventHandler extraClick)
            : base(title, w, h)
        {
            TextBox tb = new TextBox();
            tb.Multiline = true;
            tb.ReadOnly = true;
            tb.ScrollBars = ScrollBars.Vertical;
            tb.WordWrap = true;
            tb.BorderStyle = BorderStyle.FixedSingle;
            tb.BackColor = Pal.CardSoft;
            tb.ForeColor = Pal.Ink;
            tb.Font = Dialogs.UiFont;
            tb.SetBounds(Ui.Px(14), Ui.Px(14), Ui.Px(w - 28), Ui.Px(h - 14 - 30 - 14 - 8));
            tb.Text = Dialogs.CrLf(body);
            tb.SelectionStart = 0;
            tb.SelectionLength = 0;
            Controls.Add(tb);

            Button close = MakeButton("关闭", delegate { Close(); });
            if (extraText != null && extraClick != null)
            {
                Button extra = MakeButton(extraText, extraClick);
                // PlaceButtons 是"从右往左"排，最后一个参数在最右下角
                PlaceButtons(w, h - 14 - 30, extra, close);
            }
            else
            {
                PlaceButtons(w, h - 14 - 30, close);
            }
            CancelButton = close;
        }
    }

    // ============================================================ 截图样例

    /// <summary>
    /// 「使用说明」里点「查看截图样例」弹出来的图：
    /// 就是一张理想的输入截图 —— 6×5 字格完整、连边框一起截、字够大够清晰。
    /// 图片以资源形式打在 exe 里，仍然是单文件。
    /// </summary>
    class SampleDialog : FhlDialog
    {
        const int W = 680, H = 580;

        public SampleDialog()
            : base("截图样例（理想的输入长这样）", W, H)
        {
            int capH = 24, btnY = H - 14 - 30;
            MakeLabel("整格完整 · 连边框一起截 · 字够大够清晰（可以带黑边和状态栏，程序会自动裁）",
                      14, 10, W - 28, capH);

            PictureBox pb = new PictureBox();
            pb.SizeMode = PictureBoxSizeMode.Zoom;
            pb.BorderStyle = BorderStyle.FixedSingle;
            pb.BackColor = Pal.CardSoft;
            pb.SetBounds(Ui.Px(14), Ui.Px(10 + capH + 6),
                         Ui.Px(W - 28), Ui.Px(btnY - 10 - capH - 6 - 10));
            pb.Image = LoadSample();
            Controls.Add(pb);

            Button close = MakeButton("关闭", delegate { Close(); });
            PlaceButtons(W, btnY, close);
            CancelButton = close;
        }

        /// <summary>取出打包进程序里的样例图（Image 需要流保持打开，所以复制一份出来）</summary>
        static Image LoadSample()
        {
            try
            {
                using (System.IO.Stream st = System.Reflection.Assembly.GetExecutingAssembly()
                           .GetManifestResourceStream("FhlSearch.ocr-sample.jpg"))
                {
                    if (st == null) return null;
                    using (Image tmp = Image.FromStream(st))
                        return new Bitmap(tmp);
                }
            }
            catch { return null; }
        }
    }
}
