package com.wangchuan.fhlsearch.ui.sheet

import android.content.Context
import android.graphics.Bitmap
import android.graphics.RectF
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.core.os.bundleOf
import androidx.fragment.app.FragmentManager
import androidx.lifecycle.lifecycleScope
import com.wangchuan.fhlsearch.R
import com.wangchuan.fhlsearch.databinding.ViewFhlCropBinding
import com.wangchuan.fhlsearch.ocr.PoemOcr
import com.wangchuan.fhlsearch.util.ImageLoader
import com.wangchuan.fhlsearch.util.Toasts
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/**
 * 图片裁切面板（v3.2）。
 *
 * 选好图片后先不让它直接识别，而是：
 *  1. 把图片按"完整显示"放进 [com.wangchuan.fhlsearch.widget.CropView]；
 *  2. 用 [PoemOcr.detectGridBox] 只算几何，自动把框放到 6×5 字格上（找不到就居中给个默认框）；
 *  3. 用户拖动框体 / 四角四边自由调整，点「确认裁切」→ 裁成新图写进缓存，
 *     把文件路径通过 Fragment Result 回给诗词模块，由它去识别。
 *
 * 这样"裁歪了"不用重新拍照：结果区下方留着那张"识别用的图片"，点一下还能再进来裁。
 */
class CropSheetFragment : CenteredDialogFragment() {

    private var _b: ViewFhlCropBinding? = null
    private val b get() = _b!!

    /** 原始位图（裁切从这里取像素），面板销毁时随视图一起释放 */
    private var photo: Bitmap? = null

    /** 读图 / 自动框选 / 存盘的任务 */
    private var job: Job? = null

    override val maxWidthRes: Int get() = R.dimen.fhl_crop_dialog_max_w

    override val widthRatio: Float get() = 0.94f

    /**
     * 裁切要看得清字，所以这个面板比普通弹窗高：宽度按基类规则，高度取屏幕的 86%。
     * 基类默认给 WRAP_CONTENT，这里必须整块覆盖。
     */
    override fun onStart() {
        super.onStart()
        val win = dialog?.window ?: return
        val dm = resources.displayMetrics
        val w = minOf(
            (dm.widthPixels * widthRatio).toInt(),
            resources.getDimensionPixelSize(maxWidthRes),
        )
        val h = (dm.heightPixels * 0.86f).toInt()
        win.setLayout(w, h)
        win.setGravity(Gravity.CENTER)
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        _b = ViewFhlCropBinding.inflate(inflater, container, false)
        return b.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        b.btnCropConfirm.isEnabled = false
        b.btnCropCancel.setOnClickListener { dismissAllowingStateLoss() }
        b.btnCropReset.setOnClickListener { b.cropView.resetCrop() }
        b.btnCropConfirm.setOnClickListener { confirm() }
        loadSource()
    }

    override fun onDestroyView() {
        super.onDestroyView()
        job?.cancel()
        job = null
        photo = null
        _b = null
    }

    // ---------------------------------------------------------------- 读图与自动框选

    private fun loadSource() {
        val ctx = context ?: return
        val source = arguments?.getString(ARG_SOURCE).orEmpty()
        b.tvCropHint.setText(R.string.ocr_crop_detecting)

        job = viewLifecycleOwner.lifecycleScope.launch {
            val loaded = withContext(Dispatchers.IO) {
                try {
                    val bmp = readBitmap(ctx, source)
                    // 自动框选只算几何（面板检测 + 暗像素投影），在后台跑，面板立刻能看见图
                    val box = try {
                        PoemOcr.detectGridBox(bmp)
                    } catch (e: Exception) {
                        Log.w(TAG_LOG, "自动框选失败", e)
                        null
                    }
                    bmp to box
                } catch (e: Exception) {
                    Log.w(TAG_LOG, "裁切面板读图失败", e)
                    null
                }
            }
            if (loaded == null) {
                Toasts.show(ctx, getString(R.string.ocr_crop_failed))
                dismissAllowingStateLoss()
                return@launch
            }
            val (bmp, box) = loaded
            photo = bmp
            b.cropView.setImage(bmp, box?.let { expand(it) })
            b.tvCropHint.setText(
                if (box != null) R.string.ocr_crop_auto else R.string.ocr_crop_manual
            )
            b.btnCropConfirm.isEnabled = true
        }
    }

    /** 自动框四周再放一点点余量：切太紧会把格线和面板边框切掉，识别反而找不到格子 */
    private fun expand(box: RectF): RectF {
        val mx = box.width() * 0.03f
        val my = box.height() * 0.03f
        return RectF(
            (box.left - mx).coerceAtLeast(0f),
            (box.top - my).coerceAtLeast(0f),
            (box.right + mx).coerceAtMost(1f),
            (box.bottom + my).coerceAtMost(1f),
        )
    }

    private fun readBitmap(ctx: Context, source: String): Bitmap {
        if (source.startsWith("content://") || source.startsWith("file://")) {
            return ImageLoader.load(ctx, Uri.parse(source))
        }
        return ImageLoader.loadFile(File(source))
    }

    // ---------------------------------------------------------------- 确认裁切

    private fun confirm() {
        val ctx = context ?: return
        val src = photo ?: return
        val n = b.cropView.cropNormalized()

        val left = (n.left * src.width).toInt().coerceIn(0, src.width - 1)
        val top = (n.top * src.height).toInt().coerceIn(0, src.height - 1)
        val width = (n.width() * src.width).toInt().coerceIn(1, src.width - left)
        val height = (n.height() * src.height).toInt().coerceIn(1, src.height - top)
        val cropped = try {
            Bitmap.createBitmap(src, left, top, width, height)
        } catch (e: Exception) {
            Log.w(TAG_LOG, "裁切失败", e)
            Toasts.show(ctx, getString(R.string.ocr_crop_failed))
            return
        }

        b.btnCropConfirm.isEnabled = false
        job = viewLifecycleOwner.lifecycleScope.launch {
            val file = withContext(Dispatchers.IO) { save(ctx, cropped) }
            if (file == null) {
                Toasts.show(ctx, getString(R.string.ocr_crop_failed))
                b.btnCropConfirm.isEnabled = true
                return@launch
            }
            parentFragmentManager.setFragmentResult(
                REQUEST_KEY,
                bundleOf(
                    RESULT_PATH to file.absolutePath,
                    RESULT_SOURCE to arguments?.getString(ARG_SOURCE).orEmpty(),
                ),
            )
            dismissAllowingStateLoss()
        }
    }

    /** 裁好的图落到 cache/ocr 下（顺手清掉上一次的），把路径交给调用方 */
    private fun save(ctx: Context, bmp: Bitmap): File? = try {
        val dir = File(ctx.cacheDir, "ocr").apply { mkdirs() }
        dir.listFiles { f -> f.name.startsWith("crop_") }?.forEach { runCatching { it.delete() } }
        val file = File(dir, "crop_" + System.currentTimeMillis() + ".jpg")
        file.outputStream().use { out -> bmp.compress(Bitmap.CompressFormat.JPEG, 95, out) }
        if (bmp !== photo) bmp.recycle()
        file
    } catch (e: Exception) {
        Log.w(TAG_LOG, "裁切结果存盘失败", e)
        null
    }

    companion object {
        /** Fragment 的 tag（重复弹出时要先把它清掉） */
        const val TAG = "fhl_crop"

        /** Fragment Result：请求键 / 裁好的图片路径 / 原始来源 */
        const val REQUEST_KEY = "fhl_crop_result"
        const val RESULT_PATH = "crop_path"
        const val RESULT_SOURCE = "crop_source"

        private const val ARG_SOURCE = "source"

        private const val TAG_LOG = "FhlOcr"

        /**
         * 弹出裁切面板。
         *
         * @param source 图片来源：相册的 `content://`、相机的 `content://` 或本地文件绝对路径
         */
        fun show(fm: FragmentManager, source: String) {
            if (fm.isStateSaved) return
            CropSheetFragment().apply {
                arguments = bundleOf(ARG_SOURCE to source)
            }.show(fm, TAG)
        }
    }
}
