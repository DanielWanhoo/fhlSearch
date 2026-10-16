package com.wangchuan.fhlsearch.util

import android.content.Context
import android.widget.Toast

/** 统一的轻提示 */
object Toasts {
    fun show(ctx: Context, text: CharSequence) {
        Toast.makeText(ctx, text, Toast.LENGTH_SHORT).show()
    }
}
