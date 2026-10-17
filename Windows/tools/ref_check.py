# -*- coding: utf-8 -*-
"""
fhlSearch 检索规则参考实现（只用 Python + openpyxl 直接读原始 xlsx，
完全不经过 bank.txt 和 C# 代码），用于和程序内的自测输出对拍。

生成检索脚本 -> 交给 fhlSearch.exe --selftest 执行 -> 两边结果逐行 diff。

用法:
  python tools/ref_check.py gen  <脚本路径>
  python tools/ref_check.py run  <脚本路径> <输出路径>
"""
import sys, io, os
# 输出跟随系统编码（中文 Windows 的 cmd 是 GBK），只把编不出来的字符降级，避免抛异常。
# 需要强制 UTF-8 时，设环境变量 PYTHONIOENCODING=utf-8。
try:
    sys.stdout.reconfigure(errors='replace')
except Exception:
    pass
import openpyxl

SRC = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data")
_f = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bank_src.txt")
if os.path.exists(_f):
    with open(_f, encoding="utf-8-sig") as _h:
        _line = _h.readline().strip()
    if _line and not _line.startswith("#"):
        SRC = _line
US = '\x1f'


def g(v):
    return "" if v is None else str(v).strip()


# ---------------------------------------------------------------- 载入（直接读 xlsx）

def load_idioms():
    wb = openpyxl.load_workbook(os.path.join(SRC, "成语检索.xlsx"), data_only=True)
    ws = wb[wb.sheetnames[0]]
    out = []
    for r in ws.iter_rows(min_row=3, values_only=True):
        t = g(r[0])
        if not t or len(t) != 4:
            continue
        py = [g(r[c]).lower() for c in range(1, 5)]
        tn = [g(r[c]) for c in range(5, 9)]
        out.append((t, py, tn, list(t)))
    wb.close()
    return out


def load_poems():
    wb = openpyxl.load_workbook(os.path.join(SRC, "诗词检索.xlsx"), data_only=True)
    ws = wb[wb.sheetnames[0]]
    out = []
    for r in ws.iter_rows(min_row=2, values_only=True):
        v = g(r[0])
        if len(v) != 5:
            continue
        out.append((v, g(r[1]), g(r[2])))
    wb.close()
    return out


def load_people():
    wb = openpyxl.load_workbook(os.path.join(SRC, "名士检索.xlsx"), data_only=True)
    ws = wb[wb.sheetnames[0]]
    rows = list(ws.iter_rows(values_only=True))
    starts = [i for i in range(1, len(rows)) if g(rows[i][0])]
    people = []
    for k, s in enumerate(starts):
        e = starts[k + 1] - 1 if k + 1 < len(starts) else len(rows) - 1
        p = {
            "name": g(rows[s][0]), "dyn": g(rows[s][1]), "rank": g(rows[s][4]),
            "job": g(rows[s][5]), "meet": g(rows[s][6]), "origin": g(rows[s][7]),
            "skill": g(rows[s][8]), "hobby": [], "club": [], "desc": [],
        }
        for r in range(s, e + 1):
            v = g(rows[r][2])
            if v and v not in p["hobby"]: p["hobby"].append(v)
            v = g(rows[r][3])
            if v and v not in p["club"]: p["club"].append(v)
            for c in range(9, 24):
                v = g(rows[r][c])
                if v: p["desc"].append(v)
        people.append(p)
    wb.close()
    return people


# ---------------------------------------------------------------- 归一化

def cjk(s):
    return "".join(ch for ch in (s or "") if '\u4e00' <= ch <= '\u9fff' or '\u3400' <= ch <= '\u4dbf')


def strip_paren(s):
    out, depth = [], 0
    for ch in (s or ""):
        if ch in "（(":
            depth += 1; continue
        if ch in "）)":
            if depth: depth -= 1
            continue
        if depth == 0: out.append(ch)
    return "".join(out).strip()


def display(p):
    return p["name"] + ("（" + p["dyn"] + "）" if p["dyn"] else "")


# ---------------------------------------------------------------- 检索规则

def idiom_hit(it, mode, v):
    t, py, tn, zi = it
    for k in range(4):
        if not v[k]:
            continue
        if mode == 0:
            if v[k].lower() not in py[k]: return False
        elif mode == 1:
            if not v[k].isdigit() or int(v[k]) != int(tn[k]): return False
        else:
            if v[k] != zi[k]: return False
    return True


def match_poems(grid, poems):
    """grid: 长度 30，'\0' 表示空格"""
    avail, where = {}, {}
    for i, c in enumerate(grid):
        if c == '\0' or c == ' ':
            continue
        avail[c] = avail.get(c, 0) + 1
        where.setdefault(c, []).append(i)
    hits = []
    for v, title, author in poems:
        need, ok = {}, True
        for c in v:
            need[c] = need.get(c, 0) + 1
            if need[c] > avail.get(c, 0):
                ok = False; break
        if not ok: continue
        used, cells, assign = {}, [], True
        for c in v:
            n = used.get(c, 0)
            if n >= len(where[c]): assign = False; break
            cells.append(where[c][n]); used[c] = n + 1
        if not assign: continue
        hits.append((v, cells))
    return hits


def fuzzy(hay_norm, needle_raw):
    n = cjk(needle_raw)
    if not n: return True
    if not hay_norm: return False
    return n in hay_norm


def person_hit(p, mode, v):
    v = v or ""
    if mode == 0:
        return (not v) or p["dyn"] == strip_paren(v) or strip_paren(p["dyn"]) == strip_paren(v)
    if mode == 1:
        return (not v) or v in p["hobby"]
    if mode == 2:
        return (not v) or v in p["club"]
    if mode == 3:
        return (not v) or p["rank"] == v
    if not cjk(v):
        return True
    if mode == 4: return fuzzy(cjk(p["job"]), v)
    if mode == 5: return fuzzy(cjk(p["meet"]), v)
    if mode == 6: return fuzzy(cjk(p["origin"]), v)
    if mode == 7: return fuzzy(cjk(p["skill"]), v)
    if mode == 8:
        return any(fuzzy(cjk(d), v) for d in p["desc"])
    return True


# ---------------------------------------------------------------- 检索脚本

DYNASTY = ["汉", "明", "秦", "三国", "宋", "唐", "五代十国", "西楚", "晋", "先秦",
           "梦", "南北朝", "清", "元", "辽"]
HOBBY = ["博文", "乐舞", "品茗", "赏玩", "食珍", "书画", "雅宴", "演武", "弈棋", "妆饰"]
CLUB = ["百家书院", "千工苑", "金戈馆", "容华社", "棠梨坊", "饕餮居", "五湖商社", "逸趣社", "无"]
RANK = ["天", "地", "玄"]


def gen_script():
    L = []
    L.append("# 成语检索")
    for mode, vals in [
        (0, ["du", "", "", ""]),
        (0, ["", "du", "", ""]),
        (0, ["zh", "", "", ""]),
        (0, ["", "", "", "ang"]),
        (0, ["an", "", "", ""]),
        (0, ["sh", "i", "", ""]),
        (0, ["g", "g", "z", "z"]),
        (0, ["", "", "", ""]),
        (0, ["chen", "cang", "", ""]),
        (0, ["zzz", "", "", ""]),
        # 整字精确拼音：gou=狗急跳墙（题库里曾误写成 go，靠这两条锁住订正）
        (0, ["gou", "", "", ""]),
        (0, ["go", "", "", ""]),
        (0, ["gong", "", "", ""]),
        (1, ["4", "4", "2", "1"]),
        (1, ["1", "", "", ""]),
        (1, ["", "", "", "4"]),
        (1, ["2", "2", "2", "3"]),
        (2, ["暗", "", "", ""]),
        (2, ["", "渡", "", ""]),
        (2, ["风", "云", "际", "会"]),
        (2, ["龙", "", "", ""]),
    ]:
        L.append("IDIOM|%d|%s" % (mode, ",".join(vals)))
    L.append("# 成语 二次检索（先拼音 an，再在结果上加单字 暗）")
    L.append("IDIOM2|0|an,,,|2|暗,,,")
    L.append("IDIOM2|0|zh,,,|1|,,,4")
    L.append("IDIOM2|1|4,,,|0|,,chen,")
    L.append("IDIOM2|2|龙,,,|0|,ong,,")

    L.append("# 诗词检索")
    grids = [
        "城春草木深" + "." * 25,
        "烽火连三月" + "." * 25,
        "处处闻啼鸟" + "." * 25,
        "处闻啼鸟" + "." * 26,                       # 只有一个"处"，凑不出"处处闻啼鸟"
        "月片一安长" + "." * 25,                      # 打乱顺序的"长安一片月"
        "长安一片月万户捣衣声" + "." * 20,             # 两句都能拼出
        "俯仰昔人非无情送潮归" + "." * 20,
        "." * 30,                                     # 全空
        "一二三四五" + "." * 25,
        "青青园中葵" + "." * 25,                      # 含重复字"青"
        "青园中葵" + "." * 26,                        # 只有一个"青"
        "射人先射马" + "." * 25,
        "擒贼先擒王" + "." * 25,
        "离离原上草一岁一枯荣" + "." * 20,
    ]
    for gd in grids:
        L.append("POEM|" + gd)

    L.append("# 名士检索 · 朝代")
    for v in DYNASTY:
        L.append("PERSON|0|" + v)
    L.append("PERSON|0|-")
    L.append("PERSON|0|唐")           # 重复一次确认稳定
    L.append("# 名士检索 · 爱好")
    for v in HOBBY:
        L.append("PERSON|1|" + v)
    L.append("PERSON|1|-")
    L.append("# 名士检索 · 社团")
    for v in CLUB:
        L.append("PERSON|2|" + v)
    L.append("PERSON|2|-")
    L.append("# 名士检索 · 品阶")
    for v in RANK:
        L.append("PERSON|3|" + v)
    L.append("PERSON|3|-")
    L.append("# 名士检索 · 文本模糊")
    for v in ["帝王", "诗人", "将领", "皇后", "谋士", "文学", "词人",
              "乱世", "王朝更迭", "盛世", "生于乱世", "战 争 时 期", "乱 世",
              "出身显贵", "贫寒", "家道中落", "误导", "（误导）",
              "灵术", "金戈演武", "落雷", "觉醒", "求仙问道", "喜欢黑色",
              "无字碑", "口吃", "-"]:
        L.append("PERSON|4|" + v)
        L.append("PERSON|5|" + v)
        L.append("PERSON|6|" + v)
        L.append("PERSON|7|" + v)
        L.append("PERSON|8|" + v)
    return "\n".join(L) + "\n"


# ---------------------------------------------------------------- 执行脚本

def run_script(script_path, out_path):
    idioms = load_idioms()
    poems = load_poems()
    people = load_people()
    print(f"载入: 成语 {len(idioms)} | 诗句 {len(poems)} | 名士 {len(people)}")

    lines = []
    with open(script_path, encoding='utf-8') as f:
        for ln in f:
            ln = ln.strip()
            if ln and not ln.startswith('#'):
                lines.append(ln)

    out = []
    out.append("# 忘川检索 自测输出（Python 参考实现）")
    for line in lines:
        tok = line.split('|')
        kind = tok[0]
        res = []
        if kind == "IDIOM":
            mode = int(tok[1]); v = (tok[2].split(',') + [''] * 4)[:4]
            res = [it[0] for it in idioms if idiom_hit(it, mode, v)]
        elif kind == "IDIOM2":
            m1 = int(tok[1]); v1 = (tok[2].split(',') + [''] * 4)[:4]
            m2 = int(tok[3]); v2 = (tok[4].split(',') + [''] * 4)[:4]
            s1 = [it for it in idioms if idiom_hit(it, m1, v1)]
            res = [it[0] for it in s1 if idiom_hit(it, m2, v2)]
        elif kind == "POEM":
            gd = tok[1]
            grid = [(gd[i] if i < len(gd) and gd[i] != '.' else '\0') for i in range(30)]
            hits = match_poems(grid, poems)
            hits.sort(key=lambda x: x[0])
            for v, cells in hits:
                res.append(v + "[" + ",".join(str(c) for c in cells) + "]")
        elif kind == "PERSON":
            mode = int(tok[1]); v = "" if tok[2] == "-" else tok[2]
            res = [display(p) for p in people if person_hit(p, mode, v)]
        else:
            out.append("SKIP\t" + line); continue
        out.append(line + "\t" + str(len(res)) + "\t" + "|".join(res))

    with open(out_path, 'w', encoding='utf-8', newline='\n') as f:
        f.write("\n".join(out) + "\n")
    print(f"已写出 {len(lines)} 条查询结果 -> {out_path}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(1)
    cmd = sys.argv[1]
    if cmd == "gen":
        p = sys.argv[2]
        with open(p, 'w', encoding='utf-8', newline='\n') as f:
            f.write(gen_script())
        print("已生成检索脚本:", p)
    elif cmd == "run":
        run_script(sys.argv[2], sys.argv[3])
    else:
        print(__doc__); sys.exit(1)
