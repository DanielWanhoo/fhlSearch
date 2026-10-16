# -*- coding: utf-8 -*-
"""
把诗词 / 名士模块里残留的透明 Label 换成"卡片自己绘制文字"。

背景：BackColor=Transparent 的 Label 会让 WinForms 在绘制自身背景时回调父容器的
OnPaint，和自绘内容相互干扰，窗口缩放后会留下残影、文字错位。统一改成直接绘制。

【一次性脚本】v1.1 UI 重构期间跑过一次，问题已修完；留在这里只为记录当时的改法。

用法: python tools/oneoff/fix_labels.py
"""
import os
import sys
import io

try:
    sys.stdout.reconfigure(errors='replace')
except Exception:
    pass

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
                    "src", "FhlSearch", "Modules")

# 每个文件：一串 (旧文本, 新文本)
EDIT_POEM = [
    # 字段声明
    ("        Label _lblInfo;\n",
     "        string _infoText = \"\";\n"),
    # 创建 Label -> 挂 Paint
    ("""            _lblInfo = new Label();
            _lblInfo.AutoSize = false;
            _lblInfo.BackColor = Color.Transparent;
            _lblInfo.ForeColor = Pal.Ink2;
            _lblInfo.Font = Fonts.Body(9.5f);
            _lblInfo.TextAlign = ContentAlignment.MiddleLeft;
            _cardRes.Controls.Add(_lblInfo);
""",
     "            _cardRes.Paint += PaintResInfo;\n"),
    # 排版里去掉 SetBounds
    ("            _lblInfo.SetBounds(rp, Ui.Px(38), rw, Ui.Px(22));\n", ""),
    # 赋值
    ("""            _lblInfo.Text = _hits.Count == 0
                ? "未找到可组成的诗句"
                : string.Format("共 {0} 条结果 · 点某一条可标出所用字格", _hits.Count);""",
     """            _infoText = _hits.Count == 0
                ? "未找到可组成的诗句"
                : string.Format("共 {0} 条结果 · 点某一条可标出所用字格", _hits.Count);
            _cardRes.Invalidate();"""),
    ('            _lblInfo.Text = "";',
     '            _infoText = "";\n            _cardRes.Invalidate();'),
]

EDIT_PERSON = [
    ("        Label _lblModeHint, _lblCondTitle;\n", ""),
    ("        Label _lblInfo;\n", "        string _infoText = \"\";\n        string _condTitle = \"\";\n        string _modeHint = \"\";\n"),
    ("""            _lblCondTitle = new Label();
            _lblCondTitle.AutoSize = false;
            _lblCondTitle.BackColor = Color.Transparent;
            _lblCondTitle.ForeColor = Pal.ZhuDark;
            _lblCondTitle.Font = Fonts.BodyB(10f);
            _lblCondTitle.TextAlign = ContentAlignment.MiddleLeft;
            _cardCond.Controls.Add(_lblCondTitle);
""", ""),
    ("""            _lblModeHint = new Label();
            _lblModeHint.AutoSize = false;
            _lblModeHint.BackColor = Color.Transparent;
            _lblModeHint.ForeColor = Pal.Ink3;
            _lblModeHint.Font = Fonts.Body(8.5f);
            _lblModeHint.TextAlign = ContentAlignment.TopLeft;
            _cardCond.Controls.Add(_lblModeHint);
""",
     "            _cardCond.Paint += PaintCondText;\n"),
    ("""            _lblInfo = new Label();
            _lblInfo.AutoSize = false;
            _lblInfo.BackColor = Color.Transparent;
            _lblInfo.ForeColor = Pal.Ink2;
            _lblInfo.Font = Fonts.Body(9.5f);
            _lblInfo.TextAlign = ContentAlignment.MiddleLeft;
            _cardRes.Controls.Add(_lblInfo);
""",
     "            _cardRes.Paint += PaintResInfo;\n"),
    # 排版里的 SetBounds 全部去掉
    ("            _lblCondTitle.SetBounds(pad, y, innerW, Ui.Px(20));\n", ""),
    ("""            _lblModeHint.SetBounds(pad, y + Ui.Px(54), innerW, Math.Max(Ui.Px(20), condH - Ui.Px(56)));
            if (Bank.IsMenuMode(_mode))
                _lblModeHint.SetBounds(pad, y + _chips.Height + Ui.Px(8), innerW,
                    Math.Max(Ui.Px(18), condBottom - (y + _chips.Height + Ui.Px(8))));
""", ""),
    ("            _lblInfo.SetBounds(rp, Ui.Px(38), rw, Ui.Px(22));\n", ""),
    # 文本赋值
    ('            _lblCondTitle.Text = "【" + Bank.ModeName(m) + "】条件";',
     '            _condTitle = "【" + Bank.ModeName(m) + "】条件";'),
    ("            _lblModeHint.Visible = true;", ""),
    ('                _lblModeHint.Text = m == PersonMode.Dynasty\n                    ? "点选项筛选；再点一次可取消。留空表示不限。"\n                    : "点选项筛选；再点一次可取消。留空表示不限。";',
     '                _modeHint = "点选项筛选；再点一次可取消。留空表示不限。";'),
    ('                _lblModeHint.Text = "模糊检索（不拆分检索词，自动忽略标点与空格）\\n" + Bank.ModeHint(m);',
     '                _modeHint = "模糊检索（不拆分检索词，自动忽略标点与空格）\\n" + Bank.ModeHint(m);'),
    ('            _lblInfo.Text = "尚未检索";', '            _infoText = "尚未检索";'),
    ('            _lblInfo.Text = "未检索到该名士";', '            _infoText = "未检索到该名士";'),
    ("""                _lblInfo.Text = string.Format("共 {0} 条结果 · 当前第 {1} 层 · 检索次数 {2}",
                    n, _stack.Count, _searchCount);""",
     """                _infoText = string.Format("共 {0} 条结果 · 当前第 {1} 层 · 检索次数 {2}",
                    n, _stack.Count, _searchCount);"""),
]

PAINT_METHODS = """
        /// <summary>结果卡片顶部的统计文字（直接绘制，不用透明 Label）</summary>
        void PaintResInfo(object sender, PaintEventArgs e)
        {
            if (string.IsNullOrEmpty(_infoText)) return;
            Rectangle r = new Rectangle(Ui.Px(14), Ui.Px(38), _cardRes.Width - Ui.Px(28), Ui.Px(22));
            if (r.Width <= 10) return;
            Brush2.StrIn(e.Graphics, _infoText, Fonts.Body(9.5f), Pal.Ink2, r,
                TextFormatFlags.NoPadding | TextFormatFlags.SingleLine
                | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
        }
"""

PERSON_COND_PAINT = """
        /// <summary>条件卡片里的「【模式】条件」和提示文字（直接绘制，不用透明 Label）</summary>
        void PaintCondText(object sender, PaintEventArgs e)
        {
            if (_condTitleY > 0 && !string.IsNullOrEmpty(_condTitle))
            {
                Brush2.StrIn(e.Graphics, _condTitle, Fonts.BodyB(10f), Pal.ZhuDark,
                    new Rectangle(Ui.Px(16), _condTitleY, _cardCond.Width - Ui.Px(32), Ui.Px(20)),
                    TextFormatFlags.NoPadding | TextFormatFlags.SingleLine
                    | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
            }
            if (_modeHintY > 0 && _modeHintH > 0 && !string.IsNullOrEmpty(_modeHint))
            {
                TextRenderer.DrawText(e.Graphics, _modeHint, Fonts.Body(8.5f),
                    new Rectangle(Ui.Px(16), _modeHintY, _cardCond.Width - Ui.Px(32), _modeHintH),
                    Pal.Ink3, TextFormatFlags.NoPadding | TextFormatFlags.WordBreak | TextFormatFlags.Top);
            }
        }

        int _condTitleY = -1, _modeHintY = -1, _modeHintH = 0;
"""


def apply(path, edits, extra_method):
    if not os.path.exists(path):
        print("  找不到 " + path)
        return 0
    with open(path, encoding='utf-8') as f:
        src = f.read()
    n = 0
    for old, new in edits:
        if old not in src:
            print("  [未匹配] " + old.splitlines()[0][:70])
            continue
        src = src.replace(old, new, 1)
        n += 1
    if extra_method and extra_method not in src:
        # 插到最后一个成员方法之前：简单起见插在 "// ================================================================ 绘制" 之后
        marker = "        // ================================================================ 绘制"
        if marker in src:
            src = src.replace(marker, marker + "\n" + extra_method, 1)
        else:
            src = src.rstrip() + "\n" + extra_method + "\n    }\n"
            src = src.replace("\n    }\n" + extra_method, "\n" + extra_method + "\n    }\n")
    with open(path, 'w', encoding='utf-8', newline='') as f:
        f.write(src)
    print("  应用 %d/%d 处 -> %s" % (n, len(edits), os.path.basename(path)))
    return n


print("修 Label -> 直接绘制")
apply(os.path.join(ROOT, "PoemModule.cs"), EDIT_POEM, PAINT_METHODS)
apply(os.path.join(ROOT, "PersonModule.cs"), EDIT_PERSON, PAINT_METHODS + PERSON_COND_PAINT)
