package com.wangchuan.fhlsearch.util

/**
 * 将数字声调拼音转换为标准带调拼音。
 * 源数据中的 ü 用 v 表示，如 "lve4" → "lüè"。
 */
object PinyinTone {

    private val TONES_A = charArrayOf('ā', 'á', 'ǎ', 'à', 'a')
    private val TONES_E = charArrayOf('ē', 'é', 'ě', 'è', 'e')
    private val TONES_I = charArrayOf('ī', 'í', 'ǐ', 'ì', 'i')
    private val TONES_O = charArrayOf('ō', 'ó', 'ǒ', 'ò', 'o')
    private val TONES_U = charArrayOf('ū', 'ú', 'ǔ', 'ù', 'u')
    private val TONES_V = charArrayOf('ǖ', 'ǘ', 'ǚ', 'ǜ', 'ü')

    /**
     * 把单个音节的数字声调转为声调符号。
     * 支持 1-4 声与 5（轻声）；**没有数字则视为轻声**，此时原样返回、不加符号，
     * 也绝不能把末尾的字母当成声调数字删掉（"ba" 必须还是 "ba"，不是 "b"）。
     */
    fun mark(syllable: String): String {
        if (syllable.isEmpty()) return syllable
        val last = syllable.last()
        // 只有末位真的是数字时才算"带声调"，否则整体都是音节本体
        val hasTone = last in '1'..'5'
        val tone = if (hasTone) last.digitToInt() else 5
        val body = if (hasTone) syllable.dropLast(1) else syllable
        if (body.isEmpty()) return syllable

        // 源数据用 v 代替 ü
        val normalized = body.replace('v', 'ü').replace('V', 'Ü')

        // 标调位置规则：有 a 标 a；否则有 o 标 o；否则有 e 标 e；否则标最后一个元音。
        // （"iu 标 u"、"ui 标 i" 本来就落在"最后一个元音"上，无需单独判断；
        //   这里用 lowercase 只是为了不受大小写影响，拼音字母大小写转换不改变长度）
        val lower = normalized.lowercase()
        val markIndex = when {
            lower.contains('a') -> lower.indexOf('a')
            lower.contains('o') -> lower.indexOf('o')
            lower.contains('e') -> lower.indexOf('e')
            else -> normalized.indexOfLast { it in VOWELS }
        }

        if (markIndex < 0) return normalized

        val vowel = normalized[markIndex]
        val replacement = toned(vowel, tone)
        return normalized.replaceRange(markIndex, markIndex + 1, replacement.toString())
    }

    /** 把带空格的多音节数字声调串整体转换，例如 "an4 jia3 xiu1 bing1"。 */
    fun markPhrase(phrase: String): String = phrase
        .split(' ')
        .joinToString(" ") { mark(it) }

    private val VOWELS = "aeiouüAEIOUÜ"

    private fun toned(vowel: Char, tone: Int): Char = when (vowel.lowercaseChar()) {
        'a' -> TONES_A[tone - 1]
        'e' -> TONES_E[tone - 1]
        'i' -> TONES_I[tone - 1]
        'o' -> TONES_O[tone - 1]
        'u' -> TONES_U[tone - 1]
        'ü' -> TONES_V[tone - 1]
        else -> vowel
    }
}
