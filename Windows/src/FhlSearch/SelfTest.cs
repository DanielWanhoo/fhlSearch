using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using FhlSearch.Data;

namespace FhlSearch
{
    /// <summary>
    /// 离线自测：读一个检索脚本，逐条执行并输出结果，用于和 Python 参考实现对拍。
    ///
    /// 脚本格式（每行一条，UTF-8）：
    ///   IDIOM  &lt;模式0拼音/1声调/2单字&gt; &lt;v1,v2,v3,v4&gt;            在全部题库里检索
    ///   IDIOM2 &lt;模式&gt; &lt;v1..v4&gt; &lt;模式&gt; &lt;v1..v4&gt;              先检索，再在上次结果上二次检索
    ///   POEM   &lt;30 个字符的字格，. 表示空格&gt;
    ///   PERSON &lt;模式0-8&gt; &lt;检索词&gt;
    ///
    /// 输出格式：&lt;原脚本行&gt;\t&lt;条数&gt;\t&lt;结果1|结果2|...&gt;
    /// </summary>
    public static class SelfTest
    {
        public static int Run(string scriptPath, string outPath)
        {
            Bank.Load();
            if (Bank.LoadError != null)
            {
                File.WriteAllText(outPath, "BANK_ERROR\t" + Bank.LoadError + "\n", new UTF8Encoding(false));
                return 2;
            }

            List<string> lines = new List<string>();
            using (StreamReader r = new StreamReader(scriptPath, new UTF8Encoding(false), true))
            {
                string s;
                while ((s = r.ReadLine()) != null)
                {
                    s = s.Trim();
                    if (s.Length == 0 || s[0] == '#') continue;
                    lines.Add(s);
                }
            }

            StringBuilder sb = new StringBuilder();
            sb.Append("# 忘川检索 自测输出\n");
            sb.Append("# 成语=").Append(Bank.Idioms.Count)
              .Append(" 诗句=").Append(Bank.Poems.Count)
              .Append(" 名士=").Append(Bank.People.Count).Append('\n');
            sb.Append("# 生成时间 ").Append(Bank.GenTime).Append('\n');

            foreach (string line in lines)
            {
                string[] tok = line.Split('|');   // 用 | 分隔，允许检索词里含空格
                string kind = tok[0];
                List<string> res = new List<string>();

                try
                {
                    if (kind == "IDIOM" && tok.Length >= 3)
                    {
                        int mode = int.Parse(tok[1]);
                        string[] v = Split4(tok[2]);
                        foreach (Idiom it in Bank.Idioms)
                            if (IdiomOk(it, mode, v)) res.Add(it.Text);
                    }
                    else if (kind == "IDIOM2" && tok.Length >= 5)
                    {
                        int m1 = int.Parse(tok[1]);
                        string[] v1 = Split4(tok[2]);
                        int m2 = int.Parse(tok[3]);
                        string[] v2 = Split4(tok[4]);
                        List<Idiom> stage1 = new List<Idiom>();
                        foreach (Idiom it in Bank.Idioms) if (IdiomOk(it, m1, v1)) stage1.Add(it);
                        foreach (Idiom it in stage1) if (IdiomOk(it, m2, v2)) res.Add(it.Text);
                    }
                    else if (kind == "POEM" && tok.Length >= 2)
                    {
                        string g = tok[1];
                        char[] grid = new char[30];
                        for (int i = 0; i < 30; i++)
                            grid[i] = (i < g.Length && g[i] != '.') ? g[i] : '\0';
                        Dictionary<Poem, int[]> map;
                        List<Poem> hits = Bank.MatchPoems(grid, out map);
                        hits.Sort(delegate (Poem a, Poem b) { return string.CompareOrdinal(a.Verse, b.Verse); });
                        foreach (Poem p in hits)
                        {
                            int[] cells = map[p];
                            StringBuilder cb = new StringBuilder();
                            for (int i = 0; i < 5; i++) { if (i > 0) cb.Append(','); cb.Append(cells[i]); }
                            res.Add(p.Verse + "[" + cb + "]");
                        }
                    }
                    else if (kind == "PERSON" && tok.Length >= 3)
                    {
                        PersonMode m = (PersonMode)int.Parse(tok[1]);
                        string v = tok[2] == "-" ? "" : tok[2];
                        foreach (Person p in Bank.People)
                            if (Bank.PersonHit(p, m, v)) res.Add(p.Display);
                    }
                    else
                    {
                        sb.Append("SKIP\t").Append(line).Append('\n');
                        continue;
                    }
                }
                catch (Exception ex)
                {
                    sb.Append("ERROR\t").Append(line).Append('\t').Append(ex.Message).Append('\n');
                    continue;
                }

                sb.Append(line).Append('\t').Append(res.Count).Append('\t');
                for (int i = 0; i < res.Count; i++)
                {
                    if (i > 0) sb.Append('|');
                    sb.Append(res[i]);
                }
                sb.Append('\n');
            }

            File.WriteAllText(outPath, sb.ToString(), new UTF8Encoding(false));
            return 0;
        }

        static string[] Split4(string s)
        {
            string[] p = s.Split(',');
            string[] r = new string[4];
            for (int i = 0; i < 4; i++) r[i] = i < p.Length ? p[i] : "";
            return r;
        }

        static bool IdiomOk(Idiom it, int mode, string[] v)
        {
            for (int k = 0; k < 4; k++)
                if (!Bank.IdiomHit(it, mode, k, v[k])) return false;
            return true;
        }
    }
}
