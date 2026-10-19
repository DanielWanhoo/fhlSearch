# -*- coding: utf-8 -*-
"""审计 PinyinTone.mark 在真实题库上的表现（把 Kotlin 算法 1:1 移植到 Python）。"""
import io, json, os, sys, collections


import os

# ---- 路径：全部按"本脚本所在位置"推算，克隆到任何目录下都能直接跑 ----
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.makedirs(os.path.join(_ROOT, '_analysis'), exist_ok=True)

ROOT = _ROOT
ASSETS = os.path.join(ROOT, 'app', 'src', 'main', 'assets')
OUT = os.path.join(ROOT, '_analysis', 'pinyin_audit_report.txt')

TONES = {
    'a': 'āáǎàa', 'e': 'ēéěèe', 'i': 'īíǐìi',
    'o': 'ōóǒòo', 'u': 'ūúǔùu', 'ü': 'ǖǘǚǜü',
}
VOWELS = 'aeiouüAEIOUÜ'


def toned(v, tone):
    key = v.lower()
    return TONES.get(key, v)[tone - 1] if key in TONES else v


def mark(syllable):
    """与 util/PinyinTone.kt 完全一致"""
    if not syllable:
        return syllable
    last = syllable[-1]
    tone = int(last) if last in '12345' else 5
    body = syllable[:-1] if tone in (1, 2, 3, 4, 5) else syllable
    if not body:
        return syllable
    n = body.replace('v', 'ü').replace('V', 'Ü')
    low = n.lower()
    if 'a' in low:
        idx = low.index('a')
    elif 'o' in low:
        idx = low.index('o')
    elif 'e' in low:
        idx = low.index('e')
    elif 'iu' in low:
        i_pos = low.index('i')
        idx = low.find('u', i_pos)
    else:
        idx = max((i for i, c in enumerate(n) if c in VOWELS), default=-1)
    if idx < 0:
        return n
    return n[:idx] + toned(n[idx], tone) + n[idx + 1:]


def load(name):
    with io.open(os.path.join(ASSETS, name), encoding='utf-8') as f:
        return json.load(f)


lines = []


def w(s=''):
    lines.append(s)


cy = load('tiku_chengyu.json')
w('===== 成语题库 =====')
w('version=%s count=%d source=%s' % (cy.get('version'), len(cy['items']), cy.get('source')))

# 完整性
bad_shape = [x['w'] for x in cy['items'] if not (len(x['p']) == len(x['t']) == len(x['c']) == 4)]
w('字段长度不是 4 的条目: %d %s' % (len(bad_shape), bad_shape[:10]))
empty = [x['w'] for x in cy['items']
         for k in ('p', 't', 'c') for v in x[k] if not str(v).strip()]
w('存在空字段的条目: %d' % len(empty))

# 声调取值
tones = collections.Counter(t for x in cy['items'] for t in x['t'])
w('声调取值分布: %s' % dict(sorted(tones.items())))

# 单字与成语是否对得上
mismatch = []
for x in cy['items']:
    if ''.join(x['c']) != x['w']:
        mismatch.append((x['w'], ''.join(x['c'])))
w('单字拼接 != 成语 的条目: %d %s' % (len(mismatch), mismatch[:10]))

# 全部音节
syl = collections.Counter(p for x in cy['items'] for p in x['p'])
w('不同音节数: %d' % len(syl))

# 带调结果（音节+声调组合）
combo = sorted({(p, t) for x in cy['items'] for p, t in zip(x['p'], x['t'])})
w('不同(音节,声调)组合: %d' % len(combo))

# 可疑：拼音含非 a-z/v 字符
weird = sorted({p for p in syl if not p.isalpha() or any(c not in 'abcdefghijklmnopqrstuvwxyz' for c in p)})
w('含非小写字母的音节: %s' % weird)

# 可疑：标调位置看起来不对的（标在 i/u 上但后面还有元音）
suspect = []
for p, t in combo:
    m = mark(p + t)
    idx = max((i for i, c in enumerate(m) if c in 'āáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜ'), default=-1)
    if idx >= 0:
        tail = [c for c in m[idx + 1:] if c in VOWELS]
        if tail:
            suspect.append((p, t, m))
w('标调位置后仍有元音（需人工确认）: %d' % len(suspect))
for p, t, m in suspect:
    w('   %-8s %s -> %s' % (p, t, m))

# 未标调（结果里没有带调符号）
nomark = [(p, t) for p, t in combo if mark(p + t) == mark(p + t).lower().replace('v', 'ü') and
          not any(c in 'āáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜ' for c in mark(p + t))]
w('未出现声调符号的组合: %d %s' % (len(nomark), nomark[:20]))

# 逐音节全表（供人工核对）
w('')
w('----- 音节 -> 1/2/3/4/5 声标注结果 -----')
for p in sorted(syl):
    w('  %-8s %s' % (p, '  '.join('%d:%s' % (t, mark(p + str(t))) for t in (1, 2, 3, 4, 5))))

# 诗词 / 名士
sh = load('tiku_shici.json')
w('')
w('===== 诗词题库 =====')
w('count=%d' % len(sh['items']))
w('字段长度不是 5: %s' % [x['l'] for x in sh['items'] if len(x['c']) != 5])
w('单字拼接 != 诗句: %s' % [(x['l'], ''.join(x['c'])) for x in sh['items'] if ''.join(x['c']) != x['l']][:5])
w('样例: %s' % [(x['l'], x['n'], x['a'], ''.join(x['c'])) for x in sh['items'][:3]])

ms = load('tiku_mingshi.json')
w('')
w('===== 名士题库 =====')
w('count=%d' % len(ms['items']))
keys = sorted({k for x in ms['items'] for k in x.keys()})
w('字段: %s' % keys)
w('样例: %s' % json.dumps(ms['items'][0], ensure_ascii=False)[:400])
w('norm 键: %s' % sorted({k for x in ms['items'] for k in x.get('norm', {}).keys()}))

with io.open(OUT, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines))
print('written', OUT, len(lines), 'lines')
