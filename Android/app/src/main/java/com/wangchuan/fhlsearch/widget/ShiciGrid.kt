package com.wangchuan.fhlsearch.widget

import android.content.Context
import android.util.AttributeSet
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout

/**
 * 诗词检索的 6 列 × 5 行 = 30 格字格。
 *
 * 交互（按需求确认的方案）：
 *  - 手指点格子 → 选中该格（朱砂方框）并弹出输入法；
 *  - 接物理键盘时 → ↑ ↓ ← → 移动选中格，Tab / Shift+Tab 前后移动，
 *    直接打字写入当前格，Backspace / Delete 清空当前格；
 *  - 选中格：红色方框；命中格：绿色方框 + 序号 ①②③④⑤。
 */
class ShiciGrid @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : LinearLayout(context, attrs) {

    companion object {
        const val COLS = 6
        const val ROWS = 5
        const val CELL_COUNT = COLS * ROWS
    }

    private val cells = ArrayList<GridCellView>(CELL_COUNT)

    /** 当前选中格（-1 表示未选中） */
    var selectedIndex: Int = -1
        private set

    /** 点击某个格子时回调（用于弹输入法） */
    var onCellTapped: ((index: Int) -> Unit)? = null

    /** 格子内容变化后回调（用于清掉旧的检索结果） */
    var onCellChanged: (() -> Unit)? = null

    init {
        orientation = VERTICAL
        gravity = Gravity.CENTER_HORIZONTAL
        for (r in 0 until ROWS) {
            val row = LinearLayout(context).apply {
                orientation = HORIZONTAL
                gravity = Gravity.CENTER
            }
            for (c in 0 until COLS) {
                val cell = GridCellView(context).apply { bind(r, c) }
                val lp = LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f).apply {
                    marginStart = dp(2)
                    marginEnd = dp(2)
                    topMargin = dp(2)
                    bottomMargin = dp(2)
                }
                cell.layoutParams = lp
                cell.setOnClickListener { select(indexOf(cell), focus = true, notify = true) }
                row.addView(cell)
                cells.add(cell)
            }
            addView(row, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
        }
    }

    // ---------------------------------------------------------------- 取值 / 赋值
    fun charAt(index: Int): String = cells[index].value

    /** 全部 30 格（空格为 ""） */
    fun allChars(): List<String> = cells.map { it.value }

    fun setCharAt(index: Int, text: String) {
        cells[index].setValue(text)
        onCellChanged?.invoke()
    }

    fun clearAll() {
        cells.forEach { it.setValue("") }
        clearHits()
        selectedIndex = -1
        cells.forEach { it.setCellSelected(false) }
        onCellChanged?.invoke()
    }

    /** 已填格数 */
    fun filledCount(): Int = cells.count { it.value.isNotEmpty() }

    // ---------------------------------------------------------------- 选中
    /**
     * 选中某一格。
     *
     * **输入焦点必须跟着选中格一起走**：否则用物理键盘方向键移动时只有边框动，
     * 光标和输入法还留在旧格子里——接着打出来的字会落到上一格。
     * [focus] 只决定"要不要顺带唤起输入法"，焦点转移无论如何都会做。
     */
    fun select(index: Int, focus: Boolean = true, notify: Boolean = false) {
        if (index !in 0 until CELL_COUNT) return
        cells.forEachIndexed { i, c -> c.setCellSelected(i == index) }
        selectedIndex = index
        cells[index].focusForTyping(showIme = focus)
        if (notify) onCellTapped?.invoke(index)
    }

    /** 方向键移动选中格 */
    fun move(dx: Int, dy: Int) {
        if (selectedIndex < 0) {
            select(0, focus = false, notify = false)
            return
        }
        val r = selectedIndex / COLS
        val c = selectedIndex % COLS
        val nr = (r + dy).coerceIn(0, ROWS - 1)
        val nc = (c + dx).coerceIn(0, COLS - 1)
        select(nr * COLS + nc, focus = false, notify = false)
    }

    /** 前进到下一个空格（用户连续填充时更顺手）；只转移焦点，不重复唤起输入法 */
    fun focusNextEmpty() {
        val start = if (selectedIndex < 0) 0 else selectedIndex + 1
        for (i in start until CELL_COUNT) {
            if (cells[i].value.isEmpty()) {
                select(i, focus = false, notify = false)
                return
            }
        }
    }

    // ---------------------------------------------------------------- 命中标亮
    /** 传入选中的那条诗句用到的格子与顺序；传空则清除全部标亮 */
    fun setHits(usedCells: List<Int>) {
        cells.forEachIndexed { i, c ->
            val order = usedCells.indexOf(i)
            c.setHit(order >= 0, if (order >= 0) order + 1 else 0)
        }
    }

    fun clearHits() = setHits(emptyList())

    // ---------------------------------------------------------------- 键盘
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action != KeyEvent.ACTION_DOWN) return super.dispatchKeyEvent(event)
        when (event.keyCode) {
            KeyEvent.KEYCODE_DPAD_UP -> { move(0, -1); return true }
            KeyEvent.KEYCODE_DPAD_DOWN -> { move(0, 1); return true }
            KeyEvent.KEYCODE_DPAD_LEFT -> { move(-1, 0); return true }
            KeyEvent.KEYCODE_DPAD_RIGHT -> { move(1, 0); return true }
            KeyEvent.KEYCODE_TAB -> {
                move(if (event.isShiftPressed) -1 else 1, 0); return true
            }
            KeyEvent.KEYCODE_DEL, KeyEvent.KEYCODE_FORWARD_DEL -> {
                if (selectedIndex >= 0) {
                    setCharAt(selectedIndex, "")
                }
                return true
            }
        }
        // 汉字输入：写到当前选中格，随后前进到下一个空格
        val ch = event.unicodeChar
        if (ch != 0 && selectedIndex >= 0) {
            val s = String(Character.toChars(ch))
            if (s.length == 1 && s[0] in '\u4e00'..'\u9fff') {
                setCharAt(selectedIndex, s)
                focusNextEmpty()
                return true
            }
        }
        return super.dispatchKeyEvent(event)
    }

    /**
     * 格子尺寸在测量阶段按可用宽度精确算出（限制 34~60dp），
     * 这样 30 个格子在手机上不会挤成一团，在平板上也不会过大。
     */
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val availW = MeasureSpec.getSize(widthMeasureSpec)
        if (availW > 0) {
            val perSide = dp(2)                 // 每格左右各 2dp 外边距
            val usable = availW - perSide * 2 * COLS - dp(2)
            val cell = (usable / COLS).coerceIn(dp(34), dp(60))
            var changed = false
            cells.forEach { c ->
                val lp = c.layoutParams as LayoutParams
                if (lp.height != cell || lp.width != 0) {
                    lp.width = 0                    // 宽度由 weight 平分，行宽固定
                    lp.height = cell
                    c.layoutParams = lp
                    c.applyTextSize(cell)
                    changed = true
                }
            }
            if (changed) requestLayout()
        }
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    }

    private fun indexOf(v: View): Int = cells.indexOfFirst { it === v }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    /** 供外部（如方向键面板）调用：是否已有选中格 */
    fun hasSelection(): Boolean = selectedIndex in 0 until CELL_COUNT

    /** 选中格焦点交给系统输入法时调用 */
    fun ensureSelection(): Int {
        if (!hasSelection()) select(0, notify = false)
        return selectedIndex
    }
}

/** 便于外部获取全部格子视图（测试与命中标亮用） */
val ShiciGrid.cellViews: List<GridCellView>
    get() = (0 until childCount).mapNotNull { i ->
        val rowView = getChildAt(i) as? ViewGroup
        (0 until (rowView?.childCount ?: 0)).map { c -> rowView!!.getChildAt(c) as GridCellView }
    }.flatten()
