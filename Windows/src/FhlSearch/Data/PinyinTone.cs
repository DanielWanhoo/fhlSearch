using System;
using System.Text;

namespace FhlSearch.Data
{
    /// <summary>
    /// 把"无声调拼音 + 数字声调"转成标准带调拼音（题库里存的是无声调形式）。
    /// 与安卓版 util/PinyinTone.kt 同一套规则：
    ///   1. 只有末位是 1~5 才算带声调，否则整串都是音节本身
    ///      （"ba" 必须还是 "ba"，不能把末尾的 a 当成声调删掉）；
    ///   2. 题库用 v 代表 ü，先还原成 ü；
    ///   3. 标调位置：有 a 标 a，否则有 o 标 o，否则有 e 标 e，否则标最后一个元音
    ///      （"iu 标 u""ui 标 i"本来就落在"最后一个元音"上）。
    /// </summary>
    public static class PinyinTone
    {
        static readonly char[] TA = { 'ā', 'á', 'ǎ', 'à', 'a' };
        static readonly char[] TE = { 'ē', 'é', 'ě', 'è', 'e' };
        static readonly char[] TI = { 'ī', 'í', 'ǐ', 'ì', 'i' };
        static readonly char[] TO = { 'ō', 'ó', 'ǒ', 'ò', 'o' };
        static readonly char[] TU = { 'ū', 'ú', 'ǔ', 'ù', 'u' };
        static readonly char[] TV = { 'ǖ', 'ǘ', 'ǚ', 'ǜ', 'ü' };

        const string VOWELS = "aeiouüAEIOUÜ";

        /// <summary>单个音节：如 "an4" -> "àn"，"ba" -> "ba"，"lve4" -> "lüè"</summary>
        public static string Mark(string syllable)
        {
            if (string.IsNullOrEmpty(syllable)) return syllable;

            char last = syllable[syllable.Length - 1];
            bool hasTone = last >= '1' && last <= '5';
            int tone = hasTone ? (last - '0') : 5;
            string body = hasTone ? syllable.Substring(0, syllable.Length - 1) : syllable;
            if (body.Length == 0) return syllable;

            string norm = body.Replace('v', 'ü').Replace('V', 'Ü');

            string lower = norm.ToLowerInvariant();
            int mi = -1;
            if (lower.IndexOf('a') >= 0) mi = lower.IndexOf('a');
            else if (lower.IndexOf('o') >= 0) mi = lower.IndexOf('o');
            else if (lower.IndexOf('e') >= 0) mi = lower.IndexOf('e');
            else
            {
                for (int i = norm.Length - 1; i >= 0; i--)
                    if (VOWELS.IndexOf(norm[i]) >= 0) { mi = i; break; }
            }
            if (mi < 0) return norm;

            char v = norm[mi];
            char repl = Toned(v, tone);
            return norm.Substring(0, mi) + repl + norm.Substring(mi + 1);
        }

        static char Toned(char vowel, int tone)
        {
            if (tone < 1 || tone > 5) tone = 5;
            int k = tone - 1;
            char c = char.ToLowerInvariant(vowel);
            switch (c)
            {
                case 'a': return TA[k];
                case 'e': return TE[k];
                case 'i': return TI[k];
                case 'o': return TO[k];
                case 'u': return TU[k];
                case 'ü': return TV[k];
            }
            return vowel;
        }
    }
}
