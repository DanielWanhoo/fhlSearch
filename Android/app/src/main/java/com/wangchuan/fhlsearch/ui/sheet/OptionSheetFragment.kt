package com.wangchuan.fhlsearch.ui.sheet

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import com.wangchuan.fhlsearch.R
import com.wangchuan.fhlsearch.databinding.ViewFhlMsSheetBinding

/**
 * 选项型条件的"滚轮选择"面板（朝代 / 爱好 / 社团 / 品阶）。
 *
 * 点开条件行后在**屏幕正中**弹出（[CenteredDialogFragment]），中间是一个滚轮：
 *  - 上下滑动 → 滚轮一格格滚，正中那一项即当前选择；也可以直接点某一项；
 *  - 点「确定」→ 把选中项回传给名士检索页；
 *  - 点「清除该条件」→ 回传空值，等于取消这个条件。
 *
 * 选择结果通过 [FragmentResultListener] 回传，选项卡状态由名士检索页统一持有
 * （切换模块、层级检索都不会丢）。
 */
class OptionSheetFragment : CenteredDialogFragment() {

    companion object {
        const val REQ_KEY = "fhl_ms_option"
        const val ARG_TITLE = "title"
        const val ARG_OPTIONS = "options"
        const val ARG_SELECTED = "selected"

        fun newInstance(title: String, options: List<String>, selected: String?): OptionSheetFragment {
            val f = OptionSheetFragment()
            f.arguments = Bundle().apply {
                putString(ARG_TITLE, title)
                putStringArrayList(ARG_OPTIONS, ArrayList(options))
                putString(ARG_SELECTED, selected)
            }
            return f
        }
    }

    private var _b: ViewFhlMsSheetBinding? = null
    private val b get() = _b!!

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?,
    ): View {
        _b = ViewFhlMsSheetBinding.inflate(inflater, container, false)
        return b.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        val title = requireArguments().getString(ARG_TITLE).orEmpty()
        val options = requireArguments().getStringArrayList(ARG_OPTIONS).orEmpty()
        val selected = requireArguments().getString(ARG_SELECTED)

        b.tvSheetTitle.text = title
        b.wheel.setOptions(options, selected)

        b.btnWheelConfirm.setOnClickListener { deliver(b.wheel.selectedValue) }
        b.btnClearMode.setOnClickListener { deliver(null) }
    }

    private fun deliver(value: String?) {
        parentFragmentManager.setFragmentResult(
            REQ_KEY,
            Bundle().apply { putString("value", value ?: "") },
        )
        dismissAllowingStateLoss()
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _b = null
    }
}
