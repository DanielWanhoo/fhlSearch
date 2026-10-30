package com.wangchuan.fhlsearch.ui

import android.content.res.Configuration
import android.os.Bundle
import android.text.InputFilter
import android.text.InputType
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import androidx.core.widget.doAfterTextChanged
import androidx.fragment.app.Fragment
import com.google.android.material.textfield.TextInputEditText
import com.google.android.material.textfield.TextInputLayout
import com.wangchuan.fhlsearch.FhlApp
import com.wangchuan.fhlsearch.R
import com.wangchuan.fhlsearch.data.ChengyuItem
import com.wangchuan.fhlsearch.databinding.FragmentFhlChengyuBinding
import com.wangchuan.fhlsearch.databinding.ViewFhlResultBinding
import com.wangchuan.fhlsearch.logic.ChengyuLogic
import com.wangchuan.fhlsearch.logic.CyKind
import com.wangchuan.fhlsearch.logic.CyResult
import com.wangchuan.fhlsearch.ui.sheet.InfoSheetFragment
import com.wangchuan.fhlsearch.util.PinyinTone
import com.wangchuan.fhlsearch.util.Toasts

/**
 * 模块一：成语检索（山石雅集第 14 题）
 *
 * 需求要点（v3.2 起）：
 *  - 声调 / 拼音 / 单字 三组**同屏常显**，每组 4 格，对应成语的第 1~4 个字；
 *    不再用「拼音 / 声调 / 单字」页签切换；
 *  - 检索时三组条件**同时**生效：同一位置填了多种时需同时满足，整组留空表示不限；
 *  - 结果逐字对齐：声调 / 拼音 / 单字 从上到下三行、靠左，填过的位次标绿；
 *  - 检索完成后输入框内容**保留**；层级检索（二次检索在上一层结果里筛）逻辑不变；
 *  - 手机端出结果后输入区自动折叠成一行条件摘要（按键仍在），点摘要可展开继续改。
 */
class ChengyuFragment : Fragment(), ResultHost {

    private var _b: FragmentFhlChengyuBinding? = null
    private val b get() = _b!!

    /** 三组的顺序＝界面上从上到下的顺序：声调 → 拼音 → 单字 */
    private val kinds = listOf(CyKind.TONE, CyKind.PINYIN, CyKind.CHAR)

    /** 每种各 4 格（第 i 格对应成语第 i+1 个字） */
    private val etGrid = LinkedHashMap<CyKind, List<TextInputEditText>>()
    private val tilGrid = LinkedHashMap<CyKind, List<TextInputLayout>>()

    private lateinit var result: ResultView

    private var all: List<ChengyuItem> = emptyList()

    /** 检索层级栈：pool 为该层的结果范围 */
    private val levels = ArrayList<List<ChengyuItem>>()

    /** 每一层对应的"命中位次"：退回上一层时要把绿色标注一并恢复 */
    private val levelHits = ArrayList<List<Set<CyKind>>>()

    private var searchCount = 0

    /** 用户是否手动展开了条件区（折叠后点摘要切换） */
    private var formExpanded = false

    /** 手机单栏才折叠；平板双栏本来就有地方放条件 */
    private val isPhoneLayout: Boolean
        get() = resources.configuration.smallestScreenWidthDp != Configuration.SMALLEST_SCREEN_WIDTH_DP_UNDEFINED &&
            resources.configuration.smallestScreenWidthDp < 600

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?,
    ): View {
        _b = FragmentFhlChengyuBinding.inflate(inflater, container, false)
        return b.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        b.header.tvTitle.setText(R.string.cy_title)
        b.header.tvSubtitle.setText(R.string.cy_subtitle)
        b.header.btnInfo.setOnClickListener { InfoSheetFragment.show(childFragmentManager) }

        result = ResultView(b.result as ViewFhlResultBinding, b.actions, this)
        result.secondSearchEnabled = true
        result.showInitial(getString(R.string.empty_chengyu))

        buildInputs()
        updateCountText()

        b.btnSearch.setOnClickListener { doSearch() }
        b.layCondSummary.setOnClickListener { onSummaryClick() }

        formExpanded = false
        syncFormState()           // 初始状态：无结果 → 条件区展开、摘要隐藏

        (requireActivity().application as FhlApp).whenReady { tiku ->
            if (tiku == null) {
                Toasts.show(requireContext(), getString(R.string.tip_tiku_error))
                return@whenReady
            }
            all = tiku.chengyu
        }
    }

    override fun onDestroyView() {
        super.onDestroyView()
        etGrid.clear()
        tilGrid.clear()
        _b = null
    }

    // ---------------------------------------------------------------- 构建控件
    /**
     * 三组各生成 4 个输入框（布局见 item_fhl_cy_input.xml / view_fhl_cy_form.xml）。
     * 三组常显，所以每组的键盘类型、字数限制在生成时就固定下来，不再随页签切换。
     */
    private fun buildInputs() {
        etGrid.clear()
        tilGrid.clear()
        kinds.forEach { kind ->
            val row = when (kind) {
                CyKind.TONE -> b.form.layTone
                CyKind.PINYIN -> b.form.layPinyin
                CyKind.CHAR -> b.form.layChar
            }
            row.removeAllViews()
            val ets = ArrayList<TextInputEditText>(ChengyuLogic.SLOTS)
            val tils = ArrayList<TextInputLayout>(ChengyuLogic.SLOTS)
            for (i in 0 until ChengyuLogic.SLOTS) {
                val item = layoutInflater.inflate(R.layout.item_fhl_cy_input, row, false)
                val til = item as TextInputLayout
                val et = item.findViewById<TextInputEditText>(R.id.etCell)
                val lp = til.layoutParams as LinearLayout.LayoutParams
                lp.marginStart = if (i == 0) 0 else dp(5)
                lp.marginEnd = if (i == ChengyuLogic.SLOTS - 1) 0 else dp(5)
                til.layoutParams = lp

                et.filters = arrayOf(
                    InputFilter.LengthFilter(maxLen(kind))
                )
                et.inputType = if (kind == CyKind.TONE) {
                    InputType.TYPE_CLASS_NUMBER
                } else {
                    InputType.TYPE_CLASS_TEXT
                }
                til.hint = getString(hintOf(kind))
                et.setOnEditorActionListener { _, _, _ ->
                    doSearch(); true
                }
                et.doAfterTextChanged {
                    til.error = null
                    til.setBoxBackgroundColorResource(R.color.fhl_input_fill)
                }
                row.addView(til)
                ets.add(et)
                tils.add(til)
            }
            etGrid[kind] = ets
            tilGrid[kind] = tils
        }
    }

    private fun maxLen(kind: CyKind): Int = when (kind) {
        CyKind.PINYIN -> 6
        CyKind.TONE -> 1
        CyKind.CHAR -> 1
    }

    private fun hintOf(kind: CyKind): Int = when (kind) {
        CyKind.PINYIN -> R.string.cy_hint_pinyin
        CyKind.TONE -> R.string.cy_hint_tone
        CyKind.CHAR -> R.string.cy_hint_char
    }

    private fun cellsOf(kind: CyKind): List<String> =
        etGrid[kind].orEmpty().map { it.text?.toString().orEmpty().trim() }

    // ---------------------------------------------------------------- 条件区折叠
    /**
     * 条件区的三种状态（只有手机单栏会折叠，平板一直显示）：
     *  - 还没有结果：摘要隐藏、条件区展开；
     *  - 出结果后：条件区收起成一行「检索条件」摘要，按键留在结果区上方；
     *  - 点摘要：在"收起"与"展开修改"之间切换，展开时摘要仍在（可以再收起）。
     */
    private fun syncFormState() {
        val phone = isPhoneLayout
        val hasResult = levels.isNotEmpty()
        val showSummary = phone && hasResult
        val showForm = !phone || !hasResult || formExpanded

        b.layForm.visibility = if (showForm) View.VISIBLE else View.GONE
        b.layCondSummary.visibility = if (showSummary) View.VISIBLE else View.GONE
        // 第十一轮的规则照旧：出过结果就先收起「检索」，接着筛用上方的「二次检索」；
        // 清空到没有结果时再把它放出来（否则用户改完条件不知道点哪儿）
        b.btnSearch.visibility = if (hasResult) View.GONE else View.VISIBLE
        if (showSummary) {
            b.tvCondSummary.text = summaryText()
            b.tvSummaryToggle.setText(
                if (formExpanded) R.string.cy_cond_collapse else R.string.cy_cond_expand
            )
        }
    }

    private fun onSummaryClick() {
        if (!isPhoneLayout) return
        formExpanded = !formExpanded
        syncFormState()
    }

    /**
     * 折叠摘要里的条件文字（对齐演示稿「第 1 位 声 1」的写法）：
     * 只列填过的位次，同一位置填了多种就并在一行。
     */
    private fun summaryText(): CharSequence {
        val tones = cellsOf(CyKind.TONE)
        val pinyins = cellsOf(CyKind.PINYIN)
        val chars = cellsOf(CyKind.CHAR)
        val parts = ArrayList<String>(ChengyuLogic.SLOTS)
        for (i in 0 until ChengyuLogic.SLOTS) {
            val bits = ArrayList<String>(3)
            if (tones[i].isNotEmpty()) bits.add(getString(R.string.cy_sum_tone, tones[i]))
            if (pinyins[i].isNotEmpty()) bits.add(getString(R.string.cy_sum_pinyin, pinyins[i]))
            if (chars[i].isNotEmpty()) bits.add(getString(R.string.cy_sum_char, chars[i]))
            if (bits.isNotEmpty()) {
                parts.add(getString(R.string.cy_sum_pos, i + 1, bits.joinToString(" ")))
            }
        }
        return parts.joinToString("　")
    }

    private fun labelOf(kind: CyKind): Int = when (kind) {
        CyKind.PINYIN -> R.string.cy_mode_pinyin
        CyKind.TONE -> R.string.cy_mode_tone
        CyKind.CHAR -> R.string.cy_mode_char
    }

    // ---------------------------------------------------------------- 检索
    /**
     * 校验三组共 12 格：
     *  - 任一组有非法字符 → 标红该格 + 提示"非法字符"，返回 null；
     *  - 单字多输 → 只留第一个字；
     *  - 三组全空 → 提示"请至少填写一个条件"，返回 null。
     */
    private fun validated(): Boolean {
        if (all.isEmpty()) {
            Toasts.show(requireContext(), getString(R.string.tip_tiku_error))
            return false
        }
        for (kind in kinds) {
            val bad = ChengyuLogic.firstIllegal(kind, cellsOf(kind))
            if (bad >= 0) {
                tilGrid[kind]?.getOrNull(bad)?.apply {
                    error = getString(R.string.tip_illegal_char)
                    setBoxBackgroundColorResource(R.color.fhl_vermilion_tint)
                }
                Toasts.show(requireContext(), getString(R.string.tip_illegal_char))
                return false
            }
        }
        // 单字组多输的只留第一个字（长度限制已挡掉大部分，粘贴进来时兜底）
        etGrid[CyKind.CHAR].orEmpty().forEach { et ->
            val t = et.text?.toString().orEmpty()
            if (t.length > 1) {
                et.setText(t.substring(0, 1))
                et.setSelection(1)
            }
        }
        if (ChengyuLogic.isEmpty(cellsOf(CyKind.TONE), cellsOf(CyKind.PINYIN), cellsOf(CyKind.CHAR))) {
            Toasts.show(requireContext(), getString(R.string.tip_need_condition))
            return false
        }
        return true
    }

    /** 首次检索：全库筛；之后按层级，在上一层结果里筛 */
    private fun doSearch() {
        if (!validated()) return
        runSearch(levels.lastOrNull(), narrowedFrom = null)
    }

    /**
     * 二次检索：**立刻**用当前输入，在"上一次的结果"里再筛一次并给出新结果。
     * （不是"进入待筛状态、还要再按一次检索"——那样点了像没反应。）
     */
    override fun onSecondSearch() {
        if (levels.isEmpty()) {
            doSearch()
            return
        }
        if (!validated()) return
        val pool = levels.last()
        runSearch(pool, narrowedFrom = pool.size)
    }

    /** 检索并展示（两个入口共用） */
    private fun runSearch(pool: List<ChengyuItem>?, narrowedFrom: Int?) {
        val res = ChengyuLogic.search(
            cellsOf(CyKind.TONE),
            cellsOf(CyKind.PINYIN),
            cellsOf(CyKind.CHAR),
            all,
            pool,
        )

        searchCount++
        // 没命中就不入栈：否则候选范围被清空，之后怎么改条件都搜不出来
        if (res.items.isNotEmpty()) {
            levels.add(res.items)
            levelHits.add(res.hitKinds)
            formExpanded = false     // 新结果出来 → 回到折叠状态，把地方让给结果
        }
        updateCountText()
        render(res, narrowedFrom)
        syncFormState()              // 出结果 → 折叠；没出结果 → 保持展开
    }

    private fun render(res: CyResult, narrowedFrom: Int? = null) {
        if (res.items.isEmpty()) {
            result.showEmpty(getString(R.string.cy_no_result))
            return
        }
        val rows = res.items.map { item -> resultRow(item, res.hitKinds) }
        val countText = getString(R.string.cy_result_count, res.items.size)
        val secondBar = narrowedFrom?.let { getString(R.string.cy_second_search_bar, it) }
        result.show(rows, countText, secondBar)
    }

    /**
     * 一行结果 = 一张四列卡片（v3.2 逐字对齐）：
     *   每列竖排 声调 / 拼音 / 单字；被填过的位次在整列标绿。
     */
    private fun resultRow(item: ChengyuItem, hits: List<Set<CyKind>>): ResultRow {
        val pinyin = item.pinyin.indices.map { PinyinTone.mark(item.pinyin[it] + item.tone[it]) }
        return ResultRow(
            // 长按复制用的整行文本
            text = item.word + "   " + pinyin.joinToString(" ") + "   " + item.tone.joinToString(" "),
            payload = item,
            kind = RowKind.CHENGYU,
            cyChars = item.chars,
            cyPinyin = pinyin,
            cyTone = item.tone,
            cyHits = hits,
        )
    }

    private fun updateCountText() {
        b.header.tvCount.text = getString(R.string.count_times, searchCount)
    }

    // ---------------------------------------------------------------- 结果区按键
    override fun onClearAll() {
        searchCount = 0
        levels.clear()
        levelHits.clear()
        formExpanded = false
        kinds.forEach { kind ->
            etGrid[kind].orEmpty().forEach { it.setText("") }
            tilGrid[kind].orEmpty().forEach {
                it.error = null
                it.setBoxBackgroundColorResource(R.color.fhl_input_fill)
            }
        }
        result.showInitial(getString(R.string.empty_chengyu))
        updateCountText()
        syncFormState()          // 回到初始状态 → 条件区展开、摘要隐藏
    }

    override fun onClearCurrent() {
        if (levels.isEmpty()) return
        levels.removeAt(levels.size - 1)
        if (levelHits.isNotEmpty()) levelHits.removeAt(levelHits.size - 1)
        // 注意：这里**不清空输入框**——用户往往是在原条件上继续调整，
        // 把内容擦掉会逼他重打一遍（这正是之前"点二次检索内容就没了"的问题）。
        val prev = levels.lastOrNull()
        if (prev == null) {
            result.showInitial(getString(R.string.empty_chengyu))
            formExpanded = false
        } else {
            result.show(
                prev.map { resultRow(it, levelHits.lastOrNull() ?: emptyList()) },
                getString(R.string.cy_result_count, prev.size),
                null,
            )
        }
        syncFormState()
    }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()
}
