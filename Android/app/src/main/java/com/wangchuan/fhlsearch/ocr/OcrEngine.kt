package com.wangchuan.fhlsearch.ocr

import android.graphics.Bitmap
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * ML Kit 中文文字识别的薄封装：给一张位图，返回识别到的**每个汉字**及其中心坐标。
 *
 * 用的是 **com.google.mlkit:text-recognition-chinese**（内置模型版）：
 * 模型跟着 apk 一起装，不依赖 Google Play 服务、不需要联网下载 ——
 * 国产手机普遍没有 GMS，play-services 版会直接用不了，而本 App 全程离线。
 *
 * 一个坑（实测踩到过）：ML Kit 的中文识别会把**同一行里并排的几个字连成一个 element**
 * （它按"词"切，中文没有空格，于是一整行就是一个词）。拼板里一行正好是 6 个字，
 * 如果只取 element 的中心，就只会得到 1 个字、其余 5 格全空。
 * 所以这里把多字的 element 按**包围盒等宽切片**，估出每个字自己的中心 —— 拼板是按
 * 6×5 等距摆的，切片中心和真实格心最多差半格，足够映射回正确的格子。
 */
object OcrEngine {

    private val recognizer: TextRecognizer by lazy {
        TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
    }

    /** 识别一张位图。抛异常表示识别引擎本身出错（模型损坏、内存不足等）。 */
    suspend fun recognize(bitmap: Bitmap): List<Word> = suspendCancellableCoroutine { cont ->
        val input = InputImage.fromBitmap(bitmap, 0)
        recognizer.process(input)
            .addOnSuccessListener { text ->
                val words = ArrayList<Word>()
                for (block in text.textBlocks) {
                    for (line in block.lines) {
                        for (el in line.elements) {
                            val box = el.boundingBox ?: continue
                            val chars = el.text.filter { isCjk(it) }
                            if (chars.isEmpty()) continue
                            if (chars.length == 1) {
                                words.add(Word(chars[0].toString(), box.centerX(), box.centerY()))
                                continue
                            }
                            // 一行多个字被连读：等宽切片，估每个字的位置
                            val step = box.width().toFloat() / chars.length
                            val cy = box.centerY()
                            chars.forEachIndexed { i, c ->
                                val cx = (box.left + step * (i + 0.5f)).toInt()
                                words.add(Word(c.toString(), cx, cy))
                            }
                        }
                    }
                }
                if (cont.isActive) cont.resume(words)
            }
            .addOnFailureListener { e ->
                if (cont.isActive) cont.resumeWithException(e)
            }
    }

    private fun isCjk(c: Char) = c in '\u4e00'..'\u9fff' || c in '\u3400'..'\u4dbf'
}
