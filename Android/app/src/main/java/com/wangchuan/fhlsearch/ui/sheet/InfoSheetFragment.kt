package com.wangchuan.fhlsearch.ui.sheet

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import com.wangchuan.fhlsearch.FhlApp
import com.wangchuan.fhlsearch.R
import com.wangchuan.fhlsearch.databinding.ViewFhlInfoBinding

/**
 * 信息面板：点大标题右边的「i」后，在**屏幕正中**弹出（[CenteredDialogFragment]）。
 *
 * 内容分三层：
 *  - 头部：软件名 / 版本号（从 PackageManager 读，改了 build.gradle 会自己跟着变）/ 题库统计
 *  - 正文：三大模块的用法 + 图片识别怎么拍 + 版权说明 + 隐私说明（与 Windows 端的
 *    「使用说明」「关于题库」两个弹窗合并成一份，手机上一屏滚完更省事）
 *  - 底部：关闭
 *
 * 正文很长，所以滚动区高度在代码里按屏幕高度封顶（与名士详情面板同一套做法）。
 */
class InfoSheetFragment : CenteredDialogFragment() {

    companion object {
        const val TAG = "fhl_info"

        fun show(fm: androidx.fragment.app.FragmentManager) {
            if (fm.findFragmentByTag(TAG) != null) return
            InfoSheetFragment().show(fm, TAG)
        }
    }

    private var _b: ViewFhlInfoBinding? = null
    private val b get() = _b!!

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?,
    ): View {
        _b = ViewFhlInfoBinding.inflate(inflater, container, false)
        return b.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        val ctx = requireContext()

        b.tvInfoVersion.text = getString(R.string.info_version, versionName())

        // 题库统计：还没读完就只显示版本信息那一行
        val tiku = (requireActivity().application as FhlApp).tiku
        if (tiku != null) {
            b.tvInfoStats.text = getString(
                R.string.info_stats,
                tiku.chengyu.size,
                tiku.shici.size,
                tiku.mingshi.size,
            )
        } else {
            b.tvInfoStats.visibility = View.GONE
        }

        b.btnInfoClose.setOnClickListener { dismissAllowingStateLoss() }

        // 正文很长：把滚动区高度封顶，标题与关闭键始终可见。
        // 0.45 屏高 + 头部与按钮 ≈ 整个卡片占屏幕七成左右（再多就快成全屏了）
        b.scrollInfo.post {
            val max = (resources.displayMetrics.heightPixels * 0.45f).toInt()
            val sv = b.scrollInfo
            if (sv.height > max) {
                sv.layoutParams = sv.layoutParams.apply { height = max }
            }
        }
    }

    /** 版本号从安装包读，避免和 build.gradle 里写的对不上 */
    private fun versionName(): String = try {
        val pm = requireContext().packageManager
        val pkg = requireContext().packageName
        @Suppress("DEPRECATION")
        pm.getPackageInfo(pkg, 0).versionName ?: "?"
    } catch (e: Exception) {
        "?"
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _b = null
    }
}
