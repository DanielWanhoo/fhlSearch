package com.wangchuan.fhlsearch

import com.wangchuan.fhlsearch.data.Tiku
import com.wangchuan.fhlsearch.logic.ChengyuLogic
import com.wangchuan.fhlsearch.logic.CyMode
import com.wangchuan.fhlsearch.logic.MingshiLogic
import com.wangchuan.fhlsearch.logic.MsMode
import com.wangchuan.fhlsearch.logic.ShiciLogic
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 三大模块检索逻辑的回归测试。
 *
 * 语料直接读取 App 内嵌的 assets JSON，因此测试跑的就是真实数据；
 * 断言与 tools/reference_logic.py --selftest 一一对应（两边结果必须一致）。
 */
class SearchLogicTest {

    private val chengyu by lazy { Tiku.parseChengyu(readAsset("tiku_chengyu.json")) }
    private val shici by lazy { Tiku.parseShici(readAsset("tiku_shici.json")) }
    private val mingshi by lazy { Tiku.parseMingshi(readAsset("tiku_mingshi.json")) }

    private fun readAsset(name: String): String =
        java.io.File("src/main/assets/$name").readText(Charsets.UTF_8)

    // ================================================================ 题库完整性
    @Test
    fun `题库规模与字段完整`() {
        assertEquals(319, chengyu.size)
        assertEquals(282, shici.size)
        assertEquals(115, mingshi.size)
        chengyu.forEach {
            assertEquals(4, it.word.length)
            assertEquals(4, it.pinyin.size)
            assertEquals(4, it.tone.size)
            assertEquals(4, it.chars.size)
            // 单字列应逐字等于成语本身（打包期现算的结果）
            assertEquals(it.word, it.chars.joinToString(""))
            it.tone.forEach { t -> assertTrue("声调必须是 1-4：$t", t in listOf("1", "2", "3", "4")) }
            it.pinyin.forEach { p -> assertEquals("拼音必须已转小写", p.lowercase(), p) }
        }
        shici.forEach {
            assertEquals(5, it.line.length)
            assertEquals(it.line, it.chars.joinToString(""))
            assertTrue("诗词名应带书名号", it.title.startsWith("《"))
            assertTrue(it.author.isNotEmpty())
        }
        mingshi.forEach {
            assertTrue(it.name.isNotEmpty())
            assertTrue(it.dynasty.isNotEmpty())
        }
    }

    // ================================================================ 成语检索
    @Test
    fun `拼音模糊匹配与命中位次`() {
        val r = ChengyuLogic.search(CyMode.PINYIN, listOf("an", "", "", ""), chengyu)
        assertEquals("拼音第 1 格 an 应为 53 条", 53, r.items.size)
        assertTrue(r.items.all { it.pinyin[0].contains("an") })
        assertEquals(setOf(0), r.hitPositions)

        val r2 = ChengyuLogic.search(CyMode.PINYIN, listOf("", "du", "", ""), chengyu)
        assertEquals(3, r2.items.size)
        assertTrue(r2.items.all { it.pinyin[1].contains("du") })

        // 大写输入同样命中（题库里 Shuang / Zhi 两处大写，且匹配大小写不敏感）
        val r3 = ChengyuLogic.search(CyMode.PINYIN, listOf("ZH", "", "", ""), chengyu)
        assertEquals(11, r3.items.size)
    }

    @Test
    fun `声调与单字精确匹配`() {
        val tone = ChengyuLogic.search(CyMode.TONE, listOf("4", "4", "2", "1"), chengyu)
        assertEquals(4, tone.items.size)
        assertTrue(tone.items.any { it.word == "暗渡陈仓" })

        val ch = ChengyuLogic.search(CyMode.CHAR, listOf("", "", "陈", ""), chengyu)
        assertEquals(1, ch.items.size)
        assertTrue(ch.items.all { it.chars[2] == "陈" })
    }

    @Test
    fun `层级检索在上一层结果内筛`() {
        val lv1 = ChengyuLogic.search(CyMode.PINYIN, listOf("zh", "", "", ""), chengyu)
        assertTrue(lv1.items.isNotEmpty())
        val lv2 = ChengyuLogic.search(CyMode.CHAR, listOf("", "", "", "定"), chengyu, lv1.items)
        assertTrue("二次检索结果必须是上一层结果的子集",
            lv2.items.all { it in lv1.items })
        assertTrue(lv2.items.all { it.pinyin[0].contains("zh") && it.chars[3] == "定" })
        // 同样的条件在同一层里再筛，结果不变
        val again = ChengyuLogic.search(CyMode.CHAR, listOf("", "", "", "定"), chengyu, lv2.items)
        assertEquals(lv2.items.size, again.items.size)
    }

    @Test
    fun `非法字符与空条件`() {
        assertEquals(1, ChengyuLogic.firstIllegal(CyMode.PINYIN, listOf("an", "d4", "", "")))
        assertEquals(-1, ChengyuLogic.firstIllegal(CyMode.PINYIN, listOf("an", "du", "", "")))
        assertEquals(1, ChengyuLogic.firstIllegal(CyMode.TONE, listOf("1", "5", "", "")))
        assertEquals(0, ChengyuLogic.firstIllegal(CyMode.CHAR, listOf("a", "", "", "")))
        assertEquals(-1, ChengyuLogic.firstIllegal(CyMode.CHAR, listOf("陈", "", "", "")))
        assertTrue(ChengyuLogic.isEmpty(listOf("", " ", "", "")))
        var threw = false
        try {
            ChengyuLogic.search(CyMode.PINYIN, listOf("", "", "", ""), chengyu)
        } catch (e: IllegalArgumentException) {
            threw = true
        }
        assertTrue("全空条件应抛异常", threw)
    }

    // ================================================================ 诗词检索
    @Test
    fun `五字顺序无关匹配`() {
        val grid = MutableList(30) { "" }
        "离离原上草".forEachIndexed { i, c -> grid[i] = c.toString() }
        val hits = ShiciLogic.search(grid, shici)
        val hit = hits.firstOrNull { it.item.line == "离离原上草" }
        assertNotNull("应命中「离离原上草」", hit)
        assertEquals("重复字要占用两个不同格子", listOf(0, 1, 2, 3, 4), hit!!.cells.sorted())

        // 打乱顺序填入，仍应命中
        val grid2 = MutableList(30) { "" }
        "草上原离离".forEachIndexed { i, c -> grid2[i * 3] = c.toString() }
        assertTrue(ShiciLogic.search(grid2, shici).any { it.item.line == "离离原上草" })
    }

    @Test
    fun `重复字不足时不命中`() {
        val grid = MutableList(30) { "" }
        "离原上草".forEachIndexed { i, c -> grid[i] = c.toString() }   // 只有一个「离」
        assertFalse(ShiciLogic.search(grid, shici).any { it.item.line == "离离原上草" })

        val grid2 = MutableList(30) { "" }
        "离原上草".forEachIndexed { i, c -> grid2[i * 2] = c.toString() }
        assertFalse(ShiciLogic.search(grid2, shici).any { it.item.line == "离离原上草" })
    }

    @Test
    fun `空格子不报错且无结果`() {
        assertEquals(0, ShiciLogic.search(MutableList(30) { "" }, shici).size)
    }

    // ================================================================ 图片识别后的"按题库补救"

    /** 30 格里只在指定位置填字（模拟识别结果） */
    private fun ocrGrid(filled: Map<Int, String>): List<String> =
        MutableList(30) { "" }.also { g -> filled.forEach { (i, c) -> g[i] = c } }

    @Test
    fun `缺一个字时按题库补全`() {
        // 「气蒸云梦泽」少了「云」：其余 4 个字都在格子里，正常检索查不到
        val grid = ocrGrid(mapOf(0 to "气", 1 to "蒸", 2 to "梦", 3 to "泽", 4 to "最"))
        assertEquals(0, ShiciLogic.search(grid, shici).size)
        val r = ShiciLogic.rescue(grid, List(30) { emptySet() }, shici)
        assertNotNull("四个字对得上、缺的字唯一，应当补出来", r)
        assertEquals("气蒸云梦泽", r!!.item.line)
        assertEquals("4 个字是直接认对的", 4, r.strong)
        assertEquals("只有 1 格要写字", 1, r.fill.size)
        assertEquals("这一格原本是空的", 1, r.emptyFill)
        assertEquals("5 个字要落在 5 个不同的格子里", 5, r.cells.toSet().size)
    }

    @Test
    fun `候选字里出现过也能救回来`() {
        // 本趟这格认成「最」，但另一趟在同一格认出了「云」
        val grid = ocrGrid(mapOf(0 to "气", 1 to "蒸", 2 to "梦", 3 to "泽", 4 to "最"))
        val cands = MutableList(30) { emptySet<Char>() }
        cands[4] = setOf('云', '最')
        val r = ShiciLogic.rescue(grid, cands, shici)
        assertNotNull(r)
        assertEquals("气蒸云梦泽", r!!.item.line)
        assertEquals("靠候选字命中，只需要把这格改回来", 1, r.fill.size)
        assertEquals("原本不是空格，不用补", 0, r.emptyFill)
        assertEquals(5, r.cells.toSet().size)
    }

    @Test
    fun `差两个字就不猜`() {
        // 只对上 3 个字，剩下全靠猜就不能认
        val grid = ocrGrid(mapOf(0 to "气", 1 to "蒸", 2 to "泽"))
        assertNull(ShiciLogic.rescue(grid, List(30) { emptySet() }, shici))
    }

    @Test
    fun `空格子太多时不猜`() {
        assertNull(ShiciLogic.rescue(MutableList(30) { "" }, List(30) { emptySet() }, shici))
        // 只有两格有字
        assertNull(ShiciLogic.rescue(
            ocrGrid(mapOf(0 to "气", 1 to "蒸")), List(30) { emptySet() }, shici,
        ))
    }

    // ================================================================ 名士检索
    @Test
    fun `选项型检索与包含匹配`() {
        val tang = MingshiLogic.search(MsMode.DYNASTY, "唐", mingshi)
        assertEquals(23, tang.size)
        assertTrue(tang.all { it.dynasty.contains("唐") })

        // 题库写作「五代十国（南唐）」，点「五代十国」要能命中
        val wd = MingshiLogic.search(MsMode.DYNASTY, "五代十国", mingshi)
        assertEquals(2, wd.size)
        assertTrue(wd.all { it.dynasty == "五代十国（南唐）" })

        // 题库没有辽代名士
        assertEquals(0, MingshiLogic.search(MsMode.DYNASTY, "辽", mingshi).size)

        assertEquals(33, MingshiLogic.search(MsMode.LOVE, "演武", mingshi).size)
        assertEquals(34, MingshiLogic.search(MsMode.CLUB, "金戈馆", mingshi).size)
        assertEquals(58, MingshiLogic.search(MsMode.RANK, "天", mingshi).size)
    }

    @Test
    fun `大乔无品阶`() {
        val daqiao = mingshi.first { it.name == "大乔" }
        assertEquals("", daqiao.rank)
        listOf("天", "地", "玄").forEach { r ->
            assertFalse(MingshiLogic.search(MsMode.RANK, r, mingshi).any { it.name == "大乔" })
        }
    }

    @Test
    fun `模糊检索忽略标点空格且不拆分检索词`() {
        val a = MingshiLogic.search(MsMode.BORN, "乱世", mingshi)
        assertEquals(8, a.size)
        assertEquals("带空格应与不带一致",
            a.size, MingshiLogic.search(MsMode.BORN, "乱 世", mingshi).size)

        val zf = MingshiLogic.search(MsMode.ORIGIN, "出身显贵", mingshi)
        assertEquals(6, zf.size)

        // 连续子串可命中
        assertTrue(MingshiLogic.search(MsMode.OTHER, "灭诸", mingshi).isNotEmpty())

        // 「（误导）」干扰项照常参与检索，检索词带不带标点结果一致
        val plain = MingshiLogic.search(MsMode.OTHER, "受到帝王重用", mingshi)
        val withMark = MingshiLogic.search(MsMode.OTHER, "受到帝王重用（误导）", mingshi)
        assertTrue(plain.isNotEmpty())
        assertEquals(plain.map { it.name }, withMark.map { it.name })
    }

    @Test
    fun `名士层级检索与结果格式`() {
        val lv1 = MingshiLogic.search(MsMode.DYNASTY, "唐", mingshi)
        val lv2 = MingshiLogic.search(MsMode.LOVE, "书画", mingshi, lv1)
        assertEquals("唐 → 书画 应为 2 位", 2, lv2.size)
        assertTrue(lv2.all { it.dynasty.contains("唐") && it.love.contains("书画") })
        val lv3 = MingshiLogic.search(MsMode.RANK, "天", mingshi, lv2)
        assertEquals(2, lv3.size)
        assertTrue(lv3.all { it in lv2 })
        assertEquals("嬴政（秦）", mingshi.first { it.name == "嬴政" }.label)
    }

    @Test
    fun `归一化只保留汉字`() {
        assertEquals("乱世", MingshiLogic.hanOnly("乱 世"))
        // 归一化只去标点，"（误导）"里的"误导"是汉字，会被保留
        assertEquals("出身显贵误导", MingshiLogic.hanOnly("出身显贵（误导）"))
        // 因此"出身显贵"作为子串依然能命中"出身显贵（误导）"
        assertTrue(MingshiLogic.hanOnly("出身显贵（误导）").contains(MingshiLogic.hanOnly("出身显贵")))
        assertEquals("", MingshiLogic.hanOnly("abc 123 ——"))
        assertEquals("在忘川赠吴地人士", MingshiLogic.hanOnly("在忘川赠\n吴地人士"))
    }

    @Test
    fun `空条件不产生结果`() {
        assertNull(null)
        var threw = false
        try {
            MingshiLogic.search(MsMode.JOB, "  ", mingshi)
        } catch (e: IllegalArgumentException) {
            threw = true
        }
        assertTrue(threw)
    }
}
