package com.wangchuan.fhlsearch.widget

import android.content.Context
import android.text.Editable
import android.text.TextWatcher
import android.util.AttributeSet
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.TextView
import androidx.core.content.ContextCompat
import com.wangchuan.fhlsearch.R

/**
 * 诗词检索的一个字格。
 *
 * 结构：一个 1dp 宽的隐藏 EditText（只用来唤起系统输入法并接收汉字）+ 显示用的 TextView
 *      + 右上角序号（①②③④⑤）。
 *
 * 三种视觉状态（需求原文）：
 *  - 普通：宣纸面 + 细金边
 *  - 选中：朱砂方框（由 [setCellSelected] 控制）
 *  - 命中：绿框标亮 + 序号（由 [setHit] 控制）
 *
 * 输入规则（需求原文）：只接受单个汉字；输入多个汉字只保留第一个；出现其他字符提示"非法字符"。
 */
class GridCellView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : FrameLayout(context, attrs) {

    companion object {
        val ORDER_MARKS = arrayOf("①", "②", "③", "④", "⑤")
        private val CJK = Regex("[\\u4e00-\\u9fff]")

        /** 判断输入是否为合法单字（空串表示清空，也算合法） */
        fun pickFirstHan(text: String): String? {
            if (text.isEmpty()) return ""
            val first = text[0]
            return if (first in '\u4e00'..'\u9fff') first.toString() else null
        }
    }

    private val charView: TextView
    private val badgeView: TextView
    private val hiddenEdit: EditText

    var row: Int = 0
        private set
    var col: Int = 0
        private set

    /** 格内文字（空格为 ""） */
    var value: String = ""
        private set

    private var hit: Boolean = false
    private var muteWatcher = false

    /** 内容变化回调：参数为新值；非法输入时不会回调，而是通过 [onIllegalInput] 通知 */
    var onValueChanged: ((String) -> Unit)? = null
    var onIllegalInput: (() -> Unit)? = null

    init {
        isClickable = true
        background = ContextCompat.getDrawable(context, R.drawable.bg_fhl_cell)

        charView = TextView(context).apply {
            gravity = Gravity.CENTER
            setTextColor(ContextCompat.getColor(context, R.color.fhl_ink))
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
        }
        addView(charView)

        badgeView = TextView(context).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            setTextColor(ContextCompat.getColor(context, R.color.fhl_green_text))
            visibility = GONE
            layoutParams = LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
                gravity = Gravity.TOP or Gravity.END
                topMargin = dp(1)
                marginEnd = dp(3)
            }
        }
        addView(badgeView)

        hiddenEdit = EditText(context).apply {
            // 铺满整个格子但全透明，让系统输入法直接绑定它；
            // 触摸由外层 FrameLayout 统一接管（见 onInterceptTouchEvent），
            // 否则它会吃掉点击、导致"点格子没反应"。
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
            background = null
            setTextColor(0x00000000)
            isSingleLine = true
            inputType = android.text.InputType.TYPE_CLASS_TEXT
            imeOptions = EditorInfo.IME_FLAG_NO_EXTRACT_UI or EditorInfo.IME_ACTION_NEXT
            setPadding(0, 0, 0, 0)
            isClickable = false
            isFocusableInTouchMode = true
            // 光标：居中 + 朱砂色，让人一眼看到"字会打进哪一格"
            gravity = Gravity.CENTER
            isCursorVisible = true
            setTextCursorDrawable(
                ContextCompat.getDrawable(context, R.drawable.cursor_fhl_vermilion)
            )
            addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) = Unit
                override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) = Unit
                override fun afterTextChanged(s: Editable?) {
                    if (muteWatcher) return
                    val text = s?.toString().orEmpty()
                    if (text.isEmpty()) return
                    val picked = pickFirstHan(text)
                    if (picked == null) {
                        clearHidden()
                        onIllegalInput?.invoke()
                        return
                    }
                    clearHidden()
                    setValue(picked)
                }
            })
        }
        addView(hiddenEdit)
    }

    fun bind(row: Int, col: Int) {
        this.row = row
        this.col = col
        contentDescription = "第${row + 1}行第${col + 1}列"
    }

    /**
     * 所有触摸都先由本格（FrameLayout）接管。
     *
     * 隐藏的 EditText 铺满整格，如果让它拿到触摸，它会把点击吃掉——
     * 表现就是"点格子没反应、选中框不出现"。拦截后点击一律走本格的
     * click 事件，输入焦点由 [focusForTyping] 显式转移。
     */
    override fun onInterceptTouchEvent(ev: MotionEvent): Boolean = true

    /** 外部直接设定内容（清空、程序填充），不触发非法提示 */
    fun setValue(text: String) {
        value = text
        charView.text = text
        clearHidden()
        onValueChanged?.invoke(text)
    }

    private fun clearHidden() {
        muteWatcher = true
        hiddenEdit.setText("")
        muteWatcher = false
    }

    /**
     * 把输入焦点（连带光标、输入法目标）移到本格。
     * [showIme] 为真时顺带唤起输入法（点格子时用）；
     * 方向键移动只转移焦点、不弹键盘（接物理键盘时用）。
     */
    fun focusForTyping(showIme: Boolean) {
        if (!hiddenEdit.hasFocus()) hiddenEdit.requestFocus()
        if (showIme) {
            val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE)
                    as InputMethodManager
            // 第二个参数 0 = 不附加额外标志（SHOW_IMPLICIT 已废弃）
            imm.showSoftInput(hiddenEdit, 0)
        }
    }

    /** 唤起输入法（点格子时调用） */
    fun requestTyping() = focusForTyping(showIme = true)

    fun hideTyping() {
        val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE)
                as android.view.inputmethod.InputMethodManager
        imm.hideSoftInputFromWindow(hiddenEdit.windowToken, 0)
    }

    fun applyTextSize(cellPx: Int) {
        charView.setTextSize(TypedValue.COMPLEX_UNIT_PX, (cellPx * 0.46f).coerceAtLeast(dp(14).toFloat()))
    }

    fun setCellSelected(selected: Boolean) {
        isSelected = selected
        invalidate()
    }

    /**
     * 命中标亮：换背景 + 右上角序号。
     *
     * 注意 `bg_fhl_cell` 是按 `state_selected` 取状态的 selector，
     * 所以这里换完背景后要 `refreshDrawableState()`，让"选中态"立刻反映到新背景上
     * （否则选中框会被刚换上的背景吃掉）。
     */
    fun setHit(isHit: Boolean, order: Int) {
        hit = isHit
        background = ContextCompat.getDrawable(
            context,
            if (isHit) R.drawable.bg_fhl_cell_hit else R.drawable.bg_fhl_cell
        )
        refreshDrawableState()
        if (isHit && order in 1..ORDER_MARKS.size) {
            badgeView.text = ORDER_MARKS[order - 1]
            badgeView.visibility = VISIBLE
        } else {
            badgeView.visibility = GONE
        }
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()
}
