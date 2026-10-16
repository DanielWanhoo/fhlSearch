using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Text;
using FhlSearch.Data;
using FhlSearch.Theme;

namespace FhlSearch.Modules
{
    /// <summary>
    /// 名士详情的排版与绘制。详情卡片和「复制全部信息」共用这里的顺序，
    /// 保证屏幕上看到的和复制出来的一致。
    /// </summary>
    public static class PersonInfoView
    {
        /// <summary>属性项（有序）：品阶 · 职业 · 生逢 · 出身/身世 · 技能 · 爱好 · 社团</summary>
        public static List<KeyValuePair<string, string>> Fields(Person p)
        {
            List<KeyValuePair<string, string>> list = new List<KeyValuePair<string, string>>();
            if (p == null) return list;
            Add(list, "品阶", p.Rank);
            Add(list, "职业", p.Job);
            Add(list, "生逢", p.Meet);
            Add(list, "出身/身世", p.Origin);
            Add(list, "技能", p.Skill);
            Add(list, "爱好", Join(p.Hobbies));
            Add(list, "社团", Join(p.Clubs));
            return list;
        }

        static void Add(List<KeyValuePair<string, string>> list, string k, string v)
        {
            if (!string.IsNullOrEmpty(v) && v.Trim().Length > 0)
                list.Add(new KeyValuePair<string, string>(k, v.Trim()));
        }

        static string Join(string[] a)
        {
            if (a == null || a.Length == 0) return "";
            return string.Join("、", a);
        }

        // ------------------------------------------------------------ 纯文本

        public static string ToText(Person p)
        {
            if (p == null) return "";
            StringBuilder sb = new StringBuilder();
            sb.AppendLine(p.Display);

            List<KeyValuePair<string, string>> fs = Fields(p);
            if (fs.Count == 0)
            {
                sb.AppendLine("题库中该名士暂无此项");
            }
            else
            {
                foreach (KeyValuePair<string, string> kv in fs)
                    sb.AppendLine(kv.Key + "：" + kv.Value);
            }

            sb.AppendLine();
            sb.AppendLine("相关描述（共 " + (p.Descs == null ? 0 : p.Descs.Length) + " 条）");
            if (p.Descs != null)
                foreach (string d in p.Descs) sb.AppendLine("· " + d);
            return sb.ToString().TrimEnd();
        }

        // ------------------------------------------------------------ 绘制

        const int RowPad = 6;   // 属性行之间的额外间距（dp）

        static int LineH(Graphics g, Font f) { return Draw.Measure(g, "汉", f).Height; }
        static int LineGap { get { return Ui.Px(5); } }

        /// <summary>按给定宽度算出整块内容的高度</summary>
        public static int MeasureHeight(Graphics g, Person p, int width)
        {
            if (width < Ui.Px(60)) width = Ui.Px(60);
            if (p == null) return 0;

            Font nameF = Fonts.Of(20, true);
            Font lf = Fonts.BodySF(), vf = Fonts.BodyF();
            int h = LineH(g, nameF) + Ui.Px(14);

            List<KeyValuePair<string, string>> fs = Fields(p);
            if (fs.Count == 0) h += LineH(g, vf) + Ui.Px(RowPad);
            foreach (KeyValuePair<string, string> kv in fs)
            {
                int lw = Draw.Measure(g, kv.Key, lf).Width + Ui.Px(10);
                h += Wrap(g, kv.Value, vf, Math.Max(Ui.Px(40), width - lw)).Count * (LineH(g, vf) + LineGap)
                   + Ui.Px(RowPad);
            }

            h += Ui.Px(16);
            h += LineH(g, Fonts.Of(16, true)) + Ui.Px(10);
            if (p.Descs != null)
                foreach (string d in p.Descs)
                    h += Wrap(g, "· " + d, vf, width).Count * (LineH(g, vf) + LineGap) + Ui.Px(3);
            return h + Ui.Px(6);
        }

        public static List<string> Wrap(Graphics g, string text, Font f, int width)
        {
            List<string> outp = new List<string>();
            if (string.IsNullOrEmpty(text)) { outp.Add(""); return outp; }
            StringBuilder line = new StringBuilder();
            foreach (char ch in text)
            {
                if (ch == '\n') { outp.Add(line.ToString()); line.Length = 0; continue; }
                if (line.Length > 0 && Draw.Measure(g, line.ToString() + ch, f).Width > width)
                {
                    outp.Add(line.ToString());
                    line.Length = 0;
                }
                line.Append(ch);
            }
            outp.Add(line.ToString());
            return outp;
        }

        /// <summary>从 rect.Top 开始向下画整块详情；rect.Height 只用来判断是否还要继续画</summary>
        public static void Paint(Graphics g, Person p, Rectangle rect)
        {
            if (p == null) return;
            g.SmoothingMode = SmoothingMode.AntiAlias;

            int y = rect.Y, x = rect.X, w = rect.Width;
            int bottom = rect.Y + rect.Height;

            Font nameF = Fonts.Of(20, true);
            Size ns = Draw.Measure(g, p.Name, nameF);
            Draw.Str(g, p.Name, nameF, Pal.Ink, x, y);
            if (!string.IsNullOrEmpty(p.Dynasty))
            {
                Font df = Fonts.BodySF();
                string dt = "（" + p.Dynasty + "）";
                Size ds = Draw.Measure(g, dt, df);
                Draw.Str(g, dt, df, Pal.InkSub, x + ns.Width + Ui.Px(2), y + ns.Height - ds.Height - Ui.Px(2));
            }
            y += LineH(g, nameF) + Ui.Px(14);

            List<KeyValuePair<string, string>> fs = Fields(p);
            Font lf = Fonts.BodySF(), vf = Fonts.BodyF();
            int lh = LineH(g, lf), vh = LineH(g, vf);

            if (fs.Count == 0)
            {
                Draw.Str(g, "题库中该名士暂无此项", vf, Pal.InkHint, x, y);
                y += vh + Ui.Px(RowPad);
            }
            else
            {
                foreach (KeyValuePair<string, string> kv in fs)
                {
                    Draw.Str(g, kv.Key, lf, Pal.InkSub, x, y + (vh - lh) / 2);
                    int lw = Draw.Measure(g, kv.Key, lf).Width + Ui.Px(10);
                    List<string> lines = Wrap(g, kv.Value, vf, Math.Max(Ui.Px(40), w - lw));
                    for (int i = 0; i < lines.Count; i++)
                    {
                        Draw.Str(g, lines[i], vf, Pal.Ink, x + lw, y);
                        y += vh + LineGap;
                    }
                    y += Ui.Px(RowPad) - LineGap;
                }
            }

            y += Ui.Px(16);
            Font hf = Fonts.Of(16, true);
            string head = "相关描述（共 " + (p.Descs == null ? 0 : p.Descs.Length) + " 条）";
            Draw.Str(g, head, hf, Pal.Verm, x, y);
            y += LineH(g, hf) + Ui.Px(10);

            if (p.Descs != null)
            {
                foreach (string d in p.Descs)
                {
                    List<string> lines = Wrap(g, "· " + d, vf, w);
                    for (int i = 0; i < lines.Count; i++)
                    {
                        Draw.Str(g, lines[i], vf, Pal.Ink, x, y);
                        y += vh + LineGap;
                    }
                    y += Ui.Px(3);
                }
            }
        }
    }
}
