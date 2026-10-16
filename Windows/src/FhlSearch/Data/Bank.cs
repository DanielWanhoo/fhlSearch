using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Text;

namespace FhlSearch.Data
{
    // ============================================================ 数据模型

    public class Idiom
    {
        public string Text;
        public string[] Py = new string[4];
        public int[] Tone = new int[4];
        public char[] Zi = new char[4];
        /// <summary>分词文本 "暗渡陈仓 an du chen cang 4 4 2 1" 只用于排序</summary>
        public string SortKey;
    }

    public class Poem
    {
        public string Verse;
        public string Title;
        public string Author;
        public bool HasRepeat { get { return Verse != null && Verse.Length == 5 && new HashSet<char>(Verse).Count != 5; } }
    }

    public class Person
    {
        public string Name;
        public string Dynasty;        // 原始值（可能形如 "五代十国（南唐）"）
        public string DynastyKey;     // 去掉括号后的归并值，用于精确匹配
        public string Rank;
        public string Job, Meet, Origin, Skill;
        public string[] Hobbies = new string[0];
        public string[] Clubs = new string[0];
        public string[] Descs = new string[0];

        // 归一化（只留汉字）后的检索用文本
        public string JobN, MeetN, OriginN, SkillN;
        public string[] DescsN = new string[0];

        public string Display { get { return Dynasty.Length > 0 ? Name + "（" + Dynasty + "）" : Name; } }
    }

    // ============================================================ 检索模式

    public enum PersonMode
    {
        Dynasty = 0,   // 朝代     —— 菜单
        Hobby = 1,     // 爱好     —— 菜单
        Club = 2,      // 社团     —— 菜单
        Rank = 3,      // 品阶     —— 菜单
        Job = 4,       // 职业     —— 文本
        Meet = 5,      // 生逢     —— 文本
        Origin = 6,    // 出身/身世 —— 文本
        Skill = 7,     // 技能     —— 文本
        Desc = 8       // 其他描述 —— 文本
    }

    // ============================================================ 题库

    /// <summary>
    /// 内嵌题库。数据由 tools/build_data.py 从三个 xlsx 生成，
    /// 编译期塞进 exe 的资源里，运行时完全不需要 Excel。
    /// </summary>
    public static class Bank
    {
        public const string ResourceName = "FhlSearch.bank.txt";

        public static readonly List<Idiom> Idioms = new List<Idiom>();
        public static readonly List<Poem> Poems = new List<Poem>();
        public static readonly List<Person> People = new List<Person>();

        public static string[] OptDynasty = new string[0];
        public static string[] OptHobby = new string[0];
        public static string[] OptClub = new string[0];
        public static string[] OptRank = new string[0];

        public static string GenTime = "";
        public static string[] SourceInfo = new string[0];
        public static string LoadError = null;
        public static bool Loaded { get; private set; }

        const char US = '\u001f';

        public static void Load()
        {
            if (Loaded) return;
            Loaded = true;
            try
            {
                string text = ReadResource();
                if (text == null) { LoadError = "找不到内嵌题库资源 " + ResourceName; return; }
                Parse(text);
            }
            catch (Exception ex)
            {
                LoadError = ex.Message;
            }
        }

        static string ReadResource()
        {
            Assembly asm = Assembly.GetExecutingAssembly();
            using (Stream s = asm.GetManifestResourceStream(ResourceName))
            {
                if (s == null)
                {
                    // 兜底：按后缀名找
                    foreach (string n in asm.GetManifestResourceNames())
                    {
                        if (n.EndsWith("bank.txt", StringComparison.OrdinalIgnoreCase))
                        {
                            using (Stream s2 = asm.GetManifestResourceStream(n))
                                return Decode(s2);
                        }
                    }
                    return null;
                }
                return Decode(s);
            }
        }

        static string Decode(Stream s)
        {
            // 必须显式 UTF-8：中文系统上 Encoding.Default 是 gb2312，用错会乱码
            using (StreamReader r = new StreamReader(s, new UTF8Encoding(false), true))
                return r.ReadToEnd();
        }

        static void Parse(string text)
        {
            string cur = null;
            string[] lines = text.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n');
            List<string> meta = new List<string>();

            foreach (string raw in lines)
            {
                string line = raw;
                if (line.Length == 0) continue;
                if (line[0] == '#')
                {
                    if (line.StartsWith("# 生成时间: ")) GenTime = line.Substring(7).Trim();
                    else meta.Add(line.TrimStart('#', ' '));
                    continue;
                }
                if (line[0] == '[' && line[line.Length - 1] == ']')
                {
                    cur = line.Substring(1, line.Length - 2);
                    continue;
                }
                switch (cur)
                {
                    case "OPT_DYNASTY": OptDynasty = Add(OptDynasty, line); break;
                    case "OPT_HOBBY": OptHobby = Add(OptHobby, line); break;
                    case "OPT_CLUB": OptClub = Add(OptClub, line); break;
                    case "OPT_RANK": OptRank = Add(OptRank, line); break;
                    case "IDIOM": ParseIdiom(line); break;
                    case "POEM": ParsePoem(line); break;
                    case "PERSON": ParsePerson(line); break;
                }
            }
            SourceInfo = meta.ToArray();
        }

        static string[] Add(string[] arr, string v)
        {
            string[] r = new string[arr.Length + 1];
            Array.Copy(arr, r, arr.Length);
            r[arr.Length] = v;
            return r;
        }

        static string[] Split(string s, char sep)
        {
            if (string.IsNullOrEmpty(s)) return new string[0];
            return s.Split(sep);
        }

        static void ParseIdiom(string line)
        {
            string[] f = line.Split('\t');
            if (f.Length < 9) return;
            Idiom it = new Idiom();
            it.Text = f[0];
            if (it.Text.Length != 4) return;
            for (int i = 0; i < 4; i++)
            {
                it.Py[i] = f[1 + i];
                int t;
                it.Tone[i] = int.TryParse(f[5 + i], out t) ? t : 0;
                it.Zi[i] = it.Text[i];
            }
            it.SortKey = it.Py[0] + " " + it.Py[1] + " " + it.Py[2] + " " + it.Py[3] + " " + it.Text;
            Idioms.Add(it);
        }

        static void ParsePoem(string line)
        {
            string[] f = line.Split('\t');
            if (f.Length < 3) return;
            if (f[0].Length != 5) return;
            Poems.Add(new Poem { Verse = f[0], Title = f[1], Author = f[2] });
        }

        static void ParsePerson(string line)
        {
            string[] f = line.Split('\t');
            if (f.Length < 10) return;
            Person p = new Person();
            p.Name = f[0];
            p.Dynasty = f[1];
            p.Rank = f[2];
            p.Job = f[3];
            p.Meet = f[4];
            p.Origin = f[5];
            p.Skill = f[6];
            p.Hobbies = Split(f[7], US);
            p.Clubs = Split(f[8], US);
            p.Descs = Split(f[9], US);
            p.DynastyKey = StripParen(p.Dynasty);
            p.JobN = Cjk(p.Job);
            p.MeetN = Cjk(p.Meet);
            p.OriginN = Cjk(p.Origin);
            p.SkillN = Cjk(p.Skill);
            string[] dn = new string[p.Descs.Length];
            for (int i = 0; i < p.Descs.Length; i++) dn[i] = Cjk(p.Descs[i]);
            p.DescsN = dn;
            People.Add(p);
        }

        // ======================================================== 文本归一化

        /// <summary>
        /// 只保留汉字（含扩展 A 区），去掉标点、数字、字母、空格、换行、括号等一切其它字符。
        /// 用于名士检索的模糊匹配。
        /// </summary>
        public static string Cjk(string s)
        {
            if (string.IsNullOrEmpty(s)) return "";
            StringBuilder sb = new StringBuilder(s.Length);
            foreach (char ch in s)
            {
                if ((ch >= 0x4E00 && ch <= 0x9FFF) || (ch >= 0x3400 && ch <= 0x4DBF))
                    sb.Append(ch);
            }
            return sb.ToString();
        }

        /// <summary>去掉形如 "（南唐）" / "(南唐)" 的括注，用于朝代的归并匹配</summary>
        public static string StripParen(string s)
        {
            if (string.IsNullOrEmpty(s)) return "";
            StringBuilder sb = new StringBuilder(s.Length);
            int depth = 0;
            foreach (char ch in s)
            {
                if (ch == '（' || ch == '(') { depth++; continue; }
                if (ch == '）' || ch == ')') { if (depth > 0) depth--; continue; }
                if (depth == 0) sb.Append(ch);
            }
            return sb.ToString().Trim();
        }

        // ======================================================== 成语检索

        /// <summary>
        /// 按一个位置的条件判断成语是否命中。
        /// mode: 0=拼音(子串) 1=声调(精确) 2=单字(精确)
        /// </summary>
        public static bool IdiomHit(Idiom it, int mode, int pos, string value)
        {
            if (string.IsNullOrEmpty(value)) return true;
            switch (mode)
            {
                case 0: return it.Py[pos].IndexOf(value, StringComparison.OrdinalIgnoreCase) >= 0;
                case 1:
                    int t;
                    return int.TryParse(value, out t) && it.Tone[pos] == t;
                default: return it.Zi[pos].ToString() == value;
            }
        }

        // ======================================================== 诗词检索

        /// <summary>
        /// 给定字格（30 格，空格子为 '\0'），找出所有能拼出的诗句。
        /// 判据：诗句里每个字的出现次数都不超过字格里该字的可用格子数。
        /// </summary>
        public static List<Poem> MatchPoems(char[] grid, out Dictionary<Poem, int[]> cellMap)
        {
            cellMap = new Dictionary<Poem, int[]>();
            List<Poem> hits = new List<Poem>();

            Dictionary<char, int> avail = new Dictionary<char, int>();
            Dictionary<char, List<int>> where = new Dictionary<char, List<int>>();
            for (int i = 0; i < grid.Length; i++)
            {
                char c = grid[i];
                if (c == '\0' || c == ' ') continue;
                int n;
                avail.TryGetValue(c, out n);
                avail[c] = n + 1;
                List<int> lst;
                if (!where.TryGetValue(c, out lst)) { lst = new List<int>(); where[c] = lst; }
                lst.Add(i);
            }
            if (avail.Count == 0) return hits;

            foreach (Poem p in Poems)
            {
                string v = p.Verse;
                if (v.Length != 5) continue;
                // 统计需求
                Dictionary<char, int> need = new Dictionary<char, int>();
                bool ok = true;
                foreach (char c in v)
                {
                    int n;
                    need.TryGetValue(c, out n);
                    need[c] = n + 1;
                    int have;
                    if (!avail.TryGetValue(c, out have) || n + 1 > have) { ok = false; break; }
                }
                if (!ok) continue;

                // 分配具体格子（同字依次取用，保证不重复占用）
                Dictionary<char, int> used = new Dictionary<char, int>();
                int[] cells = new int[5];
                bool assign = true;
                for (int k = 0; k < 5; k++)
                {
                    char c = v[k];
                    int n;
                    used.TryGetValue(c, out n);
                    List<int> lst = where[c];
                    if (n >= lst.Count) { assign = false; break; }
                    cells[k] = lst[n];
                    used[c] = n + 1;
                }
                if (!assign) continue;

                hits.Add(p);
                cellMap[p] = cells;
            }
            return hits;
        }

        // ======================================================== 名士检索

        /// <summary>模糊命中：归一化后做连续子串匹配（不拆分检索词）</summary>
        public static bool Fuzzy(string normalizedHaystack, string rawNeedle)
        {
            string needle = Cjk(rawNeedle);
            if (needle.Length == 0) return true;   // 空条件视为不限
            if (string.IsNullOrEmpty(normalizedHaystack)) return false;
            return normalizedHaystack.IndexOf(needle, StringComparison.Ordinal) >= 0;
        }

        /// <summary>判断某位名士是否满足一次条件</summary>
        public static bool PersonHit(Person p, PersonMode mode, string value)
        {
            if (value == null) value = "";
            switch (mode)
            {
                case PersonMode.Dynasty:
                    if (value.Length == 0) return true;
                    return p.DynastyKey == StripParen(value);
                case PersonMode.Hobby:
                    if (value.Length == 0) return true;
                    foreach (string h in p.Hobbies) if (h == value) return true;
                    return false;
                case PersonMode.Club:
                    if (value.Length == 0) return true;
                    foreach (string c in p.Clubs) if (c == value) return true;
                    return false;
                case PersonMode.Rank:
                    if (value.Length == 0) return true;
                    return p.Rank == value;
                case PersonMode.Job:
                    return string.IsNullOrEmpty(Cjk(value)) || Fuzzy(p.JobN, value);
                case PersonMode.Meet:
                    return string.IsNullOrEmpty(Cjk(value)) || Fuzzy(p.MeetN, value);
                case PersonMode.Origin:
                    return string.IsNullOrEmpty(Cjk(value)) || Fuzzy(p.OriginN, value);
                case PersonMode.Skill:
                    return string.IsNullOrEmpty(Cjk(value)) || Fuzzy(p.SkillN, value);
                case PersonMode.Desc:
                    if (string.IsNullOrEmpty(Cjk(value))) return true;
                    foreach (string d in p.DescsN) if (Fuzzy(d, value)) return true;
                    return false;
            }
            return true;
        }

        /// <summary>该检索模式是否为"菜单选项卡"型</summary>
        public static bool IsMenuMode(PersonMode m)
        {
            return m == PersonMode.Dynasty || m == PersonMode.Hobby
                || m == PersonMode.Club || m == PersonMode.Rank;
        }

        public static string[] OptionsOf(PersonMode m)
        {
            switch (m)
            {
                case PersonMode.Dynasty: return OptDynasty;
                case PersonMode.Hobby: return OptHobby;
                case PersonMode.Club: return OptClub;
                case PersonMode.Rank: return OptRank;
            }
            return new string[0];
        }

        public static string ModeName(PersonMode m)
        {
            switch (m)
            {
                case PersonMode.Dynasty: return "朝代";
                case PersonMode.Hobby: return "爱好";
                case PersonMode.Club: return "社团";
                case PersonMode.Rank: return "品阶";
                case PersonMode.Job: return "职业";
                case PersonMode.Meet: return "生逢（生于…）";
                case PersonMode.Origin: return "出身 / 身世";
                case PersonMode.Skill: return "技能";
                case PersonMode.Desc: return "其他描述";
            }
            return "?";
        }

        /// <summary>文本框模式的输入框提示语</summary>
        public static string ModeHint(PersonMode m)
        {
            switch (m)
            {
                case PersonMode.Job: return "例如：帝王 / 诗人 / 将领";
                case PersonMode.Meet: return "例如：乱世 / 王朝更迭 / 盛世";
                case PersonMode.Origin: return "例如：出身显贵 / 家道中落";
                case PersonMode.Skill: return "例如：灵术 / 金戈演武 / 落雷";
                case PersonMode.Desc: return "在描述 1 – 15 中模糊查找，例如：求仙问道";
            }
            return "";
        }
    }
}
