# -*- coding: utf-8 -*-
r"""Android 资源静态校验：在跑 Gradle 之前先抓出引用错误。

检查项：
  1. 所有 XML 是否格式良好；
  2. 代码与布局里引用的 @drawable/@color/@string/@dimen/@style/@menu/@mipmap/@xml
     是否都真实存在（含 res/color、res/drawable 里的选择器与 shape）；
  3. values 里 style 的 parent 是否可解析（本工程自定义的 parent 必须存在）；
  4. 资源名是否符合 Android 命名规范（小写字母、数字、下划线）。
"""
import os
import re
import sys
import xml.etree.ElementTree as ET


# ---- 路径：全部按"本脚本所在位置"推算，克隆到任何目录下都能直接跑 ----
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

ROOT = os.path.join(_ROOT, 'app', 'src', 'main')
RES = os.path.join(ROOT, 'res')

# ---------- 收集已定义的资源 ----------
defined = {}          # type -> set(name)


def add(t, n):
    defined.setdefault(t, set()).add(n)


FILE_TYPES = {
    'drawable': 'drawable', 'color': 'color', 'mipmap': 'mipmap',
    'menu': 'menu', 'layout': 'layout', 'xml': 'xml', 'anim': 'anim',
}

for dirpath, _, files in os.walk(RES):
    folder = os.path.basename(dirpath)
    # 带限定符的目录（drawable-xxxhdpi / mipmap-anydpi-v26）并入基础类型
    kind = FILE_TYPES.get(folder.split('-')[0])
    if kind is None:
        continue                # res 根目录、values* 等
    for fn in files:
        base, ext = os.path.splitext(fn)
        add(kind, base)

# values 里定义的 string/color/dimen/style/integer/bool/array
VALUE_DIRS = [d for d in os.listdir(RES) if d.startswith('values')]
xml_errors = []
for vd in VALUE_DIRS:
    p = os.path.join(RES, vd)
    for fn in os.listdir(p):
        if not fn.endswith('.xml'):
            continue
        path = os.path.join(p, fn)
        try:
            root = ET.parse(path).getroot()
        except ET.ParseError as e:
            xml_errors.append('%s: %s' % (path, e))
            continue
        for child in root:
            tag = child.tag
            name = child.get('name')
            if not name:
                continue
            if tag == 'item':
                t = child.get('type') or 'item'
            elif tag == 'string':
                t = 'string'
            elif tag == 'style':
                t = 'style'
            elif tag == 'declare-styleable':
                t = 'styleable'
            else:
                t = tag
            add(t, name)

# 布局/菜单/其他 XML 文件也算资源（layout/ 下的文件名）
# 同时解析所有 XML，检查格式与引用
REF = re.compile(r'@(?!\+|android:|null|\*)([\w]+)/([\w.]+)')
# 注意：前面加 (?<![\w.]) 是为了排除 android.R.attr.xxx 这种系统引用，
# 否则会被当成"工程里不存在的 @attr"误报。
CODE_REF = re.compile(r'(?<![\w.])R\.(\w+)\.(\w+)')
# 布局里定义的 id（android:id="@+id/xxx"）要先收进 id 类型，
# 否则 Kotlin 里的 R.id.xxx 全都会被误判成"引用了不存在的资源"。
ID_DEF = re.compile(r'@\+id/([\w.]+)')

refs = []      # (file, type, name)
for dirpath, _, files in os.walk(ROOT):
    for fn in files:
        path = os.path.join(dirpath, fn)
        if fn.endswith('.xml'):
            try:
                ET.parse(path)
            except ET.ParseError as e:
                xml_errors.append('%s: %s' % (path, e))
            with open(path, encoding='utf-8') as f:
                text = f.read()
            for m in ID_DEF.finditer(text):
                add('id', m.group(1))
            for m in REF.finditer(text):
                refs.append((os.path.relpath(path, ROOT), m.group(1), m.group(2)))
        elif fn.endswith('.kt'):
            with open(path, encoding='utf-8') as f:
                text = f.read()
            for m in CODE_REF.finditer(text):
                refs.append((os.path.relpath(path, ROOT), m.group(1), m.group(2)))

# ---------- 校验 ----------
problems = []

for path, t, n in refs:
    if t == 'android':
        continue
    if t == 'style' and n.startswith('Theme') and n == 'Theme.FhlSearch':
        pass
    if n not in defined.get(t, set()):
        problems.append('%s 引用了不存在的 @%s/%s' % (path, t, n))

# style parent 校验（只校验本工程自定义的 parent，形如 Xxx.Yyy 且不以 android:/Theme.Material 开头）
CUSTOM_PARENT = re.compile(r'^[A-Z][\w.]*$')
style_names = defined.get('style', set())
for vd in VALUE_DIRS:
    for fn in os.listdir(os.path.join(RES, vd)):
        if not fn.endswith('.xml'):
            continue
        path = os.path.join(RES, vd, fn)
        root = ET.parse(path).getroot()
        for child in root:
            if child.tag != 'style':
                continue
            parent = child.get('parent') or ''
            if not parent or parent.startswith('android:') or '.' not in parent:
                continue
            if parent.startswith(('Theme.Material', 'Widget.Material', 'TextAppearance.Material',
                                  'ThemeOverlay.Material', 'Base.', 'Theme.AppCompat')):
                continue
            if parent not in style_names:
                problems.append('%s 的 style %s 引用了不存在的 parent: %s'
                                % (fn, child.get('name'), parent))

# 命名规范（id 例外：Android 的 id 惯例就是小驼峰，如 tvTitle / rvResult）
NAME_OK = re.compile(r'^[a-z][a-z0-9_]*$')
for t, names in defined.items():
    if t in ('style', 'styleable', 'string', 'color', 'dimen', 'bool', 'integer',
             'array', 'item', 'id'):
        continue
    for n in names:
        if not NAME_OK.match(n):
            problems.append('资源名不符合规范: %s/%s' % (t, n))

print('已定义资源：')
for t in sorted(defined):
    print('  %-10s %3d  %s' % (t, len(defined[t]),
                              ', '.join(sorted(defined[t])[:6]) + ('...' if len(defined[t]) > 6 else '')))
print('\n共检查引用 %d 处' % len(refs))

if xml_errors:
    print('\n❌ XML 格式错误 %d 个：' % len(xml_errors))
    for e in xml_errors:
        print('   -', e)
if problems:
    print('\n❌ 发现问题 %d 个：' % len(problems))
    for p in sorted(set(problems)):
        print('   -', p)
if not xml_errors and not problems:
    print('\n✅ 资源校验全部通过')
sys.exit(1 if (xml_errors or problems) else 0)
