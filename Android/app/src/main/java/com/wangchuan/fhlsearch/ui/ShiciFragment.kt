package com.wangchuan.fhlsearch.ui

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import com.wangchuan.fhlsearch.FhlApp
import com.wangchuan.fhlsearch.R
import com.wangchuan.fhlsearch.data.ShiciItem
import com.wangchuan.fhlsearch.databinding.FragmentFhlShiciBinding
import com.wangchuan.fhlsearch.databinding.ViewFhlResultBinding
import com.wangchuan.fhlsearch.logic.ScHit
import com.wangchuan.fhlsearch.logic.ShiciLogic
import com.wangchuan.fhlsearch.ocr.PoemOcr
import com.wangchuan.fhlsearch.ui.sheet.InfoSheetFragment
import com.wangchuan.fhlsearch.ui.sheet.OcrBusyFragment
import com.wangchuan.fhlsearch.util.ImageLoader
import com.wangchuan.fhlsearch.util.Toasts
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/**
 * 模块二：诗词检索（山石雅集第 15 题）
 *
 * 需求要点：
 *  - 6 列 × 5 行 = 30 格，每格一个汉字；多输只取第一个；非汉字提示"非法字符"；
 *  - 点格子选中并唤起输入法（选中格同时出现红框与光标）；
 *    接外接物理键盘时用 ↑ ↓ ← → 移动选中格、Tab 前后跳、Backspace 清格（由 [com.wangchuan.fhlsearch.widget.ShiciGrid] 直接处理按键）；
 *  - 检索时从格中选 5 个字（顺序无关）与题库诗句匹配，命中格用绿框标亮并给序号；
 *  - 结果附题目与作者。
 *
 * v3.0 新增 **图片识别**（参照搜题软件的工作过程）：
 *  - 「拍照识别」直接用系统相机拍，「相册识别」从图库挑一张；
 *    两条路都不申请 CAMERA / 存储权限（拍照走系统相机 + FileProvider 授权的临时文件，
 *    选图走系统相册选择器，都是系统给的"托管"通道）。
 *  - 图片交给 [PoemOcr]：自动找出 6×5 字格 → 逐格拼板 → ML Kit 中文识别 →
 *    把 30 个字填进格子 → **直接开始检索**（不用再点一次「开始检索」）。
 *  - 识别错的字照样可以手改：格子本来就是可编辑的。
 *
 * 该模块没有层级检索，因此结果区不显示"二次检索"；"清空"清掉字格与结果。
 * 注：v1.4 起已删除界面上的"虚拟方向键"面板，方向键只保留物理键盘这一条路径。
 */
class ShiciFragment : Fragment(), ResultHost {

    private var _b: FragmentFhlShiciBinding? = null
    private val b get() = _b!!

    private lateinit var result: ResultView
    private var all: List<ShiciItem> = emptyList()

    /** 上一次检索的命中（点选某条时切换高亮） */
    private var hits: List<ScHit> = emptyList()

    /** 是否已经检索过（决定结果区的提示语） */
    private var searched = false

    /** 检索次数（与另两个模块统一显示在右上角） */
    private var searchCount = 0

    /** 拍照时交给相机应用去写的那个临时文件（Uri 授权给它） */
    private var pendingCameraUri: Uri? = null

    /** 正在跑的识别任务（同一时间只允许一个） */
    private var ocrJob: Job? = null

    /** 这一轮的格子是不是"图片识别填进去的"（只影响没找到诗句时那句提示） */
    private var cameFromOcr = false

    /**
     * 上一张图每格的候选字（几趟识别各认出了什么）。
     * 用户一改格子就清掉——那时候格子已经不是"识别结果"了，再拿候选字去猜就是瞎猜。
     */
    private var ocrCandidates: List<Set<Char>> = emptyList()

    // ---------------------------------------------------------------- 系统相机 / 相册

    /** 拍照：系统相机把照片写进 FileProvider 授权的缓存文件，回来后直接识别 */
    private val takePicture = registerForActivityResult(ActivityResultContracts.TakePicture()) { ok ->
        val uri = pendingCameraUri
        pendingCameraUri = null
        val ctx = context ?: return@registerForActivityResult
        if (ok && uri != null) {
            startOcr { ImageLoader.load(ctx, uri) }
        } else {
            Toasts.show(ctx, getString(R.string.ocr_need_image))
        }
    }

    /** 从相册挑图：系统照片选择器（不需要读存储权限） */
    private val pickImage = registerForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        val ctx = context ?: return@registerForActivityResult
        if (uri != null) {
            startOcr { ImageLoader.load(ctx, uri) }
        }
    }

    /**
     * 自动化测试用：接收广播后
     *  - [ACTION_FILL_TEST]：填入示例字格；
     *  - [ACTION_OCR_TEST]：对手机里的某张图片跑一遍识别（extra 传文件绝对路径），
     *    走的是与「相册识别」完全相同的识别 + 填格 + 检索流程，结果打日志供脚本断言。
     * Receiver 以 RECEIVER_EXPORTED 注册，只有本应用 / shell 能触发。
     */
    private val testReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            when (intent.action) {
                ACTION_FILL_TEST -> fillTestGrid()
                ACTION_OCR_TEST -> {
                    val path = intent.getStringExtra(EXTRA_OCR_PATH).orEmpty()
                    if (path.isEmpty()) return
                    // extra dump=true 时把拼板 PNG 留在 files/ocr_dump 下，方便排查识别问题
                    PoemOcr.debugDumpDir = if (intent.getBooleanExtra(EXTRA_OCR_DUMP, false)) {
                        File(ctx.filesDir, "ocr_dump")
                    } else {
                        null
                    }
                    startOcr { ImageLoader.loadFile(File(path)) }
                }
            }
        }
    }

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?,
    ): View {
        _b = FragmentFhlShiciBinding.inflate(inflater, container, false)
        return b.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        b.header.tvTitle.setText(R.string.sc_title)
        b.header.tvSubtitle.setText(R.string.sc_subtitle)
        b.header.btnInfo.setOnClickListener { InfoSheetFragment.show(childFragmentManager) }

        result = ResultView(b.result as ViewFhlResultBinding, b.actions, this)
        result.secondSearchEnabled = false           // 诗词模块没有二次检索
        result.showInitial(getString(R.string.empty_shici))
        result.onRowPicked = { row, _ ->
            (row.payload as? ScHit)?.let { b.cond.grid.setHits(it.cells) }
        }

        b.cond.grid.onCellTapped = { index -> b.cond.grid.select(index, notify = false) }
        b.cond.grid.onCellChanged = {
            // 字格一改动，上次的标亮与结果就不再有效
            cameFromOcr = false
            ocrCandidates = emptyList()
            if (searched) clearResultsOnly()
        }

        b.cond.btnClear.setOnClickListener { clearAll() }
        b.cond.btnSearch.setOnClickListener { doSearch() }
        b.cond.btnOcrCamera.setOnClickListener { shootPhoto() }
        b.cond.btnOcrGallery.setOnClickListener { pickFromGallery() }

        updateCountText()

        (requireActivity().application as FhlApp).whenReady { tiku ->
            if (tiku == null) {
                Toasts.show(requireContext(), getString(R.string.tip_tiku_error))
                return@whenReady
            }
            all = tiku.shici
        }

        ContextCompat.registerReceiver(
            requireContext(),
            testReceiver,
            IntentFilter().apply {
                addAction(ACTION_FILL_TEST)
                addAction(ACTION_OCR_TEST)
            },
            ContextCompat.RECEIVER_EXPORTED,
        )
    }

    override fun onDestroyView() {
        super.onDestroyView()
        runCatching { requireContext().unregisterReceiver(testReceiver) }
        _b = null
    }

    private fun fillTestGrid() {
        // 与 reference_logic.py 自测用例一致：「草上原离离」对应「离离原上草」
        val chars = listOf("草", "上", "原", "离", "离")
        chars.forEachIndexed { i, c -> b.cond.grid.setCharAt(i, c) }
    }

    companion object {
        const val ACTION_FILL_TEST = "com.wangchuan.fhlsearch.action.FILL_SHICI_TEST"
        const val ACTION_OCR_TEST = "com.wangchuan.fhlsearch.action.OCR_TEST"
        const val EXTRA_OCR_PATH = "path"
        const val EXTRA_OCR_DUMP = "dump"
        private const val TAG_OCR = "FhlOcr"
    }

    // ---------------------------------------------------------------- 图片识别

    /** 拍照：先在缓存目录里占个文件名，再把它的 Uri 授权给相机应用 */
    private fun shootPhoto() {
        val ctx = context ?: return
        try {
            val dir = File(ctx.cacheDir, "ocr").apply { mkdirs() }
            val file = File(dir, "shot_" + System.currentTimeMillis() + ".jpg")
            val uri = FileProvider.getUriForFile(ctx, ctx.packageName + ".fileprovider", file)
            pendingCameraUri = uri
            takePicture.launch(uri)
        } catch (e: Exception) {
            pendingCameraUri = null
            Log.w(TAG_OCR, "启动相机失败", e)
            Toasts.show(ctx, getString(R.string.ocr_no_camera))
        }
    }

    /** 相册：系统照片选择器；老系统上会自动退化成"文件选择" */
    private fun pickFromGallery() {
        val ctx = context ?: return
        try {
            pickImage.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
        } catch (e: Exception) {
            Log.w(TAG_OCR, "启动相册失败", e)
            Toasts.show(ctx, getString(R.string.ocr_need_image))
        }
    }

    /**
     * 识别入口。[load] 负责在后台线程把图片读成位图（相册 Uri / 相机文件 / 测试文件）。
     *
     * 流程：显示等待卡片 → 读图（IO 线程）→ 找字格 + 识别（默认线程池）→
     * 关掉卡片 → 把字填进格子 → **直接开始检索**。
     */
    private fun startOcr(load: suspend () -> Bitmap) {
        val ctx = context ?: return
        if (all.isEmpty()) {
            Toasts.show(ctx, getString(R.string.tip_tiku_error))
            return
        }
        if (ocrJob?.isActive == true) return

        OcrBusyFragment.show(childFragmentManager)
        ocrJob = viewLifecycleOwner.lifecycleScope.launch {
            try {
                val bmp = withContext(Dispatchers.IO) { load() }
                val res = try {
                    PoemOcr.recognize(bmp, log = { Log.i(TAG_OCR, it) })
                } finally {
                    bmp.recycle()
                }
                Log.i(TAG_OCR, "字格:\n" + res.gridText())
                if (res.detail.isNotEmpty()) Log.d(TAG_OCR, "过程:\n" + res.detail)
                if (!res.ok) {
                    showOcrError(res.error)
                    return@launch
                }
                applyOcrGrid(res)
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.e(TAG_OCR, "识别失败", e)
                showOcrError(e.message ?: e.javaClass.simpleName)
            } finally {
                runCatching { OcrBusyFragment.hide(childFragmentManager) }
            }
        }
    }

    /** 把识别结果填进格子，然后立刻检索一次 */
    private fun applyOcrGrid(res: PoemOcr.Result) {
        val ctx = context ?: return
        val filled = res.filled
        b.cond.grid.clearAll()
        res.cells.forEachIndexed { i, ch ->
            if (ch != PoemOcr.BLANK) b.cond.grid.setCharAt(i, ch.toString())
        }
        // 候选字要在填完之后再挂上：填格会触发 onCellChanged，那边会把它清掉
        ocrCandidates = res.candidates
        cameFromOcr = true
        Toasts.show(
            ctx,
            getString(
                if (filled >= PoemOcr.COUNT) R.string.ocr_done else R.string.ocr_done_partial,
                filled,
                PoemOcr.COUNT,
            ),
        )
        doSearch()
    }

    private fun showOcrError(message: String) {
        val ctx = context ?: return
        val text = getString(R.string.ocr_failed) + "：" + message
        Log.w(TAG_OCR, text)
        Toasts.show(ctx, getString(R.string.ocr_failed))
        // 结果区地方大，把原因写在那儿，比一闪而过的提示更好读
        result.showEmpty(text)
    }

    // ---------------------------------------------------------------- 检索
    private fun doSearch() {
        if (all.isEmpty()) {
            Toasts.show(requireContext(), getString(R.string.tip_tiku_error))
            return
        }
        var grid = b.cond.grid.allChars()
        if (grid.all { it.isEmpty() }) {
            Toasts.show(requireContext(), getString(R.string.tip_need_condition))
            return
        }
        searched = true
        searchCount++
        updateCountText()

        var found = ShiciLogic.search(grid, all)
        // 图片识别的"补救"：一条都没命中，多半是有一格认错了/空着。
        // 拿每格的候选字回题库里对一遍，只有唯一一条明显更合适才用（见 ShiciLogic.rescue）
        if (found.isEmpty() && cameFromOcr && ocrCandidates.isNotEmpty()) {
            val r = ShiciLogic.rescue(grid, ocrCandidates, all)
            if (r != null) {
                r.item.chars.forEachIndexed { k, ch ->
                    val idx = r.cells[k]
                    if (grid.getOrNull(idx) != ch) b.cond.grid.setCharAt(idx, ch)
                }
                grid = b.cond.grid.allChars()
                found = ShiciLogic.search(grid, all)
                if (found.isNotEmpty()) {
                    Toasts.show(
                        requireContext(),
                        getString(
                            if (r.fill.isEmpty()) R.string.ocr_rescue_match else R.string.ocr_rescue_fill,
                            r.item.line,
                        ),
                    )
                    Log.i(TAG_OCR, "按题库补全：" + r.item.line + "（改 " + r.fill.size + " 格）")
                }
            }
            ocrCandidates = emptyList()
        }

        hits = found
        b.cond.grid.clearHits()
        if (hits.isEmpty()) {
            // 手动填的时候多半是字填错了；从图片识别过来的，更可能是认错了字，
            // 这时候多给一句"对照截图改一下"的提示
            result.showEmpty(
                getString(if (cameFromOcr) R.string.sc_no_result_ocr else R.string.sc_no_result)
            )
            return
        }
        // 默认选中第一条，并标亮它用到的格子
        b.cond.grid.setHits(hits[0].cells)
        val rows = hits.map { hit ->
            ResultRow(
                text = getString(R.string.sc_result_line, hit.item.line, hit.item.title, hit.item.author),
                payload = hit,
            )
        }
        result.show(rows, getString(R.string.sc_result_count, hits.size), null)
    }

    /** 清掉结果与标亮，保留字格内容 */
    private fun clearResultsOnly() {
        hits = emptyList()
        searched = false
        b.cond.grid.clearHits()
        result.showInitial(getString(R.string.empty_shici))
    }

    private fun clearAll() {
        b.cond.grid.clearAll()
        hits = emptyList()
        searched = false
        searchCount = 0
        updateCountText()
        result.showInitial(getString(R.string.empty_shici))
    }

    private fun updateCountText() {
        b.header.tvCount.text = getString(R.string.count_times, searchCount)
    }

    // ---------------------------------------------------------------- 结果区按键
    override fun onClearAll() = clearAll()

    /** 诗词模块只有一层：清空当前检索＝清掉结果，字格保留 */
    override fun onClearCurrent() = clearResultsOnly()

    override fun onSecondSearch() = Unit
}
