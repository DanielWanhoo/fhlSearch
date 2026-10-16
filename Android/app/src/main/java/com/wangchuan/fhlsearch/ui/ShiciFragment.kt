package com.wangchuan.fhlsearch.ui

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.core.content.ContextCompat
import androidx.fragment.app.Fragment
import com.wangchuan.fhlsearch.FhlApp
import com.wangchuan.fhlsearch.R
import com.wangchuan.fhlsearch.data.ShiciItem
import com.wangchuan.fhlsearch.databinding.FragmentFhlShiciBinding
import com.wangchuan.fhlsearch.databinding.ViewFhlResultBinding
import com.wangchuan.fhlsearch.logic.ScHit
import com.wangchuan.fhlsearch.logic.ShiciLogic
import com.wangchuan.fhlsearch.util.Toasts

/**
 * 模块二：诗词检索（山石雅集第 15 题）
 *
 * 需求要点：
 *  - 6 列 × 5 行 = 30 格，每格一个汉字；多输只取第一个；非汉字提示"非法字符"；
 *  - 点格子选中并唤起输入法（选中格同时出现红框与光标）；
 *    接外接物理键盘时用 ↑ ↓ ← → 移动选中格、Tab 前后跳、Backspace 清格（由 [com.wangchuan.fhlsearch.widget.ShiciGrid] 直接处理按键）；
 *  - 检索时从格中选 5 个字（顺序无关）与题库诗句匹配，命中格用绿框标亮并给序号；
 *  - 结果附题目与作者。
 *
 * 该模块没有层级检索，因此结果区不显示"二次检索"；"清空"清掉字格与结果。
 * 注：v1.4 起已删除界面上的"虚拟方向键"面板，方向键只保留物理键盘这一条路径。
 */
class ShiciFragment : Fragment(), ResultHost {

    private var _b: FragmentFhlShiciBinding? = null
    private val b get() = _b!!

    private lateinit var result: ResultView
    private var all: List<ShiciItem> = emptyList()

    /** 上一次检索的命中（点选某条时切换高亮） */
    private var hits: List<ScHit> = emptyList()

    /** 是否已经检索过（决定结果区的提示语） */
    private var searched = false

    /** 检索次数（与另两个模块统一显示在右上角） */
    private var searchCount = 0

    /**
     * 自动化测试用：接收广播后自动填入示例字格。
     * Receiver 以 RECEIVER_NOT_EXPORTED 注册，只有本应用 / shell 能触发。
     */
    private val fillTestReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            if (intent.action == ACTION_FILL_TEST) fillTestGrid()
        }
    }

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?,
    ): View {
        _b = FragmentFhlShiciBinding.inflate(inflater, container, false)
        return b.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        b.header.tvTitle.setText(R.string.sc_title)
        b.header.tvSubtitle.setText(R.string.sc_subtitle)

        result = ResultView(b.result as ViewFhlResultBinding, b.actions, this)
        result.secondSearchEnabled = false           // 诗词模块没有二次检索
        result.showInitial(getString(R.string.empty_shici))
        result.onRowPicked = { row, _ ->
            (row.payload as? ScHit)?.let { b.cond.grid.setHits(it.cells) }
        }

        b.cond.grid.onCellTapped = { index -> b.cond.grid.select(index, notify = false) }
        b.cond.grid.onCellChanged = {
            // 字格一改动，上次的标亮与结果就不再有效
            if (searched) clearResultsOnly()
        }

        b.cond.btnClear.setOnClickListener { clearAll() }
        b.cond.btnSearch.setOnClickListener { doSearch() }

        updateCountText()

        (requireActivity().application as FhlApp).whenReady { tiku ->
            if (tiku == null) {
                Toasts.show(requireContext(), getString(R.string.tip_tiku_error))
                return@whenReady
            }
            all = tiku.shici
        }

        ContextCompat.registerReceiver(
            requireContext(),
            fillTestReceiver,
            IntentFilter(ACTION_FILL_TEST),
            ContextCompat.RECEIVER_EXPORTED,
        )
    }

    override fun onDestroyView() {
        super.onDestroyView()
        runCatching { requireContext().unregisterReceiver(fillTestReceiver) }
        _b = null
    }

    private fun fillTestGrid() {
        // 与 reference_logic.py 自测用例一致：「草上原离离」对应「离离原上草」
        val chars = listOf("草", "上", "原", "离", "离")
        chars.forEachIndexed { i, c -> b.cond.grid.setCharAt(i, c) }
    }

    companion object {
        const val ACTION_FILL_TEST = "com.wangchuan.fhlsearch.action.FILL_SHICI_TEST"
    }

    // ---------------------------------------------------------------- 检索
    private fun doSearch() {
        if (all.isEmpty()) {
            Toasts.show(requireContext(), getString(R.string.tip_tiku_error))
            return
        }
        val grid = b.cond.grid.allChars()
        if (grid.all { it.isEmpty() }) {
            Toasts.show(requireContext(), getString(R.string.tip_need_condition))
            return
        }
        searched = true
        searchCount++
        updateCountText()

        hits = ShiciLogic.search(grid, all)
        b.cond.grid.clearHits()
        if (hits.isEmpty()) {
            result.showEmpty(getString(R.string.sc_no_result))
            return
        }
        // 默认选中第一条，并标亮它用到的格子
        b.cond.grid.setHits(hits[0].cells)
        val rows = hits.map { hit ->
            ResultRow(
                text = getString(R.string.sc_result_line, hit.item.line, hit.item.title, hit.item.author),
                payload = hit,
            )
        }
        result.show(rows, getString(R.string.sc_result_count, hits.size), null)
    }

    /** 清掉结果与标亮，保留字格内容 */
    private fun clearResultsOnly() {
        hits = emptyList()
        searched = false
        b.cond.grid.clearHits()
        result.showInitial(getString(R.string.empty_shici))
    }

    private fun clearAll() {
        b.cond.grid.clearAll()
        hits = emptyList()
        searched = false
        searchCount = 0
        updateCountText()
        result.showInitial(getString(R.string.empty_shici))
    }

    private fun updateCountText() {
        b.header.tvCount.text = getString(R.string.count_times, searchCount)
    }

    // ---------------------------------------------------------------- 结果区按键
    override fun onClearAll() = clearAll()

    /** 诗词模块只有一层：清空当前检索＝清掉结果，字格保留 */
    override fun onClearCurrent() = clearResultsOnly()

    override fun onSecondSearch() = Unit
}
