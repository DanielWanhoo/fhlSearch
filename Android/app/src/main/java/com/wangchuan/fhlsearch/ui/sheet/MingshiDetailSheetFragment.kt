package com.wangchuan.fhlsearch.ui.sheet

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import com.wangchuan.fhlsearch.R
import com.wangchuan.fhlsearch.data.MingshiItem
import com.wangchuan.fhlsearch.databinding.ViewFhlMsDetailBinding

/**
 * 名士详情面板：点检索结果里的任意一行后，在**屏幕正中**弹出（[CenteredDialogFragment]）。
 *
 * 展示内容（题库里该名士的全部信息）：
 *  - 标题：名士（朝代）
 *  - 属性：品阶 / 职业 / 生逢 / 出身·身世 / 技能 / 爱好 / 社团（有值才显示）
 *  - 相关描述：题库里属于该名士的所有描述，逐条列出
 *
 * 数据通过 Bundle 逐字段传递（MingshiItem 是普通 data class，不实现 Parcelable）。
 */
class MingshiDetailSheetFragment : CenteredDialogFragment() {

    companion object {
        private const val ARG_NAME = "name"
        private const val ARG_DYNASTY = "dynasty"
        private const val ARG_RANK = "rank"
        private const val ARG_JOB = "job"
        private const val ARG_BORN = "born"
        private const val ARG_ORIGIN = "origin"
        private const val ARG_SKILL = "skill"
        private const val ARG_LOVE = "love"
        private const val ARG_CLUB = "club"
        private const val ARG_DESC = "desc"

        fun newInstance(item: MingshiItem): MingshiDetailSheetFragment {
            val f = MingshiDetailSheetFragment()
            f.arguments = Bundle().apply {
                putString(ARG_NAME, item.name)
                putString(ARG_DYNASTY, item.dynasty)
                putString(ARG_RANK, item.rank)
                putString(ARG_JOB, item.job)
                putString(ARG_BORN, item.born)
                putString(ARG_ORIGIN, item.origin)
                putString(ARG_SKILL, item.skill)
                putStringArrayList(ARG_LOVE, ArrayList(item.love))
                putStringArrayList(ARG_CLUB, ArrayList(item.club))
                putStringArrayList(ARG_DESC, ArrayList(item.desc))
            }
            return f
        }
    }

    private var _b: ViewFhlMsDetailBinding? = null
    private val b get() = _b!!

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?,
    ): View {
        _b = ViewFhlMsDetailBinding.inflate(inflater, container, false)
        return b.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        val a = requireArguments()
        val name = a.getString(ARG_NAME).orEmpty()
        val dynasty = a.getString(ARG_DYNASTY).orEmpty()

        b.tvDetailName.text = getString(R.string.ms_label_with_dynasty, name, dynasty)

        // ---- 属性行：有值才显示，避免一屏"—" ----
        val attrs = listOf(
            getString(R.string.ms_detail_rank) to a.getString(ARG_RANK),
            getString(R.string.ms_detail_job) to a.getString(ARG_JOB),
            getString(R.string.ms_detail_born) to a.getString(ARG_BORN),
            getString(R.string.ms_detail_origin) to a.getString(ARG_ORIGIN),
            getString(R.string.ms_detail_skill) to a.getString(ARG_SKILL),
            getString(R.string.ms_detail_love) to
                    a.getStringArrayList(ARG_LOVE)?.joinToString("、"),
            getString(R.string.ms_detail_club) to
                    a.getStringArrayList(ARG_CLUB)?.joinToString("、"),
        )
        b.layAttrs.removeAllViews()
        var shown = 0
        attrs.forEach { (label, value) ->
            if (value.isNullOrBlank()) return@forEach
            val row = layoutInflater.inflate(R.layout.item_fhl_ms_attr, b.layAttrs, false)
            row.findViewById<TextView>(R.id.tvAttrLabel).text = label
            row.findViewById<TextView>(R.id.tvAttrValue).text = value
            b.layAttrs.addView(row)
            shown++
        }
        if (shown == 0) {
            val row = layoutInflater.inflate(R.layout.item_fhl_ms_attr, b.layAttrs, false)
            row.findViewById<TextView>(R.id.tvAttrLabel).text = ""
            row.findViewById<TextView>(R.id.tvAttrValue).text =
                getString(R.string.ms_detail_empty)
            b.layAttrs.addView(row)
        }

        // ---- 相关描述：逐条列出 ----
        val desc = a.getStringArrayList(ARG_DESC).orEmpty().filter { it.isNotBlank() }
        b.tvDescHeader.text = getString(R.string.ms_detail_desc, desc.size)
        b.tvDescBody.text = if (desc.isEmpty()) {
            getString(R.string.ms_detail_empty)
        } else {
            desc.joinToString("\n") { "· $it" }
        }

        b.btnDetailClose.setOnClickListener { dismissAllowingStateLoss() }

        // 描述多的名士（最多 15 条）会很高：把滚动区限制在屏幕约 6 成，别把整屏盖满
        b.scrollDetail.post {
            val max = (resources.displayMetrics.heightPixels * 0.6f).toInt()
            val sv = b.scrollDetail
            if (sv.height > max) {
                sv.layoutParams = sv.layoutParams.apply { height = max }
            }
        }
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _b = null
    }
}
