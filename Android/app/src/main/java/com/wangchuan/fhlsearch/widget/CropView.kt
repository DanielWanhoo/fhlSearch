package com.wangchuan.fhlsearch.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * 图片裁切框（v3.2）。
 *
 * 需求：用户选好图片后先看预览，**框可自由比例拖动**，把完整的 6 列 × 5 行字格框进来再识别。
 *
 * 做法：
 *  - 图片按"完整显示"缩放进控件（居中留黑边），裁切框用**位图坐标**保存，
 *    这样控件大小变化（横竖屏、平板）不用重算框；
 *  - 四角 + 四边共 8 个拖拽点，框内任意位置可整体拖动；框外按下＝重新拉一个新框；
 *  - 尺寸比例完全自由（不锁宽高比），只限制最小边长，避免拉成一条线；
 *  - 对外只暴露归一化坐标（0~1），调用方据此裁剪，不必关心控件尺寸。
 */
class CropView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : View(context, attrs, defStyleAttr) {

    private companion object {
        /** 拖拽点半径（dp） */
        const val HANDLE_R = 11f

        /** 裁切框最小边长（dp） */
        const val MIN_SIDE_DP = 48f
    }

    private val density = resources.displayMetrics.density

    /** 位图 → 控件坐标 / 反向 */
    private val m = Matrix()
    private val inv = Matrix()

    private var bmp: Bitmap? = null

    /** 裁切框（位图坐标） */
    private val crop = RectF()

    /** setImage 时给的初始框（归一化），等布局完成后再应用 */
    private var pending: RectF? = null
    private var layoutDone = false

    /** 当前拖拽模式：见 [MODE_*] */
    private var mode = MODE_NONE
    private var downView = FloatArray(2)
    private val startCrop = RectF()
    private var newRect: RectF? = null

    private val paintBitmap = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
    private val paintDim = Paint().apply { color = 0x99000000.toInt() }
    private val paintGrid = Paint().apply {
        color = 0x55FFFFFF
        style = Paint.Style.STROKE
        strokeWidth = 1f * density
    }
    private val paintBorder = Paint().apply {
        color = 0xFFFFFFFF.toInt()
        style = Paint.Style.STROKE
        strokeWidth = 2f * density
        isAntiAlias = true
    }
    private val paintHandle = Paint().apply {
        color = 0xFFFFFFFF.toInt()
        style = Paint.Style.FILL
        isAntiAlias = true
    }
    private val paintHandleLine = Paint().apply {
        color = 0xFF9E2B25.toInt()
        style = Paint.Style.STROKE
        strokeWidth = 1.5f * density
        isAntiAlias = true
    }

    private val tmpRect = RectF()

    /** 设置图片与初始框（[box] 为归一化坐标，null 表示取中间 90%） */
    fun setImage(bitmap: Bitmap, box: RectF?) {
        bmp = bitmap
        pending = box?.let { RectF(it) } ?: RectF(0.05f, 0.05f, 0.95f, 0.95f)
        if (layoutDone) applyPending()
        invalidate()
    }

    /** 把框恢复到初始位置（重新框选） */
    fun resetCrop() {
        val b = bmp ?: return
        val box = pending ?: RectF(0.05f, 0.05f, 0.95f, 0.95f)
        crop.set(
            box.left * b.width,
            box.top * b.height,
            box.right * b.width,
            box.bottom * b.height,
        )
        clampCrop(MODE_NONE)
        invalidate()
    }

    /** 当前裁切框（归一化 0~1） */
    fun cropNormalized(): RectF {
        val b = bmp ?: return RectF(0f, 0f, 1f, 1f)
        return RectF(
            crop.left / b.width,
            crop.top / b.height,
            crop.right / b.width,
            crop.bottom / b.height,
        )
    }

    // ---------------------------------------------------------------- 布局与绘制

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        layoutDone = true
        updateMatrix()
        if (crop.isEmpty) applyPending() else clampCrop(MODE_NONE)
    }

    private fun updateMatrix() {
        val b = bmp ?: return
        val vw = (width - paddingLeft - paddingRight).toFloat()
        val vh = (height - paddingTop - paddingBottom).toFloat()
        if (vw <= 0f || vh <= 0f || b.width <= 0 || b.height <= 0) return
        val s = min(vw / b.width, vh / b.height)
        m.reset()
        m.setScale(s, s)
        m.postTranslate(
            paddingLeft + (vw - b.width * s) / 2f,
            paddingTop + (vh - b.height * s) / 2f,
        )
        m.invert(inv)
    }

    private fun applyPending() {
        val b = bmp ?: return
        updateMatrix()
        val box = pending ?: RectF(0.05f, 0.05f, 0.95f, 0.95f)
        crop.set(
            box.left * b.width,
            box.top * b.height,
            box.right * b.width,
            box.bottom * b.height,
        )
        clampCrop(MODE_NONE)
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val b = bmp ?: return
        if (m.isIdentity) updateMatrix()

        canvas.drawColor(0xFF1A1A1A.toInt())
        canvas.drawBitmap(b, m, paintBitmap)

        mapRect(crop, tmpRect)
        // 框外压暗
        canvas.drawRect(0f, 0f, width.toFloat(), tmpRect.top, paintDim)
        canvas.drawRect(0f, tmpRect.bottom, width.toFloat(), height.toFloat(), paintDim)
        canvas.drawRect(0f, tmpRect.top, tmpRect.left, tmpRect.bottom, paintDim)
        canvas.drawRect(tmpRect.right, tmpRect.top, width.toFloat(), tmpRect.bottom, paintDim)

        // 三分线
        for (i in 1..2) {
            val x = tmpRect.left + tmpRect.width() * i / 3f
            canvas.drawLine(x, tmpRect.top, x, tmpRect.bottom, paintGrid)
            val y = tmpRect.top + tmpRect.height() * i / 3f
            canvas.drawLine(tmpRect.left, y, tmpRect.right, y, paintGrid)
        }
        canvas.drawRect(tmpRect, paintBorder)
        handlePoints(tmpRect).forEach { p ->
            canvas.drawCircle(p[0], p[1], HANDLE_R * density, paintHandle)
            canvas.drawCircle(p[0], p[1], HANDLE_R * density, paintHandleLine)
        }
    }

    // ---------------------------------------------------------------- 触摸

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (bmp == null) return false
        val vx = event.x
        val vy = event.y
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downView = floatArrayOf(vx, vy)
                startCrop.set(crop)
                mode = hitTest(vx, vy)
                if (mode == MODE_NEW) {
                    newRect = RectF()
                    mode = MODE_NEW
                }
                parent?.requestDisallowInterceptTouchEvent(true)
                return true
            }

            MotionEvent.ACTION_MOVE -> {
                if (mode == MODE_NONE) return true
                if (mode == MODE_NEW) {
                    dragNew(vx, vy)
                } else {
                    drag(vx, vy)
                }
                invalidate()
                return true
            }

            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                if (mode == MODE_NEW && newRect != null) {
                    commitNew()
                } else if (mode != MODE_NONE) {
                    clampCrop(mode)
                }
                mode = MODE_NONE
                newRect = null
                parent?.requestDisallowInterceptTouchEvent(false)
                performClick()
                invalidate()
                return true
            }
        }
        return super.onTouchEvent(event)
    }

    override fun performClick(): Boolean {
        super.performClick()
        return true
    }

    /** 按位图坐标增量移动框（8 个拖拽点各自的方向） */
    private fun drag(vx: Float, vy: Float) {
        val b = bmp ?: return
        // 视图位移换成位图位移：mapVectors 会忽略平移，只保留缩放
        val delta = floatArrayOf(vx - downView[0], vy - downView[1])
        inv.mapVectors(delta)
        val dx = delta[0]
        val dy = delta[1]
        crop.set(startCrop)
        when (mode) {
            MODE_MOVE -> {
                crop.offset(dx, dy)
                clampMove(b)
            }
            MODE_TL, MODE_TR, MODE_BL, MODE_BR, MODE_T, MODE_B, MODE_L, MODE_R -> {
                if (mode == MODE_TL || mode == MODE_L || mode == MODE_BL) crop.left = startCrop.left + dx
                if (mode == MODE_TR || mode == MODE_R || mode == MODE_BR) crop.right = startCrop.right + dx
                if (mode == MODE_TL || mode == MODE_T || mode == MODE_TR) crop.top = startCrop.top + dy
                if (mode == MODE_BL || mode == MODE_B || mode == MODE_BR) crop.bottom = startCrop.bottom + dy
                clampCrop(mode)
            }
        }
    }

    /** 框外按下 → 拖出一个新框 */
    private fun dragNew(vx: Float, vy: Float) {
        val a = toBitmap(downView[0], downView[1])
        val c = toBitmap(vx, vy)
        val r = RectF(min(a[0], c[0]), min(a[1], c[1]), max(a[0], c[0]), max(a[1], c[1]))
        newRect = r
        crop.set(r)
    }

    private fun commitNew() {
        val b = bmp ?: return
        val minSide = MIN_SIDE_DP * density / scaleFactor()
        if (crop.width() < minSide || crop.height() < minSide) {
            // 只是点了一下没拖动 → 恢复原框
            crop.set(startCrop)
        }
        clampCrop(MODE_NONE)
    }

    // ---------------------------------------------------------------- 命中判断

    private fun hitTest(vx: Float, vy: Float): Int {
        mapRect(crop, tmpRect)
        val pts = handlePoints(tmpRect)
        val r = HANDLE_R * density * 1.6f
        val names = intArrayOf(MODE_TL, MODE_T, MODE_TR, MODE_R, MODE_BR, MODE_B, MODE_BL, MODE_L)
        var best = MODE_NONE
        var bestD = r
        pts.forEachIndexed { i, p ->
            val d = max(abs(vx - p[0]), abs(vy - p[1]))
            if (d < bestD) {
                bestD = d
                best = names[i]
            }
        }
        if (best != MODE_NONE) return best
        return if (tmpRect.contains(vx, vy)) MODE_MOVE else MODE_NEW
    }

    /** 8 个拖拽点：四角 + 四边中点（顺序 TL, T, TR, R, BR, B, BL, L） */
    private fun handlePoints(r: RectF): List<FloatArray> {
        val cx = (r.left + r.right) / 2f
        val cy = (r.top + r.bottom) / 2f
        return listOf(
            floatArrayOf(r.left, r.top),
            floatArrayOf(cx, r.top),
            floatArrayOf(r.right, r.top),
            floatArrayOf(r.right, cy),
            floatArrayOf(r.right, r.bottom),
            floatArrayOf(cx, r.bottom),
            floatArrayOf(r.left, r.bottom),
            floatArrayOf(r.left, cy),
        )
    }

    // ---------------------------------------------------------------- 边界约束

    private fun scaleFactor(): Float {
        val v = FloatArray(9)
        m.getValues(v)
        return max(0.0001f, abs(v[Matrix.MSCALE_X]))
    }

    private fun minBitmapSide(): Float = MIN_SIDE_DP * density / scaleFactor()

    /** 整体移动时把框挡在图内 */
    private fun clampMove(b: Bitmap) {
        val dx = when {
            crop.left < 0f -> -crop.left
            crop.right > b.width -> b.width - crop.right
            else -> 0f
        }
        val dy = when {
            crop.top < 0f -> -crop.top
            crop.bottom > b.height -> b.height - crop.bottom
            else -> 0f
        }
        crop.offset(dx, dy)
    }

    /** 拉伸时把边界挡在图内，并保证最小边长 */
    private fun clampCrop(mode: Int) {
        val b = bmp ?: return
        val minSide = minBitmapSide()
        val w = b.width.toFloat()
        val h = b.height.toFloat()
        crop.left = crop.left.coerceIn(0f, w)
        crop.right = crop.right.coerceIn(0f, w)
        crop.top = crop.top.coerceIn(0f, h)
        crop.bottom = crop.bottom.coerceIn(0f, h)
        if (crop.right - crop.left < minSide) {
            if (mode == MODE_L || mode == MODE_TL || mode == MODE_BL || mode == MODE_NONE) {
                crop.left = max(0f, crop.right - minSide)
            } else {
                crop.right = min(w, crop.left + minSide)
            }
        }
        if (crop.bottom - crop.top < minSide) {
            if (mode == MODE_T || mode == MODE_TL || mode == MODE_TR || mode == MODE_NONE) {
                crop.top = max(0f, crop.bottom - minSide)
            } else {
                crop.bottom = min(h, crop.top + minSide)
            }
        }
        crop.sort()
    }

    // ---------------------------------------------------------------- 坐标换算

    private fun mapRect(src: RectF, out: RectF) {
        out.set(src)
        m.mapRect(out)
    }

    private fun toBitmap(vx: Float, vy: Float): FloatArray {
        val pts = floatArrayOf(vx, vy)
        inv.mapPoints(pts)
        val b = bmp
        if (b != null) {
            pts[0] = pts[0].coerceIn(0f, b.width.toFloat())
            pts[1] = pts[1].coerceIn(0f, b.height.toFloat())
        }
        return pts
    }
}

/** 拖拽模式取值（不使用 enum，避免每次触摸装箱） */
private const val MODE_NONE = 0
private const val MODE_MOVE = 1
private const val MODE_NEW = 2
private const val MODE_TL = 3
private const val MODE_T = 4
private const val MODE_TR = 5
private const val MODE_R = 6
private const val MODE_BR = 7
private const val MODE_B = 8
private const val MODE_BL = 9
private const val MODE_L = 10
