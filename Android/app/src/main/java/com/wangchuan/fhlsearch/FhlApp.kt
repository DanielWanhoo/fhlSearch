package com.wangchuan.fhlsearch

import android.app.Application
import com.wangchuan.fhlsearch.data.LoadedTiku
import com.wangchuan.fhlsearch.data.loadAllTiku
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * 应用入口：启动时在后台把内嵌题库读进内存（合计约 135 KB，一次性）。
 *
 * 题库是编译期内嵌的 assets 文件，不联网、不读 Excel，因此加载是纯本地操作。
 */
class FhlApp : Application() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    /** 题库缓存（读好后对所有界面可见） */
    @Volatile
    var tiku: LoadedTiku? = null
        private set

    /** 加载失败信息（正常为 null；失败时界面提示"题库数据读取失败，请重新安装应用"） */
    @Volatile
    var loadError: String? = null
        private set

    private val callbacks = ArrayList<(LoadedTiku?) -> Unit>()

    override fun onCreate() {
        super.onCreate()
        scope.launch {
            try {
                val t = loadAllTiku(this@FhlApp)
                tiku = t
                notifyCallbacks(t)
            } catch (e: Exception) {
                loadError = e.message ?: e.javaClass.simpleName
                notifyCallbacks(null)
            }
        }
    }

    /** 题库就绪时回调；已就绪则立即回调 */
    fun whenReady(cb: (LoadedTiku?) -> Unit) {
        val t = tiku
        if (t != null) {
            cb(t)
            return
        }
        if (loadError != null) {
            cb(null)
            return
        }
        synchronized(callbacks) { callbacks.add(cb) }
    }

    private fun notifyCallbacks(t: LoadedTiku?) {
        val list: List<(LoadedTiku?) -> Unit>
        synchronized(callbacks) {
            list = ArrayList(callbacks)
            callbacks.clear()
        }
        list.forEach { it(t) }
    }
}
