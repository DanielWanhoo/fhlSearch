using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace FhlSearch.Ocr
{
    /// <summary>一次识别的结果</summary>
    public class OcrResult
    {
        public bool Ok;
        public string Error = "";
        /// <summary>30 个格子（行优先），'\0' 表示这格没认出来</summary>
        public char[] Cells = new char[PoemOcr.Count];
        public int Filled;
        /// <summary>调试用的过程信息</summary>
        public string Detail = "";
    }

    /// <summary>
    /// 「导入图片」的识别引擎。
    ///
    /// 做法（参照搜题软件：先把题目区域抠出来，再交给 OCR）：
    ///   1. 找"游戏面板"——亮色大块，自动忽略长截图上下的黑边、手机状态栏；
    ///      **面板和整图各算一遍，谁能切出 5 行 6 列就用谁**（面板切歪时还能靠整图兜住）
    ///   2. 在选区里用暗像素投影切出 6 列 × 5 行的字格
    ///   3. **逐格抠出来，按这格自己的底色判极性、拉对比、放大、锐化**，拼成白底黑字的大图
    ///   4. 整张图丢给 Windows 自带 OCR —— 这样 30 个字一定被切成 30 个独立词
    ///   5. 按包围盒中心把识别结果映射回格子
    ///
    /// 为什么要逐格拼板：整图直接 OCR 会把相邻字连读、把单个字误读成标点。
    ///
    /// 为什么要两种拼板：归一化版和原图版各有各认不出的字，**取并集**比任何一版都稳。
    /// 为了不让每张图都跑两趟 PowerShell，只在第一趟还有空格子时才补第二趟。
    ///
    /// OCR 用的是 Windows.Media.Ocr（WinRT）。.NET Framework 4.0 直接调不了 WinRT，
    /// 所以通过系统自带的 Windows PowerShell 转一手（Win10/11 必定带 PowerShell 5.1），
    /// 主程序得以继续停留在 net40、继续是单文件。
    /// </summary>
    public static class PoemOcr
    {
        public const int Cols = 6, Rows = 5, Count = Cols * Rows;

        // 拼板参数：每格放大到 240px 见方，格间距 80px（实测这组参数 OCR 最稳）
        const int MontageCell = 240;
        const int MontageGap = 80;

        /// <summary>支持 OCR 所需的最低 Windows 版本：Windows 10 1809</summary>
        static readonly Version MinWin = new Version(10, 0, 17763);

        // ================================================================ 系统能力

        static string _verdict;
        static bool _probed;

        /// <summary>
        /// 返回 null 表示这台机器能用 OCR；否则返回不能用的原因（给界面提示用）。
        /// 先用版本号做一次零成本的判断；语言包之类的要真起 PowerShell 才知道，放到点击时再探。
        /// </summary>
        public static string UnsupportedReason
        {
            get
            {
                if (!_probed)
                {
                    _probed = true;
                    _verdict = ProbeVersion();
                }
                return _verdict;
            }
        }

        static string ProbeVersion()
        {
            Version v = RealOsVersion();
            if (v == null) return "拿不到系统版本号，无法判断是否支持 OCR。";
            if (v.Major < 10 || (v.Major == 10 && v.Build < 17763))
            {
                return "系统自带的文字识别需要 Windows 10 (1809) 及以上；\r\n"
                     + "当前系统是 Windows " + v.Major + "." + v.Minor + " (build " + v.Build + ")，这条功能用不了。\r\n"
                     + "其余功能不受影响，汉字仍可手动输入。";
            }
            return null;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct Osvi
        {
            public int dwOSVersionInfoSize;
            public int dwMajorVersion;
            public int dwMinorVersion;
            public int dwBuildNumber;
            public int dwPlatformId;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
            public string szCSDVersion;
        }

        [DllImport("ntdll.dll")]
        static extern int RtlGetVersion(ref Osvi v);

        static Version _osv;

        /// <summary>
        /// 真实的系统版本。Environment.OSVersion 在没有 supportedOS 清单时会谎报成 6.2，
        /// 所以走 RtlGetVersion。
        /// </summary>
        public static Version RealOsVersion()
        {
            if (_osv != null) return _osv;
            try
            {
                Osvi v = new Osvi();
                v.dwOSVersionInfoSize = Marshal.SizeOf(typeof(Osvi));
                if (RtlGetVersion(ref v) == 0)
                {
                    _osv = new Version(v.dwMajorVersion, v.dwMinorVersion, v.dwBuildNumber);
                    return _osv;
                }
            }
            catch { }
            try { _osv = Environment.OSVersion.Version; } catch { _osv = new Version(6, 1); }
            return _osv;
        }

        // ================================================================ 主流程

        public static OcrResult Recognize(string path)
        {
            OcrResult r = new OcrResult();
            StringBuilder log = new StringBuilder();
            try
            {
                string reason = UnsupportedReason;
                if (reason != null) { r.Error = reason; return r; }
                if (string.IsNullOrEmpty(path) || !File.Exists(path)) { r.Error = "找不到图片文件。"; return r; }

                Bitmap src;
                try { src = LoadScaled(path, 2400); }
                catch (Exception ex) { r.Error = "这张图片打不开：" + ex.Message; return r; }

                using (src)
                {
                    int w, h;
                    float[] lum = ToLuma(src, out w, out h);
                    log.AppendLine("图片 " + w + "x" + h);

                    // ---- 候选选区：面板优先，切不出来再用整图 ----
                    List<int[]> rects = new List<int[]>();
                    List<string> names = new List<string>();
                    int px0, py0, px1, py1;
                    if (FindPanel(lum, w, h, out px0, out py0, out px1, out py1)
                        && !(px0 == 0 && py0 == 0 && px1 == w - 1 && py1 == h - 1))
                    {
                        rects.Add(new int[] { px0, py0, px1, py1 });
                        names.Add("面板");
                    }
                    rects.Add(new int[] { 0, 0, w - 1, h - 1 });
                    names.Add("整图");

                    int[] rowb = null, colb = null;
                    bool found = false;
                    for (int i = 0; i < rects.Count && !found; i++)
                    {
                        int[] rect = rects[i];
                        int[] rr, cc;
                        string why;
                        if (FindGrid(lum, w, h, rect[0], rect[1], rect[2], rect[3], out rr, out cc, out why))
                        {
                            log.AppendLine(names[i] + " " + (rect[2] - rect[0] + 1) + "x" + (rect[3] - rect[1] + 1) + " -> 5x6");
                            rowb = rr; colb = cc; found = true;
                        }
                        else
                        {
                            log.AppendLine(names[i] + " " + (rect[2] - rect[0] + 1) + "x" + (rect[3] - rect[1] + 1) + " -> " + why);
                        }
                    }
                    if (!found)
                    {
                        r.Error = "没能在图里找到 6×5 的字格。\r\n\r\n"
                                + "请让截图里包含完整的 6×5 字格（可以连周围界面一起截，程序会自动裁）。";
                        r.Detail = log.ToString();
                        return r;
                    }

                    // ---- 第一趟：归一化拼板 ----
                    List<string> words = new List<string>();
                    List<int> wx = new List<int>(), wy = new List<int>();
                    string err;
                    if (!OcrPass(src, w, h, rowb, colb, true, words, wx, wy, out err, log))
                    {
                        r.Error = err; r.Detail = log.ToString(); return r;
                    }
                    MapToCells(words, wx, wy, r.Cells);
                    int filled = CountFilled(r.Cells);
                    if (words.Count > 0)
                    {
                        StringBuilder dbg = new StringBuilder("  前几个词: ");
                        for (int i = 0; i < Math.Min(4, words.Count); i++)
                            dbg.Append("[" + words[i] + "@" + wx[i] + "," + wy[i] + "] ");
                        log.AppendLine(dbg.ToString());
                    }
                    log.AppendLine("第一趟（归一化）认到 " + filled + " / " + Count);

                    // ---- 第二趟：只有还有空格才补，用原图风格再认一遍 ----
                    if (filled < Count)
                    {
                        List<string> w2 = new List<string>();
                        List<int> x2 = new List<int>(), y2 = new List<int>();
                        if (OcrPass(src, w, h, rowb, colb, false, w2, x2, y2, out err, log))
                        {
                            char[] c2 = new char[Count];
                            MapToCells(w2, x2, y2, c2);
                            for (int i = 0; i < Count; i++)
                                if (r.Cells[i] == '\0' && c2[i] != '\0') r.Cells[i] = c2[i];
                            log.AppendLine("第二趟（原图）补到 " + CountFilled(r.Cells) + " / " + Count);
                        }
                    }

                    r.Filled = CountFilled(r.Cells);
                    log.AppendLine("最终 " + r.Filled + " / " + Count + " 格");
                    r.Detail = log.ToString();
                    if (r.Filled == 0)
                    {
                        r.Error = "图片里的字一个都没认出来。\r\n请确认截图里包含了完整的 6×5 字格。";
                        return r;
                    }
                    r.Ok = true;
                    return r;
                }
            }
            catch (Exception ex)
            {
                r.Error = "识别出错：" + ex.Message;
                r.Detail = log.ToString();
                return r;
            }
        }

        static int CountFilled(char[] cells)
        {
            int n = 0;
            for (int i = 0; i < cells.Length; i++) if (cells[i] != '\0') n++;
            return n;
        }

        static void MapToCells(List<string> words, List<int> xs, List<int> ys, char[] cells)
        {
            for (int i = 0; i < words.Count; i++)
            {
                // 拼板是按 6x5 摆的，第 k 格的中心固定
                int best = -1; long bd = long.MaxValue;
                for (int k = 0; k < Count; k++)
                {
                    int gx = MontageGap + (k % Cols) * (MontageCell + MontageGap) + MontageCell / 2;
                    int gy = MontageGap + (k / Cols) * (MontageCell + MontageGap) + MontageCell / 2;
                    long dx = gx - xs[i], dy = gy - ys[i];
                    long d = dx * dx + dy * dy;
                    if (d < bd) { bd = d; best = k; }
                }
                if (best < 0) continue;
                long lim = (long)(MontageCell * 1.1 / 2) * (long)(MontageCell * 1.1 / 2);
                if (bd > lim) continue;
                char ch = FirstCjk(words[i]);
                if (ch == '\0') continue;
                if (cells[best] == '\0') cells[best] = ch;
            }
        }

        static char FirstCjk(string s)
        {
            if (string.IsNullOrEmpty(s)) return '\0';
            foreach (char c in s)
                if ((c >= 0x4E00 && c <= 0x9FFF) || (c >= 0x3400 && c <= 0x4DBF)) return c;
            return '\0';
        }

        /// <summary>做一趟识别：拼板 -> OCR -> 词表（坐标是拼板里的坐标）</summary>
        static bool OcrPass(Bitmap src, int w, int h, int[] rowb, int[] colb, bool normalized,
                            List<string> words, List<int> xs, List<int> ys, out string error, StringBuilder log)
        {
            error = null;
            string tmpImg = Path.Combine(Path.GetTempPath(), "fhlsearch-ocr-" + Guid.NewGuid().ToString("N") + ".png");
            try
            {
                using (Bitmap montage = BuildMontage(src, w, h, rowb, colb, normalized))
                {
                    montage.Save(tmpImg, ImageFormat.Png);
                }
                return RunOcr(tmpImg, words, xs, ys, out error, log);
            }
            finally
            {
                try { File.Delete(tmpImg); } catch { }
            }
        }

        // ================================================================ 拼板

        static Bitmap BuildMontage(Bitmap src, int w, int h, int[] rowb, int[] colb, bool normalized)
        {
            int mw = Cols * MontageCell + (Cols + 1) * MontageGap;
            int mh = Rows * MontageCell + (Rows + 1) * MontageGap;
            Bitmap sheet = new Bitmap(mw, mh, PixelFormat.Format24bppRgb);
            using (Graphics g = Graphics.FromImage(sheet))
            {
                g.Clear(Color.White);
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                for (int rr = 0; rr < Rows; rr++)
                {
                    for (int cc = 0; cc < Cols; cc++)
                    {
                        int y0 = rowb[rr * 2], y1 = rowb[rr * 2 + 1];
                        int x0 = colb[cc * 2], x1 = colb[cc * 2 + 1];
                        int pad = 4;
                        Rectangle s = Rectangle.FromLTRB(
                            Math.Max(0, x0 - pad), Math.Max(0, y0 - pad),
                            Math.Min(w, x1 + pad + 1), Math.Min(h, y1 + pad + 1));
                        using (Bitmap cell = MakeCellImage(src, s, normalized))
                        {
                            if (cell == null) continue;
                            int dx = MontageGap + cc * (MontageCell + MontageGap) + (MontageCell - cell.Width) / 2;
                            int dy = MontageGap + rr * (MontageCell + MontageGap) + (MontageCell - cell.Height) / 2;
                            g.DrawImage(cell, dx, dy, cell.Width, cell.Height);
                        }
                    }
                }
            }
            return sheet;
        }

        /// <summary>
        /// 一格 -> 白底黑字的标准化图。
        /// 关键：**按这格自己的底色判极性**，深底浅字会自动反相；
        /// 再按 2%/98% 分位拉对比，放大到 MontageCell 见方（归一化版再锐化一道）。
        /// </summary>
        static Bitmap MakeCellImage(Bitmap src, Rectangle rect, bool normalized)
        {
            int cw = rect.Width, ch = rect.Height;
            if (cw < 6 || ch < 6) return null;

            float[] v = new float[cw * ch];
            BitmapData bd = src.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
            try
            {
                int stride = bd.Stride;
                byte[] row = new byte[stride];
                for (int y = 0; y < ch; y++)
                {
                    Marshal.Copy(IntPtr.Add(bd.Scan0, y * stride), row, 0, stride);
                    for (int x = 0; x < cw; x++)
                    {
                        int i = x * 3;
                        v[y * cw + x] = 0.114f * row[i] + 0.587f * row[i + 1] + 0.299f * row[i + 2];
                    }
                }
            }
            finally { src.UnlockBits(bd); }

            // 直方图：求中位数与 2%/98% 分位
            int[] hist = new int[256];
            for (int i = 0; i < v.Length; i++)
            {
                int b = (int)v[i]; if (b < 0) b = 0; else if (b > 255) b = 255;
                hist[b]++;
            }
            int n = v.Length;
            int p2 = Pct(hist, n, 0.02), p50 = Pct(hist, n, 0.50), p98 = Pct(hist, n, 0.98);
            float bg = p50;
            bool darkGlyph = (bg - p2) >= (p98 - bg);

            // 用 2%/98% 分位当"墨的深浅范围"，不要用像素极值 ——
            // JPEG 噪点和抗锯齿会把极值拉偏，字反而被压得没对比
            float inkLo = darkGlyph ? (bg - p98) : (p2 - bg);
            float inkHi = darkGlyph ? (bg - p2) : (p98 - bg);
            if (inkHi - inkLo < 10) return null;          // 基本是纯色，没字
            float span = inkHi - inkLo;

            // 拉对比 + 找墨迹包围盒
            int minX = cw, minY = ch, maxX = -1, maxY = -1;
            byte[] gray = new byte[n];
            for (int y = 0; y < ch; y++)
            {
                for (int x = 0; x < cw; x++)
                {
                    int i = y * cw + x;
                    float raw = darkGlyph ? (bg - v[i]) : (v[i] - bg);
                    float a = (raw - inkLo) / span;
                    if (a < 0) a = 0; else if (a > 1) a = 1;
                    gray[i] = (byte)((1f - a) * 255f);          // 墨 -> 黑，底 -> 白
                    if (a > 0.35f)
                    {
                        if (x < minX) minX = x;
                        if (x > maxX) maxX = x;
                        if (y < minY) minY = y;
                        if (y > maxY) maxY = y;
                    }
                }
            }
            if (maxX < 0) return null;
            int bw = maxX - minX + 1, bh = maxY - minY + 1;
            if (bw < 4 || bh < 4) return null;

            // 裁到墨迹再等比例放大
            Bitmap crop = new Bitmap(bw, bh, PixelFormat.Format24bppRgb);
            BitmapData bdc = crop.LockBits(new Rectangle(0, 0, bw, bh), ImageLockMode.WriteOnly, PixelFormat.Format24bppRgb);
            try
            {
                int stride = bdc.Stride;
                byte[] row = new byte[stride];
                for (int y = 0; y < bh; y++)
                {
                    for (int x = 0; x < bw; x++)
                    {
                        byte gv = gray[(minY + y) * cw + (minX + x)];
                        int i3 = x * 3;
                        row[i3] = gv; row[i3 + 1] = gv; row[i3 + 2] = gv;
                    }
                    Marshal.Copy(row, 0, IntPtr.Add(bdc.Scan0, y * stride), stride);
                }
            }
            finally { crop.UnlockBits(bdc); }

            float k2 = (float)MontageCell / Math.Max(bw, bh);
            int dw = Math.Max(1, (int)Math.Round(bw * k2));
            int dh = Math.Max(1, (int)Math.Round(bh * k2));
            Bitmap scaled = new Bitmap(dw, dh, PixelFormat.Format24bppRgb);
            using (Graphics g = Graphics.FromImage(scaled))
            {
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.DrawImage(crop, new Rectangle(0, 0, dw, dh), new Rectangle(0, 0, bw, bh), GraphicsUnit.Pixel);
            }
            crop.Dispose();

            if (!normalized) return scaled;
            return Unsharp(scaled);
        }

        static int Pct(int[] hist, int n, double p)
        {
            int want = (int)(n * p);
            int acc = 0;
            for (int i = 0; i < 256; i++)
            {
                acc += hist[i];
                if (acc >= want) return i;
            }
            return 255;
        }

        /// <summary>反锐化（把细笔画提出来，OCR 对细字更敏感）</summary>
        static Bitmap Unsharp(Bitmap bmp)
        {
            int w = bmp.Width, h = bmp.Height;
            byte[] buf = new byte[w * h];
            BitmapData bd = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
            try
            {
                int stride = bd.Stride;
                byte[] row = new byte[stride];
                for (int y = 0; y < h; y++)
                {
                    Marshal.Copy(IntPtr.Add(bd.Scan0, y * stride), row, 0, stride);
                    for (int x = 0; x < w; x++) buf[y * w + x] = row[x * 3];
                }
            }
            finally { bmp.UnlockBits(bd); }

            Bitmap outp = new Bitmap(w, h, PixelFormat.Format24bppRgb);
            BitmapData bo = outp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format24bppRgb);
            try
            {
                int stride = bo.Stride;
                byte[] row = new byte[stride];
                for (int y = 0; y < h; y++)
                {
                    for (int x = 0; x < w; x++)
                    {
                        int c = buf[y * w + x];
                        // 3x3 均值当作"模糊版"，再 out = in + 0.6 * (in - blur)
                        int sum = 0, cnt = 0;
                        for (int dy = -1; dy <= 1; dy++)
                        {
                            int yy = y + dy; if (yy < 0 || yy >= h) continue;
                            for (int dx = -1; dx <= 1; dx++)
                            {
                                int xx = x + dx; if (xx < 0 || xx >= w) continue;
                                sum += buf[yy * w + xx]; cnt++;
                            }
                        }
                        int blur = sum / Math.Max(1, cnt);
                        int val = c + (int)(0.6f * (c - blur));
                        if (val < 0) val = 0; else if (val > 255) val = 255;
                        int o = x * 3;
                        row[o] = (byte)val; row[o + 1] = (byte)val; row[o + 2] = (byte)val;
                    }
                    Marshal.Copy(row, 0, IntPtr.Add(bo.Scan0, y * stride), stride);
                }
            }
            finally { outp.UnlockBits(bo); }

            bmp.Dispose();
            return outp;
        }

        // ================================================================ 图像

        static Bitmap LoadScaled(string path, int maxSide)
        {
            // 先读进内存流再解码，避免 Image.FromFile 占着文件句柄
            using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
            {
                byte[] buf = new byte[fs.Length];
                int read = 0;
                while (read < buf.Length)
                {
                    int n = fs.Read(buf, read, buf.Length - read);
                    if (n <= 0) break;
                    read += n;
                }
                using (MemoryStream ms = new MemoryStream(buf, 0, read))
                {
                    using (Image img = Image.FromStream(ms))
                    {
                        int w = img.Width, h = img.Height;
                        int side = Math.Max(w, h);
                        if (side <= maxSide)
                        {
                            Bitmap bmp = new Bitmap(w, h, PixelFormat.Format24bppRgb);
                            using (Graphics g = Graphics.FromImage(bmp))
                            {
                                g.DrawImage(img, new Rectangle(0, 0, w, h));
                            }
                            return bmp;
                        }
                        float k = (float)maxSide / side;
                        int nw = Math.Max(1, (int)Math.Round(w * k));
                        int nh = Math.Max(1, (int)Math.Round(h * k));
                        Bitmap b2 = new Bitmap(nw, nh, PixelFormat.Format24bppRgb);
                        using (Graphics g = Graphics.FromImage(b2))
                        {
                            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                            g.DrawImage(img, new Rectangle(0, 0, nw, nh));
                        }
                        return b2;
                    }
                }
            }
        }

        /// <summary>取亮度数组（0..255）</summary>
        static float[] ToLuma(Bitmap bmp, out int w, out int h)
        {
            w = bmp.Width; h = bmp.Height;
            float[] lum = new float[w * h];
            BitmapData bd = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
            try
            {
                int stride = bd.Stride;
                byte[] row = new byte[stride];
                for (int y = 0; y < h; y++)
                {
                    Marshal.Copy(IntPtr.Add(bd.Scan0, y * stride), row, 0, stride);
                    int o = y * w;
                    for (int x = 0; x < w; x++)
                    {
                        int i = x * 3;
                        lum[o + x] = 0.114f * row[i] + 0.587f * row[i + 1] + 0.299f * row[i + 2];
                    }
                }
            }
            finally { bmp.UnlockBits(bd); }
            return lum;
        }

        /// <summary>Otsu 阈值</summary>
        static int Otsu(float[] lum, int w, int h, int x0, int y0, int x1, int y1)
        {
            int[] hist = new int[256];
            int n = 0;
            for (int y = y0; y <= y1; y++)
            {
                int o = y * w;
                for (int x = x0; x <= x1; x++)
                {
                    int v = (int)lum[o + x];
                    if (v < 0) v = 0; else if (v > 255) v = 255;
                    hist[v]++; n++;
                }
            }
            if (n == 0) return 120;
            double sum = 0;
            for (int i = 0; i < 256; i++) sum += (double)i * hist[i];
            double sumB = 0, best = -1;
            int wB = 0, thr = 120;
            for (int t = 0; t < 256; t++)
            {
                wB += hist[t];
                if (wB == 0) continue;
                int wF = n - wB;
                if (wF == 0) break;
                sumB += (double)t * hist[t];
                double mB = sumB / wB;
                double mF = (sum - sumB) / wF;
                double between = (double)wB * wF * (mB - mF) * (mB - mF);
                if (between > best) { best = between; thr = t; }
            }
            return thr;
        }

        /// <summary>找亮底大面板（两趟：先按整幅找行段，再在行段里找列段）</summary>
        static bool FindPanel(float[] lum, int w, int h,
                              out int x0, out int y0, out int x1, out int y1)
        {
            x0 = 0; y0 = 0; x1 = w - 1; y1 = h - 1;
            try
            {
                double[] rl = new double[h];
                for (int y = 0; y < h; y++)
                {
                    int o = y * w, c = 0;
                    for (int x = 0; x < w; x++) if (lum[o + x] > 195) c++;
                    rl[y] = (double)c / w;
                }
                int a, b;
                int minRows = Math.Max(50, h / 12);
                if (!LongestBand(rl, 0.45, minRows, out a, out b)) return false;
                int py0 = a, py1 = b;

                double[] cl = new double[w];
                for (int x = 0; x < w; x++)
                {
                    int c = 0;
                    for (int y = py0; y <= py1; y++) if (lum[y * w + x] > 195) c++;
                    cl[x] = (double)c / (py1 - py0 + 1);
                }
                int minCols = Math.Max(50, w / 12);
                int c0, c1;
                if (!LongestBand(cl, 0.45, minCols, out c0, out c1)) return false;

                y0 = py0; y1 = py1; x0 = c0; x1 = c1;
                return true;
            }
            catch { return false; }
        }

        static bool LongestBand(double[] frac, double thresh, int minLen, out int a, out int b)
        {
            a = -1; b = -1;
            int bestLen = 0, st = -1;
            for (int i = 0; i < frac.Length; i++)
            {
                if (frac[i] > thresh)
                {
                    if (st < 0) st = i;
                }
                else if (st >= 0)
                {
                    int len = i - st;
                    if (len >= minLen && len > bestLen) { bestLen = len; a = st; b = i - 1; }
                    st = -1;
                }
            }
            if (st >= 0)
            {
                int len = frac.Length - st;
                if (len >= minLen && len > bestLen) { bestLen = len; a = st; b = frac.Length - 1; }
            }
            return a >= 0;
        }

        /// <summary>用暗像素投影找 5 行 6 列</summary>
        static bool FindGrid(float[] lum, int w, int h,
                             int px0, int py0, int px1, int py1,
                             out int[] rows, out int[] cols, out string why)
        {
            rows = null; cols = null; why = null;
            int thr = Otsu(lum, w, h, px0, py0, px1, py1);
            if (thr < 60) thr = 60;
            if (thr > 180) thr = 180;

            int pw = px1 - px0 + 1, ph = py1 - py0 + 1;
            int[] rowProj = new int[ph];
            int[] colProj = new int[pw];
            for (int y = 0; y < ph; y++)
            {
                int o = (py0 + y) * w + px0, c = 0;
                for (int x = 0; x < pw; x++) if (lum[o + x] < thr) { c++; colProj[x]++; }
                rowProj[y] = c;
            }

            int rowThr = Math.Max(2, pw / 400);
            int colThr = Math.Max(2, ph / 400);
            int minRow = Math.Max(8, ph / 40);
            int minCol = Math.Max(8, pw / 40);

            List<int[]> rb = PickBest(Bands(rowProj, rowThr, minRow), Rows);
            List<int[]> cb = PickBest(Bands(colProj, colThr, minCol), Cols);

            if (rb.Count != Rows || cb.Count != Cols)
            {
                why = "不是 5x6（" + cb.Count + " 列 × " + rb.Count + " 行）";
                return false;
            }

            rows = new int[Rows * 2];
            cols = new int[Cols * 2];
            for (int i = 0; i < Rows; i++) { rows[i * 2] = rb[i][0] + py0; rows[i * 2 + 1] = rb[i][1] + py0; }
            for (int i = 0; i < Cols; i++) { cols[i * 2] = cb[i][0] + px0; cols[i * 2 + 1] = cb[i][1] + px0; }
            return true;
        }

        static List<int[]> Bands(int[] proj, int thresh, int minLen)
        {
            List<int[]> outp = new List<int[]>();
            int st = -1;
            for (int i = 0; i < proj.Length; i++)
            {
                if (proj[i] > thresh) { if (st < 0) st = i; }
                else if (st >= 0)
                {
                    if (i - st >= minLen) outp.Add(new int[] { st, i - 1 });
                    st = -1;
                }
            }
            if (st >= 0 && proj.Length - st >= minLen) outp.Add(new int[] { st, proj.Length - 1 });
            return outp;
        }

        /// <summary>带宽多于需要的条数时，保留最"粗"的那几条，再按位置排好</summary>
        static List<int[]> PickBest(List<int[]> bands, int need)
        {
            List<int[]> list = new List<int[]>(bands);
            if (list.Count > need)
            {
                list.Sort(delegate (int[] a, int[] b)
                {
                    int la = a[1] - a[0], lb = b[1] - b[0];
                    return lb.CompareTo(la);
                });
                list = list.GetRange(0, need);
            }
            list.Sort(delegate (int[] a, int[] b) { return a[0].CompareTo(b[0]); });
            return list;
        }

        // ================================================================ OCR

        /// <summary>通过 Windows PowerShell 调 Windows.Media.Ocr</summary>
        static bool RunOcr(string imagePath, List<string> words, List<int> xs, List<int> ys,
                           out string error, StringBuilder log)
        {
            error = null;
            string outFile = Path.Combine(Path.GetTempPath(), "fhlsearch-ocr-" + Guid.NewGuid().ToString("N") + ".txt");
            try
            {
                string script = BuildScript(imagePath, outFile);
                string b64 = Convert.ToBase64String(Encoding.Unicode.GetBytes(script));

                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "powershell.exe";
                psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand " + b64;
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
                psi.StandardOutputEncoding = Encoding.UTF8;

                string stdErr = "";
                using (Process p = Process.Start(psi))
                {
                    if (p == null) { error = "启动系统 OCR 失败。"; return false; }
                    // 先读 stdout 再读 stderr，避免两边都塞满缓冲区互相等
                    p.StandardOutput.ReadToEnd();
                    stdErr = p.StandardError.ReadToEnd();
                    if (!p.WaitForExit(60000))
                    {
                        try { p.Kill(); } catch { }
                        error = "识别超时（60 秒）。这张图可能太大了。";
                        return false;
                    }
                    if (p.ExitCode != 0 && !File.Exists(outFile))
                    {
                        error = "系统 OCR 调用失败。\r\n" + Trim(stdErr, 400);
                        return false;
                    }
                }

                if (!File.Exists(outFile))
                {
                    error = "系统 OCR 没有返回结果。\r\n" + Trim(stdErr, 400);
                    return false;
                }

                string[] lines = File.ReadAllLines(outFile, Encoding.UTF8);
                foreach (string raw in lines)
                {
                    string line = raw; if (line.Length == 0) continue;
                    string[] f = line.Split('\t');
                    // 先看是不是脚本自己报的错，它只有两段，不能跟着下面的字段检查走
                    if (f.Length > 0 && f[0] == "ERR")
                    {
                        error = f.Length > 1 ? f[1] : "系统 OCR 报错。";
                        return false;
                    }
                    if (f.Length < 5) continue;
                    int x, y, ww, hh;
                    if (!int.TryParse(f[1], out x) || !int.TryParse(f[2], out y)) continue;
                    if (!int.TryParse(f[3], out ww) || !int.TryParse(f[4], out hh)) continue;
                    words.Add(f[0]);
                    // 存词的中心，和格子中心比距离；直接用左上角会在"格子大、留白多"时判飞
                    xs.Add(x + ww / 2);
                    ys.Add(y + hh / 2);
                }
                log.AppendLine("  OCR 词数 " + words.Count);
                return true;
            }
            finally
            {
                try { if (File.Exists(outFile)) File.Delete(outFile); } catch { }
            }
        }

        static string Trim(string s, int n)
        {
            if (string.IsNullOrEmpty(s)) return "";
            s = s.Trim();
            return s.Length <= n ? s : s.Substring(0, n) + "…";
        }

        static string Q(string s)
        {
            return "'" + (s ?? "").Replace("'", "''") + "'";
        }

        static string BuildScript(string imagePath, string outFile)
        {
            StringBuilder sb = new StringBuilder();
            sb.AppendLine("$ErrorActionPreference = 'Stop'");
            sb.AppendLine("$img = " + Q(imagePath));
            sb.AppendLine("$out = " + Q(outFile));
            sb.AppendLine("$lines = New-Object System.Collections.ArrayList");
            sb.AppendLine("try {");
            sb.AppendLine("  Add-Type -AssemblyName System.Runtime.WindowsRuntime | Out-Null");
            sb.AppendLine("  $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {");
            sb.AppendLine("      $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and");
            sb.AppendLine("      $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]");
            sb.AppendLine("  function Await($op, $t) {");
            sb.AppendLine("    $m = $asTask.MakeGenericMethod($t); $task = $m.Invoke($null, @($op));");
            sb.AppendLine("    $task.Wait(-1) | Out-Null; $task.Result }");
            sb.AppendLine("  [Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime] | Out-Null");
            sb.AppendLine("  [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType=WindowsRuntime] | Out-Null");
            sb.AppendLine("  [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType=WindowsRuntime] | Out-Null");
            sb.AppendLine("  [Windows.Globalization.Language, Windows.Globalization, ContentType=WindowsRuntime] | Out-Null");
            sb.AppendLine("  $engine = $null");
            sb.AppendLine("  foreach ($tag in @('zh-Hans-CN','zh-Hans')) {");
            sb.AppendLine("    try { $l = New-Object Windows.Globalization.Language $tag;");
            sb.AppendLine("          $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($l);");
            sb.AppendLine("          if ($engine -ne $null) { break } } catch { }");
            sb.AppendLine("  }");
            sb.AppendLine("  if ($engine -eq $null) {");
            sb.AppendLine("    $avail = ([Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages | ForEach-Object { $_.LanguageTag }) -join ','");
            sb.AppendLine("    [void]$lines.Add(\"ERR\t没有可用的简体中文 OCR 语言包。系统当前可用的识别语言：$avail\")");
            sb.AppendLine("  } else {");
            sb.AppendLine("    $file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($img)) ([Windows.Storage.StorageFile])");
            sb.AppendLine("    $stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])");
            sb.AppendLine("    $dec = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])");
            sb.AppendLine("    $bmp = Await ($dec.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])");
            sb.AppendLine("    $res = Await ($engine.RecognizeAsync($bmp)) ([Windows.Media.Ocr.OcrResult])");
            sb.AppendLine("    foreach ($ln in $res.Lines) { foreach ($wd in $ln.Words) {");
            sb.AppendLine("      $r = $wd.BoundingRect");
            sb.AppendLine("      [void]$lines.Add((\"{0}`t{1}`t{2}`t{3}`t{4}\" -f $wd.Text, [int]$r.X, [int]$r.Y, [int]$r.Width, [int]$r.Height))");
            sb.AppendLine("    } }");
            sb.AppendLine("  }");
            sb.AppendLine("} catch {");
            sb.AppendLine("  [void]$lines.Add(('ERR\t' + $_.Exception.Message))");
            sb.AppendLine("}");
            sb.AppendLine("[IO.File]::WriteAllLines($out, $lines, (New-Object System.Text.UTF8Encoding($false)))");
            return sb.ToString();
        }
    }
}
