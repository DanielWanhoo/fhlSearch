package com.wangchuan.fhlsearch.ocr

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * 「诗词检索 · 图片识别」的取字引擎。
 *
 * 整体思路（搜题软件那套：先找到字格，再逐格认）：
 *   1. 找"游戏面板"——亮色大块；面板和整图**各算一遍**，谁能切出 5 行 6 列就用谁
 *   2. 在选区里用暗像素投影切出 5 行 6 列 → 把切出来的**带子中心拟合成等距点阵**
 *      （关键：投影切歪、宽字被劈成两半、整格被装饰带偏时，带子的**宽窄**会乱，
 *       但带子在哪儿基本没错，拟合成等距点阵后按点阵均分就不会错位）
 *   3. **逐格**抠字：按这格自己的底色判极性（深底浅字自动反相）、
 *      只用"字心"判方向（避免把格子边框、装饰光圈当成字）、去掉横贯整行的线、
 *      按对比拉成白底黑字、放大到 240px
 *   4. 30 格拼成白底大图交给 ML Kit 中文识别 —— 这样 30 个字一定被切成 30 个独立词
 *   5. 按包围盒中心把识别结果映射回格子
 *
 * 为什么要多趟：同一张图，笔画"粗一点/细一点"认出来的字会不一样
 * （淡笔画的字细版认不出、粗版认得出）。这里按"紧→柔→宽"三档跑，**投票**取多数字；
 * 每格的候选字都留着，供检索时"认不准就按题库对"用。
 *
 * 本文件**不依赖 Android 的界面代码**，只用到 Bitmap 的像素读写，方便单独调参数。
 */
object PoemOcr {

    const val COLS = 6
    const val ROWS = 5
    const val COUNT = COLS * ROWS

    /** 拼板参数：每格放大到 240px 见方，格间距 80px（与 Windows 版同一组实测参数） */
    internal const val MONTAGE_CELL = 240
    internal const val MONTAGE_GAP = 80

    /** 送进来之前先把长边缩到这个尺寸（再大对识别没帮助，只是费内存） */
    private const val MAX_SIDE = 2200

    /** 没认出字时格子里的占位符 */
    const val BLANK = '\u0000'

    /** 最近一次 makeCellImage 返回 null 的原因（只用于日志：能看出某格为什么被跳过） */
    private var lastSkip = ""

    /**
     * 调试用：设成某个目录后，每趟的拼板都会存成 PNG 到那里。
     * 自动化测试靠它把拼板拉回来看（排查"字没认出来是拼板的问题还是识别的问题"）。
     */
    @Volatile
    var debugDumpDir: java.io.File? = null

    /** 格的预处理风格（三趟各用一种，见 [makeCellImage]） */
    internal enum class Style(val label: String) {
        /** 紧：强墨阈值、锐化——笔画清楚、字大时最准 */
        TIGHT("紧"),
        /** 柔：同样的裁剪，但对比拉得温和、不锐化——笔画发虚/粘连时更准 */
        SOFT("柔"),
        /** 宽：阈值更松、四周留白——淡笔画、小字号时更准 */
        LOOSE("宽"),
    }

    /**
     * 一次识别的结果。
     * [cells] 按行优先排 30 格，[BLANK] 表示这格没认出来；
     * [candidates] 是每格"各趟认出来的字"（按票数从多到少，可能为空）。
     */
    class Result(
        val ok: Boolean,
        val error: String = "",
        val cells: CharArray = CharArray(COUNT),
        /** 便于排查的过程日志（出问题时能看出卡在哪一步） */
        val detail: String = "",
        val candidates: List<Set<Char>> = emptyList(),
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

    // ================================================================ 主流程

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

            // ---- 候选选区：面板优先，再用整图兜底 ----
            val regions = ArrayList<IntArray>()
            val names = ArrayList<String>()
            val panel = findPanel(lum, w, h)
            if (panel != null && !(panel[0] == 0 && panel[1] == 0 && panel[2] == w - 1 && panel[3] == h - 1)) {
                regions.add(panel)
                names.add("面板")
            }
            regions.add(intArrayOf(0, 0, w - 1, h - 1))
            names.add("整图")

            // ---- 逐候选切格 ----
            val grids = ArrayList<Grid>()
            for (i in regions.indices) {
                val r = regions[i]
                val size = "${r[2] - r[0] + 1}x${r[3] - r[1] + 1}"
                val g = findGrid(lum, w, h, r[0], r[1], r[2], r[3])
                if (g == null) {
                    L("${names[i]} $size -> 不是 5x6")
                    continue
                }
                L("${names[i]} $size -> 5x6（${g.how}；行距 ${g.rowPitch}，列距 ${g.colPitch}）")
                if (grids.any { it.almostSame(g) }) {
                    L("  ${names[i]} 与前面切出的格子基本重合，跳过")
                    continue
                }
                grids.add(g)
            }
            if (grids.isEmpty()) {
                return Result(
                    false,
                    "没能在图里找到 6×5 的字格。\n\n" +
                        "请让图片包含完整的 6×5 字格（可以把周围界面一起截进来，程序会自动裁）。",
                    detail = sb.toString(),
                )
            }

            // ---- 逐候选识别，取"靠谱且填得多"的那个 ----
            var best: Pass? = null
            for ((idx, g) in grids.withIndex()) {
                val p = recognizeGrid(img, g, ::L, ocr)
                if (best == null || p.rank > best.rank) best = p
                if (p.filled == COUNT && p.unanimous && g.reliable) break  // 已经没问题了
                if (idx == 0 && grids.size > 1) L("  换下一个候选选区再试")
            }
            val win = best!!
            L("最终 ${win.filled} / $COUNT 格")

            if (win.filled == 0) {
                return Result(
                    false,
                    "图片里的字一个都没认出来。\n\n请确认图片里包含了完整的 6×5 字格。",
                    win.cells, sb.toString(), win.candidates,
                )
            }
            return Result(true, "", win.cells, sb.toString(), win.candidates)
        } catch (e: Exception) {
            return Result(false, "识别出错：" + (e.message ?: e.javaClass.simpleName), detail = sb.toString())
        }
    }

    /** 一套格子识别完的结果 */
    private class Pass(
        val cells: CharArray,
        val candidates: List<Set<Char>>,
        /** 排序用：填充格数为主，全票一致为辅 */
        val rank: Int,
        val filled: Int,
        val unanimous: Boolean,
    )

    /**
     * 对一套格子跑识别：**"紧""柔"两趟必跑，再用"宽"补一趟**，每格按**票数**定字
     * （票数相同比置信度，再相同取靠前那一趟）。
     *
     * 为什么是投票而不是"取置信度最高的"：两趟认出来的字经常不一样
     * （10272 的这一格：紧版读「云」、柔版读「园」，而柔版置信度反而更高），
     * 单看置信度会挑错；少数服从多数更稳。
     * 两趟完全一致时（清晰的图片基本都是）就不再跑第三趟，省时间。
     */
    private suspend fun recognizeGrid(
        img: Bitmap,
        g: Grid,
        log: (String) -> Unit,
        ocr: suspend (Bitmap) -> List<Word>,
    ): Pass {
        val votes = Array(COUNT) { LinkedHashMap<Char, Int>() }
        val confSum = Array(COUNT) { HashMap<Char, Float>() }
        val firstPass = Array(COUNT) { HashMap<Char, Int>() }
        // 额外的候选字：多字被读成一格时（见 OcrEngine）留下的其它可能
        val extras: Array<MutableSet<Char>> = Array(COUNT) { LinkedHashSet() }
        var prev: CharArray? = null
        var pass = 0
        for (style in Style.entries) {
            val cells = CharArray(COUNT)
            val confs = FloatArray(COUNT) { -1f }
            val words = ocrPass(img, g, style, log, ocr)
            mapToCells(words, cells, confs, extras)
            val n = cells.count { it != BLANK }
            for (i in 0 until COUNT) {
                val ch = cells[i]
                if (ch == BLANK) continue
                votes[i][ch] = (votes[i][ch] ?: 0) + 1
                confSum[i][ch] = (confSum[i][ch] ?: 0f) + (if (confs[i] < 0f) 0.5f else confs[i])
                firstPass[i].putIfAbsent(ch, pass)
            }
            pass++
            val filled = votes.count { it.isNotEmpty() }
            log("  第${pass}趟（${style.label}）认到 $n / $COUNT，累计 $filled / $COUNT")
            if (pass == 2) {
                // 两趟一模一样就不必再跑第三趟了
                val same = prev != null && (0 until COUNT).all { cells[it] == prev!![it] }
                if (same && filled == COUNT) break
            }
            prev = cells
            if (pass >= 3) break
        }

        val cells = CharArray(COUNT)
        val cands = ArrayList<Set<Char>>(COUNT)
        var unanimous = true
        for (i in 0 until COUNT) {
            val ranked = votes[i].entries.sortedWith(
                compareByDescending<Map.Entry<Char, Int>> { it.value }
                    .thenByDescending { confSum[i][it.key] ?: 0f }
                    .thenBy { firstPass[i][it.key] ?: 9 },
            )
            if (ranked.size > 1) unanimous = false
            if (ranked.isNotEmpty()) cells[i] = ranked[0].key
            val set = LinkedHashSet<Char>(ranked.map { it.key })
            set.addAll(extras[i])
            cands.add(set)
        }
        val filledN = cells.count { it != BLANK }
        // 排序：先看填了多少，再给"格子切得靠谱"的那套一点偏爱（均分兜底不可信）
        val rank = filledN * 2 + (if (g.reliable) 8 else 0) + if (unanimous) 1 else 0
        return Pass(cells, cands, rank, filledN, unanimous)
    }

    // ================================================================ 一趟识别

    private suspend fun ocrPass(
        src: Bitmap,
        g: Grid,
        style: Style,
        log: (String) -> Unit,
        ocr: suspend (Bitmap) -> List<Word>,
    ): List<Word> {
        val montage = buildMontage(src, g, style, log)
        debugDumpDir?.let { dir ->
            runCatching {
                dir.mkdirs()
                val f = java.io.File(dir, "montage_${style.name.lowercase()}.png")
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
        // 排查用：把这一趟认到的词全打出来（只在 dump 时才打，平时太吵）
        if (debugDumpDir != null && words.isNotEmpty()) {
            log("  全部词：" + words.joinToString(" ") { "${it.text}@${it.cx},${it.cy}" })
        }
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
    private fun mapToCells(
        words: List<Word>,
        cells: CharArray,
        confs: FloatArray? = null,
        extra: Array<MutableSet<Char>>? = null,
    ) {
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
                val d = abs(rowCenters[r] - w.cy)
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
                    val d = abs(colCenters[c] - w.cx)
                    if (d < bestD) {
                        bestD = d
                        bestCol = c
                    }
                }
                if (bestCol < 0 || bestD > colTol) continue
                val raw = firstCjk(w.text)
                if (raw == BLANK) continue
                // ML Kit 偶尔吐繁体（燒/別/國…），题库是简体，统一转过来再填
                val ch = T2S.of(raw)
                used[bestCol] = true
                val idx = r * COLS + bestCol
                if (cells[idx] == BLANK) {
                    cells[idx] = ch
                    confs?.set(idx, w.conf)
                }
                // 一个字被读成了好几个字（例如「野」→「里予」）：除主选外全记成这格的候选
                if (extra != null && w.text.length > 1) {
                    for (c in w.text) {
                        if (!isCjk(c)) continue
                        val s = T2S.of(c)
                        if (s != ch) extra[idx].add(s)
                    }
                }
            }
        }
    }

    private fun isCjk(c: Char) = c in '\u4e00'..'\u9fff' || c in '\u3400'..'\u4dbf'

    private fun firstCjk(s: CharSequence): Char {
        for (c in s) {
            if (c in '\u4e00'..'\u9fff' || c in '\u3400'..'\u4dbf') return c
        }
        return BLANK
    }

    // ================================================================ 拼板

    private fun buildMontage(src: Bitmap, g: Grid, style: Style, log: (String) -> Unit): Bitmap {
        val mw = COLS * MONTAGE_CELL + (COLS + 1) * MONTAGE_GAP
        val mh = ROWS * MONTAGE_CELL + (ROWS + 1) * MONTAGE_GAP
        val sheet = Bitmap.createBitmap(mw, mh, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(sheet)
        canvas.drawColor(Color.WHITE)
        val paint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
        var inked = 0
        val skips = ArrayList<String>()
        for (rr in 0 until ROWS) {
            for (cc in 0 until COLS) {
                val rect = Rect(g.colStart[cc], g.rowStart[rr], g.colEnd[cc] + 1, g.rowEnd[rr] + 1)
                val cell = makeCellImage(src, rect, style)
                if (cell == null) {
                    skips.add("${rr},${cc}:$lastSkip")
                    continue
                }
                inked++
                val dx = MONTAGE_GAP + cc * (MONTAGE_CELL + MONTAGE_GAP) + (MONTAGE_CELL - cell.width) / 2
                val dy = MONTAGE_GAP + rr * (MONTAGE_CELL + MONTAGE_GAP) + (MONTAGE_CELL - cell.height) / 2
                canvas.drawBitmap(cell, dx.toFloat(), dy.toFloat(), paint)
                cell.recycle()
            }
        }
        log(
            "  拼板(${style.label}) ${mw}x$mh：$inked / $COUNT 格取到了墨迹" +
                if (skips.isEmpty()) "" else "；跳过 " + skips.take(8).joinToString(" ")
        )
        return sheet
    }

    /**
     * 一格 → 白底黑字的标准化小图（返回 null 表示这格是空的/没法认）。
     *
     * 和"抓暗像素"相比多了四件针对游戏界面的处理：
     *  1. **只看字心判方向**：格子四周常有装饰（光圈、圆角框、选中高亮底色），
     *     整格统计会被带偏；用中间 56% 的区域判断"浅底深字"还是"深底浅字"。
     *  2. **双重阈值**：判极性用低阈值（宁可多算），定包围盒用"半边量程"的高阈值
     *     —— 装饰一般是淡的，字是全对比的，高阈值天然把光圈/边框滤掉。
     *  3. **去掉横贯整行/整列**：格子边框、田字格线在被选中的极性下会连成一整条，
     *     把占满一整行/一整列的像素清掉，包围盒就不会把整个边框框进去。
     *  4. **对比拉伸到白底黑字**：用该格自己的分位数，JPEG 噪点与抗锯齿不会把极值拉偏。
     */
    private fun makeCellImage(src: Bitmap, rect: Rect, style: Style, retried: Boolean = false): Bitmap? {
        val cw = rect.width()
        val ch = rect.height()
        if (cw < 8 || ch < 8) {
            lastSkip = "太小"
            return null
        }

        val pix = IntArray(cw * ch)
        src.getPixels(pix, 0, cw, rect.left, rect.top, cw, ch)
        val v = FloatArray(cw * ch)
        for (i in pix.indices) {
            val c = pix[i]
            v[i] = 0.114f * (c and 0xFF) + 0.587f * ((c shr 8) and 0xFF) + 0.299f * ((c shr 16) and 0xFF)
        }

        // 直方图：求 2% / 50% / 98% 分位
        val hist = IntArray(256)
        for (f in v) hist[f.toInt().coerceIn(0, 255)]++
        val n = v.size
        val p2 = pct(hist, n, 0.02).toFloat()
        val bg = pct(hist, n, 0.50).toFloat()
        val p98 = pct(hist, n, 0.98).toFloat()
        val span = p98 - p2
        if (span < 12f) {
            lastSkip = "纯色"
            return null                                      // 基本是纯色，没字
        }

        // ---- 极性：只看中心 56% 的区域，比底色暗的像素 vs 亮的像素谁多 ----
        val tPol = max(6f, 0.18f * span)
        val mx0 = (cw * 0.22f).toInt()
        val mx1 = (cw * 0.78f).toInt()
        val my0 = (ch * 0.22f).toInt()
        val my1 = (ch * 0.78f).toInt()
        var darkN = 0
        var lightN = 0
        for (y in my0 until my1) {
            val o = y * cw
            for (x in mx0 until mx1) {
                val d = bg - v[o + x]
                if (d > tPol) darkN++ else if (-d > tPol) lightN++
            }
        }
        if (darkN + lightN < 8) {
            lastSkip = "字心空"
            return null                                      // 中心区没东西
        }
        val lightGlyph = lightN > darkN

        // 该极性方向的量程（用于定阈值和拉伸）
        val side = if (lightGlyph) p98 - bg else bg - p2
        if (side < 10f) {
            lastSkip = "对比低"
            return null
        }
        // 定包围盒的阈值：三趟各不同。
        // 紧的那趟取高阈值——只留"全对比"的笔画，格子四周淡装饰（光圈、圆角框）会被滤掉；
        // 万一这格的字本来就淡（高阈值下几乎没墨迹），柔/宽那两趟会把它捞回来。
        val bboxRatio = when (style) {
            Style.TIGHT -> 0.62f
            Style.SOFT -> 0.44f
            Style.LOOSE -> 0.30f
        }
        val tStrong = max(10f, bboxRatio * side)
        val tWeak = max(8f, (if (style == Style.LOOSE) 0.18f else 0.28f) * side)

        // ---- 墨迹掩膜（高阈值：只留全对比的笔画） ----
        val mask = BooleanArray(n)
        var any = false
        for (y in 0 until ch) {
            val o = y * cw
            for (x in 0 until cw) {
                val d = if (lightGlyph) v[o + x] - bg else bg - v[o + x]
                if (d > tStrong) {
                    mask[o + x] = true
                    any = true
                }
            }
        }
        if (!any) {
            lastSkip = "没墨迹"
            return null
        }

        // ---- 去掉"横贯整行/整列"的装饰线（格子边框、田字格、高亮底框的下沿） ----
        val rowCount = IntArray(ch)
        val colCount = IntArray(cw)
        for (y in 0 until ch) {
            val o = y * cw
            for (x in 0 until cw) {
                if (mask[o + x]) {
                    rowCount[y]++
                    colCount[x]++
                }
            }
        }
        // 只清"贴着窗口边"的整行/整列：格子边框、圆角框都在这里；
        // 而「一」「三」这种贯穿字的横笔在中间，不能被误删。
        val edgeY = max(1, (ch * 0.12f).toInt())
        val edgeX = max(1, (cw * 0.12f).toInt())
        val lineRows = BooleanArray(ch) {
            rowCount[it] > 0.62f * cw && (it <= edgeY || it >= ch - 1 - edgeY)
        }
        val lineCols = BooleanArray(cw) {
            colCount[it] > 0.62f * ch && (it <= edgeX || it >= cw - 1 - edgeX)
        }
        if (lineRows.any { it } || lineCols.any { it }) {
            for (y in 0 until ch) {
                val o = y * cw
                for (x in 0 until cw) {
                    if (mask[o + x] && (lineRows[y] || lineCols[x])) mask[o + x] = false
                }
            }
        }

        // ---- 包围盒 ----
        var minX = cw
        var minY = ch
        var maxX = -1
        var maxY = -1
        var inkN = 0
        for (y in 0 until ch) {
            val o = y * cw
            for (x in 0 until cw) {
                if (!mask[o + x]) continue
                inkN++
                if (x < minX) minX = x
                if (x > maxX) maxX = x
                if (y < minY) minY = y
                if (y > maxY) maxY = y
            }
        }
        if (inkN < 6) {
            lastSkip = "空"
            return null                                  // 这格基本是空的
        }
        var bw = maxX - minX + 1
        var bh = maxY - minY + 1
        if (bw < 3 || bh < 3) {
            lastSkip = "太小"
            return null
        }

        // ---- 框住整格时：先把"跟窗口边连通的墨迹"当装饰框扔掉，再重算包围盒 ----
        // 高亮格外面那圈圆角框、田字格线都会在这里被清掉；万一连字一起扔掉了
        // （字压到框上），就退回原来的包围盒，不冒险。
        if (bw > cw * 0.90f || bh > ch * 0.90f) {
            val keepX0 = minX
            val keepY0 = minY
            val keepX1 = maxX
            val keepY1 = maxY
            val borderInk = dropBorderComponents(mask, cw, ch)
            if (borderInk > 0) {
                var n2 = 0
                var aX = cw
                var aY = ch
                var bX = -1
                var bY = -1
                for (y in 0 until ch) {
                    val o = y * cw
                    for (x in 0 until cw) {
                        if (!mask[o + x]) continue
                        n2++
                        if (x < aX) aX = x
                        if (x > bX) bX = x
                        if (y < aY) aY = y
                        if (y > bY) bY = y
                    }
                }
                val okInk = n2 >= 15
                val okBox = bX > aX && bY > aY &&
                    (bX - aX + 1) >= cw * 0.10f && (bY - aY + 1) >= ch * 0.10f
                if (okInk && okBox) {
                    minX = aX
                    minY = aY
                    maxX = bX
                    maxY = bY
                    inkN = n2
                    bw = maxX - minX + 1
                    bh = maxY - minY + 1
                } else {
                    minX = keepX0
                    minY = keepY0
                    maxX = keepX1
                    maxY = keepY1
                }
            }
        }

        // 还是几乎占满整格：把窗口往里收一圈再来一次
        if (!retried && (bw > cw * 0.94f || bh > ch * 0.94f)) {
            val ix = (cw * 0.12f).toInt()
            val iy = (ch * 0.12f).toInt()
            if (cw - 2 * ix >= 12 && ch - 2 * iy >= 12) {
                val inner = Rect(rect.left + ix, rect.top + iy, rect.right - ix, rect.bottom - iy)
                return makeCellImage(src, inner, style, retried = true)
            }
        }

        // 细条形的墨迹（「一」「二」这种）不能丢：把短边补到窗口的 20% 再裁，
        // 否则送进去的是一条细线，ML Kit 什么也认不出来。
        val minW = max(6, (cw * 0.20f).toInt())
        val minH = max(6, (ch * 0.20f).toInt())
        if (bw < minW) {
            val extra = (minW - bw) / 2
            minX = max(0, minX - extra)
            maxX = min(cw - 1, maxX + extra)
            bw = maxX - minX + 1
        }
        if (bh < minH) {
            val extra = (minH - bh) / 2
            minY = max(0, minY - extra)
            maxY = min(ch - 1, maxY + extra)
            bh = maxY - minY + 1
        }

        // ---- 裁到包围盒（宽的留白 6%，紧的不留），拉成白底黑字 ----
        val padPx = if (style == Style.LOOSE) max(2, (max(bw, bh) * 0.06f).toInt()) else 1
        val x0 = max(0, minX - padPx)
        val y0 = max(0, minY - padPx)
        val x1 = min(cw - 1, maxX + padPx)
        val y1 = min(ch - 1, maxY + padPx)
        val w2 = x1 - x0 + 1
        val h2 = y1 - y0 + 1

        val lo = tWeak * 0.55f
        val hi = max(lo + 1f, side * if (style == Style.SOFT) 1.45f else 0.85f)
        val outPix = IntArray(w2 * h2)
        for (y in 0 until h2) {
            val so = (y + y0) * cw + x0
            val to = y * w2
            for (x in 0 until w2) {
                val d = if (lightGlyph) v[so + x] - bg else bg - v[so + x]
                val a = ((d - lo) / hi).coerceIn(0f, 1f)
                val g = ((1f - a) * 255f).toInt()
                outPix[to + x] = Color.argb(255, g, g, g)
            }
        }
        val crop = Bitmap.createBitmap(w2, h2, Bitmap.Config.ARGB_8888)
        crop.setPixels(outPix, 0, w2, 0, 0, w2, h2)

        // 等比例放大到 MONTAGE_CELL 见方（长边对齐）
        val k = MONTAGE_CELL.toFloat() / max(w2, h2)
        val dw = max(1, (w2 * k).roundToInt())
        val dh = max(1, (h2 * k).roundToInt())
        val scaled = Bitmap.createScaledBitmap(crop, dw, dh, true)
        if (scaled !== crop) crop.recycle()
        return if (style == Style.SOFT) scaled else unsharp(scaled)
    }

    /**
     * 把"与窗口边连通"的墨迹从 [mask] 里删掉（装饰框、圆角框、田字格线都连着边）。
     * 删除的点数作为返回值返回，0 表示没有可删的。
     */
    private fun dropBorderComponents(mask: BooleanArray, cw: Int, ch: Int): Int {
        val seen = BooleanArray(mask.size)
        val stack = IntArray(mask.size)
        var sp = 0
        fun push(i: Int) {
            if (i in mask.indices && mask[i] && !seen[i]) {
                seen[i] = true
                stack[sp++] = i
            }
        }
        for (x in 0 until cw) {
            push(x)
            push((ch - 1) * cw + x)
        }
        for (y in 0 until ch) {
            push(y * cw)
            push(y * cw + cw - 1)
        }
        var n = 0
        while (sp > 0) {
            val i = stack[--sp]
            if (mask[i]) {
                mask[i] = false
                n++
            }
            val x = i % cw
            val y = i / cw
            if (x > 0) push(i - 1)
            if (x + 1 < cw) push(i + 1)
            if (y > 0) push(i - cw)
            if (y + 1 < ch) push(i + cw)
        }
        return n
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

    // ================================================================ 切格

    /**
     * 一套 5 行 6 列的格子窗口（像素坐标，闭区间）。
     * [how] 记录怎么切出来的，[rowPitch]/[colPitch] 是拟合出的行/列间距，都只用于日志；
     * [reliable] 表示"两条轴都拟合成等距点阵"了——这种格子可信，兜底切出来的不可信。
     */
    private class Grid(
        val rowStart: IntArray, val rowEnd: IntArray,
        val colStart: IntArray, val colEnd: IntArray,
        val how: String,
        val rowPitch: Int = 0,
        val colPitch: Int = 0,
        val reliable: Boolean = false,
    ) {
        fun almostSame(o: Grid): Boolean {
            var diff = 0.0
            for (i in 0 until COLS) {
                diff += abs((colStart[i] + colEnd[i]) - (o.colStart[i] + o.colEnd[i])) / 2.0
            }
            for (i in 0 until ROWS) {
                diff += abs((rowStart[i] + rowEnd[i]) - (o.rowStart[i] + o.rowEnd[i])) / 2.0
            }
            val scale = max(1.0, (colEnd[COLS - 1] - colStart[0]).toDouble())
            return diff / (COLS + ROWS) < scale * 0.03
        }
    }

    /** 用暗像素投影找 5 行 6 列 */
    private fun findGrid(
        lum: ShortArray, w: Int, h: Int,
        px0: Int, py0: Int, px1: Int, py1: Int,
    ): Grid? {
        val pw = px1 - px0 + 1
        val ph = py1 - py0 + 1
        if (pw < 60 || ph < 60) return null

        var thr = otsu(lum, w, h, px0, py0, px1, py1)
        if (thr < 60) thr = 60
        if (thr > 180) thr = 180

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

        val rb = bands(rowProj, max(2, pw / 400), max(8, ph / 40))
        val cb = bands(colProj, max(2, ph / 400), max(8, pw / 40))

        // 首选：把带子中心拟合成等距点阵，再按点阵均分窗口
        // 注意：带子是**选区内部**的坐标，拟合出的起点要加回选区原点，
        // 否则面板不在图左上角时整片格子会画到别处去。
        val rfit0 = fitLattice(rb, ROWS)
        val cfit0 = fitLattice(cb, COLS)
        if (rfit0 != null && cfit0 != null) {
            val rfit = floatArrayOf(rfit0[0] + py0, rfit0[1])
            val cfit = floatArrayOf(cfit0[0] + px0, cfit0[1])
            return latticeGrid(rfit, cfit, w, h, "点阵", reliable = true)
        }
        // 次选：某条轴的条数刚好对得上就直接用那几条，另一条轴用点阵/均分
        if (rb.size == ROWS || cb.size == COLS) {
            val rows = axisWindows(rb, ROWS, rfit0, py0, py1)
            val cols = axisWindows(cb, COLS, cfit0, px0, px1)
            if (rows != null && cols != null) {
                return Grid(
                    IntArray(ROWS) { rows[it * 2] }, IntArray(ROWS) { rows[it * 2 + 1] },
                    IntArray(COLS) { cols[it * 2] }, IntArray(COLS) { cols[it * 2 + 1] },
                    "投影带",
                    medianPitch(rows, ROWS), medianPitch(cols, COLS),
                )
            }
        }
        // 兜底：按墨迹范围 6 等分
        return uniformGrid(lum, w, h, px0, py0, px1, py1, thr)
    }

    /** 一条轴上的窗口：点阵优先 → 宽松点阵 → 原始带子（条数必须对得上） */
    private fun axisWindows(
        b: List<IntArray>, need: Int, fit0: FloatArray?, lo: Int, hi: Int,
    ): IntArray? {
        val fit = fit0 ?: fitLattice(b, need, maxRes = 10f)?.also { it[0] += lo }
        if (fit != null) {
            val out = IntArray(need * 2)
            for (i in 0 until need) {
                val c = fit[0] + fit[1] * i
                out[i * 2] = max(lo, (c - fit[1] * 0.46f).roundToInt())
                out[i * 2 + 1] = min(hi, (c + fit[1] * 0.46f).roundToInt())
            }
            return out
        }
        if (b.size != need) return null
        val out = IntArray(need * 2)
        for (i in 0 until need) {
            out[i * 2] = b[i][0] + lo
            out[i * 2 + 1] = b[i][1] + lo
        }
        return out
    }

    private fun latticeGrid(
        rfit: FloatArray, cfit: FloatArray, w: Int, h: Int, how: String, reliable: Boolean,
    ): Grid {
        val rs = IntArray(ROWS)
        val re = IntArray(ROWS)
        val cs = IntArray(COLS)
        val ce = IntArray(COLS)
        for (i in 0 until ROWS) {
            val cy = rfit[0] + rfit[1] * i
            rs[i] = max(0, (cy - rfit[1] * 0.46f).roundToInt())
            re[i] = min(h - 1, (cy + rfit[1] * 0.46f).roundToInt())
        }
        for (i in 0 until COLS) {
            val cx = cfit[0] + cfit[1] * i
            cs[i] = max(0, (cx - cfit[1] * 0.46f).roundToInt())
            ce[i] = min(w - 1, (cx + cfit[1] * 0.46f).roundToInt())
        }
        return Grid(rs, re, cs, ce, how, rfit[1].roundToInt(), cfit[1].roundToInt(), reliable)
    }

    private fun medianPitch(w2: IntArray, need: Int): Int {
        if (need < 2) return 0
        var sum = 0
        for (i in 0 until need) sum += w2[i * 2 + 1] - w2[i * 2] + 1
        return sum / need
    }

    /** 墨迹范围 → 6 等分（什么都切不出来时兜底，至少不会全空） */
    private fun uniformGrid(
        lum: ShortArray, w: Int, h: Int,
        px0: Int, py0: Int, px1: Int, py1: Int, thr: Int,
    ): Grid? {
        var x0 = Int.MAX_VALUE
        var y0 = Int.MAX_VALUE
        var x1 = -1
        var y1 = -1
        for (y in py0..py1) {
            val o = y * w
            for (x in px0..px1) {
                if (at(lum, o + x) < thr) {
                    if (x < x0) x0 = x
                    if (x > x1) x1 = x
                    if (y < y0) y0 = y
                    if (y > y1) y1 = y
                }
            }
        }
        if (x1 <= x0 || y1 <= y0) return null
        if (x1 - x0 < 60 || y1 - y0 < 60) return null
        val cw = (x1 - x0 + 1).toFloat() / COLS
        val chh = (y1 - y0 + 1).toFloat() / ROWS
        return Grid(
            IntArray(ROWS) { (y0 + chh * it).toInt() },
            IntArray(ROWS) { (y0 + chh * (it + 1)).toInt() - 1 },
            IntArray(COLS) { (x0 + cw * it).toInt() },
            IntArray(COLS) { (x0 + cw * (it + 1)).toInt() - 1 },
            "均分兜底",
            chh.roundToInt(), cw.roundToInt(),
        )
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

    /**
     * 把若干条带子的**中心**拟合到等距点阵：中心 = a + i·p。
     *
     * 为什么只信中心：投影切出来的带子可能被拆成两半（宽字的左右两半各成一条），
     * 也可能因为某格被装饰包围而变宽，**宽窄**不可信；但"这条带子在哪"基本没错。
     * 条数多于需要时取残差最小的一组，条数不足直接放弃（交给后面的兜底）。
     */
    private fun fitLattice(b: List<IntArray>, need: Int, maxRes: Float = 0.22f): FloatArray? {
        if (b.size < need) return null
        var bestRes = Float.MAX_VALUE
        var bestA = 0f
        var bestP = 0f
        for (i in 0..(b.size - need)) {
            val first = (b[i][0] + b[i][1]) / 2f
            val last = (b[i + need - 1][0] + b[i + need - 1][1]) / 2f
            val p = (last - first) / (need - 1)
            if (p < 8f) continue
            var res = 0f
            for (j in 0 until need) {
                val c = (b[i + j][0] + b[i + j][1]) / 2f
                res += abs(c - (first + p * j))
            }
            res /= need
            if (res < bestRes) {
                bestRes = res
                bestA = first
                bestP = p
            }
        }
        if (bestP <= 0f) return null
        // 残差太大说明这些带子根本不在一条等距线上
        if (bestRes > bestP * maxRes) return null
        return floatArrayOf(bestA, bestP)
    }
}

/** 一次 OCR 词表：文本 + 包围盒中心（拼板坐标系）+ ML Kit 给的置信度（<0 表示没给） */
data class Word(val text: String, val cx: Int, val cy: Int, val conf: Float = -1f)
