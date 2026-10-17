"""
成语题库 Excel → idiom_db.ets（+ idiom_db.json）转换脚本

读取成语题库 Excel（13 列）转换为 ArkTS 硬编码数据文件。
Excel 默认取本仓库 `data/成语检索.xlsx`，也可用环境变量 `FHL_TIKU_SRC` 指定题库目录。

列结构（A~M）：
  A 成语 | B~E 拼音(无音调小写) | F~I 声调(1~4) | J~M 单字

处理要点：
  1. 剥离拼音里可能预先带上的声调符号（数据里有少量已标调拼音，如「风云际会」）
  2. ü 在 Excel 里写成 v，脚本统一归一为 ü（如 lve → lüe）
  3. 按标准规则（a→o→e→i/u/ü）重新正确标调，用于结果展示

用法：
    python scripts/excel_to_idiom.py

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
EXCEL_PATH = resolve_excel("成语检索.xlsx", r"C:\Users\wtswg\Desktop\成语检索.xlsx")

# 输出路径
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ETS_PATH = os.path.join(SCRIPT_DIR, "..", "entry", "src", "main", "ets", "data", "idiom_db.ets")
JSON_PATH = os.path.join(SCRIPT_DIR, "idiom_db.json")

# 声调符号 → 无音调基础元音（用于剥离已有声调符号）
TONED_TO_BASE = {
    'ā': 'a', 'á': 'a', 'ǎ': 'a', 'à': 'a',
    'ē': 'e', 'é': 'e', 'ě': 'e', 'è': 'e',
    'ī': 'i', 'í': 'i', 'ǐ': 'i', 'ì': 'i',
    'ō': 'o', 'ó': 'o', 'ǒ': 'o', 'ò': 'o',
    'ū': 'u', 'ú': 'u', 'ǔ': 'u', 'ù': 'u',
    'ǖ': 'ü', 'ǘ': 'ü', 'ǚ': 'ü', 'ǜ': 'ü',
}

# 基础元音 → 1~4 声调符号
TONE_MARKS = {
    'a': ['ā', 'á', 'ǎ', 'à'],
    'o': ['ō', 'ó', 'ǒ', 'ò'],
    'e': ['ē', 'é', 'ě', 'è'],
    'i': ['ī', 'í', 'ǐ', 'ì'],
    'u': ['ū', 'ú', 'ǔ', 'ù'],
    'ü': ['ǖ', 'ǘ', 'ǚ', 'ǜ'],
}


def strip_tone(syllable: str) -> str:
    """去掉拼音里的声调符号，返回无音调形式（保留 ü）"""
    return ''.join(TONED_TO_BASE.get(ch, ch) for ch in syllable)


def mark_tone(syllable: str, tone: int) -> str:
    """给无音调拼音按标准规则标声调，返回带声调形式。

    规则：有 a 标 a，其次 o，其次 e，都没有则标 i/u/ü 里靠后的那个元音。
    """
    if tone not in (1, 2, 3, 4):
        return syllable
    if 'a' in syllable:
        target = 'a'
    elif 'o' in syllable:
        target = 'o'
    elif 'e' in syllable:
        target = 'e'
    else:
        target = ''
        for ch in reversed(syllable):
            if ch in 'iuü':
                target = ch
                break
        if not target:
            return syllable
    idx = syllable.index(target)
    return syllable[:idx] + TONE_MARKS[target][tone - 1] + syllable[idx + 1:]


def load_idioms(excel_path: str):
    """读取 Excel，返回 [{word, chars, plain, tones, pinyin}, ...]"""
    import openpyxl
    wb = openpyxl.load_workbook(excel_path, read_only=True, data_only=True)
    ws = wb.active

    idioms = []
    skipped = []
    for r in range(1, ws.max_row + 1):
        word = str(ws.cell(row=r, column=1).value or "").strip()
        if not word or word == "成语":
            continue  # 表头 / 空行

        plain_raw = [str(ws.cell(row=r, column=c).value or "").strip() for c in range(2, 6)]
        tones = [ws.cell(row=r, column=c).value for c in range(6, 10)]
        chars = [str(ws.cell(row=r, column=c).value or "").strip() for c in range(10, 14)]

        # 完整性校验：成语 4 字、拼音 4 个非空、声调 4 个 1~4、单字 4 个
        if (len(word) != 4
                or any(not p for p in plain_raw)
                or any(t not in (1, 2, 3, 4) for t in tones)
                or len(chars) != 4 or any(not c for c in chars)):
            skipped.append((r, word))
            continue

        plain = [strip_tone(p).lower().replace('v', 'ü') for p in plain_raw]
        pinyin = [mark_tone(p, t) for p, t in zip(plain, tones)]

        idioms.append({
            "word": word,
            "chars": chars,
            "plain": plain,
            "tones": tones,
            "pinyin": pinyin,
        })

    wb.close()
    return idioms, skipped


def ets_str(value: str) -> str:
    """把 Python 字符串转成 ArkTS 字符串字面量（双引号 + 转义）"""
    return json.dumps(value, ensure_ascii=False)


def generate(idioms, ets_path: str, json_path: str) -> int:
    # 生成 .ets
    lines = [
        "// Auto-generated from 成语检索.xlsx — DO NOT EDIT",
        'import { IdiomItem } from "../model/IdiomItem"',
        "",
        f"// Total: {len(idioms)} idioms",
        "export const IDIOM_DB: IdiomItem[] = [",
    ]
    for i, it in enumerate(idioms):
        chars = ", ".join(ets_str(c) for c in it["chars"])
        plain = ", ".join(ets_str(p) for p in it["plain"])
        tones = ", ".join(str(t) for t in it["tones"])
        pinyin = ", ".join(ets_str(p) for p in it["pinyin"])
        entry = (
            f'  {{ word: {ets_str(it["word"])}, '
            f'chars: [{chars}], '
            f'plain: [{plain}], '
            f'tones: [{tones}], '
            f'pinyin: [{pinyin}] }}'
        )
        if i < len(idioms) - 1:
            entry += ","
        lines.append(entry)
    lines.append("]")

    with open(ets_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    # 生成 .json（开发调试/测试参考用，不打包进 APP）
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(idioms, f, ensure_ascii=False, indent=2)

    return len(idioms)


if __name__ == "__main__":
    if not os.path.exists(EXCEL_PATH):
        print(f"[ERROR] 找不到题库文件：{EXCEL_PATH}")
        raise SystemExit(1)

    idioms, skipped = load_idioms(EXCEL_PATH)
    os.makedirs(os.path.dirname(ETS_PATH), exist_ok=True)
    count = generate(idioms, ETS_PATH, JSON_PATH)

    print(f"[OK] 转换 {count} 条成语")
    print(f"     .ets → {ETS_PATH}")
    print(f"     .json → {JSON_PATH}")
    if skipped:
        print(f"[WARN] 跳过 {len(skipped)} 条异常行：")
        for r, w in skipped:
            print(f"       行 {r}: {w}")
