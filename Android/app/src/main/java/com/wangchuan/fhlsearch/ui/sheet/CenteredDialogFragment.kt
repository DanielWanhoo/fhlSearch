package com.wangchuan.fhlsearch.ui.sheet

import android.app.Dialog
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import androidx.fragment.app.DialogFragment
import com.wangchuan.fhlsearch.R

/**
 * 屏幕居中弹窗的基类。
 *
 * 原本这两个面板是"从底部弹出的 BottomSheet"，现改为**屏幕正中显示的卡片**：
 *  - 窗口背景透明，圆角卡片由布局自己的 `bg_fhl_sheet` 提供；
 *  - 宽度 = min(屏幕宽 × 0.9, [maxWidthRes])，窄屏（手机）不吃满、宽屏（平板）保持易读宽度；
 *  - 高度由内容决定，点空白处 / 返回键即可关闭。
 *
 * 子类只需要照常实现 onCreateView 并返回自己的布局。
 */
abstract class CenteredDialogFragment : DialogFragment() {

    /** 卡片最大宽度（宽屏时生效，窄屏按屏幕宽度的 [widthRatio] 收缩） */
    protected open val maxWidthRes: Int = R.dimen.fhl_dialog_max_w

    /** 窄屏时占屏幕宽度的比例（0.86 ≈ 两侧各留 29dp，看起来才像"对话框"而不是铺满） */
    protected open val widthRatio: Float = 0.86f

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog =
        Dialog(requireContext(), R.style.ThemeFhlSearchDialog)

    override fun onStart() {
        super.onStart()
        val win = dialog?.window ?: return
        val screenW = resources.displayMetrics.widthPixels
        val maxW = resources.getDimensionPixelSize(maxWidthRes)
        win.setLayout(
            minOf((screenW * widthRatio).toInt(), maxW),
            ViewGroup.LayoutParams.WRAP_CONTENT,
        )
        win.setGravity(Gravity.CENTER)
    }
}
