package com.wangchuan.fhlsearch.ui.sheet

import android.content.Context
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import com.wangchuan.fhlsearch.R
import com.wangchuan.fhlsearch.databinding.ViewFhlMsInputBinding

/**
 * 输入型模式的输入面板（职业 / 生逢 / 出身-身世 / 技能 / 其他描述）。
 *
 * 与滚轮面板一样，在**屏幕正中**弹出（[CenteredDialogFragment]）。
 * 需求原文要求这五种模式用对话框输入，并做模糊检索（不拆分检索词、忽略标点空格）。
 * 归一化与匹配由 MingshiLogic 负责，这里只收集文本。
 */
class InputSheetFragment : CenteredDialogFragment() {

    companion object {
        const val REQ_KEY = "fhl_ms_input"
        const val ARG_TITLE = "title"
        const val ARG_HINT = "hint"
        const val ARG_VALUE = "value"

        fun newInstance(title: String, hint: String, value: String?): InputSheetFragment {
            val f = InputSheetFragment()
            f.arguments = Bundle().apply {
                putString(ARG_TITLE, title)
                putString(ARG_HINT, hint)
                putString(ARG_VALUE, value)
            }
            return f
        }
    }

    private var _b: ViewFhlMsInputBinding? = null
    private val b get() = _b!!

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?,
    ): View {
        _b = ViewFhlMsInputBinding.inflate(inflater, container, false)
        return b.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        b.tvSheetTitle.text = requireArguments().getString(ARG_TITLE).orEmpty()
        b.tilInput.hint = requireArguments().getString(ARG_HINT)
        b.etInput.setText(requireArguments().getString(ARG_VALUE).orEmpty())
        b.etInput.setSelection(b.etInput.text?.length ?: 0)
        b.etInput.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_SEARCH) {
                deliver(b.etInput.text?.toString().orEmpty())
                true
            } else false
        }
        b.btnConfirm.setOnClickListener { deliver(b.etInput.text?.toString().orEmpty()) }
        b.btnClearMode.setOnClickListener { deliver("") }

        // 弹出即聚焦输入框并唤起输入法（浮窗不会自动弹键盘，这里显式叫一次）
        b.etInput.requestFocus()
        b.etInput.post {
            val imm = requireContext().getSystemService(Context.INPUT_METHOD_SERVICE)
                    as InputMethodManager
            // 第二个参数 0 = 不附加额外标志（SHOW_IMPLICIT 已废弃）
            imm.showSoftInput(b.etInput, 0)
        }
    }

    private fun deliver(value: String) {
        parentFragmentManager.setFragmentResult(
            REQ_KEY,
            Bundle().apply { putString("value", value) },
        )
        dismissAllowingStateLoss()
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _b = null
    }
}
