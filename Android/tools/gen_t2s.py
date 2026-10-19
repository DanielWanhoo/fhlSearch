# -*- coding: utf-8 -*-
r"""生成 Kotlin 用的「繁 → 简」小表 —— 产出 `ocr/T2S.kt`。

为什么要这张表
    ML Kit 的中文模型是中英混训的，碰到界面美术字 / 低分辨率字时会吐出繁体
    （別 / 燒 / 國 / 擷 / 間 / 兩 / 嬋…），而题库和检索全是简体。
    实测：10272 那张图里「別」被认成繁体，**「别有千金笑」这一整句就检索不到了**。
    所以在把识别的字填进格子之前先过一遍这张表。

怎么生成
    用 Windows 自带的繁简转换（LCMapString，经 VisualBasic 的 `StrConv` 调用），
    把 U+4E00..U+9FFF 全部过一遍，只留下同时满足两条的对子：
      1. 转出来的简体字**确实在题库里**（否则转了也没用）；
      2. 繁体字**本身不是题库里的正经字**（否则会把本来认对的字改错）。
    结果写死进 `T2S.kt`（768 对的常量字符串），运行时不依赖任何系统能力。

用法
    python tools\gen_t2s.py

    只有在**改了题库**、或想把表扩到题库之外的常用字时才需要重跑；
    生成结果是确定的（按码位遍历），重跑不会产生无谓的 diff。

前置条件
    只在 Windows 上能跑（依赖 LCMapString）。生成好的 `T2S.kt` 已经入库，
    非 Windows 环境直接编译即可，不需要跑这个脚本。
"""
import io
import os
import shutil
import subprocess
import sys
import tempfile


# ---- 路径：全部按"本脚本所在位置"推算，克隆到任何目录下都能直接跑 ----
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

ASSETS = os.path.join(_ROOT, 'app', 'src', 'main', 'assets')
OUT = os.path.join(_ROOT, 'app', 'src', 'main', 'java', 'com', 'wangchuan', 'fhlsearch', 'ocr', 'T2S.kt')

# 交给 PowerShell 做繁→简：整段码位区间过一遍，结果写成一个"繁体简体"交替的串
PS = r'''
[void][Reflection.Assembly]::LoadWithPartialName('Microsoft.VisualBasic')
$out = New-Object System.Text.StringBuilder
for ($cp = 0x4E00; $cp -le 0x9FFF; $cp++) {
  $ch = [string][char]$cp
  $conv = [Microsoft.VisualBasic.Strings]::StrConv($ch, [Microsoft.VisualBasic.VbStrConv]::SimplifiedChinese, 0)
  if ($conv.Length -eq 1 -and $conv[0] -ne $ch) { [void]$out.Append($ch).Append($conv) }
}
[IO.File]::WriteAllText($env:T2S_TMP, $out.ToString(), (New-Object System.Text.UTF8Encoding($false)))
'''

HEADER = '''package com.wangchuan.fhlsearch.ocr

/**
 * 「繁 → 简」小表 —— **自动生成，不要手改**。
 *
 * 生成脚本：`tools/gen_t2s.py`（用 Windows 的 LCMapString 把 U+4E00..U+9FFF 过一遍，
 * 只留"转出来的简体确实在题库里、且繁体本身不是题库正字"的对子）。
 *
 * 为什么需要：ML Kit 的中文模型遇到界面美术字、低分辨率字时会吐出繁体
 * （別 / 燒 / 國 / 擷 / 間 / 兩 / 嬋…），而题库与检索全是简体 ——
 * 实测光一个「別」就能让「别有千金笑」这句诗检索不到。
 *
 * 表里的字都在题库里出现过，所以只会"把繁体改回简体"，不会改坏本来正确的字。
 */
object T2S {

    /** 成对的「繁体＋简体」直接拼在一起，两两一组 */
    private const val PAIRS =
%s

    private val MAP: Map<Char, Char> = buildMap {
        var i = 0
        while (i + 1 < PAIRS.length) {
            put(PAIRS[i], PAIRS[i + 1])
            i += 2
        }
    }

    /** 繁体就转成简体，其余原样返回 */
    fun of(c: Char): Char = MAP[c] ?: c
}
'''


def corpus_chars():
    """题库里出现过的全部汉字（三份 JSON 都要，含名士描述）"""
    import json
    chars = set()
    for fn in ('tiku_shici.json', 'tiku_chengyu.json', 'tiku_mingshi.json'):
        path = os.path.join(ASSETS, fn)
        if not os.path.isfile(path):
            raise SystemExit('缺少题库文件：%s\n（先跑 tools\\build_tiku.py）' % path)
        data = json.load(io.open(path, encoding='utf-8'))
        for item in data['items']:
            for v in item.values():
                if isinstance(v, str):
                    chars.update(c for c in v if '\u4e00' <= c <= '\u9fff')
                elif isinstance(v, list):
                    for x in v:
                        if isinstance(x, str):
                            chars.update(c for c in x if '\u4e00' <= c <= '\u9fff')
                elif isinstance(v, dict):
                    for x in v.values():
                        if isinstance(x, str):
                            chars.update(c for c in x if '\u4e00' <= c <= '\u9fff')
    return chars


def all_pairs():
    """让 PowerShell 输出全量繁→简对子（繁体简体交替的一整串）"""
    shell = shutil.which('powershell') or shutil.which('pwsh')
    if not shell:
        raise SystemExit('找不到 PowerShell；这个脚本只能在 Windows 上跑。\n'
                         '（T2S.kt 已经入库，一般不需要重新生成）')
    tmpdir = tempfile.mkdtemp(prefix='fhl_t2s_')
    ps1 = os.path.join(tmpdir, 't2s.ps1')
    out = os.path.join(tmpdir, 't2s.txt')
    io.open(ps1, 'w', encoding='utf-8-sig', newline='\r\n').write(PS)
    env = dict(os.environ, T2S_TMP=out)
    subprocess.run([shell, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ps1],
                   check=True, timeout=600, env=env)
    text = io.open(out, encoding='utf-8').read()
    shutil.rmtree(tmpdir, ignore_errors=True)
    return text


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    corpus = corpus_chars()
    print('题库汉字 %d 个' % len(corpus))

    raw = all_pairs()
    print('系统给出的繁→简对子 %d 个' % (len(raw) // 2))

    pairs = []
    for i in range(0, len(raw) - 1, 2):
        trad, simp = raw[i], raw[i + 1]
        if simp in corpus and trad not in corpus:
            pairs.append((trad, simp))
    print('落在题库里的 %d 个' % len(pairs))
    if not pairs:
        raise SystemExit('一个都没匹配上，检查题库是否为空')

    body = ''.join(t + s for t, s in pairs)
    lines = []
    for i in range(0, len(body), 120):          # 120 字符 ≈ 60 对一行，读起来不费劲
        lines.append('        "%s" +' % body[i:i + 120])
    lines[-1] = lines[-1].rstrip(' +')

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    io.open(OUT, 'w', encoding='utf-8', newline='\n').write(HEADER % '\n'.join(lines))
    print('已写', OUT)
    print('样例：', ' '.join('%s→%s' % p for p in pairs[:12]))


if __name__ == '__main__':
    main()
