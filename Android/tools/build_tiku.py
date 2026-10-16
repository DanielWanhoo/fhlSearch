# -*- coding: utf-8 -*-
r"""题库转换：三份 Excel → 程序内嵌数据。

用法：
    python tools/build_tiku.py [--out <输出目录>]

读 `data/` 下的三份 Excel，生成到 `app/src/main/assets/`：
    tiku_chengyu.json   成语题库（319 条）
    tiku_shici.json     诗词题库（282 条）
    tiku_mingshi.json   名士题库（115 位）

题库目录默认是项目里的 `data/`；想放到别处，设环境变量 FHL_TIKU_SRC 指向那个目录。
`data/` 下找不到 Excel 时本脚本会跳过转换（构建直接沿用 assets/ 里已有的 JSON），
所以没有 Python 环境也能正常出包。

设计要点（与《需求梳理.md》一致）：
  1. 单字一律从"成语 / 诗句"文本现算，不读 Excel 的公式列，避免公式缓存问题；
  2. 拼音统一转小写（题库里有两处首字母大写）；声调统一转字符串 "1"~"4"；
  3. 名士按"名士列非空即块首"归并，爱好 / 社团 / 描述可多值；
  4. 模糊检索用的归一化字段（py / han / norm / descNorm）在打包期就算好，
     运行时不再处理，既省电又保证 Android 与 Windows 两侧行为完全一致。
"""
import argparse
import json
import os
import re
import sys
from collections import Counter

import openpyxl


# ---- 路径：全部按"本脚本所在位置"推算，克隆到任何目录下都能直接跑 ----
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SRC = os.environ.get('FHL_TIKU_SRC') or os.path.join(_ROOT, 'data')
DEFAULT_OUT = os.path.join(_ROOT, 'app', 'src', 'main', 'assets')

F_CS = os.path.join(SRC, '成语检索.xlsx')
F_SC = os.path.join(SRC, '诗词检索.xlsx')
F_MS = os.path.join(SRC, '名士检索.xlsx')

CJK = re.compile(r'[\u4e00-\u9fff]')


def s(v):
    """单元格取字符串（去首尾空白，None → 空串）。"""
    return '' if v is None else str(v).strip()


def has(v):
    return s(v) != ''


def han_only(text):
    """只保留汉字：忽略标点、空格、换行、字母、数字——模糊检索的归一化规则。"""
    return ''.join(CJK.findall(text))


# ---------------------------------------------------------------- 成语
def build_chengyu():
    wb = openpyxl.load_workbook(F_CS, data_only=True)
    ws = wb['Sheet1']
    items, errs = [], []
    for row in ws.iter_rows(min_row=3, values_only=True):
        word = s(row[0])
        if not word:
            continue
        if len(word) != 4:
            errs.append('成语长度异常: %s' % word)
            continue
        # 拼音：B-E，统一小写；非字母一律剔除后判空
        py = [re.sub(r'[^A-Za-z]', '', s(row[1 + i])).lower() for i in range(4)]
        # 声调：F-I，统一成 "1"~"4"
        sd = [s(row[5 + i]) for i in range(4)]
        # 单字：从成语现算，不信 J-M 公式列
        chars = list(word)
        if any(p == '' for p in py):
            errs.append('拼音为空: %s' % word)
        if any(t not in ('1', '2', '3', '4') for t in sd):
            errs.append('声调异常: %s %s' % (word, sd))
        items.append({
            'w': word,          # 成语
            'p': py,            # 4 个无声调小写拼音
            't': sd,            # 4 个声调数字
            'c': chars,         # 4 个单字（现算）
        })
    wb.close()
    assert len(items) == len({i['w'] for i in items}), '成语有重复'
    return {'count': len(items), 'items': items}, errs


# ---------------------------------------------------------------- 诗词
def build_shici():
    wb = openpyxl.load_workbook(F_SC, data_only=True)
    ws = ws_name = None
    for cand in wb.worksheets:
        ws, ws_name = cand, cand.title
        break
    if ws is None:
        raise SystemExit('诗词表为空')
    items, errs = [], []
    for row in ws.iter_rows(min_row=2, values_only=True):
        line = s(row[0])
        if not line:
            continue
        if len(line) != 5:
            errs.append('诗句长度异常: %s' % line)
            continue
        title = s(row[1])
        if not title.startswith('《'):
            title = '《%s》' % title
        items.append({
            'l': line,           # 诗句
            'n': title,          # 诗词名（统一带书名号）
            'a': s(row[2]),      # 作者
            'c': list(line),     # 5 个单字（现算）
        })
    wb.close()
    assert len(items) == len({i['l'] for i in items}), '诗句有重复'
    return {'count': len(items), 'items': items, 'sheet': ws_name}, errs


# ---------------------------------------------------------------- 名士
MS_FIELDS = [
    ('dynasty', '朝代', 1),
    ('rank', '品阶', 4),
    ('job', '职业', 5),
    ('born', '生逢（生于...）', 6),
    ('origin', '出身/身世', 7),
    ('skill', '技能', 8),
]


def build_mingshi():
    wb = openpyxl.load_workbook(F_MS, data_only=True)
    ws = wb['众里寻他']
    header = [s(c.value) for c in ws[1]]
    desc_idx = [i for i, h in enumerate(header) if h.startswith('描述')]
    love_idx, club_idx = 2, 3          # 爱好、社团

    items, errs = [], []
    cur = None
    for row in ws.iter_rows(min_row=2, values_only=True):
        if has(row[0]):
            cur = {
                'name': s(row[0]), 'dynasty': '', 'rank': '', 'job': '',
                'born': '', 'origin': '', 'skill': '',
                'love': [], 'club': [], 'desc': [],
            }
            items.append(cur)
        if cur is None:
            continue
        for key, _, idx in MS_FIELDS:
            v = s(row[idx])
            if v and not cur[key]:
                cur[key] = v
        for key, idx in (('love', love_idx), ('club', club_idx)):
            v = s(row[idx])
            if v and v not in cur[key]:
                cur[key].append(v)
        for idx in desc_idx:
            v = s(row[idx])
            if v and v not in cur['desc']:
                cur['desc'].append(v)

    # 预处理模糊检索用的归一化文本
    for it in items:
        it['norm'] = {k: han_only(it[k]) for k, _, _ in MS_FIELDS}
        it['descNorm'] = [han_only(d) for d in it['desc']]
        it['love'] = sorted(it['love'])
        it['club'] = sorted(it['club'])
        if not it['rank']:
            it['rank'] = ''          # 大乔缺品阶，留空

    wb.close()
    assert len(items) == len({i['name'] for i in items}), '名士有重复'
    return {'count': len(items), 'items': items}, errs


# ---------------------------------------------------------------- 主流程
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default=DEFAULT_OUT)
    args = ap.parse_args()

    missing = [p for p in (F_CS, F_SC, F_MS) if not os.path.exists(p)]
    if missing:
        print('未找到题库源文件，跳过转换（构建将沿用 assets/ 里已生成的 JSON）：')
        for p in missing:
            print('  -', p)
        print('提示：把三份 xlsx 放进 %s 后重跑本脚本即可更新题库。' % SRC)
        return

    os.makedirs(args.out, exist_ok=True)

    print('=' * 68)
    cs, e1 = build_chengyu()
    sc, e2 = build_shici()
    ms, e3 = build_mingshi()

    files = [('tiku_chengyu.json', cs), ('tiku_shici.json', sc), ('tiku_mingshi.json', ms)]
    total = 0
    for name, data in files:
        data['version'] = 1
        data['source'] = {'chengyu': '成语检索.xlsx#Sheet1',
                          'shici': '诗词检索.xlsx#择字成诗',
                          'mingshi': '名士检索.xlsx#众里寻他'}[name.split('_')[1].split('.')[0]]
        path = os.path.join(args.out, name)
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, separators=(',', ':'))
        size = os.path.getsize(path)
        total += size
        print('%-22s %5d 条  %8.1f KB' % (name, data['count'], size / 1024.0))

    print('-' * 68)
    print('合计 %.1f KB' % (total / 1024.0))
    print('成语: %d 条' % cs['count'])
    print('诗词: %d 条（%d 位作者 / %d 个诗词名，%d 条含重复字）'
          % (sc['count'], len({i['a'] for i in sc['items']}), len({i['n'] for i in sc['items']}),
             sum(1 for i in sc['items'] if len(set(i['l'])) < 5)))
    print('名士: %d 位（描述合计 %d 条）'
          % (ms['count'], sum(len(i['desc']) for i in ms['items'])))
    print('朝代取值:', sorted({i['dynasty'] for i in ms['items']}))
    print('品阶取值:', sorted({i['rank'] for i in ms['items'] if i['rank']}))
    for tag, errs in (('成语', e1), ('诗词', e2), ('名士', e3)):
        print('%s 告警 %d 条%s' % (tag, len(errs), ('：' + '; '.join(errs[:5])) if errs else ''))
    print('输出目录:', args.out)


if __name__ == '__main__':
    main()
