package com.wangchuan.fhlsearch.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.text.SpannableString
import android.text.Spanned
import android.text.style.BackgroundColorSpan
import android.text.style.ForegroundColorSpan
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.wangchuan.fhlsearch.R
import com.wangchuan.fhlsearch.databinding.ViewFhlActionsBinding
import com.wangchuan.fhlsearch.databinding.ViewFhlResultBinding

/** 结果行的三种版式 */
enum class RowKind {
    /** 单行文字（诗词，以及兜底） */
    SINGLE,

    /** 成语：三行卡片 —— 成语 / 带调拼音 / 声调：数字 */
    CHENGYU,

    /** 名士：左边名字，右边（朝代） */
    MINGSHI,
}

/** 结果区里的一行 */
data class ResultRow(
    /** 单行版式的文本，也用于长按复制 */
    val text: String = "",
    /** 单行版式里需要绿色标出的区间 */
    val highlights: List<IntRange> = emptyList(),
    /** 该行对应的原始数据（点选时回调 / 打开详情用） */
    val payload: Any? = null,
    val kind: RowKind = RowKind.SINGLE,
    /** 成语：4 个字 / 4 个带调拼音 / 4 个声调数字，以及被填过的位次 */
    val cyChars: List<String> = emptyList(),
    val cyPinyin: List<String> = emptyList(),
    val cyTone: List<String> = emptyList(),
    val cyHits: Set<Int> = emptySet(),
    /** 名士：名字与朝代分两列显示 */
    val msName: String = "",
    val msDynasty: String = "",
)

/** 结果区的按键与状态回调 */
interface ResultHost {
    /** 清空所有检索（回到初始状态） */
    fun onClearAll()

    /** 清空当前检索（回到上一级） */
    fun onClearCurrent()

    /** 二次检索（在当前结果范围内继续筛） */
    fun onSecondSearch()
}

/**
 * 检索结果区（三个模块共用）：结果标题（匹配结果 N）、结果卡片列表。
 *
 * 按键行（清空所有 / 清空当前 / 二次检索）在 v1.2 抽成了独立的 [ViewFhlActionsBinding]，
 * 由各页放在图一/图二要求的位置（成语在结果标题上方、名士在条件列表上方）——
 * 传 null 表示这一页不放按键行（按键由别处控制）。
 *
 * 按键显隐规则（需求原文）：
 *   结果 ≥2 条 → 清空所有 + 清空当前 + 二次检索
 *   结果 =1 条 → 清空所有 + 清空当前
 *   结果 =0 条 → 提示语 + 清空所有 + 清空当前
 */
class ResultView(
    private val binding: ViewFhlResultBinding,
    private val actions: ViewFhlActionsBinding?,
    private val host: ResultHost,
) {
    private val adapter = RowAdapter()

    /** 点选某一行时回调（诗词用来切高亮、名士用来打开详情） */
    var onRowPicked: ((ResultRow, Int) -> Unit)? = null

    /** 是否显示"二次检索"键（诗词模块没有层级检索，永远不显示） */
    var secondSearchEnabled: Boolean = true

    /** "清空当前"按键的文案（名士模块曾用"返回上一级检索"） */
    var clearCurrentLabel: CharSequence? = null

    var rows: List<ResultRow> = emptyList()
        private set

    init {
        binding.rvResult.layoutManager = LinearLayoutManager(binding.root.context)
        binding.rvResult.adapter = adapter
        actions?.let { a ->
            a.btnClearAll.setOnClickListener { host.onClearAll() }
            a.btnClearCurrent.setOnClickListener { host.onClearCurrent() }
            a.btnSecondSearch.setOnClickListener { host.onSecondSearch() }
        }
    }

    /**
     * 结果列表嵌在"整页翻页"里时调用（名士手机页）：
     * 列表自己不再滚动，高度按内容撑开，滚动交给外层 NestedScrollView。
     */
    fun embedInPageScroll() {
        binding.rvResult.isNestedScrollingEnabled = false
        binding.rvResult.layoutParams = binding.rvResult.layoutParams.apply {
            height = ViewGroup.LayoutParams.WRAP_CONTENT
        }
    }

    /** 初始空态：只显示一句提示，按键隐藏 */
    fun showInitial(hint: CharSequence) {
        rows = emptyList()
        adapter.notifyDataSetChanged()
        binding.layStatus.visibility = View.GONE
        actions?.root?.visibility = View.GONE
        binding.tvEmpty.visibility = View.VISIBLE
        binding.tvEmpty.text = hint
    }

    /** 结果为空（已检索但没命中） */
    fun showEmpty(message: CharSequence) {
        rows = emptyList()
        adapter.notifyDataSetChanged()
        binding.layStatus.visibility = View.GONE
        binding.tvEmpty.visibility = View.VISIBLE
        binding.tvEmpty.text = message
        actions?.root?.visibility = View.VISIBLE
        actions?.btnSecondSearch?.visibility = View.GONE
        actions?.btnClearCurrent?.visibility = View.VISIBLE
        applyClearCurrentLabel()
    }

    /**
     * 展示结果。
     * @param countText 结果标题，如"匹配结果 (25)"
     * @param secondBarText 二次检索的范围提示；null 表示不显示
     */
    fun show(rows: List<ResultRow>, countText: CharSequence?, secondBarText: CharSequence? = null) {
        this.rows = rows
        adapter.notifyDataSetChanged()

        binding.tvEmpty.visibility = View.GONE
        if (countText != null) {
            binding.layStatus.visibility = View.VISIBLE
            binding.tvResultCount.text = countText
        } else {
            binding.layStatus.visibility = View.GONE
        }
        binding.tvSecondBar.visibility = if (secondBarText != null) View.VISIBLE else View.GONE
        binding.tvSecondBar.text = secondBarText

        actions?.root?.visibility = View.VISIBLE
        actions?.btnClearCurrent?.visibility = View.VISIBLE
        applyClearCurrentLabel()
        actions?.btnSecondSearch?.visibility =
            if (secondSearchEnabled && rows.size >= 2) View.VISIBLE else View.GONE
    }

    private fun applyClearCurrentLabel() {
        clearCurrentLabel?.let { actions?.btnClearCurrent?.text = it }
    }

    private inner class RowAdapter : RecyclerView.Adapter<RowAdapter.VH>() {
        private var selected = -1

        override fun getItemViewType(position: Int): Int = when (rows[position].kind) {
            RowKind.CHENGYU -> TYPE_CY
            RowKind.MINGSHI -> TYPE_MS
            RowKind.SINGLE -> TYPE_SINGLE
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
            val layout = when (viewType) {
                TYPE_CY -> R.layout.item_fhl_cy_result
                TYPE_MS -> R.layout.item_fhl_ms_result
                else -> R.layout.item_fhl_result
            }
            return VH(LayoutInflater.from(parent.context).inflate(layout, parent, false))
        }

        override fun getItemCount(): Int = rows.size

        override fun onBindViewHolder(holder: VH, position: Int) {
            val row = rows[position]
            val v = holder.itemView
            when (row.kind) {
                RowKind.CHENGYU -> bindChengyu(v, row)
                RowKind.MINGSHI -> bindMingshi(v, row)
                RowKind.SINGLE -> bindSingle(v, row)
            }
            v.isSelected = position == selected
            v.setOnClickListener {
                val old = selected
                selected = holder.bindingAdapterPosition
                if (old >= 0) notifyItemChanged(old)
                notifyItemChanged(selected)
                onRowPicked?.invoke(row, selected)
            }
            v.setOnLongClickListener {
                copyToClipboard(v.context, row.text.ifEmpty { row.msName })
                true
            }
        }

        // ------------------------------------------------------------ 三种版式
        private fun bindSingle(v: View, row: ResultRow) {
            val tv = v.findViewById<TextView>(R.id.tvText)
            tv.text = highlight(row.text, row.highlights, v.context)
        }

        private fun bindChengyu(v: View, row: ResultRow) {
            v.findViewById<TextView>(R.id.tvCyWord).text =
                mark(row.cyChars, row.cyHits, "", null, v.context)
            v.findViewById<TextView>(R.id.tvCyPinyin).text =
                mark(row.cyPinyin, row.cyHits, " ", null, v.context)
            v.findViewById<TextView>(R.id.tvCyTone).text =
                mark(row.cyTone, row.cyHits, " ", v.context.getString(R.string.cy_tone_prefix), v.context)
        }

        private fun bindMingshi(v: View, row: ResultRow) {
            v.findViewById<TextView>(R.id.tvMsName).text = row.msName
            v.findViewById<TextView>(R.id.tvMsDynasty).text =
                v.context.getString(R.string.ms_dynasty_suffix, row.msDynasty)
        }

        // ------------------------------------------------------------ 标绿工具
        /** 给指定区间加浅绿底 + 深绿字 */
        private fun highlight(text: String, ranges: List<IntRange>, ctx: Context): CharSequence {
            if (ranges.isEmpty()) return text
            val sp = SpannableString(text)
            ranges.forEach { r -> span(sp, r.first, r.last + 1, ctx) }
            return sp
        }

        /**
         * 把若干片段拼起来，命中的片段标绿。
         * @param prefix 行首固定文字（如"声调："），不参与标绿
         */
        private fun mark(
            parts: List<String>,
            hits: Set<Int>,
            sep: String,
            prefix: String?,
            ctx: Context,
        ): CharSequence {
            if (parts.isEmpty()) return prefix.orEmpty()
            val sb = StringBuilder(prefix.orEmpty())
            val ranges = ArrayList<IntRange>()
            parts.forEachIndexed { i, s ->
                if (hits.contains(i)) ranges.add(sb.length until sb.length + s.length)
                sb.append(s)
                if (i < parts.lastIndex) sb.append(sep)
            }
            if (ranges.isEmpty()) return sb.toString()
            val sp = SpannableString(sb)
            ranges.forEach { r -> span(sp, r.first, r.last + 1, ctx) }
            return sp
        }

        private fun span(sp: SpannableString, start: Int, end: Int, ctx: Context) {
            val s = start.coerceIn(0, sp.length)
            val e = end.coerceIn(s, sp.length)
            if (s >= e) return
            sp.setSpan(
                BackgroundColorSpan(ContextCompat.getColor(ctx, R.color.fhl_green_bg)),
                s, e, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
            )
            sp.setSpan(
                ForegroundColorSpan(ContextCompat.getColor(ctx, R.color.fhl_green_text)),
                s, e, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
            )
        }

        private fun copyToClipboard(ctx: Context, text: String) {
            val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            cm.setPrimaryClip(ClipData.newPlainText("忘川检索", text))
            com.wangchuan.fhlsearch.util.Toasts.show(ctx, ctx.getString(R.string.copy_done))
        }

        inner class VH(v: View) : RecyclerView.ViewHolder(v)
    }

    private companion object {
        const val TYPE_SINGLE = 0
        const val TYPE_CY = 1
        const val TYPE_MS = 2
    }
}
