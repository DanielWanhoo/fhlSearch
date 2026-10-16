package com.wangchuan.fhlsearch

import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updateLayoutParams
import androidx.core.view.updatePadding
import androidx.core.widget.TextViewCompat
import androidx.fragment.app.Fragment
import androidx.fragment.app.FragmentTransaction
import com.wangchuan.fhlsearch.ui.ChengyuFragment
import com.wangchuan.fhlsearch.ui.MingshiFragment
import com.wangchuan.fhlsearch.ui.ShiciFragment

/**
 * 主界面：三大模块的容器。
 *
 * 布局自适应：
 *  - 手机（宽度 < 600dp）：单栏 + 底部悬浮导航条，模块内采用上下分栏
 *  - 平板（宽度 ≥ 600dp）：左侧边栏 + 右侧内容，模块内采用左右分栏
 *
 * 三个模块用 hide/show 切换（不销毁视图），因此各自填好的条件、检索结果
 * 在来回切换时都会保留。
 */
class MainActivity : AppCompatActivity() {

    private lateinit var content: View

    /** 三个模块的 Fragment，首次进入时才创建 */
    private val fragments = HashMap<Int, Fragment>()
    private var currentTab = -1

    private val tabs = listOf(
        Tab(R.id.nav_chengyu, R.drawable.ic_fhl_book, R.string.nav_chengyu),
        Tab(R.id.nav_shici, R.drawable.ic_fhl_grid, R.string.nav_shici),
        Tab(R.id.nav_mingshi, R.drawable.ic_fhl_person, R.string.nav_mingshi),
    )

    private data class Tab(val id: Int, val icon: Int, val label: Int)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        content = findViewById(R.id.content)

        // Android 15 默认启用 edge-to-edge，需要自行处理状态栏/导航栏 insets
        window?.let { win ->
            androidx.core.view.WindowCompat.setDecorFitsSystemWindows(win, false)
        }

        val rail = findViewById<LinearLayout>(R.id.railNav)
        val bottom = findViewById<LinearLayout>(R.id.bottomNav)
        if (rail != null) {
            buildNav(rail, vertical = true)
        } else if (bottom != null) {
            buildNav(bottom, vertical = false)
        }
        applySystemBarInsets(rail, bottom)

        if (savedInstanceState == null) {
            selectTab(R.id.nav_chengyu)
        } else {
            currentTab = savedInstanceState.getInt(KEY_TAB, R.id.nav_chengyu)
            fragments.keys.forEach { id -> fragments[id] = createFragment(id) }
            restoreFragments()
            selectTab(currentTab, force = true)
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putInt(KEY_TAB, currentTab)
    }

    // ---------------------------------------------------------------- 系统栏避让
    /**
     * 让界面躲开系统栏（状态栏 / 手势条 / 三键导航 / 刘海 / 横屏时侧边的导航条）。
     *
     *  - 内容区：四边都让开（横屏时导航条可能在左/右侧，刘海也可能在侧边）
     *  - 手机底部 tab 栏：整条贴底，但**内部内容**要抬到系统导航条之上，
     *    这样手势条、三键导航条都不会压住 tab 文字（不同手机/不同导航方式都安全）
     *  - 平板左侧 tab 栏：四边同样让开
     */
    private fun applySystemBarInsets(rail: LinearLayout?, bottom: LinearLayout?) {
        val root = findViewById<View>(R.id.root) ?: return
        val railPadV = resources.getDimensionPixelSize(R.dimen.fhl_gap_s)
        val railPadH = resources.getDimensionPixelSize(R.dimen.fhl_gap_xs)
        val navPadV = resources.getDimensionPixelSize(R.dimen.fhl_gap_xs)
        val navPadH = resources.getDimensionPixelSize(R.dimen.fhl_gap_xs)
        val safeTypes = WindowInsetsCompat.Type.systemBars() or
                WindowInsetsCompat.Type.displayCutout()

        ViewCompat.setOnApplyWindowInsetsListener(root) { _, insets ->
            val safe = insets.getInsets(safeTypes)
            content.updatePadding(
                left = safe.left,
                top = safe.top,
                right = safe.right,
                bottom = 0,
            )
            bottom?.updatePadding(
                left = navPadH + safe.left,
                right = navPadH + safe.right,
                top = navPadV,
                bottom = navPadV + safe.bottom,
            )
            rail?.updatePadding(
                left = railPadH + safe.left,
                right = railPadH + safe.right,
                top = railPadV + safe.top,
                bottom = railPadV + safe.bottom,
            )
            insets
        }
    }

    // ---------------------------------------------------------------- 导航
    private fun buildNav(container: LinearLayout, vertical: Boolean) {
        container.removeAllViews()
        tabs.forEach { tab ->
            val item = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                isClickable = true
                isFocusable = true
                setPadding(dp(4), dp(4), dp(4), dp(4))
                layoutParams = if (vertical) {
                    // 平板左侧 tab：三等分整栏高度 → 三个 tab 均匀排布、且每个都居中在自己的那一格
                    LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f
                    ).apply { bottomMargin = dp(4) }
                } else {
                    // 手机底部 tab：三等分（普通通栏 tab 栏）
                    LinearLayout.LayoutParams(0, dp(52), 1f).apply {
                        marginStart = dp(2)
                        marginEnd = dp(2)
                    }
                }
            }
            val icon = ImageView(this).apply {
                setImageResource(tab.icon)
                setColorFilter(color(R.color.fhl_ink_sub))
                layoutParams = LinearLayout.LayoutParams(
                    resources.getDimensionPixelSize(R.dimen.fhl_tab_icon),
                    resources.getDimensionPixelSize(R.dimen.fhl_tab_icon)
                )
            }
            val label = TextView(this).apply {
                text = getString(tab.label)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                setTextColor(color(R.color.fhl_ink_sub))
                gravity = Gravity.CENTER
                // 底部导航一格只有 88dp 宽，系统字体放大后「成语检索」会被截成「成语检」，
                // 这里让字号自适应（下限 8sp，放大 2 倍时观感仍约 16sp）保证四个字完整显示。
                maxLines = 1
                TextViewCompat.setAutoSizeTextTypeUniformWithConfiguration(
                    this, 8, 12, 1, TypedValue.COMPLEX_UNIT_SP
                )
            }
            item.addView(icon)
            item.addView(label)
            item.tag = tab.id
            item.setOnClickListener { selectTab(tab.id) }
            container.addView(item)
        }
    }

    private fun highlightNav() {
        val rail = findViewById<LinearLayout>(R.id.railNav)
        val bottom = findViewById<LinearLayout>(R.id.bottomNav)
        listOfNotNull(rail, bottom).forEach { c ->
            val isRail = c === rail
            for (i in 0 until c.childCount) {
                val item = c.getChildAt(i) as LinearLayout
                val selected = item.tag == currentTab
                val tint = color(if (selected) R.color.fhl_vermilion else R.color.fhl_ink_sub)
                (item.getChildAt(0) as ImageView).setColorFilter(tint)
                (item.getChildAt(1) as TextView).setTextColor(tint)
                // 普通 tab 栏样式：平板左侧选中项用朱砂淡底块，手机底部保持通栏平铺
                item.isSelected = selected
                item.setBackgroundResource(if (isRail) R.drawable.bg_fhl_rail_item else 0)
            }
        }
    }

    // ---------------------------------------------------------------- 模块切换
    private fun createFragment(id: Int): Fragment = when (id) {
        R.id.nav_shici -> ShiciFragment()
        R.id.nav_mingshi -> MingshiFragment()
        else -> ChengyuFragment()
    }

    private fun selectTab(id: Int, force: Boolean = false) {
        if (!force && id == currentTab) return
        val fm = supportFragmentManager
        val tx = fm.beginTransaction()
        fragments.values.forEach { f -> if (f.isAdded) tx.hide(f) }

        var target = fragments[id]
        if (target == null) {
            target = createFragment(id)
            fragments[id] = target
            tx.add(R.id.content, target, "tab_$id")
        } else {
            tx.show(target)
        }
        tx.commit()
        currentTab = id
        highlightNav()
    }

    private fun restoreFragments() {
        val fm = supportFragmentManager
        val tx = fm.beginTransaction()
        fragments.forEach { (id, f) ->
            if (!f.isAdded) tx.add(R.id.content, f, "tab_$id") else tx.hide(f)
        }
        tx.commit()
    }

    private fun color(res: Int) = ContextCompat.getColor(this, res)

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    companion object {
        private const val KEY_TAB = "fhl_current_tab"
    }
}
