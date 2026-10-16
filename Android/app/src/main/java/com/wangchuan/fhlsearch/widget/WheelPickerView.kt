package com.wangchuan.fhlsearch.widget

import android.content.Context
import android.graphics.Typeface
import android.util.AttributeSet
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.PagerSnapHelper
import androidx.recyclerview.widget.RecyclerView
import com.wangchuan.fhlsearch.R
import kotlin.math.abs

/**
 * 滚轮选择器（名士检索里「朝代 / 爱好 / 社团 / 品阶」四个选项型条件用）。
 *
 * 实现要点：
 *  - RecyclerView + [PagerSnapHelper]：松手后自动对齐到最近一行，形成"一格格滚"的手感；
 *  - 上下各留半个可视高度的内边距且 clipToPadding=false，这样第一项和最后一项也能滚到正中间；
 *  - 离中线越远的行越淡越小，配合中间那条"选中带"，做出滚轮的纵深；
 *  - 选中判定只在滚动停止时做一次，避免滚动过程中频繁刷新列表。
 */
class WheelPickerView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : FrameLayout(context, attrs) {

    private val recycler: RecyclerView
    private val adapter = WheelAdapter()
    private val itemHeight: Int = resources.getDimensionPixelSize(R.dimen.fhl_wheel_item_h)

    private var options: List<String> = emptyList()

    /** 选中项变化时回调（下标, 文本） */
    var onSelected: ((index: Int, value: String) -> Unit)? = null

    /** 当前正中那一项的下标（-1 表示空） */
    var selectedIndex: Int = -1
        private set

    /** 当前选中的文本；无选项时为 null */
    val selectedValue: String?
        get() = options.getOrNull(selectedIndex)

    init {
        // 中间"选中带"先加，滚轮文字叠在它上面
        val band = View(context).apply {
            background = ContextCompat.getDrawable(context, R.drawable.bg_fhl_wheel_band)
        }
        addView(band, LayoutParams(LayoutParams.MATCH_PARENT, itemHeight, Gravity.CENTER_VERTICAL))

        recycler = RecyclerView(context).apply {
            layoutManager = LinearLayoutManager(context)
            adapter = this@WheelPickerView.adapter
            clipToPadding = false
            overScrollMode = OVER_SCROLL_NEVER
            isVerticalScrollBarEnabled = false
            setHasFixedSize(true)
            itemAnimator = null
        }
        PagerSnapHelper().attachToRecyclerView(recycler)
        addView(recycler, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))

        recycler.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(rv: RecyclerView, dx: Int, dy: Int) {
                updateFalloff()
            }

            override fun onScrollStateChanged(rv: RecyclerView, newState: Int) {
                if (newState == RecyclerView.SCROLL_STATE_IDLE) settle()
            }
        })

        addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> applyPadding() }
    }

    /** 设定候选项；[selected] 命中则滚到该项，否则停在第一项 */
    fun setOptions(items: List<String>, selected: String?) {
        options = items
        val hit = items.indexOf(selected)
        selectedIndex = if (items.isEmpty()) -1 else if (hit >= 0) hit else 0
        adapter.notifyDataSetChanged()
        if (selectedIndex >= 0) {
            recycler.scrollToPosition(selectedIndex)
            post { updateFalloff() }
        }
    }

    /** 上下留白 = (可视高度 - 一行高度) / 2，保证首尾也能居中 */
    private fun applyPadding() {
        val pad = ((height - itemHeight) / 2).coerceAtLeast(0)
        if (recycler.paddingTop != pad) {
            recycler.setPadding(0, pad, 0, pad)
            if (selectedIndex >= 0) recycler.scrollToPosition(selectedIndex)
            post { updateFalloff() }
        }
    }

    /** 滚动中：按离中线的距离改每一行的透明度与缩放（只改视觉，不动数据） */
    private fun updateFalloff() {
        if (itemHeight <= 0 || recycler.childCount == 0) return
        val center = (recycler.paddingTop + recycler.height - recycler.paddingBottom) / 2
        for (i in 0 until recycler.childCount) {
            val child = recycler.getChildAt(i)
            val d = abs((child.top + child.bottom) / 2 - center)
            // 距离 0 → 1.0；超过约一行半 → 0.35（变淡变小）
            val f = (1f - d.toFloat() / (itemHeight * 1.6f)).coerceIn(0.35f, 1f)
            child.alpha = f
            val s = 0.82f + 0.18f * f
            child.scaleX = s
            child.scaleY = s
        }
    }

    /** 滚动停止：取正中那一项作为选中项 */
    private fun settle() {
        updateFalloff()
        if (itemHeight <= 0 || recycler.childCount == 0) return
        val center = (recycler.paddingTop + recycler.height - recycler.paddingBottom) / 2
        var best = -1
        var bestD = Int.MAX_VALUE
        for (i in 0 until recycler.childCount) {
            val child = recycler.getChildAt(i)
            val d = abs((child.top + child.bottom) / 2 - center)
            if (d < bestD) {
                bestD = d
                best = recycler.getChildAdapterPosition(child)
            }
        }
        if (best < 0 || best == selectedIndex) return
        applySelection(best, scroll = false)
    }

    /**
     * 选中某一项（[scroll] 为真时把它滚到正中）。
     * 除了滑动滚轮，直接点某一项也会走到这里——点选手感比反复滑更方便。
     */
    private fun applySelection(index: Int, scroll: Boolean) {
        if (index !in options.indices) return
        val old = selectedIndex
        if (old != index) {
            selectedIndex = index
            if (old >= 0) adapter.notifyItemChanged(old)
            adapter.notifyItemChanged(index)
            performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
            onSelected?.invoke(index, options.getOrElse(index) { "" })
        }
        if (scroll) recycler.smoothScrollToPosition(index)
    }

    private inner class WheelAdapter : RecyclerView.Adapter<WheelAdapter.VH>() {

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
            val v = LayoutInflater.from(parent.context)
                .inflate(R.layout.item_fhl_wheel, parent, false)
            return VH(v)
        }

        override fun getItemCount(): Int = options.size

        override fun onBindViewHolder(holder: VH, position: Int) {
            val selected = position == selectedIndex
            holder.text.text = options[position]
            holder.text.setTextColor(
                ContextCompat.getColor(
                    context,
                    if (selected) R.color.fhl_vermilion else R.color.fhl_ink
                )
            )
            holder.text.setTypeface(null, if (selected) Typeface.BOLD else Typeface.NORMAL)
            // 直接点某一项 = 选中它并滚到正中
            holder.itemView.setOnClickListener {
                val pos = holder.bindingAdapterPosition
                if (pos != RecyclerView.NO_POSITION) applySelection(pos, scroll = true)
            }
        }

        inner class VH(v: View) : RecyclerView.ViewHolder(v) {
            val text: TextView = v.findViewById(R.id.tvWheelItem)
        }
    }
}
