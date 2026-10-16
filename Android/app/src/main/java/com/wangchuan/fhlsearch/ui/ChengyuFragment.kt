package com.wangchuan.fhlsearch.ui

import android.os.Bundle
import android.text.InputFilter
import android.text.InputType
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import androidx.core.widget.doAfterTextChanged
import androidx.fragment.app.Fragment
import com.google.android.material.button.MaterialButton
import com.google.android.material.tabs.TabLayout
import com.google.android.material.textfield.TextInputEditText
import com.google.android.material.textfield.TextInputLayout
import com.wangchuan.fhlsearch.FhlApp
import com.wangchuan.fhlsearch.R
import com.wangchuan.fhlsearch.data.ChengyuItem
import com.wangchuan.fhlsearch.databinding.FragmentFhlChengyuBinding
import com.wangchuan.fhlsearch.databinding.ViewFhlResultBinding
import com.wangchuan.fhlsearch.logic.ChengyuLogic
import com.wangchuan.fhlsearch.logic.CyMode
import com.wangchuan.fhlsearch.util.PinyinTone
import com.wangchuan.fhlsearch.util.Toasts

/**
 * 模块一：成语检索（山石雅集第 14 题）
 *
 * 需求要点：
 *  - 拼音 / 声调 / 单字 三种模式，各 4 个输入框；拼音模糊，声调与单字精确；
 *  - 层级检索：首次在全库筛，之后在上一层结果里筛；
 *  - 结果里把用户填了内容的位次，在汉字 / 拼音 / 声调三处同时标绿；
 *  - 按键规则：≥2 条给"清空所有 / 清空当前 / 二次检索"，=1 条或 0 条不给"二次检索"；
 *  - 检索键显隐：首次检索出结果后自动收起（之后都走"二次检索"），
 *    「清空所有」/「清空当前」退回初始状态时自动恢复。
 */
class ChengyuFragment : Fragment(), ResultHost {

    private var _b: FragmentFhlChengyuBinding? = null
    private val b get() = _b!!

    private val ets = ArrayList<TextInputEditText>(4)
    private val tils = ArrayList<TextInputLayout>(4)

    private lateinit var result: ResultView

    private var all: List<ChengyuItem> = emptyList()
    private var mode = CyMode.PINYIN

    /** 各模式各自记住的输入内容（切模式不丢内容） */
    private val modeInputs = HashMap<CyMode, List<String>>()

    /** 检索层级栈：pool 为该层的结果范围 */
    private val levels = ArrayList<List<ChengyuItem>>()

    /** 每一层对应的"命中位次"：退回上一层时要把绿色标注一并恢复 */
    private val levelHits = ArrayList<Set<Int>>()

    private var searchCount = 0

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?,
    ): View {
        _b = FragmentFhlChengyuBinding.inflate(inflater, container, false)
        return b.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        b.header.tvTitle.setText(R.string.cy_title)
        b.header.tvSubtitle.setText(R.string.cy_subtitle)

        result = ResultView(b.result as ViewFhlResultBinding, b.actions, this)
        result.secondSearchEnabled = true
        result.showInitial(getString(R.string.empty_chengyu))

        buildTabs()
        buildInputs()
        updateCountText()

        b.btnSearch.setOnClickListener { doSearch() }
        updateSearchButton()      // 初始状态：检索键显示

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
        _b = null
    }

    // ---------------------------------------------------------------- 构建控件
    private fun buildTabs() {
        val names = listOf(R.string.cy_mode_pinyin, R.string.cy_mode_tone, R.string.cy_mode_char)
        names.forEachIndexed { i, res ->
            val tab = b.tabMode.newTab().setText(res)
            b.tabMode.addTab(tab, i == 0)
        }
        b.tabMode.addOnTabSelectedListener(object : TabLayout.OnTabSelectedListener {
            override fun onTabSelected(tab: TabLayout.Tab) {
                // 切换模式前先保存当前模式的内容，再恢复目标模式的内容
                modeInputs[mode] = currentCells()
                mode = CyMode.entries[tab.position]
                applyMode()
            }

            override fun onTabUnselected(tab: TabLayout.Tab) = Unit
            override fun onTabReselected(tab: TabLayout.Tab) = Unit
        })
    }

    private fun buildInputs() {
        b.layInputs.removeAllViews()
        ets.clear()
        tils.clear()
        // 需求：四个输入框分别对应成语的第 1~4 个字
        for (i in 0 until 4) {
            val item = layoutInflater.inflate(R.layout.item_fhl_cy_input, b.layInputs, false)
            val til = item as TextInputLayout
            val et = item.findViewById<TextInputEditText>(R.id.etCell)
            val lp = til.layoutParams as LinearLayout.LayoutParams
            lp.marginStart = if (i == 0) 0 else dp(5)
            lp.marginEnd = if (i == 3) 0 else dp(5)
            til.layoutParams = lp
            et.setOnEditorActionListener { _, _, _ ->
                doSearch(); true
            }
            et.doAfterTextChanged {
                til.error = null
                til.setBoxBackgroundColorResource(R.color.fhl_input_fill)
            }
            b.layInputs.addView(til)
            ets.add(et)
            tils.add(til)
        }
        applyMode()
    }

    /** 按当前模式设置输入限制与提示 */
    private fun applyMode() {
        val saved = modeInputs[mode] ?: listOf("", "", "", "")
        val hintRes = when (mode) {
            CyMode.PINYIN -> R.string.cy_hint_pinyin
            CyMode.TONE -> R.string.cy_hint_tone
            CyMode.CHAR -> R.string.cy_hint_char
        }
        ets.forEachIndexed { i, et ->
            et.filters = arrayOf(
                InputFilter.LengthFilter(
                    when (mode) {
                        CyMode.PINYIN -> 6
                        CyMode.TONE -> 1
                        CyMode.CHAR -> 1
                    }
                )
            )
            et.inputType = InputType.TYPE_CLASS_TEXT
            tils[i].hint = getString(hintRes)
            tils[i].error = null
            tils[i].setBoxBackgroundColorResource(R.color.fhl_input_fill)
            if (et.text?.toString() != saved[i]) et.setText(saved[i])
        }
    }

    private fun currentCells(): List<String> = ets.map { it.text?.toString().orEmpty().trim() }

    // ---------------------------------------------------------------- 检索
    /**
     * 校验当前 4 格输入：
     *  - 有非法字符 → 标红该格 + 提示"非法字符"，返回 null；
     *  - 单字模式多输 → 只留第一个字；
     *  - 全空 → 提示"请至少填写一个条件"，返回 null；
     * 通过则返回 trim 后的 4 格内容。
     */
    private fun validatedCells(): List<String>? {
        if (all.isEmpty()) {
            Toasts.show(requireContext(), getString(R.string.tip_tiku_error))
            return null
        }
        val cells = currentCells()
        val bad = ChengyuLogic.firstIllegal(mode, cells)
        if (bad >= 0) {
            tils[bad].error = getString(R.string.tip_illegal_char)
            tils[bad].setBoxBackgroundColorResource(R.color.fhl_vermilion_tint)
            Toasts.show(requireContext(), getString(R.string.tip_illegal_char))
            return null
        }
        // 单字模式：多输的只留第一个字（与需求一致）
        if (mode == CyMode.CHAR) {
            ets.forEachIndexed { i, et ->
                val t = et.text?.toString().orEmpty()
                if (t.length > 1) {
                    et.setText(t.substring(0, 1))
                    et.setSelection(1)
                }
            }
        }
        if (ChengyuLogic.isEmpty(currentCells())) {
            Toasts.show(requireContext(), getString(R.string.tip_need_condition))
            return null
        }
        return currentCells()
    }

    /** 首次检索：全库筛；之后按层级，在上一层结果里筛 */
    private fun doSearch() {
        val cells = validatedCells() ?: return
        runSearch(cells, levels.lastOrNull(), narrowedFrom = null)
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
        val cells = validatedCells() ?: return
        val pool = levels.last()
        runSearch(cells, pool, narrowedFrom = pool.size)
    }

    /** 检索并展示（两个入口共用） */
    private fun runSearch(
        cells: List<String>,
        pool: List<ChengyuItem>?,
        narrowedFrom: Int?,
    ) {
        val res = ChengyuLogic.search(mode, cells, all, pool)

        searchCount++
        // 没命中就不入栈：否则候选范围被清空，之后怎么改条件都搜不出来
        if (res.items.isNotEmpty()) {
            levels.add(res.items)
            levelHits.add(res.hitPositions)
        }
        modeInputs[mode] = cells
        updateCountText()
        render(res, narrowedFrom)
        updateSearchButton()      // 出结果了 → 收起检索键；没出结果（层没入栈）→ 保持显示
    }

    /**
     * 检索键的显隐：
     *  - 还没检索过、或已经退回初始层（没有可继续筛的结果）→ 显示；
     *  - 一旦检索出结果就自动收起：此后"检索"与"二次检索"做的事完全一样
     *    （都是在这一层结果里筛），留着只是白占一块地方，还把结果区挤小；
     *  - 「清空所有」、以及「清空当前」退到最后一层之下时 → 自动恢复。
     *
     * 注意：没命中的检索不入层（levels 仍为空），所以那种情况下检索键保持显示，
     * 用户可以直接改条件再按——不会被"藏起来的键"卡住。
     */
    private fun updateSearchButton() {
        b.btnSearch.visibility = if (levels.isEmpty()) View.VISIBLE else View.GONE
    }

    private fun render(res: com.wangchuan.fhlsearch.logic.CyResult, narrowedFrom: Int? = null) {
        if (res.items.isEmpty()) {
            result.showEmpty(getString(R.string.cy_no_result))
            return
        }
        val rows = res.items.map { item -> resultRow(item, res.hitPositions) }
        val countText = getString(R.string.cy_result_count, res.items.size)
        val secondBar = narrowedFrom?.let { getString(R.string.cy_second_search_bar, it) }
        result.show(rows, countText, secondBar)
    }

    /**
     * 一行结果 = 一张三行卡片（图一样式）：
     *   成语 / 带调拼音 / 声调：数字；被填过的位次在三处同时标绿。
     */
    private fun resultRow(item: ChengyuItem, hits: Set<Int>): ResultRow {
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
        modeInputs.clear()
        mode = CyMode.PINYIN
        b.tabMode.selectTab(b.tabMode.getTabAt(0))
        ets.forEachIndexed { i, et ->
            et.setText("")
            tils[i].error = null
            tils[i].setBoxBackgroundColorResource(R.color.fhl_input_fill)
        }
        result.showInitial(getString(R.string.empty_chengyu))
        updateCountText()
        updateSearchButton()      // 回到初始状态 → 检索键恢复
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
        } else {
            result.show(
                prev.map { resultRow(it, levelHits.lastOrNull() ?: emptySet()) },
                getString(R.string.cy_result_count, prev.size),
                null,
            )
        }
        updateSearchButton()      // 退到最后一层之下 → 检索键恢复
    }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()
}
