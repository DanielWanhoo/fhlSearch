"""
诗词题库 Excel → poetry_db.ets 转换脚本

读取诗词题库 Excel（8 列：诗句 | 诗词名 | 作者 | ① | ② | ③ | ④ | ⑤）
转换为 entry/src/main/ets/data/poetry_db.ets（ArkTS 硬编码数据文件）。
Excel 默认取本仓库 `data/诗词检索.xlsx`，也可用环境变量 `FHL_TIKU_SRC` 指定题库目录。

用法：
    python scripts/excel_to_poetry.py

依赖：openpyxl（pip install openpyxl）
"""

import json
import os
import sys

# ---------------------------------------------------------------- 题库 Excel 定位
# 依次尝试：命令行参数 > 环境变量 FHL_TIKU_SRC 目录 > 本仓库 data/ 目录 > 开发时的历史路径。
# 这样仓库 clone 下来（data/ 里带三份 Excel）就能直接跑，本机开发环境也不受影响。
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPT_DIR)


def resolve_excel(file_name, *legacy_paths):
    if len(sys.argv) > 1:
        return sys.argv[1]
    src_dir = os.environ.get("FHL_TIKU_SRC")
    if src_dir:
        candidate = os.path.join(src_dir, file_name)
        if os.path.exists(candidate):
            return candidate
    candidate = os.path.join(ROOT_DIR, "data", file_name)
    if os.path.exists(candidate):
        return candidate
    for legacy in legacy_paths:
        if os.path.exists(legacy):
            return legacy
    return candidate  # 都不存在时返回仓库内路径，报错信息更直白

# 源题库 Excel 路径
EXCEL_PATH = resolve_excel("诗词检索.xlsx", r"H:\projects\info\题库.xlsx")

# 输出 .ets 文件路径（相对本脚本目录）
OUTPUT_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..", "entry", "src", "main", "ets", "data", "poetry_db.ets",
)


def load_poems(excel_path: str):
    """读取 Excel，返回 [{line, title, author, chars}, ...]"""
    import openpyxl
    wb = openpyxl.load_workbook(excel_path, read_only=True)
    ws = wb.active

    poems = []
    for r in range(2, ws.max_row + 1):  # 跳过第 1 行表头
        line = str(ws.cell(row=r, column=1).value or "").strip()
        title = str(ws.cell(row=r, column=2).value or "").strip()
        author = str(ws.cell(row=r, column=3).value or "").strip()

        # ①~⑤ 五列单字（列 D~H）
        chars = []
        for c in range(4, 9):
            ch = str(ws.cell(row=r, column=c).value or "").strip()
            if ch:
                chars.append(ch)

        if not line or not chars:
            continue  # 跳过空行

        poems.append({"line": line, "title": title, "author": author, "chars": chars})

    wb.close()
    return poems


def ets_str(value: str) -> str:
    """把 Python 字符串转成 ArkTS 字符串字面量（双引号 + 转义）"""
    return json.dumps(value, ensure_ascii=False)


def generate(poems, output_path: str) -> int:
    """生成 poetry_db.ets 文件"""
    lines = [
        "// Auto-generated from 题库.xlsx — DO NOT EDIT",
        'import { PoetryItem } from "../model/PoetryItem"',
        "",
        f"// Total: {len(poems)} poems",
        "export const POETRY_DB: PoetryItem[] = [",
    ]

    for i, p in enumerate(poems):
        char_list = ", ".join(ets_str(ch) for ch in p["chars"])
        entry = (
            f'  {{ line: {ets_str(p["line"])}, '
            f'title: {ets_str(p["title"])}, '
            f'author: {ets_str(p["author"])}, '
            f'chars: [{char_list}] }}'
        )
        if i < len(poems) - 1:
            entry += ","
        lines.append(entry)

    lines.append("]")

    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    return len(poems)


if __name__ == "__main__":
    if not os.path.exists(EXCEL_PATH):
        print(f"[ERROR] 找不到题库文件：{EXCEL_PATH}")
        raise SystemExit(1)

    poems = load_poems(EXCEL_PATH)
    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
    count = generate(poems, OUTPUT_PATH)
    print(f"[OK] 转换 {count} 句诗 → {OUTPUT_PATH}")
