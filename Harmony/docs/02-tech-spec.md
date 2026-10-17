# 技术规格说明书

## 1. 技术选型

| 层面 | 选择 | 说明 |
|------|------|------|
| 开发语言 | ArkTS | TypeScript 超集，HarmonyOS 原生语言 |
| UI 框架 | ArkUI | 声明式 UI |
| 开发工具 | DevEco Studio 6.1.1 | 华为官方 IDE |
| SDK | 6.1.1 (API 24) | HarmonyOS NEXT |
| 数据格式 | 硬编码 .ets 文件 | Excel → JSON → .ets，离线内置 |

---

## 2. 项目架构

```
entry/src/main/ets/
├── entryability/EntryAbility.ets     # 入口，沉浸式窗口设置
├── pages/
│   ├── Index.ets                      # 主页面：底部悬浮导航 + 双模块切换
│   ├── idiom/IdiomSearchPage.ets      # 成语检索页
│   └── poetry/PoetrySearchPage.ets    # 诗词检索页（迁入）
├── model/
│   ├── IdiomItem.ets                  # 成语数据模型
│   └── PoetryItem.ets                 # 诗词数据模型（含 @Observed 格子类）
├── service/
│   └── IdiomSearchService.ets         # 成语检索（三模式 + 历史栈）
├── engine/
│   └── SearchEngine.ets               # 诗词检索引擎（集合匹配）
├── data/
│   ├── idiom_db.ets                   # 成语库（脚本生成）
│   └── poetry_db.ets                  # 诗词库（282 条）
├── common/
│   ├── Theme.ets                      # 统一主题常量
│   └── BottomNavBar.ets               # 底部悬浮导航栏
└── components/
    ├── GridCell.ets / PoetryGrid.ets  # 诗词输入组件
    └── ResultCard.ets / ResultList.ets # 诗词结果组件
```

---

## 3. 数据模型

### IdiomItem（成语）

```typescript
class IdiomItem {
  word: string      // 成语，如 "暗渡陈仓"
  chars: string[]   // 4 单字
  plain: string[]   // 无音调拼音，如 ["an","du","chen","cang"]
  tones: number[]   // 声调，如 [4,4,2,1]
  pinyin: string[]  // 带声调拼音，如 ["àn","dù","chén","cāng"]
}
```

- `word/chars/plain/tones` 直接来自 Excel。
- `pinyin` 由 `plain + tones` 推导，用于结果展示。
- 标调规则：音节内按 a→o→e→i/u 后置元音标调；`v` 转 `ü`。

### PoetryItem（诗词，沿用）

```typescript
class PoetryItem {
  line: string       // 诗句原文
  title: string      // 篇名
  author: string     // 作者
  chars: string[]    // 单字数组
}
```

---

## 4. 成语检索算法

维护「候选集 + 历史栈」：

```
第 0 级：候选集 = 完整 IDIOM_DB
每次检索：对候选集逐条比对 4 个位置
  位置 i 输入为空 → 跳过（通配）
  位置 i 输入非空 → 精确匹配该模式对应字段（拼音/声调/单字）
  命中集合 → 下一级候选集，压栈
```

| 操作 | 行为 |
|------|------|
| 检索 / 二次检索 | 在当前候选集匹配，压栈 |
| 清空当前检索 | 弹栈，回到上一级 |
| 清空所有检索 | 清输入 + 清栈，回到第 0 级 |

拼音匹配前归一化：去空格、统一小写、`v`↔`ü`。
拼音模式逐位置匹配分三档：输入为声母 → 前缀匹配；为韵母 → 后缀匹配；否则（完整音节）→ 精确匹配。

---

## 5. 诗词检索算法（沿用）

- 构建 `Map<汉字, GridPosition[]>`，逐句判断所有字是否都在表格中
- 重复汉字用笛卡尔积生成多组坐标组合
- 复杂度 O(N×K)，N=条目数，K=每句字数

---

## 6. 主题与深色模式

- 所有颜色用 `$r('app.color.xxx')` 资源引用
- `resources/base/element/color.json`（浅色）+ `resources/dark/element/color.json`（深色）成对定义
- 系统切深色时 ArkUI 自动切换资源
- 主题为中国风配色：主色朱砂红、背景淡黄宣纸、命中高亮竹绿

---

## 7. 沉浸式处理

- `EntryAbility`：`setWindowSystemBarProperties` 设状态栏/导航条颜色与图标色
- 页面：`.expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])`

---

## 8. 响应式布局

- `onAreaChange` 拿窗口宽度
- 断点 600vp：≤600 单栏，>600 双栏/加宽
- 所有尺寸用 `vp` 单位

---

## 9. 依赖关系

- 无第三方运行时依赖（纯 ArkTS/ArkUI）
- 无网络依赖（数据内置）
- Excel 转换脚本用 Python（openpyxl，仅开发阶段）
