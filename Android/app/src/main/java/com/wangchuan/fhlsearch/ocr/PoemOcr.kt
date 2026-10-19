package com.wangchuan.fhlsearch.ocr

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * 「诗词检索 · 图片识别」的取字引擎。
 *
 * 做法照搬 Windows 版 `src/FhlSearch/Ocr/PoemOcr.cs`（那边已经在同一批样例图上验证过）：
 *   1. 找"游戏面板"——亮色大块，自动忽略长截图上下的黑边、手机状态栏；
 *      **面板和整图各算一遍，谁能切出 5 行 6 列就用谁**（面板切歪时还能靠整图兜住）
 *   2. 在选区里用暗像素投影切出 6 列 × 5 行的字格
 *   3. **逐格抠出来，按这格自己的底色判极性、拉对比、放大、锐化**，拼成白底黑字的大图
 *   4. 整张拼板交给 ML Kit 中文识别 —— 这样 30 个字一定被切成 30 个独立的词
 *   5. 按包围盒中心把识别结果映射回格子
 *
 * 为什么要逐格拼板：整图直接 OCR 会把相邻的字连读、把单个字误读成标点。
 * 为什么要两种拼板：归一化版和原图版各有各认不出的字，**取并集**比任何一版都稳；
 * 为了不让每张图都跑两趟识别，只在第一趟还有空格子时才补第二趟。
 *
 * 本文件**不依赖 Android 的界面代码**，只用到 Bitmap 的像素读写，方便单独调参数。
 */
object PoemOcr {

    const val COLS = 6
    const val ROWS = 5
    const val COUNT = COLS * ROWS

    /** 拼板参数：每格放大到 240px 见方，格间距 80px（与 Windows 版同一组实测参数） */
    private const val MONTAGE_CELL = 240
    private const val MONTAGE_GAP = 80

    /** 送进来之前先把长边缩到这个尺寸（再大对识别没帮助，只是费内存） */
    private const val MAX_SIDE = 2200

    /** 没认出字时格子里的占位符 */
    const val BLANK = '\u0000'

    /**
     * 调试用：设成某个目录后，每趟的拼板都会存成 PNG 到那里。
     * 自动化测试靠它把拼板拉回来看（排查"字没认出来是拼板的问题还是识别的问题"）。
     */
    @Volatile
    var debugDumpDir: java.io.File? = null

    /**
     * 一次识别的结果。
     * [cells] 按行优先排 30 格，[BLANK] 表示这格没认出来。
     */
    class Result(
        val ok: Boolean,
        val error: String = "",
        val cells: CharArray = CharArray(COUNT),
        /** 便于排查的过程日志（出问题时能看出卡在哪一步） */
        val detail: String = "",
    ) {
        val filled: Int get() = cells.count { it != BLANK }

        /** 30 格按 5 行 6 列排版，未识别的显示成「？」——给日志和自动化测试用 */
        fun gridText(): String = (0 until ROWS).joinToString("\n") { r ->
            (0 until COLS).joinToString(" ") { c ->
                val ch = cells[r * COLS + c]
                if (ch == BLANK) "？" else ch.toString()
            }
        }
    }

    /** 识别入口。[ocr] 是可替换的"拼板 → 词表"实现（真机用 ML Kit，测试里可以打桩） */
    suspend fun recognize(
        source: Bitmap,
        log: (String) -> Unit = {},
        ocr: suspend (Bitmap) -> List<Word> = OcrEngine::recognize,
    ): Result {
        val sb = StringBuilder()
        fun L(s: String) {
            sb.appendLine(s)
            log(s)
        }
        try {
            val img = scaleTo(source, MAX_SIDE)
            val w = img.width
            val h = img.height
            val lum = luma(img)
            L("图片 ${w}x$h")

            // ---- 候选选区：面板优先，切不出来再用整图 ----
            val rects = ArrayList<IntArray>()
            val names = ArrayList<String>()
            val panel = findPanel(lum, w, h)
            if (panel != null && !(panel[0] == 0 && panel[1] == 0 && panel[2] == w - 1 && panel[3] == h - 1)) {
                rects.add(panel)
                names.add("面板")
            }
            rects.add(intArrayOf(0, 0, w - 1, h - 1))
            names.add("整图")

            var rows: IntArray? = null
            var cols: IntArray? = null
            for (i in rects.indices) {
                val r = rects[i]
                val g = findGrid(lum, w, h, r[0], r[1], r[2], r[3])
                val size = "${r[2] - r[0] + 1}x${r[3] - r[1] + 1}"
                if (g != null) {
                    L("${names[i]} $size -> 5x6")
                    rows = g.first
                    cols = g.second
                    break
                }
                L("${names[i]} $size -> 不是 5x6")
            }
            if (rows == null || cols == null) {
                return Result(
                    false,
                    "没能在图里找到 6×5 的字格。\n\n" +
                        "请让图片包含完整的 6×5 字格（可以把周围界面一起截进来，程序会自动裁）。",
                    detail = sb.toString(),
                )
            }

            // ---- 第一趟：归一化拼板 ----
            val cells = CharArray(COUNT)
            var words = ocrPass(img, rows, cols, normalized = true, log = ::L, ocr = ocr)
            mapToCells(words, cells)
            L("第一趟（归一化）认到 ${cells.count { it != BLANK }} / $COUNT")

            // ---- 第二趟：只有还有空格才补，用原图风格再认一遍 ----
            if (cells.count { it != BLANK } < COUNT) {
                words = ocrPass(img, rows, cols, normalized = false, log = ::L, ocr = ocr)
                val second = CharArray(COUNT)
                mapToCells(words, second)
                for (i in 0 until COUNT) {
                    if (cells[i] == BLANK && second[i] != BLANK) cells[i] = second[i]
                }
                L("第二趟（原图）补到 ${cells.count { it != BLANK }} / $COUNT")
            }

            val filled = cells.count { it != BLANK }
            L("最终 $filled / $COUNT 格")
            if (filled == 0) {
                return Result(
                    false,
                    "图片里的字一个都没认出来。\n\n请确认图片里包含了完整的 6×5 字格。",
                    cells,
                    sb.toString(),
                )
            }
            return Result(true, "", cells, sb.toString())
        } catch (e: Exception) {
            return Result(false, "识别出错：" + (e.message ?: e.javaClass.simpleName), detail = sb.toString())
        }
    }

    // ================================================================ 一趟识别

    private suspend fun ocrPass(
        src: Bitmap,
        rowb: IntArray,
        colb: IntArray,
        normalized: Boolean,
        log: (String) -> Unit,
        ocr: suspend (Bitmap) -> List<Word>,
    ): List<Word> {
        val montage = buildMontage(src, rowb, colb, normalized, log)
        val tag = if (normalized) "norm" else "raw"
        debugDumpDir?.let { dir ->
            runCatching {
                dir.mkdirs()
                val f = java.io.File(dir, "montage_$tag.png")
                java.io.FileOutputStream(f).use {
                    montage.compress(Bitmap.CompressFormat.PNG, 90, it)
                }
                log("  拼板已存: ${f.absolutePath}")
            }
        }
        val words = try {
            ocr(montage)
        } finally {
            montage.recycle()
        }
        log("  OCR 词数 ${words.size}" + if (words.isNotEmpty()) {
            "；前几个：" + words.take(6).joinToString(" ") { "${it.text}@${it.cx},${it.cy}" }
        } else "")
        return words
    }

    /**
     * 把识别到的字映射回 6×5 格子。
     *
     * 拼板是按固定网格摆的，所以格子中心是已知的：
     *  - 先按 y 归到最接近的一行；
     *  - 行内按 x 排序，每个字**认领最近的一个还没被占用的列**（一列只放一个字）。
     *
     * 为什么不是"直接取最近的格子"：ML Kit 会把一行里的几个字连成一个词，
     * 我们按包围盒等宽切片估位置，一旦某个字漏认，切片位置就会整体偏移；
     * 这时"最近且未被占用"能保证字还是按从左到右的顺序填，不会挤在同一格里。
     */
    private fun mapToCells(words: List<Word>, cells: CharArray) {
        val pitch = MONTAGE_CELL + MONTAGE_GAP
        val rowCenters = IntArray(ROWS) { MONTAGE_GAP + it * pitch + MONTAGE_CELL / 2 }
        val colCenters = IntArray(COLS) { MONTAGE_GAP + it * pitch + MONTAGE_CELL / 2 }
        val rowTol = pitch / 2 + MONTAGE_CELL / 4          // 行归属容差（别把相邻行算进来）
        val colTol = MONTAGE_CELL / 2                       // 离格心超过半格就不认

        val byRow = Array(ROWS) { ArrayList<Word>() }
        for (w in words) {
            var best = -1
            var bd = Int.MAX_VALUE
            for (r in 0 until ROWS) {
                val d = kotlin.math.abs(rowCenters[r] - w.cy)
                if (d < bd) {
                    bd = d
                    best = r
                }
            }
            if (best >= 0 && bd <= rowTol) byRow[best].add(w)
        }

        for (r in 0 until ROWS) {
            val used = BooleanArray(COLS)
            for (w in byRow[r].sortedBy { it.cx }) {
                var bestCol = -1
                var bestD = Int.MAX_VALUE
                for (c in 0 until COLS) {
                    if (used[c]) continue
                    val d = kotlin.math.abs(colCenters[c] - w.cx)
                    if (d < bestD) {
                        bestD = d
                        bestCol = c
                    }
                }
                if (bestCol < 0 || bestD > colTol) continue
                val ch = firstCjk(w.text)
                if (ch == BLANK) continue
                used[bestCol] = true
                val idx = r * COLS + bestCol
                if (cells[idx] == BLANK) cells[idx] = ch
            }
        }
    }

    private fun firstCjk(s: CharSequence): Char {
        for (c in s) {
            if (c in '\u4e00'..'\u9fff' || c in '\u3400'..'\u4dbf') return c
        }
        return BLANK
    }

    // ================================================================ 拼板

    private fun buildMontage(
        src: Bitmap,
        rowb: IntArray,
        colb: IntArray,
        normalized: Boolean,
        log: (String) -> Unit,
    ): Bitmap {
        val mw = COLS * MONTAGE_CELL + (COLS + 1) * MONTAGE_GAP
        val mh = ROWS * MONTAGE_CELL + (ROWS + 1) * MONTAGE_GAP
        val sheet = Bitmap.createBitmap(mw, mh, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(sheet)
        canvas.drawColor(Color.WHITE)
        val paint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
        var inked = 0
        for (rr in 0 until ROWS) {
            for (cc in 0 until COLS) {
                val y0 = rowb[rr * 2]
                val y1 = rowb[rr * 2 + 1]
                val x0 = colb[cc * 2]
                val x1 = colb[cc * 2 + 1]
                val pad = 4
                val rect = Rect(
                    max(0, x0 - pad), max(0, y0 - pad),
                    min(src.width, x1 + pad + 1), min(src.height, y1 + pad + 1),
                )
                val cell = makeCellImage(src, rect, normalized) ?: continue
                inked++
                val dx = MONTAGE_GAP + cc * (MONTAGE_CELL + MONTAGE_GAP) + (MONTAGE_CELL - cell.width) / 2
                val dy = MONTAGE_GAP + rr * (MONTAGE_CELL + MONTAGE_GAP) + (MONTAGE_CELL - cell.height) / 2
                canvas.drawBitmap(cell, dx.toFloat(), dy.toFloat(), paint)
                cell.recycle()
            }
        }
        log("  拼板(${if (normalized) "归一化" else "原图"}) ${mw}x$mh：$inked / $COUNT 格取到了墨迹")
        return sheet
    }

    /**
     * 一格 → 白底黑字的标准化小图。
     *
     * 关键：**按这格自己的底色判极性**，深底浅字会自动反相；
     * 再按 2% / 98% 分位拉对比（不用像素极值——JPEG 噪点与抗锯齿会把极值拉偏），
     * 裁到墨迹后等比例放大到 [MONTAGE_CELL] 见方（归一化版再锐化一道）。
     */
    private fun makeCellImage(src: Bitmap, rect: Rect, normalized: Boolean): Bitmap? {
        val cw = rect.width()
        val ch = rect.height()
        if (cw < 6 || ch < 6) return null

        val pix = IntArray(cw * ch)
        src.getPixels(pix, 0, cw, rect.left, rect.top, cw, ch)
        val v = FloatArray(cw * ch)
        for (i in pix.indices) {
            val c = pix[i]
            v[i] = 0.114f * (c and 0xFF) + 0.587f * ((c shr 8) and 0xFF) + 0.299f * ((c shr 16) and 0xFF)
        }

        // 直方图：求中位数与 2% / 98% 分位
        val hist = IntArray(256)
        for (f in v) {
            hist[f.toInt().coerceIn(0, 255)]++
        }
        val n = v.size
        val p2 = pct(hist, n, 0.02)
        val p50 = pct(hist, n, 0.50)
        val p98 = pct(hist, n, 0.98)
        val bg = p50.toFloat()
        val darkGlyph = (bg - p2) >= (p98 - bg)

        val inkLo = if (darkGlyph) bg - p98 else p2 - bg
        val inkHi = if (darkGlyph) bg - p2 else p98 - bg
        if (inkHi - inkLo < 10f) return null // 基本是纯色，没字
        val span = inkHi - inkLo

        // 拉对比 + 找墨迹包围盒
        var minX = cw
        var minY = ch
        var maxX = -1
        var maxY = -1
        val gray = IntArray(n)
        for (y in 0 until ch) {
            for (x in 0 until cw) {
                val i = y * cw + x
                val raw = if (darkGlyph) bg - v[i] else v[i] - bg
                val a = ((raw - inkLo) / span).coerceIn(0f, 1f)
                gray[i] = ((1f - a) * 255f).toInt() // 墨 → 黑，底 → 白
                if (a > 0.35f) {
                    if (x < minX) minX = x
                    if (x > maxX) maxX = x
                    if (y < minY) minY = y
                    if (y > maxY) maxY = y
                }
            }
        }
        if (maxX < 0) return null
        val bw = maxX - minX + 1
        val bh = maxY - minY + 1
        if (bw < 4 || bh < 4) return null

        // 裁到墨迹
        val cropPix = IntArray(bw * bh)
        for (y in 0 until bh) {
            for (x in 0 until bw) {
                val g = gray[(minY + y) * cw + (minX + x)]
                cropPix[y * bw + x] = Color.argb(255, g, g, g)
            }
        }
        val crop = Bitmap.createBitmap(bw, bh, Bitmap.Config.ARGB_8888)
        crop.setPixels(cropPix, 0, bw, 0, 0, bw, bh)

        // 等比例放大到 MONTAGE_CELL 见方（长边对齐）
        val k = MONTAGE_CELL.toFloat() / max(bw, bh)
        val dw = max(1, (bw * k).roundToInt())
        val dh = max(1, (bh * k).roundToInt())
        val scaled = Bitmap.createScaledBitmap(crop, dw, dh, true)
        if (scaled !== crop) crop.recycle()
        return if (normalized) unsharp(scaled) else scaled
    }

    private fun pct(hist: IntArray, n: Int, p: Double): Int {
        val want = (n * p).toInt()
        var acc = 0
        for (i in 0 until 256) {
            acc += hist[i]
            if (acc >= want) return i
        }
        return 255
    }

    /** 反锐化：out = in + 0.6 × (in − 3×3 均值)，把细笔画提出来 */
    private fun unsharp(bmp: Bitmap): Bitmap {
        val w = bmp.width
        val h = bmp.height
        val pix = IntArray(w * h)
        bmp.getPixels(pix, 0, w, 0, 0, w, h)
        val buf = IntArray(w * h) { pix[it] and 0xFF }
        val out = IntArray(w * h)
        for (y in 0 until h) {
            for (x in 0 until w) {
                val c = buf[y * w + x]
                var sum = 0
                var cnt = 0
                for (dy in -1..1) {
                    val yy = y + dy
                    if (yy < 0 || yy >= h) continue
                    for (dx in -1..1) {
                        val xx = x + dx
                        if (xx < 0 || xx >= w) continue
                        sum += buf[yy * w + xx]
                        cnt++
                    }
                }
                val blur = sum / max(1, cnt)
                val g = (c + (0.6f * (c - blur)).toInt()).coerceIn(0, 255)
                out[y * w + x] = Color.argb(255, g, g, g)
            }
        }
        val res = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        res.setPixels(out, 0, w, 0, 0, w, h)
        bmp.recycle()
        return res
    }

    // ================================================================ 图像基础

    private fun scaleTo(src: Bitmap, maxSide: Int): Bitmap {
        val side = max(src.width, src.height)
        if (side <= maxSide) return src
        val k = maxSide.toFloat() / side
        return Bitmap.createScaledBitmap(
            src,
            max(1, (src.width * k).roundToInt()),
            max(1, (src.height * k).roundToInt()),
            true,
        )
    }

    /** 亮度数组（短整型省一半内存） */
    private fun luma(bmp: Bitmap): ShortArray {
        val w = bmp.width
        val h = bmp.height
        val pix = IntArray(w * h)
        bmp.getPixels(pix, 0, w, 0, 0, w, h)
        val out = ShortArray(w * h)
        for (i in pix.indices) {
            val c = pix[i]
            out[i] = (0.114f * (c and 0xFF) + 0.587f * ((c shr 8) and 0xFF) + 0.299f * ((c shr 16) and 0xFF)).toInt().toShort()
        }
        return out
    }

    private fun at(lum: ShortArray, i: Int): Int = lum[i].toInt() and 0xFF

    /** Otsu 阈值 */
    private fun otsu(lum: ShortArray, w: Int, h: Int, x0: Int, y0: Int, x1: Int, y1: Int): Int {
        val hist = IntArray(256)
        var n = 0
        for (y in y0..y1) {
            val o = y * w
            for (x in x0..x1) {
                hist[at(lum, o + x)]++
                n++
            }
        }
        if (n == 0) return 120
        var sum = 0.0
        for (i in 0 until 256) sum += i.toDouble() * hist[i]
        var sumB = 0.0
        var best = -1.0
        var wB = 0
        var thr = 120
        for (t in 0 until 256) {
            wB += hist[t]
            if (wB == 0) continue
            val wF = n - wB
            if (wF == 0) break
            sumB += t.toDouble() * hist[t]
            val mB = sumB / wB
            val mF = (sum - sumB) / wF
            val between = wB.toDouble() * wF * (mB - mF) * (mB - mF)
            if (between > best) {
                best = between
                thr = t
            }
        }
        return thr
    }

    /** 找亮底大面板（先按整幅找行段，再在行段里找列段） */
    private fun findPanel(lum: ShortArray, w: Int, h: Int): IntArray? {
        return try {
            val rl = DoubleArray(h)
            for (y in 0 until h) {
                val o = y * w
                var c = 0
                for (x in 0 until w) if (at(lum, o + x) > 195) c++
                rl[y] = c.toDouble() / w
            }
            val minRows = max(50, h / 12)
            val band = longestBand(rl, 0.45, minRows) ?: return null
            val py0 = band[0]
            val py1 = band[1]

            val cl = DoubleArray(w)
            for (x in 0 until w) {
                var c = 0
                for (y in py0..py1) if (at(lum, y * w + x) > 195) c++
                cl[x] = c.toDouble() / (py1 - py0 + 1)
            }
            val minCols = max(50, w / 12)
            val cb = longestBand(cl, 0.45, minCols) ?: return null
            intArrayOf(cb[0], py0, cb[1], py1)
        } catch (e: Exception) {
            null
        }
    }

    private fun longestBand(frac: DoubleArray, thresh: Double, minLen: Int): IntArray? {
        var a = -1
        var b = -1
        var bestLen = 0
        var st = -1
        for (i in frac.indices) {
            if (frac[i] > thresh) {
                if (st < 0) st = i
            } else if (st >= 0) {
                val len = i - st
                if (len >= minLen && len > bestLen) {
                    bestLen = len
                    a = st
                    b = i - 1
                }
                st = -1
            }
        }
        if (st >= 0) {
            val len = frac.size - st
            if (len >= minLen && len > bestLen) {
                a = st
                b = frac.size - 1
            }
        }
        return if (a >= 0) intArrayOf(a, b) else null
    }

    /** 用暗像素投影找 5 行 6 列，返回 (行带, 列带)，每个带是 [起, 止] 成对排列 */
    private fun findGrid(
        lum: ShortArray, w: Int, h: Int,
        px0: Int, py0: Int, px1: Int, py1: Int,
    ): Pair<IntArray, IntArray>? {
        var thr = otsu(lum, w, h, px0, py0, px1, py1)
        if (thr < 60) thr = 60
        if (thr > 180) thr = 180

        val pw = px1 - px0 + 1
        val ph = py1 - py0 + 1
        if (pw < 30 || ph < 30) return null
        val rowProj = IntArray(ph)
        val colProj = IntArray(pw)
        for (y in 0 until ph) {
            val o = (py0 + y) * w + px0
            var c = 0
            for (x in 0 until pw) {
                if (at(lum, o + x) < thr) {
                    c++
                    colProj[x]++
                }
            }
            rowProj[y] = c
        }

        val rowThr = max(2, pw / 400)
        val colThr = max(2, ph / 400)
        val minRow = max(8, ph / 40)
        val minCol = max(8, pw / 40)

        val rb = pickBest(bands(rowProj, rowThr, minRow), ROWS)
        val cb = pickBest(bands(colProj, colThr, minCol), COLS)
        if (rb.size != ROWS || cb.size != COLS) return null

        val rows = IntArray(ROWS * 2)
        val cols = IntArray(COLS * 2)
        for (i in 0 until ROWS) {
            rows[i * 2] = rb[i][0] + py0
            rows[i * 2 + 1] = rb[i][1] + py0
        }
        for (i in 0 until COLS) {
            cols[i * 2] = cb[i][0] + px0
            cols[i * 2 + 1] = cb[i][1] + px0
        }
        return rows to cols
    }

    private fun bands(proj: IntArray, thresh: Int, minLen: Int): List<IntArray> {
        val out = ArrayList<IntArray>()
        var st = -1
        for (i in proj.indices) {
            if (proj[i] > thresh) {
                if (st < 0) st = i
            } else if (st >= 0) {
                if (i - st >= minLen) out.add(intArrayOf(st, i - 1))
                st = -1
            }
        }
        if (st >= 0 && proj.size - st >= minLen) out.add(intArrayOf(st, proj.size - 1))
        return out
    }

    /** 带宽多于需要的条数时，保留最"粗"的那几条，再按位置排好 */
    private fun pickBest(list0: List<IntArray>, need: Int): List<IntArray> {
        val list = if (list0.size > need) {
            list0.sortedByDescending { it[1] - it[0] }.take(need)
        } else {
            list0
        }
        return list.sortedBy { it[0] }
    }
}

/** 一次 OCR 词表：文本 + 包围盒中心（拼板坐标系） */
data class Word(val text: String, val cx: Int, val cy: Int)
