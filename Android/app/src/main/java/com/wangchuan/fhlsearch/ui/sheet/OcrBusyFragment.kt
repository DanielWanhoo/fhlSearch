package com.wangchuan.fhlsearch.ui.sheet

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import com.wangchuan.fhlsearch.R
import com.wangchuan.fhlsearch.databinding.ViewFhlOcrBusyBinding

/**
 * 「正在识别图片…」的等待卡片（屏幕正中，转圈 + 说明）。
 *
 * 识别一般 1~2 秒：期间用这个卡片挡住重复点击，识完立刻关掉。
 * 卡片本身不可取消（点外面 / 返回键都不关），由调用方在识别结束时关——
 * 否则用户中途关掉卡片会以为自己取消了，其实后台还在跑。
 */
class OcrBusyFragment : CenteredDialogFragment() {

    companion object {
        private const val TAG = "fhl_ocr_busy"

        /** 显示等待卡片；重复调用不会叠出两张 */
        fun show(fm: androidx.fragment.app.FragmentManager) {
            if (fm.findFragmentByTag(TAG) != null) return
            OcrBusyFragment().show(fm, TAG)
        }

        /** 关掉等待卡片（没显示时什么都不做） */
        fun hide(fm: androidx.fragment.app.FragmentManager) {
            val f = fm.findFragmentByTag(TAG) as? OcrBusyFragment ?: return
            f.dismissAllowingStateLoss()
        }
    }

    private var _b: ViewFhlOcrBusyBinding? = null
    private val b get() = _b!!

    init {
        isCancelable = false
    }

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?,
    ): View {
        _b = ViewFhlOcrBusyBinding.inflate(inflater, container, false)
        return b.root
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _b = null
    }
}
