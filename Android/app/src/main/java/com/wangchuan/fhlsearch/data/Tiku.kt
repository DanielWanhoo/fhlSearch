package com.wangchuan.fhlsearch.data

import com.wangchuan.fhlsearch.util.PinyinTone
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.InputStreamReader

/**
 * 题库数据（编译期内嵌在 assets 中，运行时完全离线）。
 *
 * 数据由 tools/build_tiku.py 从三份 Excel 生成，字段含义：
 *  - 成语：[w]成语 [p]4个无声调小写拼音 [t]4个声调 [c]4个单字
 *  - 诗句：[l]诗句 [n]诗词名 [a]作者 [c]5个单字
 *  - 名士：name/dynasty/rank/job/born/origin/skill + love[]/club[]/desc[]
 *          norm{} 与 descNorm[] 是打包期算好的"只留汉字"归一化文本，供模糊检索用
 */
object Tiku {

    const val FILE_CHENGYU = "tiku_chengyu.json"
    const val FILE_SHIci = "tiku_shici.json"
    const val FILE_MINGSHI = "tiku_mingshi.json"

    /** 名士的 5 个模糊检索字段，顺序与界面一致 */
    val TEXT_FIELDS = listOf(
        "job" to "职业",
        "born" to "生逢（生于...）",
        "origin" to "出身/身世",
        "skill" to "技能",
    )
    const val FIELD_OTHER = "other"

    private fun text(app: android.content.Context, name: String, loader: (String) -> Unit) {
        app.assets.open(name).use { ins ->
            InputStreamReader(ins, Charsets.UTF_8).use { r -> loader(r.readText()) }
        }
    }

    fun loadChengyu(app: android.content.Context): List<ChengyuItem> {
        var out: List<ChengyuItem> = emptyList()
        text(app, FILE_CHENGYU) { s -> out = parseChengyu(s) }
        return out
    }

    fun loadShici(app: android.content.Context): List<ShiciItem> {
        var out: List<ShiciItem> = emptyList()
        text(app, FILE_SHIci) { s -> out = parseShici(s) }
        return out
    }

    fun loadMingshi(app: android.content.Context): List<MingshiItem> {
        var out: List<MingshiItem> = emptyList()
        text(app, FILE_MINGSHI) { s -> out = parseMingshi(s) }
        return out
    }

    // ---------------------------------------------------------------- 解析
    internal fun parseChengyu(json: String): List<ChengyuItem> {
        val root = JSONObject(json)
        val arr = root.getJSONArray("items")
        val list = ArrayList<ChengyuItem>(arr.length())
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            list.add(
                ChengyuItem(
                    word = o.getString("w"),
                    pinyin = o.getJSONArray("p").toStringList(),
                    tone = o.getJSONArray("t").toStringList(),
                    chars = o.getJSONArray("c").toStringList(),
                )
            )
        }
        return list
    }

    internal fun parseShici(json: String): List<ShiciItem> {
        val root = JSONObject(json)
        val arr = root.getJSONArray("items")
        val list = ArrayList<ShiciItem>(arr.length())
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            list.add(
                ShiciItem(
                    line = o.getString("l"),
                    title = o.getString("n"),
                    author = o.getString("a"),
                    chars = o.getJSONArray("c").toStringList(),
                )
            )
        }
        return list
    }

    internal fun parseMingshi(json: String): List<MingshiItem> {
        val root = JSONObject(json)
        val arr = root.getJSONArray("items")
        val list = ArrayList<MingshiItem>(arr.length())
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            val normObj = o.optJSONObject("norm") ?: JSONObject()
            val norm = HashMap<String, String>()
            for (k in normObj.keys()) norm[k] = normObj.optString(k, "")
            list.add(
                MingshiItem(
                    name = o.getString("name"),
                    dynasty = o.optString("dynasty"),
                    rank = o.optString("rank"),
                    job = o.optString("job"),
                    born = o.optString("born"),
                    origin = o.optString("origin"),
                    skill = o.optString("skill"),
                    love = o.optJSONArray("love").toStringList(),
                    club = o.optJSONArray("club").toStringList(),
                    desc = o.optJSONArray("desc").toStringList(),
                    norm = norm,
                    descNorm = o.optJSONArray("descNorm").toStringList(),
                )
            )
        }
        return list
    }

    private fun org.json.JSONArray?.toStringList(): List<String> {
        if (this == null) return emptyList()
        val l = ArrayList<String>(length())
        for (i in 0 until length()) l.add(optString(i, ""))
        return l
    }
}

/** 成语条目 */
data class ChengyuItem(
    val word: String,
    val pinyin: List<String>,
    val tone: List<String>,
    val chars: List<String>,
) {
    /** 结果列表展示用：拼音与声调合起来，如 "àn dù chén cāng" */
    val pinyinWithTone: String
        get() = (0 until 4).joinToString(" ") { PinyinTone.mark(pinyin[it] + tone[it]) }
}

/** 诗句条目 */
data class ShiciItem(
    val line: String,
    val title: String,
    val author: String,
    val chars: List<String>,
)

/** 名士条目 */
data class MingshiItem(
    val name: String,
    val dynasty: String,
    val rank: String,
    val job: String,
    val born: String,
    val origin: String,
    val skill: String,
    val love: List<String>,
    val club: List<String>,
    val desc: List<String>,
    val norm: Map<String, String>,
    val descNorm: List<String>,
) {
    /** 需求指定的展示格式：名士（朝代） */
    val label: String get() = "$name（$dynasty）"
}

/** 在后台线程读一次题库并缓存（三个模块共用一份） */
suspend fun loadAllTiku(ctx: android.content.Context) = withContext(Dispatchers.IO) {
    LoadedTiku(
        chengyu = Tiku.loadChengyu(ctx),
        shici = Tiku.loadShici(ctx),
        mingshi = Tiku.loadMingshi(ctx),
    )
}

data class LoadedTiku(
    val chengyu: List<ChengyuItem>,
    val shici: List<ShiciItem>,
    val mingshi: List<MingshiItem>,
)
