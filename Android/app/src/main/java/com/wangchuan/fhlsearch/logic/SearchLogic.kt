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
