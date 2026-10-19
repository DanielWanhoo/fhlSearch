"""
名士题库 Excel → mingzi_db.ets（+ mingzi_db.json）转换脚本

读取名士题库 Excel 转换为 ArkTS 硬编码数据文件。
Excel 默认取本仓库 `data/名士检索.xlsx`，也可用环境变量 `FHL_TIKU_SRC` 指定题库目录。

列结构（A~X，共 24 列）：
  A 名士 | B 朝代 | C 爱好 | D 社团 | E 品阶 | F 职业
  G 生逢（生于...） | H 出身/身世 | I 技能 | J~W 描述1~描述15

数据规则：
  1. 一条名士记录 = 连续若干行（名士列非空开启新记录，其后名士列为空的行属于前一条记录）
  2. 爱好/社团/品阶 可出现在多条续行 → 合并（去重，保序）；其余标量字段取首条非空
  3. 规范化：爱好「奕棋」→「弈棋」（数据笔误）；朝代「五代十国（南唐）」→「五代十国」（去除括号附注）

用法：
    python scripts/excel_to_mingzi.py

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
EXCEL_PATH = resolve_excel("名士检索.xlsx")

# 输出路径
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ETS_PATH = os.path.join(SCRIPT_DIR, "..", "entry", "src", "main", "ets", "data", "mingzi_db.ets")
JSON_PATH = os.path.join(SCRIPT_DIR, "mingzi_db.json")


def normalize_hobby(value: str) -> str:
    """爱好规范化：修正数据笔误（奕棋 → 弈棋）"""
    return value.replace("奕棋", "弈棋")


def normalize_dynasty(value: str) -> str:
    """朝代规范化：去除括号附注，如「五代十国（南唐）」→「五代十国」"""
    for mark in ("（", "("):
        idx = value.find(mark)
        if idx != -1:
            value = value[:idx]
            break
    return value


def load_scholars(excel_path: str):
    """读取 Excel，返回 [{name, dynasty, hobbies, groups, rank, occupation, born, origin, skill, descriptions}, ...]"""
    import openpyxl
    wb = openpyxl.load_workbook(excel_path, read_only=True, data_only=True)
    ws = wb[wb.sheetnames[0]]

    # 按「名士」列分组的原始记录
    raw_records = []
    cur = None
    for row in ws.iter_rows(values_only=True):
        cells = ["" if v is None else str(v).strip() for v in row]
        if cells[0] == "名士":
            continue  # 表头行
        if cells[0]:
            cur = {"lines": []}
            raw_records.append(cur)
        if cur is not None:
            cur["lines"].append(cells)

    scholars = []
    for rec in raw_records:
        lines = rec["lines"]

        def first_non_empty(col: int) -> str:
            for line in lines:
                if line[col]:
                    return line[col]
            return ""

        def collect(col: int) -> list:
            out = []
            for line in lines:
                if line[col]:
                    val = line[col]
                    if col == 2:
                        val = normalize_hobby(val)
                    elif col == 1:
                        val = normalize_dynasty(val)
                    if val not in out:
                        out.append(val)
            return out

        hobbies = collect(2)
        groups = collect(3)
        descriptions = []
        desc_indexes = []
        for ci in range(9, 24):
            v = first_non_empty(ci)
            if v:
                descriptions.append(v)
                desc_indexes.append(ci - 8)  # 描述列号 1~15

        scholars.append({
            "name": first_non_empty(0),
            "dynasty": normalize_dynasty(first_non_empty(1)),
            "hobbies": hobbies,
            "groups": groups,
            "rank": first_non_empty(4),
            "occupation": first_non_empty(5),
            "born": first_non_empty(6),
            "origin": first_non_empty(7),
            "skill": first_non_empty(8),
            "descriptions": descriptions,
            "desc_indexes": desc_indexes,
        })

    wb.close()
    return scholars


def ets_str(value: str) -> str:
    """把 Python 字符串转成 ArkTS 字符串字面量（双引号 + 转义）"""
    return json.dumps(value, ensure_ascii=False)


def ets_str_arr(values) -> str:
    if not values:
        return "[]"
    return "[" + ", ".join(ets_str(v) for v in values) + "]"


def ets_num_arr(values) -> str:
    if not values:
        return "[]"
    return "[" + ", ".join(str(v) for v in values) + "]"


def generate(scholars, ets_path: str, json_path: str) -> int:
    # 生成 .ets
    lines = [
        "// Auto-generated from 众里寻他.xlsx — DO NOT EDIT",
        'import { MingziItem } from "../model/MingziItem"',
        "",
        f"// Total: {len(scholars)} scholars",
        "export const MINGZI_DB: MingziItem[] = [",
    ]
    for i, it in enumerate(scholars):
        entry = (
            f'  {{ name: {ets_str(it["name"])}, '
            f'dynasty: {ets_str(it["dynasty"])}, '
            f'hobbies: {ets_str_arr(it["hobbies"])}, '
            f'groups: {ets_str_arr(it["groups"])}, '
            f'rank: {ets_str(it["rank"])}, '
            f'occupation: {ets_str(it["occupation"])}, '
            f'born: {ets_str(it["born"])}, '
            f'origin: {ets_str(it["origin"])}, '
            f'skill: {ets_str(it["skill"])}, '
            f'descriptions: {ets_str_arr(it["descriptions"])}, '
            f'descIndexes: {ets_num_arr(it["desc_indexes"])} }}'
        )
        if i < len(scholars) - 1:
            entry += ","
        lines.append(entry)
    lines.append("]")

    with open(ets_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    # 生成 .json（开发调试/测试参考用，不打包进 APP）
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(scholars, f, ensure_ascii=False, indent=2)

    return len(scholars)


if __name__ == "__main__":
    if not os.path.exists(EXCEL_PATH):
        print(f"[ERROR] 找不到题库文件：{EXCEL_PATH}")
        raise SystemExit(1)

    scholars = load_scholars(EXCEL_PATH)
    os.makedirs(os.path.dirname(ETS_PATH), exist_ok=True)
    count = generate(scholars, ETS_PATH, JSON_PATH)

    print(f"[OK] 转换 {count} 条名士")
    print(f"     .ets → {ETS_PATH}")
    print(f"     .json → {JSON_PATH}")
    with_hobby = sum(1 for s in scholars if s["hobbies"])
    with_group = sum(1 for s in scholars if s["groups"])
    with_desc = sum(1 for s in scholars if s["descriptions"])
    print(f"[INFO] 有爱好 {with_hobby} / 有社团 {with_group} / 有描述 {with_desc}")