using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Text;
using System.Windows.Forms;

namespace FhlSearch.Theme
{
    // ============================================================ 配色

    /// <summary>
    /// 全局配色。取值与《忘川检索》安卓版 res/values/colors.xml 一一对应，
    /// 也就是《界面文案与配色规范.md》里那一套：宣纸 + 墨 + 朱砂 + 描金 + 青竹。
    /// 改色只需要改这里。
    /// </summary>
    public static class Pal
    {
        // 宣纸底（竖向渐变的起止色）
        public static readonly Color PaperTop = Color.FromArgb(0xF7, 0xF1, 0xE3);
        public static readonly Color PaperBottom = Color.FromArgb(0xEF, 0xE4, 0xCE);

        // 卡片 / 输入框 / 按钮填充
        public static readonly Color Card = Color.FromArgb(0xFB, 0xF7, 0xEC);       // 卡片、面板
        public static readonly Color CardSoft = Color.FromArgb(0xFD, 0xFB, 0xF5);   // 更亮的面（字格、选项卡容器）
        public static readonly Color BtnLight = Color.FromArgb(0xFF, 0xFD, 0xF7);   // 浅色按钮
        public static readonly Color InputFill = Color.FromArgb(0xF5, 0xEE, 0xDC);  // 输入框内凹底

        // 朱砂
        public static readonly Color Verm = Color.FromArgb(0x9E, 0x2B, 0x25);        // 主色
        public static readonly Color VermLight = Color.FromArgb(0xC0, 0x39, 0x2B);   // 高亮 / 选中红框
        public static readonly Color VermPressed = Color.FromArgb(0x7E, 0x21, 0x1C);
        public static readonly Color VermTint = Color.FromArgb(0xF3, 0xE3, 0xDF);    // 朱砂淡底（选中块）

        // 描金
        public static readonly Color Gold = Color.FromArgb(0xB0, 0x8A, 0x3E);
        public static readonly Color GoldLight = Color.FromArgb(0xD8, 0xC4, 0x8E);
        public static readonly Color GoldTint = Color.FromArgb(0xF1, 0xE8, 0xD2);

        // 墨色与文字
        public static readonly Color Ink = Color.FromArgb(0x2B, 0x21, 0x18);         // 正文
        public static readonly Color InkSub = Color.FromArgb(0x6B, 0x5B, 0x4B);      // 次级文字
        public static readonly Color InkHint = Color.FromArgb(0x9C, 0x8B, 0x76);     // 占位 / 提示
        public static readonly Color OnDark = Color.FromArgb(0xFB, 0xF3, 0xE4);      // 朱砂底上的文字

        // 青竹
        public static readonly Color Bamboo = Color.FromArgb(0x3F, 0x6B, 0x4A);

        // 命中绿（结果标注）
        public static readonly Color GreenBg = Color.FromArgb(0xD6, 0xEB, 0xD4);
        public static readonly Color GreenText = Color.FromArgb(0x1F, 0x6B, 0x2C);
        public static readonly Color GreenLine = Color.FromArgb(0x4E, 0x9A, 0x5B);

        // 结构线
        public static readonly Color Line = Color.FromArgb(0xE3, 0xD9, 0xC2);
        public static readonly Color LineStrong = Color.FromArgb(0xCD, 0xBE, 0x9F);

        // 状态
        public static readonly Color Error = Color.FromArgb(0xC0, 0x39, 0x2B);
        public static readonly Color Disabled = Color.FromArgb(0xBC, 0xAE, 0x97);

        public static Color Alpha(Color c, int a) { return Color.FromArgb(a, c.R, c.G, c.B); }
    }

    // ============================================================ 尺寸

    /// <summary>
    /// 尺寸与 DPI 缩放。设计稿以 dp 为单位；这里 1dp = 1 逻辑像素，
    /// 再统一乘 DPI 缩放系数，保证 125% / 150% / 200% 下比例不变。
    /// </summary>
    public static class Ui
    {
        public static float Scale = 1f;

        static Ui()
        {
            try
            {
                using (Graphics g = Graphics.FromHwnd(IntPtr.Zero)) Scale = g.DpiX / 96f;
            }
            catch { Scale = 1f; }
            if (Scale < 0.75f) Scale = 0.75f;
            if (Scale > 4f) Scale = 4f;
        }

        /// <summary>dp -> 实际像素</summary>
        public static int Px(double dp) { return (int)Math.Round(dp * Scale); }

        /// <summary>dp -> 实际浮点像素</summary>
        public static float Pf(double dp) { return (float)(dp * Scale); }

        public static Size Sz(double w, double h) { return new Size(Px(w), Px(h)); }

        public static Rectangle Rect(double x, double y, double w, double h)
        {
            return new Rectangle(Px(x), Px(y), Px(w), Px(h));
        }

        // ---- 间距（dimens.xml: fhl_gap_*）----
        public const int GapXs = 4, GapS = 8, GapM = 12, GapL = 16, GapXl = 24;

        // ---- 圆角（fhl_radius_*）----
        public const int RadiusS = 8, RadiusM = 14, RadiusL = 22;

        // ---- 控件高度 ----
        public const int BtnH = 48, BtnHLarge = 52, BtnHSmall = 42, InputH = 48, RowH = 56;

        // ---- 屏幕边距 ----
        public const int ScreenPad = 16, PaneGap = 20;

        // ---- 侧边栏（平板）----
        public const int RailW = 132, TabIcon = 24;

        /// <summary>胶囊圆角（等于高度的一半）</summary>
        public static int Pill(int h) { return h / 2; }
    }

    // ============================================================ 字体

    /// <summary>
    /// 字体仓库。每次取字体都从缓存里拿（绝对不要 using 包住 —— 那会把共享的字体对象
    /// 释放掉，之后再用就抛"参数无效"）。找不到雅黑时逐级回退，英文系统上也不会出方块。
    /// </summary>
    public static class Fonts
    {
        // 设计稿字号（sp），1sp = 1 逻辑像素
        public const double Title = 24;     // 大标题
        public const double Subtitle = 13;  // 副标题
        public const double Body = 16;      // 正文 / 结果
        public const double BodyS = 14;     // 次级正文
        public const double Result = 17;    // 诗词结果行
        public const double Btn = 16;       // 按钮
        public const double RailLabel = 12; // 侧栏文字
        public const double IdiomWord = 22; // 成语名
        public const double MsName = 18;    // 名士名
        public const double CellSize = 24;  // 字格里的字

        static readonly Dictionary<string, Font> _cache = new Dictionary<string, Font>();

        /// <summary>正文/界面字体：安卓是 Noto Sans，桌面用微软雅黑最接近</summary>
        static readonly string[] UiFamilies = { "Microsoft YaHei UI", "Microsoft YaHei", "微软雅黑", "SimHei", "黑体", "SimSun", "宋体", "Arial" };
        /// <summary>等宽（拼音 / 数字）</summary>
        static readonly string[] MonoFamilies = { "Consolas", "Courier New", "Microsoft YaHei", "SimSun", "Arial" };

        static readonly HashSet<string> _installed = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        static string _ui, _mono;
        static bool _ready;

        static void Ensure()
        {
            if (_ready) return;
            _ready = true;
            try
            {
                InstalledFontCollection col = new InstalledFontCollection();
                foreach (FontFamily f in col.Families)
                {
                    try { _installed.Add(f.Name); } catch { }
                }
            }
            catch { }
            _ui = Pick(UiFamilies);
            _mono = Pick(MonoFamilies);
        }

        static string Pick(string[] cand)
        {
            foreach (string c in cand) if (_installed.Contains(c)) return c;
            return cand[cand.Length - 1];
        }

        /// <summary>按 dp 取界面字体（bold = 加粗）</summary>
        public static Font Of(double dp, bool bold)
        {
            return Get(_ui, dp, bold ? FontStyle.Bold : FontStyle.Regular);
        }

        /// <summary>按 dp 取等宽字体</summary>
        public static Font MonoOf(double dp, bool bold)
        {
            return Get(_mono, dp, bold ? FontStyle.Bold : FontStyle.Regular);
        }

        public static Font TitleF() { return Of(Title, true); }
        public static Font SubtitleF() { return Of(Subtitle, false); }
        public static Font BodyF() { return Of(Body, false); }
        public static Font BodySF() { return Of(BodyS, false); }
        public static Font BtnF() { return Of(Btn, true); }

        static Font Get(string family, double dp, FontStyle style)
        {
            Ensure();
            float px = Ui.Pf(dp);
            if (px < 1f) px = 1f;
            string key = family + "|" + px.ToString("0.##") + "|" + (int)style;
            Font f;
            if (_cache.TryGetValue(key, out f)) return f;
            try { f = new Font(family, px, style, GraphicsUnit.Pixel); }
            catch
            {
                try { f = new Font(FontFamily.GenericSansSerif, px, style, GraphicsUnit.Pixel); }
                catch { f = SystemFonts.DefaultFont; }
            }
            _cache[key] = f;
            return f;
        }

        /// <summary>测量一段文字的宽度（像素）</summary>
        public static int Measure(Graphics g, string s, Font f)
        {
            if (string.IsNullOrEmpty(s)) return 0;
            return (int)Math.Ceiling(g.MeasureString(s, f, int.MaxValue, StringFormat.GenericTypographic).Width);
        }
    }
}
