using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using System.Text;
using System.Windows.Forms;

namespace FhlSearch.Theme
{
    /// <summary>一段可标绿的文字（成语 / 拼音 / 声调按位次标绿时用）</summary>
    public struct Seg
    {
        public string Text;
        public bool Hit;
        public Seg(string t) { Text = t; Hit = false; }
        public Seg(string t, bool hit) { Text = t; Hit = hit; }
    }

    /// <summary>
    /// 绘制原语。所有控件都只用这里的方法画，保证观感统一。
    /// 文字一律走 TextRenderer（GDI），中文小字比 Graphics.DrawString 清楚得多。
    /// </summary>
    public static class Draw
    {
        // ---------------------------------------------------------- 圆角

        public static GraphicsPath Round(RectangleF r, float radius)
        {
            GraphicsPath p = new GraphicsPath();
            if (r.Width <= 0 || r.Height <= 0) { p.AddRectangle(r); return p; }
            float d = radius * 2f;
            if (d > r.Width) d = r.Width;
            if (d > r.Height) d = r.Height;
            if (d < 1f) { p.AddRectangle(r); return p; }
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }

        public static GraphicsPath Round(Rectangle r, int radius)
        {
            return Round(new RectangleF(r.X, r.Y, r.Width, r.Height), radius);
        }

        // ---------------------------------------------------------- 填充 / 描边

        public static void FillRound(Graphics g, Rectangle r, int radius, Color c)
        {
            if (r.Width <= 0 || r.Height <= 0) return;
            using (SolidBrush b = new SolidBrush(c))
            using (GraphicsPath p = Round(r, radius))
                g.FillPath(b, p);
        }

        public static void FillRound(Graphics g, RectangleF r, float radius, Color c)
        {
            if (r.Width <= 0 || r.Height <= 0) return;
            using (SolidBrush b = new SolidBrush(c))
            using (GraphicsPath p = Round(r, radius))
                g.FillPath(b, p);
        }

        /// <summary>描圆角边。内部已按线宽内缩，1px 线不会糊成 2px 灰边。</summary>
        public static void StrokeRound(Graphics g, Rectangle r, int radius, Color c, float width)
        {
            if (r.Width <= 2 || r.Height <= 2) return;
            float w = width;
            RectangleF rf = new RectangleF(r.X + w / 2f, r.Y + w / 2f, r.Width - w, r.Height - w);
            float rad = radius - w / 2f;
            if (rad < 0) rad = 0;
            using (Pen p = new Pen(c, w))
            using (GraphicsPath path = Round(rf, rad))
                g.DrawPath(p, path);
        }

        /// <summary>卡片：宣纸面 + 1px 描金细边</summary>
        public static void Card(Graphics g, Rectangle r, Color fill, Color line)
        {
            Card(g, r, fill, line, Ui.Px(Ui.RadiusM));
        }

        public static void Card(Graphics g, Rectangle r, Color fill, Color line, int radius)
        {
            FillRound(g, r, radius, fill);
            StrokeRound(g, r, radius, line, 1f);
        }

        // ---------------------------------------------------------- 宣纸底

        /// <summary>宣纸竖向渐变（#F7F1E3 → #EFE4CE）</summary>
        public static void Paper(Graphics g, Rectangle r)
        {
            if (r.Width <= 0 || r.Height <= 0) return;
            if (r.Height < 2) { using (SolidBrush b = new SolidBrush(Pal.PaperTop)) g.FillRectangle(b, r); return; }
            using (LinearGradientBrush b = new LinearGradientBrush(
                new Rectangle(r.X, r.Y, r.Width, r.Height), Pal.PaperTop, Pal.PaperBottom, LinearGradientMode.Vertical))
            {
                b.WrapMode = WrapMode.TileFlipXY;
                g.FillRectangle(b, r);
            }
        }

        public static void HLine(Graphics g, int x, int y, int w, Color c)
        {
            if (w <= 0) return;
            using (SolidBrush b = new SolidBrush(c)) g.FillRectangle(b, x, y, w, 1);
        }

        public static void VLine(Graphics g, int x, int y, int h, Color c)
        {
            if (h <= 0) return;
            using (SolidBrush b = new SolidBrush(c)) g.FillRectangle(b, x, y, 1, h);
        }

        // ---------------------------------------------------------- 文字

        public const TextFormatFlags FL = TextFormatFlags.Left | TextFormatFlags.NoPadding | TextFormatFlags.SingleLine;
        public const TextFormatFlags FLV = FL | TextFormatFlags.VerticalCenter;
        public const TextFormatFlags FCV = TextFormatFlags.HorizontalCenter | TextFormatFlags.NoPadding | TextFormatFlags.SingleLine | TextFormatFlags.VerticalCenter;
        public const TextFormatFlags FRV = TextFormatFlags.Right | TextFormatFlags.NoPadding | TextFormatFlags.SingleLine | TextFormatFlags.VerticalCenter;

        /// <summary>左上角起笔写一行字</summary>
        public static void Str(Graphics g, string s, Font f, Color c, int x, int y)
        {
            if (string.IsNullOrEmpty(s)) return;
            TextRenderer.DrawText(g, s, f, new Point(x, y), c, FL);
        }

        /// <summary>在矩形里写一行字</summary>
        public static void StrIn(Graphics g, string s, Font f, Color c, Rectangle r, TextFormatFlags fl)
        {
            if (string.IsNullOrEmpty(s)) return;
            TextRenderer.DrawText(g, s, f, r, c, fl | TextFormatFlags.SingleLine);
        }

        /// <summary>垂直居中写一行字（按实测高度居中，中文不会偏高偏低）</summary>
        public static void StrVC(Graphics g, string s, Font f, Color c, Rectangle r, TextFormatFlags fl)
        {
            if (string.IsNullOrEmpty(s)) return;
            Size sz = Measure(g, s, f);
            int y = r.Y + (r.Height - sz.Height) / 2;
            TextRenderer.DrawText(g, s, f, new Point(r.X, y), c,
                (fl & ~TextFormatFlags.VerticalCenter) | TextFormatFlags.Top | TextFormatFlags.SingleLine);
        }

        public static Size Measure(Graphics g, string s, Font f)
        {
            if (string.IsNullOrEmpty(s)) return Size.Empty;
            return TextRenderer.MeasureText(g, s, f, new Size(int.MaxValue, int.MaxValue),
                TextFormatFlags.Left | TextFormatFlags.NoPadding | TextFormatFlags.SingleLine);
        }

        /// <summary>把字号压到能放进 width 为止（结果区那排小按钮用）</summary>
        public static Font Fit(Graphics g, string s, double dp, bool bold, int width)
        {
            Font f = Fonts.Of(dp, bold);
            if (width <= 0 || Measure(g, s, f).Width <= width) return f;
            double d = dp;
            while (d > 6)
            {
                d -= 1;
                f = Fonts.Of(d, bold);
                if (Measure(g, s, f).Width <= width) return f;
            }
            return f;
        }

        // ---------------------------------------------------------- 命中标绿

        /// <summary>
        /// 逐段写字：命中的段落先铺一层浅绿底（#D6EBD4）再写绿字（#1F6B2C），其余写正常色。
        /// 返回结束时的 x。
        /// </summary>
        public static int Segments(Graphics g, Seg[] segs, Font f, Color fg, int x, int y, int padY)
        {
            for (int i = 0; i < segs.Length; i++)
            {
                string t = segs[i].Text;
                if (string.IsNullOrEmpty(t)) continue;
                Size sz = Measure(g, t, f);
                if (segs[i].Hit)
                {
                    FillRound(g, new Rectangle(x, y - padY, sz.Width + Ui.Px(2), sz.Height + padY * 2),
                              Ui.Px(3), Pal.GreenBg);
                    TextRenderer.DrawText(g, t, f, new Point(x + Ui.Px(1), y), Pal.GreenText, FL);
                }
                else
                {
                    TextRenderer.DrawText(g, t, f, new Point(x, y), fg, FL);
                }
                x += sz.Width;
            }
            return x;
        }

        public static int SegmentsWidth(Graphics g, Seg[] segs, Font f)
        {
            int w = 0;
            for (int i = 0; i < segs.Length; i++) w += Measure(g, segs[i].Text, f).Width;
            return w;
        }

        // ---------------------------------------------------------- 导航图标

        /// <summary>
        /// 侧栏图标。路径直接取自安卓版的 vector drawable，
        /// 保证两边图形完全一致（书 / 六宫格 / 人物剪影）。
        /// </summary>
        public enum Icon { Book, Grid, Person }

        const string PathBook =
            "M12,6.1c-1.7,-1.2 -3.9,-1.9 -6.2,-1.9C4.6,4.2 3.3,4.4 2,4.8v14.4c1.3,-0.4 2.6,-0.6 3.8,-0.6" +
            "c2.3,0 4.5,0.7 6.2,1.9c1.7,-1.2 3.9,-1.9 6.2,-1.9c1.2,0 2.5,0.2 3.8,0.6V4.8c-1.3,-0.4 -2.6,-0.6 -3.8,-0.6" +
            "C15.9,4.2 13.7,4.9 12,6.1zM12,18.1V8.1c1.4,-0.8 3.1,-1.3 4.9,-1.4v9.9C15.1,16.7 13.4,17.2 12,18.1z";
        const string PathGrid = "M3,3h8v8h-8zM3,13h8v8h-8zM13,3h8v8h-8zM13,13h8v8h-8z";
        const string PathPerson =
            "M12,12c2.21,0 4,-1.79 4,-4s-1.79,-4 -4,-4 -4,1.79 -4,4 1.79,4 4,4z" +
            "M12,14c-2.67,0 -8,1.34 -8,4v2h16v-2c0,-2.66 -5.33,-4 -8,-4z";

        public static void NavIcon(Graphics g, Icon kind, Rectangle box, Color c)
        {
            float s = Math.Min(box.Width, box.Height) / 24f;
            float ox = box.X + (box.Width - Math.Min(box.Width, box.Height)) / 2f;
            float oy = box.Y + (box.Height - Math.Min(box.Width, box.Height)) / 2f;
            string d = kind == Icon.Book ? PathBook : (kind == Icon.Grid ? PathGrid : PathPerson);
            using (GraphicsPath p = Svg.Parse(d, s, ox, oy))
            using (SolidBrush b = new SolidBrush(c))
                g.FillPath(b, p);
        }

        public static void NavIcon(Graphics g, Icon kind, Rectangle box, Color c, float scale)
        {
            int w = (int)Math.Round(24 * scale);
            int h = w;
            Rectangle r = new Rectangle(box.X + (box.Width - w) / 2, box.Y + (box.Height - h) / 2, w, h);
            NavIcon(g, kind, r, c);
        }

        /// <summary>向下的小箭头「⌄」（名士条件行右侧）</summary>
        public static void Chevron(Graphics g, int cx, int cy, int w, Color c)
        {
            using (Pen p = new Pen(c, Math.Max(1.2f, Ui.Pf(1.4))))
            {
                p.StartCap = LineCap.Round; p.EndCap = LineCap.Round;
                g.DrawLines(p, new PointF[]
                {
                    new PointF(cx - w / 2f, cy - w / 4f),
                    new PointF(cx,          cy + w / 4f),
                    new PointF(cx + w / 2f, cy - w / 4f)
                });
            }
        }
    }

    // ============================================================ SVG 路径

    /// <summary>
    /// 极简 SVG path 解析器（只认图标里用得到的那几个命令：M L H V C S Q T Z 及相对形式）。
    /// 用它把安卓 vector drawable 的 pathData 原样搬到 WinForms，省得手画贝塞尔。
    /// </summary>
    public static class Svg
    {
        public static GraphicsPath Parse(string d, float scale, float dx, float dy)
        {
            GraphicsPath path = new GraphicsPath();
            path.FillMode = FillMode.Winding;

            List<object> tk = Tokenize(d);
            int i = 0;
            char cmd = 'M';
            float x = 0, y = 0, sx = 0, sy = 0;
            float px = 0, py = 0;      // 上一个控制点（S/T 的镜像用）
            char prev = ' ';

            while (i < tk.Count)
            {
                if (tk[i] is char) { cmd = (char)tk[i]; i++; }
                else if (cmd == 'M') { cmd = 'L'; }   // 隐式重复

                float X(float v) { return dx + v * scale; }
                float Y(float v) { return dy + v * scale; }

                switch (cmd)
                {
                    case 'M': case 'm':
                        {
                            float a = N(tk, ref i), b = N(tk, ref i);
                            if (cmd == 'm') { a += x; b += y; }
                            x = a; y = b; sx = x; sy = y;
                            path.StartFigure();
                            cmd = cmd == 'm' ? 'l' : 'L';
                            prev = 'M';
                            break;
                        }
                    case 'L': case 'l':
                        {
                            float a = N(tk, ref i), b = N(tk, ref i);
                            if (cmd == 'l') { a += x; b += y; }
                            path.AddLine(X(x), Y(y), X(a), Y(b));
                            x = a; y = b; prev = 'L';
                            break;
                        }
                    case 'H': case 'h':
                        {
                            float a = N(tk, ref i);
                            if (cmd == 'h') a += x;
                            path.AddLine(X(x), Y(y), X(a), Y(y));
                            x = a; prev = 'L';
                            break;
                        }
                    case 'V': case 'v':
                        {
                            float a = N(tk, ref i);
                            if (cmd == 'v') a += y;
                            path.AddLine(X(x), Y(y), X(x), Y(a));
                            y = a; prev = 'L';
                            break;
                        }
                    case 'C': case 'c':
                        {
                            float a1 = N(tk, ref i), b1 = N(tk, ref i);
                            float a2 = N(tk, ref i), b2 = N(tk, ref i);
                            float a3 = N(tk, ref i), b3 = N(tk, ref i);
                            if (cmd == 'c') { a1 += x; b1 += y; a2 += x; b2 += y; a3 += x; b3 += y; }
                            path.AddBezier(X(x), Y(y), X(a1), Y(b1), X(a2), Y(b2), X(a3), Y(b3));
                            px = a2; py = b2; x = a3; y = b3; prev = 'C';
                            break;
                        }
                    case 'S': case 's':
                        {
                            float a2 = N(tk, ref i), b2 = N(tk, ref i);
                            float a3 = N(tk, ref i), b3 = N(tk, ref i);
                            if (cmd == 's') { a2 += x; b2 += y; a3 += x; b3 += y; }
                            float a1 = x, b1 = y;
                            if (prev == 'C' || prev == 'S') { a1 = 2 * x - px; b1 = 2 * y - py; }
                            path.AddBezier(X(x), Y(y), X(a1), Y(b1), X(a2), Y(b2), X(a3), Y(b3));
                            px = a2; py = b2; x = a3; y = b3; prev = 'S';
                            break;
                        }
                    case 'Q': case 'q':
                        {
                            float a1 = N(tk, ref i), b1 = N(tk, ref i);
                            float a2 = N(tk, ref i), b2 = N(tk, ref i);
                            if (cmd == 'q') { a1 += x; b1 += y; a2 += x; b2 += y; }
                            path.AddBezier(X(x), Y(y), X(a1), Y(b1), X(a1), Y(b1), X(a2), Y(b2));
                            px = a1; py = b1; x = a2; y = b2; prev = 'Q';
                            break;
                        }
                    case 'T': case 't':
                        {
                            float a2 = N(tk, ref i), b2 = N(tk, ref i);
                            if (cmd == 't') { a2 += x; b2 += y; }
                            float a1 = x, b1 = y;
                            if (prev == 'Q' || prev == 'T') { a1 = 2 * x - px; b1 = 2 * y - py; }
                            path.AddBezier(X(x), Y(y), X(a1), Y(b1), X(a1), Y(b1), X(a2), Y(b2));
                            px = a1; py = b1; x = a2; y = b2; prev = 'T';
                            break;
                        }
                    case 'Z': case 'z':
                        path.CloseFigure();
                        x = sx; y = sy; prev = 'Z';
                        break;
                    default:
                        i++;   // 不认识的命令直接跳过，别死循环
                        break;
                }
            }
            return path;
        }

        static float N(List<object> tk, ref int i)
        {
            if (i < tk.Count && tk[i] is float) { float v = (float)tk[i]; i++; return v; }
            return 0f;
        }

        static List<object> Tokenize(string d)
        {
            List<object> outp = new List<object>();
            int i = 0;
            while (i < d.Length)
            {
                char c = d[i];
                if (char.IsLetter(c)) { outp.Add(c); i++; continue; }
                if (c == ',' || c == ' ' || c == '\t' || c == '\n' || c == '\r') { i++; continue; }
                int st = i;
                if (c == '-' || c == '+') i++;
                while (i < d.Length && (char.IsDigit(d[i]) || d[i] == '.')) i++;
                if (i == st) { i++; continue; }
                float v;
                if (float.TryParse(d.Substring(st, i - st), NumberStyles.Float, CultureInfo.InvariantCulture, out v))
                    outp.Add(v);
            }
            return outp;
        }
    }
}
