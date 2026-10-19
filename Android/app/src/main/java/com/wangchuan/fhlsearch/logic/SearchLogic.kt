package com.wangchuan.fhlsearch.logic

import com.wangchuan.fhlsearch.data.ChengyuItem
import com.wangchuan.fhlsearch.data.MingshiItem
import com.wangchuan.fhlsearch.data.ShiciItem

/**
 * 三大模块的检索逻辑（纯函数，与 tools/reference_logic.py 的语义逐条对齐）。
 *
 * 这个文件不依赖任何 Android API，因此可以直接用单元测试验证——
 * 测试用例与 tools/reference_logic.py --selftest 的断言一一对应。
 */

// ==================================================================== 成语检索
enum class CyMode { PINYIN, TONE, CHAR }

data class CyResult(
    val items: List<ChengyuItem>,
    /** 用户填了内容的位次（0..3），用于结果里的绿色标注 */
    val hitPositions: Set<Int>,
)

object ChengyuLogic {

    private val PINYIN_RE = Regex("[A-Za-z]+")
    private val TONE_RE = Regex("[1-4]")
    private val CHAR_RE = Regex("[\\u4e00-\\u9fff]")

    /** 校验四格输入，返回第一个非法格的序号（全部合法返回 -1）。 */
    fun firstIllegal(mode: CyMode, cells: List<String>): Int {
        cells.forEachIndexed { i, raw ->
            val c = raw.trim()
            if (c.isEmpty()) return@forEachIndexed
            val ok = when (mode) {
                CyMode.PINYIN -> PINYIN_RE.matches(c)
                CyMode.TONE -> TONE_RE.matches(c)
                CyMode.CHAR -> CHAR_RE.matches(c)
            }
            if (!ok) return i
        }
        return -1
    }

    fun isEmpty(cells: List<String>): Boolean = cells.all { it.trim().isEmpty() }

    /**
     * 在 [pool]（为空表示全库）中检索。
     * 拼音＝连续子串模糊匹配（大小写不敏感）；声调/单字＝精确相等；空格子＝该位不限。
     * 结果≥2 条时按第 1 字拼音升序。
     */
    fun search(
        mode: CyMode,
        cells: List<String>,
        all: List<ChengyuItem>,
        pool: List<ChengyuItem>? = null,
    ): CyResult {
        require(cells.size == 4) { "成语检索需要 4 个输入格" }
        if (isEmpty(cells)) throw IllegalArgumentException("请至少填写一个条件")

        val hits = cells.indices.filter { cells[it].trim().isNotEmpty() }.toSet()
        val src = pool ?: all
        val out = ArrayList<ChengyuItem>()
        for (it in src) {
            var ok = true
            for (i in 0 until 4) {
                val c = cells[i].trim()
                ok = when (mode) {
                    CyMode.PINYIN -> c.isEmpty() || it.pinyin[i].contains(c, ignoreCase = true)
                    CyMode.TONE -> c.isEmpty() || it.tone[i] == c
                    CyMode.CHAR -> c.isEmpty() || it.chars[i] == c
                }
                if (!ok) break
            }
            if (ok) out.add(it)
        }
        val sorted = if (out.size >= 2) {
            out.sortedWith(compareBy({ it.pinyin[0] }, { it.word }))
        } else out
        return CyResult(sorted, hits)
    }
}

// ==================================================================== 诗词检索
data class ScHit(val item: ShiciItem, val cells: List<Int>)

/**
 * "认不准就按题库对一次"的结果：[cells] 是该诗句 5 个字各自落在哪一格（与 [item.chars] 一一对应），
 * [fill] 是需要写字的格子（原本空着、或认成了别的字），[emptyFill] 是其中原本空着的个数。
 */
data class ScRescue(
    val item: ShiciItem,
    val cells: List<Int>,
    val fill: List<Int>,
    val emptyFill: Int,
    /** 5 个字里，几格是"直接认对"的 */
    val strong: Int,
)

object ShiciLogic {

    /**
     * 从 30 格中为每条诗句找出 5 个互不相同的格子（与格内顺序无关）。
     * 诗句含重复字时，格内也必须有对应数量的相同字。
     */
    fun search(grid: List<String>, all: List<ShiciItem>): List<ScHit> {
        val pos = HashMap<String, MutableList<Int>>()
        grid.forEachIndexed { idx, ch ->
            if (ch.isNotEmpty()) pos.getOrPut(ch) { ArrayList() }.add(idx)
        }
        if (pos.isEmpty()) return emptyList()
        val out = ArrayList<ScHit>()
        for (it in all) {
            val used = assign(it.chars, pos)
            if (used != null) out.add(ScHit(it, used))
        }
        return out
    }

    /** 回溯分配：5 个字各占一个不同格子。 */
    private fun assign(
        chars: List<String>,
        pos: Map<String, List<Int>>,
    ): List<Int>? {
        val used = HashSet<Int>()
        val order = ArrayList<Int>(chars.size)

        fun bt(k: Int): Boolean {
            if (k == chars.size) return true
            for (idx in pos[chars[k]] ?: emptyList<Int>()) {
                if (!used.add(idx)) continue
                order.add(idx)
                if (bt(k + 1)) return true
                order.removeAt(order.size - 1)
                used.remove(idx)
            }
            return false
        }

        return if (bt(0)) order.toList() else null
    }

    /**
     * 图片识别专用：30 格填了字、却一条诗句都没命中时的"按题库对一次"。
     *
     * 为什么会走到这里：30 格里通常只错/空一两个字，而诗句要求 5 个字全在，
     * 只要错一个字就查不到。这里改成"哪条诗句的 5 个字最可能就在格子里"：
     *  - 直接认对的格子算"强命中"（2 分）；
     *  - 这格几趟识别里出现过这个字，算"弱命中"（1 分）；
     *  - 空格子算"要补字"（0 分）。
     *
     * 只有**最优的一条**（总分 ≥ [MIN_SCORE]，且明显好于第二名）才认，
     * 否则返回 null —— 宁可提示"没找到"，也不瞎给一条错诗句。
     */
    fun rescue(
        grid: List<String>,
        candidates: List<Set<Char>>,
        all: List<ShiciItem>,
    ): ScRescue? {
        if (grid.isEmpty()) return null
        val n = grid.size
        // 每种字能落在哪些格子：先强命中，再弱命中，最后空格
        val strongMap = HashMap<Char, MutableList<Int>>()
        val weakMap = HashMap<Char, MutableList<Int>>()
        val blanks = ArrayList<Int>()
        for (i in 0 until n) {
            val prim = grid.getOrNull(i)?.firstOrNull()
            if (prim != null) strongMap.getOrPut(prim) { ArrayList() }.add(i) else blanks.add(i)
            for (c in candidates.getOrNull(i).orEmpty()) {
                if (c != prim) weakMap.getOrPut(c) { ArrayList() }.add(i)
            }
        }

        var top: ScRescue? = null
        var topScore = -1
        var topStrong = -1
        var secondScore = -1
        var secondStrong = -1
        for (item in all) {
            val chars = item.chars.map { it[0] }
            // 空格子对每个字都是"0 分选项"，取前几个就够了（再多也没用，最多补 1 个字）
            val blankOpts = blanks.take(chars.size).map { intArrayOf(it, 0) }
            val opts: Array<List<IntArray>> = Array(chars.size) { k ->
                val c = chars[k]
                val out = ArrayList<IntArray>()
                strongMap[c]?.forEach { out.add(intArrayOf(it, 2)) }
                weakMap[c]?.forEach { out.add(intArrayOf(it, 1)) }
                out.addAll(blankOpts)
                out
            }
            val r = bestAssign(opts) ?: continue
            val score = r.first
            val cells = r.second
            var strong = 0
            for ((k, idx) in cells.withIndex()) {
                if (grid.getOrNull(idx)?.firstOrNull() == chars[k]) strong++
            }
            if (score > topScore || (score == topScore && strong > topStrong)) {
                if (top != null) {
                    secondScore = topScore
                    secondStrong = topStrong
                }
                topScore = score
                topStrong = strong
                val fill = ArrayList<Int>()
                var emptyFill = 0
                for ((k, idx) in cells.withIndex()) {
                    if (grid.getOrNull(idx)?.firstOrNull() != chars[k]) {
                        fill.add(idx)
                        if (grid.getOrNull(idx).isNullOrEmpty()) emptyFill++
                    }
                }
                top = ScRescue(item, cells.toList(), fill, emptyFill, strong)
            } else if (score > secondScore || (score == secondScore && strong > secondStrong)) {
                secondScore = score
                secondStrong = strong
            }
        }

        val winner = top ?: return null
        // 至少 4 个直接认对（8 分），否则不足以说服人
        if (topScore < MIN_RESCUE_SCORE) return null
        // 和次优的一条分不开 → 宁可不猜
        if (secondScore == topScore && secondStrong == topStrong) return null
        // 要改/补的格子最多 1 个，多了等于替用户编字
        if (winner.fill.size > 1) return null
        return winner
    }

    /**
     * 5 个字各挑一格（格子不能重复），总分最高的一种挑法。
     * [opts] 每项是 (格子下标, 分值) 列表；返回 (总分, 每格下标数组)。
     */
    private fun bestAssign(opts: Array<List<IntArray>>): Pair<Int, IntArray>? {
        val size = opts.size
        if (opts.any { it.isEmpty() }) return null
        var bestScore = -1
        val cur = IntArray(size)
        val bestCells = IntArray(size)
        val used = HashSet<Int>()
        var nodes = 0

        fun bt(k: Int, score: Int) {
            if (nodes++ > 20000) return
            // 剩下的字全按 2 分算也追不上，剪掉
            if (score + (size - k) * 2 <= bestScore) return
            if (k == size) {
                bestScore = score
                System.arraycopy(cur, 0, bestCells, 0, size)
                return
            }
            for (o in opts[k]) {
                if (!used.add(o[0])) continue
                cur[k] = o[0]
                bt(k + 1, score + o[1])
                used.remove(o[0])
            }
        }
        bt(0, 0)
        return if (bestScore < 0) null else bestScore to bestCells.copyOf()
    }

    /** 救回来的门槛：4 个直接认对 + 1 个（弱的/补的）＝8 分 */
    private const val MIN_RESCUE_SCORE = 8
}

// ==================================================================== 名士检索
/** 名士的九种检索模式 */
enum class MsMode(val key: String) {
    DYNASTY("dynasty"),
    LOVE("love"),
    CLUB("club"),
    RANK("rank"),
    JOB("job"),
    BORN("born"),
    ORIGIN("origin"),
    SKILL("skill"),
    OTHER("other"),
}

object MingshiLogic {

    private val CJK = Regex("[\\u4e00-\\u9fff]")

    /** 归一化：只保留汉字（忽略标点、空格、换行、字母、数字） */
    fun hanOnly(text: String?): String =
        if (text.isNullOrEmpty()) "" else CJK.findAll(text).joinToString("") { it.value }

    /**
     * @param value 选项名（朝代/爱好/社团/品阶）或输入框文本（其余 5 种）
     * @param pool  上一次检索的结果；为 null 表示在全部名士里筛
     */
    fun search(
        mode: MsMode,
        value: String,
        all: List<MingshiItem>,
        pool: List<MingshiItem>? = null,
    ): List<MingshiItem> {
        val v = value.trim()
        require(v.isNotEmpty()) { "请先选择或输入检索条件" }
        val src = pool ?: all
        return when (mode) {
            // 「辽」题库无数据；「五代十国」按包含匹配命中"五代十国（南唐）"
            MsMode.DYNASTY -> if (v == "辽") emptyList() else src.filter { it.dynasty.contains(v) }
            MsMode.LOVE -> src.filter { it.love.contains(v) }
            MsMode.CLUB -> src.filter { it.club.contains(v) }
            MsMode.RANK -> src.filter { it.rank == v }
            MsMode.OTHER -> {
                val nv = hanOnly(v)
                if (nv.isEmpty()) emptyList()
                else src.filter { it.descNorm.any { d -> d.contains(nv) } }
            }
            else -> {
                val nv = hanOnly(v)
                if (nv.isEmpty()) emptyList()
                else src.filter { it.norm[mode.key]?.contains(nv) == true }
            }
        }
    }
}
