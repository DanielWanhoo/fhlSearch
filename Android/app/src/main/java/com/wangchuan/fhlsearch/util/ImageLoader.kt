package com.wangchuan.fhlsearch.util

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.net.Uri
import androidx.exifinterface.media.ExifInterface
import java.io.File
import java.io.InputStream
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * 把相册 / 相机给的 Uri（或本地文件）读成位图，顺便做两件必须做的事：
 *
 *  1. **降采样**：手机照片动辄 4000×3000，直接解码要 40 MB 以上，低端机直接 OOM。
 *     先按 inJustDecodeBounds 拿到尺寸，用 2 的幂次采样解到长边 2 倍以内，再精确缩到 [maxSide]。
 *  2. **按 EXIF 摆正**：相机拍出来的照片常常是"躺着"的（像素横着存，靠 EXIF 里的
 *     orientation 标记摆正）。不处理的话整张图会转 90°/180°，字格检测必然失败。
 */
object ImageLoader {

    /** 长边缩到这个尺寸以内再送去识别（再大对识别没帮助，只是费内存） */
    const val DEFAULT_MAX_SIDE = 2400

    /** 相册 / 相机给的 Uri */
    fun load(context: Context, uri: Uri, maxSide: Int = DEFAULT_MAX_SIDE): Bitmap =
        decode({ context.contentResolver.openInputStream(uri) }, maxSide)

    /** 本地文件（拍照时我们自己的缓存文件、自动化测试塞进手机的图片） */
    fun loadFile(file: File, maxSide: Int = DEFAULT_MAX_SIDE): Bitmap =
        decode({ file.inputStream() }, maxSide)

    // ---------------------------------------------------------------- 内部实现

    private fun decode(open: () -> InputStream?, maxSide: Int): Bitmap {
        // ---- 1. 先量尺寸（只读文件头，不解码像素）----
        // 注意：inJustDecodeBounds 时 decodeStream 一定返回 null，所以不能把它的返回值
        // 当成"流有没有打开"来判断（早期版本就在这里错判成"图片打不开"）。
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        val s1 = open() ?: throw IllegalStateException("这张图片打不开")
        s1.use { BitmapFactory.decodeStream(it, null, bounds) }
        val srcW = bounds.outWidth
        val srcH = bounds.outHeight
        if (srcW <= 0 || srcH <= 0) throw IllegalStateException("这张图片打不开")

        // ---- 2. 降采样解码（采样率取 2 的幂）----
        var sample = 1
        while (max(srcW, srcH) / (sample * 2) >= maxSide) sample *= 2
        val opts = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val s2 = open() ?: throw IllegalStateException("这张图片打不开")
        var bmp = s2.use { BitmapFactory.decodeStream(it, null, opts) }
            ?: throw IllegalStateException("这张图片打不开")

        // ---- 3. 按 EXIF 摆正 ----
        val orientation = try {
            open()?.use {
                ExifInterface(it).getAttributeInt(
                    ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL,
                )
            } ?: ExifInterface.ORIENTATION_NORMAL
        } catch (e: Exception) {
            ExifInterface.ORIENTATION_NORMAL
        }
        val m = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> m.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> m.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> m.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> m.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> m.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                m.postRotate(90f)
                m.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                m.postRotate(270f)
                m.postScale(-1f, 1f)
            }
        }
        if (!m.isIdentity) {
            val rotated = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, m, true)
            if (rotated !== bmp) bmp.recycle()
            bmp = rotated
        }

        // ---- 4. 精确缩到长边上限 ----
        val side = max(bmp.width, bmp.height)
        if (side > maxSide) {
            val k = maxSide.toFloat() / side
            val scaled = Bitmap.createScaledBitmap(
                bmp,
                max(1, (bmp.width * k).roundToInt()),
                max(1, (bmp.height * k).roundToInt()),
                true,
            )
            if (scaled !== bmp) bmp.recycle()
            bmp = scaled
        }
        return bmp
    }
}
