# -*- coding: utf-8 -*-
"""Minimal Markdown -> styled Chinese-style HTML converter for the fhlSearch docs."""
import sys, io, os, re, html

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

CSS = """
:root{
  --paper:#F7F1E3; --paper2:#EFE4CE; --ink:#2B2118; --ink2:#5A4A38;
  --zhu:#9E2B25; --zhu2:#C0392B; --jin:#B08A3E; --qing:#3F6B4A; --green:#1F6B2C;
}
*{box-sizing:border-box}
body{
  margin:0; padding:0 0 80px 0;
  background:
    radial-gradient(circle at 12% 8%, rgba(176,138,62,.10), transparent 45%),
    radial-gradient(circle at 88% 92%, rgba(158,43,37,.08), transparent 45%),
    linear-gradient(180deg,var(--paper) 0%, var(--paper2) 100%);
  background-attachment:fixed;
  color:var(--ink);
  font-family:"KaiTi","STKaiti","Microsoft YaHei","SimSun",serif;
  font-size:16px; line-height:1.85;
}
.wrap{max-width:1000px;margin:0 auto;padding:0 28px}
header{
  border-bottom:3px double var(--jin);
  margin:0 0 28px 0; padding:38px 28px 22px 28px;
  background:linear-gradient(180deg,rgba(255,255,255,.55),rgba(255,255,255,0));
}
header .wrap{padding:0 0}
h1{
  font-size:34px;letter-spacing:.14em;margin:0 0 10px 0;color:var(--zhu);
  font-weight:bold; text-shadow:0 1px 0 rgba(255,255,255,.7);
}
h1::before{content:"❖ ";color:var(--jin);font-size:22px;vertical-align:3px}
h2{
  font-size:23px;margin:52px 0 16px 0;color:var(--zhu);
  padding:6px 0 8px 16px;border-left:6px solid var(--zhu);
  background:linear-gradient(90deg,rgba(158,43,37,.09),rgba(158,43,37,0));
  letter-spacing:.06em;
}
h3{font-size:19px;margin:34px 0 12px 0;color:var(--ink);
   border-bottom:1px solid var(--jin);padding-bottom:6px;letter-spacing:.05em}
h3::before{content:"▍";color:var(--jin);margin-right:6px}
h4{font-size:17px;margin:24px 0 10px 0;color:var(--qing)}
p{margin:12px 0}
strong{color:var(--zhu2)}
code{
  font-family:Consolas,"Courier New",monospace;font-size:14px;
  background:rgba(176,138,62,.16);border:1px solid rgba(176,138,62,.35);
  border-radius:3px;padding:1px 6px;color:#6A4A18;
}
pre{
  background:#2B2118;color:#F0E6D2;border-radius:6px;padding:18px 20px;
  overflow:auto;border-left:6px solid var(--jin);
  font-family:Consolas,"Courier New",monospace;font-size:14px;line-height:1.6;
}
pre code{background:none;border:none;color:inherit;padding:0;font-size:14px}
table{
  border-collapse:collapse;width:100%;margin:18px 0;font-size:15px;
  box-shadow:0 2px 10px rgba(90,74,56,.10);background:rgba(255,255,255,.58);
}
th{
  background:linear-gradient(180deg,#8E2620,#7A1F1A);color:#F7F1E3;
  font-weight:bold;letter-spacing:.05em;
}
th,td{border:1px solid rgba(176,138,62,.55);padding:9px 13px;text-align:left;vertical-align:top}
tbody tr:nth-child(even){background:rgba(176,138,62,.075)}
tbody tr:hover{background:rgba(176,138,62,.16)}
blockquote{
  margin:18px 0;padding:12px 20px;border-left:5px solid var(--jin);
  background:rgba(176,138,62,.11);color:var(--ink2);border-radius:0 5px 5px 0;
}
blockquote p{margin:6px 0}
ul,ol{margin:12px 0;padding-left:30px}
li{margin:7px 0}
li::marker{color:var(--zhu)}
hr{border:none;border-top:1px solid var(--jin);margin:40px 0;opacity:.6}
a{color:var(--zhu);text-decoration:none;border-bottom:1px dashed var(--jin)}
footer{
  margin-top:60px;padding-top:18px;border-top:3px double var(--jin);
  text-align:center;color:var(--ink2);font-size:14px;letter-spacing:.2em;
}
"""


def esc(t):
    return html.escape(t, quote=False)


def inline(t):
    t = esc(t)
    t = re.sub(r'`([^`]+)`', r'<code>\1</code>', t)
    t = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', t)
    t = re.sub(r'(?<![\w*])\*([^*\n]+)\*(?![\w*])', r'<em>\1</em>', t)
    t = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', r'<a href="\2">\1</a>', t)
    return t


def convert(md):
    lines = md.split("\n")
    out = []
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]

        # fenced code
        if line.strip().startswith("```"):
            lang = line.strip()[3:].strip()
            i += 1
            buf = []
            while i < n and not lines[i].strip().startswith("```"):
                buf.append(lines[i]); i += 1
            i += 1
            out.append('<pre><code>%s</code></pre>' % esc("\n".join(buf)))
            continue

        # table
        if line.lstrip().startswith("|") and i + 1 < n and re.match(r'^\s*\|[\s:|-]+\|\s*$', lines[i+1]):
            header = [c.strip() for c in line.strip().strip("|").split("|")]
            i += 2
            body = []
            while i < n and lines[i].lstrip().startswith("|"):
                body.append([c.strip() for c in lines[i].strip().strip("|").split("|")])
                i += 1
            t = ['<table><thead><tr>']
            for h in header:
                t.append('<th>%s</th>' % inline(h))
            t.append('</tr></thead><tbody>')
            for row in body:
                t.append('<tr>')
                for c in row:
                    t.append('<td>%s</td>' % inline(c))
                t.append('</tr>')
            t.append('</tbody></table>')
            out.append("".join(t))
            continue

        # heading
        m = re.match(r'^(#{1,6})\s+(.*)$', line)
        if m:
            lvl = len(m.group(1))
            out.append('<h%d>%s</h%d>' % (lvl, inline(m.group(2)), lvl))
            i += 1
            continue

        # hr
        if re.match(r'^\s*(---|\*\*\*|___)\s*$', line):
            out.append('<hr/>')
            i += 1
            continue

        # blockquote
        if line.lstrip().startswith(">"):
            buf = []
            while i < n and lines[i].lstrip().startswith(">"):
                buf.append(lines[i].lstrip()[1:].strip())
                i += 1
            out.append('<blockquote>%s</blockquote>' % " ".join(inline(b) for b in buf if b))
            continue

        # lists
        if re.match(r'^\s*([-*+]|\d+\.)\s+', line):
            ordered = bool(re.match(r'^\s*\d+\.\s+', line))
            tag = "ol" if ordered else "ul"
            items = []
            while i < n and re.match(r'^\s*([-*+]|\d+\.)\s+', lines[i]):
                items.append(re.sub(r'^\s*([-*+]|\d+\.)\s+', '', lines[i]))
                i += 1
            out.append('<%s>%s</%s>' % (tag, "".join('<li>%s</li>' % inline(x) for x in items), tag))
            continue

        if not line.strip():
            i += 1
            continue

        # paragraph
        buf = []
        while i < n and lines[i].strip() and not re.match(r'^\s*(#{1,6}\s|[-*+]\s|\d+\.\s|>|\||```|---)', lines[i]):
            buf.append(lines[i].strip())
            i += 1
        if buf:
            out.append('<p>%s</p>' % inline(" ".join(buf)))
    return "\n".join(out)


def main():
    src = sys.argv[1]
    dst = sys.argv[2]
    title = sys.argv[3] if len(sys.argv) > 3 else "文档"
    with open(src, "r", encoding="utf-8") as f:
        md = f.read()
    body = convert(md)
    page = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>%s</title>
<style>%s</style>
</head>
<body>
<header><div class="wrap">%s</div></header>
<div class="wrap">
%s
<footer>忘 川 检 索 · fhlSearch</footer>
</div>
</body>
</html>""" % (esc(title), CSS, body.split("</h1>")[0] + "</h1>" if "</h1>" in body else "", body.split("</h1>", 1)[1] if "</h1>" in body else body)
    with open(dst, "w", encoding="utf-8") as f:
        f.write(page)
    print("written:", dst, os.path.getsize(dst), "bytes")


if __name__ == "__main__":
    main()
