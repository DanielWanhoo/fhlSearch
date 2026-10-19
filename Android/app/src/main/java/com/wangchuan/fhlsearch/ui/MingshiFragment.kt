package com.wangchuan.fhlsearch.ui

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import androidx.fragment.app.Fragment
import androidx.fragment.app.setFragmentResultListener
import com.google.android.material.button.MaterialButton
import com.wangchuan.fhlsearch.FhlApp
import com.wangchuan.fhlsearch.R
import com.wangchuan.fhlsearch.data.MingshiItem
import com.wangchuan.fhlsearch.databinding.FragmentFhlMingshiBinding
import com.wangchuan.fhlsearch.databinding.ViewFhlResultBinding
import com.wangchuan.fhlsearch.logic.MingshiLogic
import com.wangchuan.fhlsearch.logic.MsMode
import com.wangchuan.fhlsearch.ui.sheet.InfoSheetFragment
import com.wangchuan.fhlsearch.ui.sheet.InputSheetFragment
import com.wangchuan.fhlsearch.ui.sheet.MingshiDetailSheetFragment
import com.wangchuan.fhlsearch.ui.sheet.OptionSheetFragment
import com.wangchuan.fhlsearch.util.Toasts
import kotlin.math.max

/**
 * 模块三：名士检索（众里寻他）
 *
 * 需求要点：
 *  - 九种检索模式；朝代/爱好/社团/品阶 用**滚轮**选择，其余 5 种用输入框模糊检索；
 *  - 结果 1 条 → "名士（朝代）"，只给"清空所有检索"；
 *    结果 ≥2 条 → 全部列出，给"清空所有检索 / 返回上一级检索 / 二次检索"；
 *    无结果 → "未检索到该名士" + "清空所有检索"；
 *  - 点结果里的任意一行 → 弹出该名士的详情（全部属性 + 所有相关描述）；
 *  - 检索次数计数，清空所有检索时归零；
 *  - 二次检索时切换模式必须保留原有检索结果；
 *  - 检索键显隐：首次检索出结果后自动收起（之后都走"二次检索"），
 *    「清空所有」/「清空当前」退回初始状态时自动恢复。
 */
class MingshiFragment : Fragment(), ResultHost {

    /** 一个检索条件 */
    private class Cond(val mode: MsMode, val name: String) {
        var value: String? = null
        var applied = false          // 本轮是否已经参与过筛选
        lateinit var stateText: TextView
        lateinit var row: LinearLayout
    }

    private var _b: FragmentFhlMingshiBinding? = null
    private val b get() = _b!!

    private lateinit var result: ResultView
    private var all: List<MingshiItem> = emptyList()

    private val conds = ArrayList<Cond>()

    /** 当前正在打开面板（选项卡或输入框）的条件行，结果通过 FragmentResult 回写 */
    private var openingCond: Cond? = null

    /** 层级栈：每一层是当次"检索"筛选后的结果 */
    private val levels = ArrayList<List<MingshiItem>>()

    /** 当前层级用到的条件数（用于回到上一级时正确复位条件） */
    private val usedAtLevel = ArrayList<Int>()

    private var searchCount = 0

    private val dynastyOptions = listOf(
        "汉", "明", "秦", "三国", "宋", "唐", "五代十国", "西楚", "晋", "先秦", "梦", "南北朝", "清", "元", "辽"
    )
    private val loveOptions = listOf(
        "博文", "乐舞", "品茗", "赏玩", "食珍", "书画", "雅宴", "演武", "弈棋", "妆饰"
    )
    private val clubOptions = listOf(
        "百家书院", "千工苑", "金戈馆", "容华社", "棠梨坊", "饕餮居", "五湖商社", "逸趣社", "无"
    )
    private val rankOptions = listOf("天", "地", "玄")

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?,
    ): View {
        _b = FragmentFhlMingshiBinding.inflate(inflater, container, false)
        return b.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        b.header.tvTitle.setText(R.string.ms_title)
        b.header.tvSubtitle.setText(R.string.ms_subtitle)
        b.header.btnInfo.setOnClickListener { InfoSheetFragment.show(childFragmentManager) }

        result = ResultView(b.result as ViewFhlResultBinding, b.actions, this)
        result.secondSearchEnabled = true
        // 手机版是"整页翻页"：结果列表跟着整页一起滚，自己不单独滚动
        result.embedInPageScroll()
        result.showInitial(getString(R.string.empty_mingshi))
        // 点结果里的任意一行 → 弹出该名士的详情（全部属性 + 所有相关描述）
        result.onRowPicked = { row, _ ->
            (row.payload as? MingshiItem)?.let { item ->
                try {
                    MingshiDetailSheetFragment.newInstance(item)
                        .show(childFragmentManager, "ms_detail_${item.name}")
                } catch (e: Exception) {
                    android.util.Log.e("FhlSearch", "打开名士详情失败: ${item.name}", e)
                    Toasts.show(requireContext(), "无法打开详情：" + (e.message ?: e.javaClass.simpleName))
                }
            }
        }

        // 面板通过 childFragmentManager 弹出，因此监听器也要挂在 childFragmentManager 上
        childFragmentManager.setFragmentResultListener(
            OptionSheetFragment.REQ_KEY, viewLifecycleOwner
        ) { _, bundle ->
            val value = bundle.getString("value").orEmpty()
            openingCond?.let { cond ->
                cond.value = if (value.isEmpty()) null else value
                refreshRow(cond)
            }
            openingCond = null
        }
        childFragmentManager.setFragmentResultListener(
            InputSheetFragment.REQ_KEY, viewLifecycleOwner
        ) { _, bundle ->
            val value = bundle.getString("value").orEmpty()
            openingCond?.let { cond ->
                cond.value = if (value.isEmpty()) null else value
                refreshRow(cond)
            }
            openingCond = null
        }

        buildModeRows()
        updateCountText()
        updateSearchButton()

        b.btnSearch.setOnClickListener { doSearch() }

        (requireActivity().application as FhlApp).whenReady { tiku ->
            if (tiku == null) {
                Toasts.show(requireContext(), getString(R.string.tip_tiku_error))
                return@whenReady
            }
            all = tiku.mingshi
        }
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _b = null
    }

    // ---------------------------------------------------------------- 条件行
    private fun buildModeRows() {
        b.modes.layModeList.removeAllViews()
        conds.clear()

        val specs = listOf(
            MsMode.DYNASTY to getString(R.string.ms_mode_dynasty),
            MsMode.LOVE to getString(R.string.ms_mode_love),
            MsMode.CLUB to getString(R.string.ms_mode_club),
            MsMode.RANK to getString(R.string.ms_mode_rank),
            MsMode.JOB to getString(R.string.ms_mode_job),
            MsMode.BORN to getString(R.string.ms_mode_born),
            MsMode.ORIGIN to getString(R.string.ms_mode_origin),
            MsMode.SKILL to getString(R.string.ms_mode_skill),
            MsMode.OTHER to getString(R.string.ms_mode_other),
        )

        specs.forEach { (mode, name) ->
            val rowView = layoutInflater.inflate(R.layout.item_fhl_ms_mode, b.modes.layModeList, false)
            val cond = Cond(mode, name)
            cond.row = rowView as LinearLayout
            cond.stateText = rowView.findViewById(R.id.tvModeState)
            (rowView.findViewById<TextView>(R.id.tvModeName)).text = name
            rowView.findViewById<View>(R.id.tvArrow).visibility = View.VISIBLE
            rowView.setOnClickListener { openSheet(cond) }
            b.modes.layModeList.addView(rowView)
            conds.add(cond)
            refreshRow(cond)
        }
    }

    private fun isOptionMode(mode: MsMode) =
        mode == MsMode.DYNASTY || mode == MsMode.LOVE || mode == MsMode.CLUB || mode == MsMode.RANK

    private fun refreshRow(cond: Cond) {
        val v = cond.value
        if (v.isNullOrEmpty()) {
            cond.stateText.text = getString(if (isOptionMode(cond.mode)) R.string.ms_pick else R.string.ms_input)
            cond.stateText.setTextColor(requireContext().getColor(R.color.fhl_ink_hint))
        } else {
            cond.stateText.text = v
            cond.stateText.setTextColor(requireContext().getColor(R.color.fhl_vermilion))
        }
        updateAppliedLine()
        updateSearchButton()
    }

    /**
     * 图二里的「已检索：朝代：先秦」汇总行：把当前填了值的条件按顺序列出来。
     * 没有条件时不显示这一行。
     */
    private fun updateAppliedLine() {
        val parts = conds.filter { !it.value.isNullOrEmpty() }
            .map { "${it.name}：${it.value}" }
        if (parts.isEmpty()) {
            b.tvApplied.visibility = View.GONE
            return
        }
        val prefix = getString(R.string.ms_applied_prefix)
        val s = android.text.SpannableString(prefix + parts.joinToString("、"))
        s.setSpan(
            android.text.style.ForegroundColorSpan(
                requireContext().getColor(R.color.fhl_vermilion)
            ),
            prefix.length, s.length, android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
        )
        b.tvApplied.text = s
        b.tvApplied.visibility = View.VISIBLE
    }

    private fun openSheet(cond: Cond) {
        openingCond = cond
        val sheet = if (isOptionMode(cond.mode)) {
            OptionSheetFragment.newInstance(cond.name, optionsOf(cond.mode), cond.value)
        } else {
            InputSheetFragment.newInstance(cond.name, getString(R.string.ms_input_hint), cond.value)
        }
        try {
            sheet.show(childFragmentManager, "sheet_${cond.mode.key}")
        } catch (e: Exception) {
            // 面板弹不出来时给出明确提示，而不是静默失败
            openingCond = null
            android.util.Log.e("FhlSearch", "弹出面板失败: ${cond.mode.key}", e)
            Toasts.show(requireContext(), "无法打开面板：" + (e.message ?: e.javaClass.simpleName))
        }
    }

    private fun optionsOf(mode: MsMode): List<String> = when (mode) {
        MsMode.DYNASTY -> dynastyOptions
        MsMode.LOVE -> loveOptions
        MsMode.CLUB -> clubOptions
        MsMode.RANK -> rankOptions
        else -> emptyList()
    }

    // ---------------------------------------------------------------- 检索
    /** 首次检索：全库筛；之后按层级，在上一层结果里筛 */
    private fun doSearch() {
        applyPending(levels.lastOrNull() ?: all, narrowedFrom = null)
    }

    /**
     * 二次检索：**立刻**用"还没用上的新条件"在上一次结果里再筛一次并给出结果。
     * （不是"进入待筛状态、还要再按一次检索"——那样点了像没反应。）
     */
    override fun onSecondSearch() {
        if (levels.isEmpty()) {
            doSearch()
            return
        }
        val pool = levels.last()
        applyPending(pool, narrowedFrom = pool.size)
    }

    /** 把还没用上的条件依次叠加到 [base] 上并展示结果（两个检索入口共用） */
    private fun applyPending(base: List<MingshiItem>, narrowedFrom: Int?) {
        if (all.isEmpty()) {
            Toasts.show(requireContext(), getString(R.string.tip_tiku_error))
            return
        }
        val pending = conds.filter { !it.value.isNullOrEmpty() && !it.applied }
        if (pending.isEmpty()) {
            // 没有新条件可用：把页面滚回条件区，让用户直接看到该去哪儿挑
            Toasts.show(
                requireContext(),
                getString(
                    if (narrowedFrom != null) R.string.ms_need_new_condition
                    else R.string.tip_need_condition
                )
            )
            scrollToTop()
            return
        }
        var pool = base
        var used = 0
        pending.forEach { cond ->
            pool = MingshiLogic.search(cond.mode, cond.value!!, all, pool)
            cond.applied = true
            used++
        }
        searchCount++
        // 没命中就不入栈：否则候选范围被清空，之后怎么改条件都搜不出来
        if (pool.isNotEmpty()) {
            levels.add(pool)
            usedAtLevel.add(used)
        }
        updateCountText()
        render(pool, narrowedFrom)
        updateSearchButton()
    }

    /**
     * 检索键的显隐：
     *  - 还没检索过、或已经退回初始层（没有可继续筛的结果）→ 显示；
     *  - 一旦检索出结果就自动收起：此后"检索"与"二次检索"做的事完全一样
     *    （都是把新条件叠到这一层结果上），留着只是白占一块地方；
     *  - 「清空所有」、以及「清空当前」退到最后一层之下时 → 自动恢复。
     *
     * 注意：没命中的检索不入层（levels 没变），所以首次就没命中时检索键保持显示，
     * 用户可以直接改条件再按——不会被"藏起来的键"卡住。
     */
    private fun updateSearchButton() {
        b.btnSearch.visibility = if (levels.isEmpty()) View.VISIBLE else View.GONE
    }

    private fun render(pool: List<MingshiItem>, narrowedFrom: Int? = null) {
        if (pool.isEmpty()) {
            result.showEmpty(getString(R.string.ms_no_result))
            scrollToResults()
            return
        }
        result.show(
            mingshiRows(pool),
            getString(R.string.ms_result_count, pool.size),
            narrowedFrom?.let { getString(R.string.ms_second_search_bar, it) },
        )
        scrollToResults()
    }

    /**
     * 手机版是整页翻页，条件列表（九行）占满一屏，检索完结果在折叠线以下，
     * 所以检索后自动把「匹配结果」滚进视野；反过来点"二次检索"要挑新条件时，滚回顶部。
     * 平板上结果在右栏，找不到滚动容器，会自动跳过。
     */
    private fun pageScroll(): androidx.core.widget.NestedScrollView? {
        var v: View? = b.result.root
        while (v != null && v !is androidx.core.widget.NestedScrollView) {
            v = v.parent as? View
        }
        return v as? androidx.core.widget.NestedScrollView
    }

    private fun scrollToResults() {
        runCatching {
            val sv = pageScroll() ?: return
            sv.post { sv.smoothScrollTo(0, (b.result.root.top - dp(8)).coerceAtLeast(0)) }
        }
    }

    private fun scrollToTop() {
        runCatching {
            val sv = pageScroll() ?: return
            sv.post { sv.smoothScrollTo(0, 0) }
        }
    }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    /** 图二样式的结果行：左边名士名，右边（朝代） */
    private fun mingshiRows(pool: List<MingshiItem>) = pool.map { item ->
        ResultRow(
            text = item.label,
            payload = item,
            kind = RowKind.MINGSHI,
            msName = item.name,
            msDynasty = item.dynasty,
        )
    }

    private fun updateCountText() {
        b.header.tvCount.text = getString(R.string.count_times, searchCount)
    }

    // ---------------------------------------------------------------- 结果区按键
    override fun onClearAll() {
        searchCount = 0
        levels.clear()
        usedAtLevel.clear()
        conds.forEach {
            it.value = null
            it.applied = false
            refreshRow(it)
        }
        updateCountText()
        result.showInitial(getString(R.string.empty_mingshi))
        updateSearchButton()          // 回到初始状态 → "检索"键恢复
        scrollToTop()
    }

    override fun onClearCurrent() {
        if (levels.isEmpty()) return
        levels.removeAt(levels.size - 1)
        val used = if (usedAtLevel.isNotEmpty()) usedAtLevel.removeAt(usedAtLevel.size - 1) else 0
        // 复位上一层用到的条件标记（保留用户已选的值，便于重新筛）
        var left = used
        for (i in conds.indices.reversed()) {
            if (left <= 0) break
            if (conds[i].applied) {
                conds[i].applied = false
                left--
            }
        }
        val prev = levels.lastOrNull()
        if (prev == null) {
            result.showInitial(getString(R.string.empty_mingshi))
        } else {
            render(prev)
        }
        updateSearchButton()      // 退到最后一层之下 → "检索"键恢复
    }
}
