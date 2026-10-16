package com.wangchuan.fhlsearch

import com.wangchuan.fhlsearch.util.PinyinTone
import org.junit.Assert.assertEquals
import org.junit.Test

class PinyinToneTest {

    @Test
    fun singleSyllables() {
        assertEquals("àn", PinyinTone.mark("an4"))
        assertEquals("jiǎ", PinyinTone.mark("jia3"))
        assertEquals("xiū", PinyinTone.mark("xiu1"))
        assertEquals("bīng", PinyinTone.mark("bing1"))
        assertEquals("dù", PinyinTone.mark("du4"))
        assertEquals("chén", PinyinTone.mark("chen2"))
        assertEquals("cāng", PinyinTone.mark("cang1"))
    }

    @Test
    fun specialVowelGroups() {
        // iu -> 标在 u 上
        assertEquals("liú", PinyinTone.mark("liu2"))
        assertEquals("qiǔ", PinyinTone.mark("qiu3"))
        // ui -> 标在 i 上（uei 省略 e）
        assertEquals("tuī", PinyinTone.mark("tui1"))
        assertEquals("shuǐ", PinyinTone.mark("shui3"))
        // un / in -> 标在剩余元音上
        assertEquals("lún", PinyinTone.mark("lun2"))
        assertEquals("jīn", PinyinTone.mark("jin1"))
    }

    @Test
    fun umlautFromV() {
        assertEquals("lüè", PinyinTone.mark("lve4"))
        assertEquals("nǚ", PinyinTone.mark("nv3"))
        assertEquals("què", PinyinTone.mark("que4")) // 源数据用 ue 表示 üe
    }

    @Test
    fun neutralTone() {
        assertEquals("a", PinyinTone.mark("a5"))
        assertEquals("ba", PinyinTone.mark("ba"))
    }

    /** 回归测试：没有声调数字时，末尾字母绝不能当成声调数字被删掉 */
    @Test
    fun noToneDigitKeepsWholeSyllable() {
        assertEquals("ba", PinyinTone.mark("ba"))
        assertEquals("an", PinyinTone.mark("an"))
        assertEquals("de", PinyinTone.mark("de"))
        assertEquals("lü", PinyinTone.mark("lv"))
        // 整串都没有数字时，每个音节都要完整保留
        assertEquals("an du chen cang", PinyinTone.markPhrase("an du chen cang"))
        // 单字母音节也不能被删空
        assertEquals("a", PinyinTone.mark("a"))
        assertEquals("e", PinyinTone.mark("e"))
    }

    @Test
    fun phrase() {
        assertEquals("àn dù chén cāng", PinyinTone.markPhrase("an4 du4 chen2 cang1"))
    }
}
