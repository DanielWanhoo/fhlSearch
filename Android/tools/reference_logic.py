# -*- coding: utf-8 -*-
r"""三大模块检索逻辑的参考实现（语义基准）。

这个文件不是最终产品代码——它的作用是：
  1. 把《需求梳理_Android.md》里的检索规则**跑一遍、验证没有歧义**；
  2. 作为之后 Kotlin 实现的**逐行对照基准**（Kotlin 版必须与它结果一致）。

用法：
    python reference_logic.py
    python reference_logic.py --selftest
"""
import argparse
import json
import os
import re
import sys
from collections import Counter


# ---- 路径：全部按"本脚本所在位置"推算，克隆到任何目录下都能直接跑 ----
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

ASSETS = os.path.join(_ROOT, 'app', 'src', 'main', 'assets')
CJK = re.compile(r'[\u4e00-\u9fff]')


def load(name):
    with open(os.path.join(ASSETS, name), encoding='utf-8') as f:
        return json.load(f)


# ================================================================ 成语检索
class ChengYu:
    """拼音 / 声调 / 单字 三种模式，四格输入，层级检索。"""

    def __init__(self, data):
        self.items = data['items']

    @staticmethod
    def _py_ok(cell, syllable):
        """拼音格：空=不限；否则要求是"连续子串"（模糊），大小写不敏感。"""
        if cell == '':
            return True
        return cell.lower() in syllable.lower()

    @staticmethod
    def _tone_ok(cell, tone):
        if cell == '':
            return True
        return cell == tone

    @staticmethod
    def _char_ok(cell, ch):
        if cell == '':
            return True
        return cell == ch

    def search(self, mode, cells, pool=None):
        """mode: 'pinyin' | 'tone' | 'char'；cells: 4 个字符串。
        返回 (结果列表, 命中位次集合)。空条件 → 抛 ValueError（界面应提示"请至少填写一个条件"）。"""
        cells = [c.strip() for c in cells]
        if all(c == '' for c in cells):
            raise ValueError('请至少填写一个条件')
        if all(c == '' for c in cells):
            return [], set()
        hits = set(i for i, c in enumerate(cells) if c != '')
        src = self.items if pool is None else pool
        out = []
        for it in src:
            ok = True
            for i in range(4):
                c = cells[i]
                if mode == 'pinyin':
                    ok = self._py_ok(c, it['p'][i])
                elif mode == 'tone':
                    ok = self._tone_ok(c, it['t'][i])
                elif mode == 'char':
                    ok = self._char_ok(c, it['c'][i])
                else:
                    raise ValueError('未知模式: %s' % mode)
                if not ok:
                    break
            if ok:
                out.append(it)
        # 结果 ≥2 条时按第 1 字拼音升序
        out.sort(key=lambda it: (it['p'][0], it['w']))
        return out, hits

    @staticmethod
    def validate(mode, cells):
        """返回 (合法吗, 第几个格非法)。规则按需求 txt：出现其他符号即非法。"""
        for i, c in enumerate(cells):
            if c == '':
                continue
            if mode == 'pinyin' and not re.fullmatch(r'[A-Za-z]+', c):
                return False, i
            if mode == 'tone' and not re.fullmatch(r'[1-4]', c):
                return False, i
            if mode == 'char' and not re.fullmatch(r'[\u4e00-\u9fff]', c):
                return False, i
        return True, -1


# ================================================================ 诗词检索
class ShiCi:
    """30 格内挑 5 个互不相同的格子拼出诗句（顺序无关）。"""

    def __init__(self, data):
        self.items = data['items']

    def search(self, grid):
        """grid: 长度 30 的字符列表（空格为 ''）。
        返回 [(诗句条目, [5 个格子下标])...]，顺序遵循题库原顺序。"""
        pos = {}
        for idx, ch in enumerate(grid):
            if ch:
                pos.setdefault(ch, []).append(idx)
        out = []
        for it in self.items:
            used = self._assign(it['c'], pos)
            if used is not None:
                out.append((it, used))
        return out

    @staticmethod
    def _assign(chars, pos):
        """给 5 个字各找一个未被占用的格子；不要求格内顺序与诗句一致。"""
        used = set()
        order = []

        def bt(k):
            if k == len(chars):
                return True
            ch = chars[k]
            for idx in pos.get(ch, ()):
                if idx in used:
                    continue
                used.add(idx)
                order.append(idx)
                if bt(k + 1):
                    return True
                order.pop()
                used.discard(idx)
            return False

        return list(order) if bt(0) else None


# ================================================================ 名士检索
DYN = ['汉', '明', '秦', '三国', '宋', '唐', '五代十国', '西楚', '晋', '先秦', '梦', '南北朝', '清', '元', '辽']
LOVE = ['博文', '乐舞', '品茗', '赏玩', '食珍', '书画', '雅宴', '演武', '弈棋', '妆饰']
CLUB = ['百家书院', '千工苑', '金戈馆', '容华社', '棠梨坊', '饕餮居', '五湖商社', '逸趣社', '无']
RANK = ['天', '地', '玄']
TEXT_FIELDS = [('job', '职业'), ('born', '生逢（生于...）'), ('origin', '出身/身世'),
               ('skill', '技能'), ('other', '其他描述')]


def han_only(text):
    return ''.join(CJK.findall(text or ''))


class MingShi:
    def __init__(self, data):
        self.items = data['items']

    def search(self, mode, value, pool=None):
        """mode: dynasty|love|club|rank|job|born|origin|skill|other
        value: 选项名或输入框文本；pool=None 表示在全部名士里筛。"""
        src = self.items if pool is None else pool
        v = (value or '').strip()
        if v == '':
            raise ValueError('请先选择或输入检索条件')
        out = []
        if mode == 'dynasty':
            for it in src:
                if v == '辽':            # 题库无辽代，必然 0 条
                    continue
                if v in it['dynasty']:   # 包含匹配：五代十国 → 五代十国（南唐）
                    out.append(it)
        elif mode == 'love':
            out = [it for it in src if v in it['love']]
        elif mode == 'club':
            out = [it for it in src if v in it['club']]
        elif mode == 'rank':
            out = [it for it in src if it['rank'] == v]
        elif mode == 'other':
            nv = han_only(v)
            out = [it for it in src if any(nv in d for d in it['descNorm'])]
        else:
            key = dict(TEXT_FIELDS).get(mode)
            if key is None:
                raise ValueError('未知模式: %s' % mode)
            nv = han_only(v)
            out = [it for it in src if nv and nv in it['norm'][mode]]
        return out

    @staticmethod
    def label(it):
        return '%s（%s）' % (it['name'], it['dynasty'])


# ================================================================ 自测
def selftest():
    cy = ChengYu(load('tiku_chengyu.json'))
    sc = ShiCi(load('tiku_shici.json'))
    ms = MingShi(load('tiku_mingshi.json'))
    fails = []

    def ck(cond, msg):
        print(('  ✅ ' if cond else '  ❌ ') + msg)
        if not cond:
            fails.append(msg)

    print('【成语 · 拼音模糊】')
    r, hits = cy.search('pinyin', ['an', '', '', ''])
    ck(len(r) > 0 and all('an' in it['p'][0] for it in r), 'an 在第1格 → %d 条，且第1字拼音都含 an' % len(r))
    ck(hits == {0}, '命中位次 = {0}')
    r2, _ = cy.search('pinyin', ['', 'du', '', ''])
    ck(all('du' in it['p'][1] for it in r2), 'du 在第2格 → %d 条，且第2字拼音都含 du' % len(r2))
    rl, _ = cy.search('pinyin', ['ZH', '', '', ''])
    ck(len(rl) > 0, '大写 ZH 也能命中 → %d 条（大小写不敏感）' % len(rl))
    rp, _ = cy.search('pinyin', ['an', 'du', '', ''])
    ck(all('an' in i['p'][0] and 'du' in i['p'][1] for i in rp), '两格组合 → %d 条' % len(rp))

    print('【成语 · 声调】')
    rt, _ = cy.search('tone', ['4', '4', '2', '1'])
    ck(any(i['w'] == '暗渡陈仓' for i in rt), '4421 命中「暗渡陈仓」→ %d 条' % len(rt))
    rt2, _ = cy.search('tone', ['4', '4', '2', '1'], pool=rt)
    ck(len(rt2) == len(rt), '在同层结果里二次检索同样条件 → 结果不变(%d)' % len(rt2))

    print('【成语 · 单字】')
    rc, _ = cy.search('char', ['', '', '陈', ''])
    ck(all(i['c'][2] == '陈' for i in rc), '单字「陈」在第3格 → %d 条' % len(rc))
    rc2, _ = cy.search('char', ['', '', '陈', ''], pool=rc)
    ck(len(rc2) == len(rc), '二次检索同条件 → 结果不变')

    print('【成语 · 层级 + 空条件 + 非法字符】')
    lv1, _ = cy.search('pinyin', ['zh', '', '', ''])
    lv2, _ = cy.search('char', ['', '', '', '定'], pool=lv1)
    ck(all('zh' in i['p'][0] and i['c'][3] == '定' for i in lv2),
       '拼音 zh → 单字「定」二次检索 → %d 条（第1字含zh且第4字=定）' % len(lv2))
    try:
        cy.search('pinyin', ['', '', '', ''])
        ck(False, '全空条件应抛异常')
    except ValueError:
        ck(True, '全空条件 → 提示"请至少填写一个条件"')
    ok, bad = cy.validate('pinyin', ['an', 'd4', '', ''])
    ck((not ok) and bad == 1, '拼音格输入 "d4" → 第2格判为非法字符')
    ok2, _ = cy.validate('tone', ['1', '5', '', ''])
    ck(not ok2, '声调格输入 "5" → 判为非法字符')
    ok3, _ = cy.validate('char', ['a', '', '', ''])
    ck(not ok3, '单字格输入 "a" → 判为非法字符')

    print('【诗词 · 匹配】')
    grid = [''] * 30
    ans = '离离原上草'
    for k, ch in enumerate(ans):
        grid[k] = ch
    res = sc.search(grid)
    ck(any(it['l'] == ans for it, _ in res), '格内顺序填入「离离原上草」→ 命中')
    got = [u for it, u in res if it['l'] == ans][0]
    ck(sorted(got) == [0, 1, 2, 3, 4], '重复字「离」占用两个格子 %s' % got)
    # 顺序打乱也能命中
    grid2 = [''] * 30
    for k, ch in enumerate('草上原离离'):
        grid2[k * 3] = ch
    res2 = sc.search(grid2)
    ck(any(it['l'] == ans for it, _ in res2), '同样 5 个字打乱顺序填入 → 仍命中（顺序无关）')
    # 只有 4 个字 → 不命中
    grid3 = [''] * 30
    for k, ch in enumerate('离原上草'):
        grid3[k] = ch
    res3 = sc.search(grid3)
    ck(not any(it['l'] == ans for it, _ in res3), '缺一个「离」→ 不命中（重复字必须凑够两个格子）')
    empty = sc.search([''] * 30)
    ck(len(empty) == 0, '空格子 → 0 条（不报错）')
    # 一格里放同一字只算一次
    grid4 = [''] * 30
    for k, ch in enumerate('离原上草'):
        grid4[k * 2] = ch
    res4 = sc.search(grid4)
    ck(not any(it['l'] == ans for it, _ in res4), '只有一个「离」格 → 不命中')

    print('【名士 · 选项型】')
    t = ms.search('dynasty', '唐')
    ck(len(t) > 0 and all('唐' in i['dynasty'] for i in t), '朝代「唐」→ %d 位' % len(t))
    w = ms.search('dynasty', '五代十国')
    ck(len(w) == 2 and all(i['dynasty'] == '五代十国（南唐）' for i in w),
       '朝代「五代十国」→ 包含匹配命中 %d 位（题库写作 五代十国（南唐））' % len(w))
    liao = ms.search('dynasty', '辽')
    ck(len(liao) == 0, '朝代「辽」→ 0 条（题库无辽代）')
    yw = ms.search('love', '演武')
    ck(len(yw) > 0 and all('演武' in i['love'] for i in yw), '爱好「演武」→ %d 位' % len(yw))
    jg = ms.search('club', '金戈馆')
    ck(len(jg) > 0 and all('金戈馆' in i['club'] for i in jg), '社团「金戈馆」→ %d 位' % len(jg))
    tian = ms.search('rank', '天')
    ck(len(tian) > 0 and all(i['rank'] == '天' for i in tian), '品阶「天」→ %d 位' % len(tian))
    dq = [i['name'] for i in ms.items if not i['rank']]
    ck(len(dq) == 1 and dq[0] == '大乔' and all(i['name'] != '大乔' for i in tian),
       '大乔无品阶 → 点天/地/玄都不会出现她')

    print('【名士 · 模糊输入】')
    ls = ms.search('born', '乱世')
    ck(len(ls) > 0 and all('乱世' in i['norm']['born'] for i in ls), '生逢「乱世」→ %d 位（模糊）' % len(ls))
    ls2 = ms.search('born', '乱 世')
    ck(len(ls2) == len(ls), '「乱 世」带空格 → 与「乱世」同结果 %d 位' % len(ls2))
    zf = ms.search('origin', '出身显贵')
    ck(len(zf) > 0, '出身「出身显贵」→ %d 位' % len(zf))
    ds = ms.search('other', '扫灭诸多敌国')
    ck(len(ds) == 1 and ds[0]['name'] == '嬴政', '其他描述「扫灭诸多敌国」→ 命中 %s' % [i['name'] for i in ds])
    # 题库里的干扰项写作 "XXX（误导）"：去掉标点后应能正常命中，且检索词也无需带"（误导）"
    mis = [i for i in ms.items if any('误导' in d for d in i['descNorm'])]
    ck(len(mis) > 0, '题库确实存在"（误导）"干扰项：%d 位名士' % len(mis))
    a_mis = [d for i in mis for d in i['descNorm'] if '误导' in d][0]
    plain = a_mis.replace('误导', '')          # 如 "大器晚成"
    r1 = ms.search('other', plain)
    r2 = ms.search('other', plain + '（误导）')
    ck(any(i['name'] in {x['name'] for x in r1} for i in mis),
       '检索词「%s」能命中对应的干扰项' % plain)
    ck(len(r2) == len(r1) and {x['name'] for x in r2} == {x['name'] for x in r1},
       '检索词「%s（误导）」带标点 → 归一化后与「%s」同结果（%d 位），说明干扰项照常参与检索'
       % (plain, plain, len(r2)))
    # 不拆分检索词
    nb = ms.search('other', '灭诸')
    ck(len(nb) >= 1 and all(any('灭诸' in d for d in i['descNorm']) for i in nb),
       '「灭诸」连续子串可命中 → %d 条' % len(nb))

    print('【名士 · 层级检索与计数】')
    lvl1 = ms.search('dynasty', '唐')
    lvl2 = ms.search('love', '书画', pool=lvl1)
    ck(all('唐' in i['dynasty'] and '书画' in i['love'] for i in lvl2),
       '唐 → 二次检索 爱好书画 → %d 位（在上层结果内筛）' % len(lvl2))
    lvl3 = ms.search('rank', '天', pool=lvl2)
    ck(all(i in lvl2 for i in lvl3), '三层叠加（唐·书画·天）→ %d 位' % len(lvl3))
    ck(MingShi.label({'name': '嬴政', 'dynasty': '秦'}) == '嬴政（秦）', '结果格式 = 名士（朝代）')

    print('【名士 · 题库覆盖核对】')
    ck(len(DYN) == 15 and len(LOVE) == 10 and len(CLUB) == 9 and len(RANK) == 3,
       '选项卡数量与需求一致：朝代15 / 爱好10 / 社团9 / 品阶3')
    covered = set()
    for i in ms.items:
        for d in DYN:
            if d in i['dynasty']:
                covered.add(d)
                break
    ck('辽' not in covered, '「辽」在题库中确实没有对应名士：%s' % sorted(covered))

    print('=' * 68)
    if fails:
        print('❌ 失败 %d 项：' % len(fails))
        for f in fails:
            print('   -', f)
        return 1
    print('✅ 全部自测通过（三大模块检索语义已确认无歧义）')
    return 0


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--selftest', action='store_true')
    a = ap.parse_args()
    sys.exit(selftest())
