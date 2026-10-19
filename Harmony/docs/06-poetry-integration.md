# 诗词模块说明

## 定位

诗词模块 = 「择字成诗」：6×5 填字检索。**本模块为本仓库内从零重写**（不再沿用早期 PoetrySearch 工程里的源码）。

## 数据来源

- 题库文件：`data/诗词检索.xlsx`（Sheet 名「择字成诗」）
- 数据量：**282 句五言诗**，37 位作者，132 个篇名，全部 5 字、无空缺
- 列结构（8 列）：`诗句 | 诗词名 | 作者 | ① | ② | ③ | ④ | ⑤`（①~⑤ 为五个单字）
- 转换脚本：`scripts/excel_to_poetry.py` → 生成 `entry/src/main/ets/data/poetry_db.ets`

> 注意：下载目录里的 `忘川风华录诗词题库2.xlsx`、`忘川风华录诗词题库_校对版.xlsx` 是旧草稿，以 `题库.xlsx` 为准。

## 文件清单

| 文件 | 说明 |
|------|------|
| `model/PoetryItem.ets` | 数据模型（PoetryItem / GridPosition / MatchResult / GridCellData） |
| `engine/SearchEngine.ets` | 检索引擎：集合覆盖匹配 + 笛卡尔积 |
| `data/poetry_db.ets` | 题库数据（脚本生成，282 条，勿手改） |
| `components/GridCell.ets` | 单个输入格（限 1 汉字 + 校验 + 高亮） |
| `components/PoetryGrid.ets` | 6×5 填字表格（6 列 5 行，共 30 格） |
| `components/ResultCard.ets` | 单条结果卡片 |
| `components/ResultList.ets` | 结果列表（含空状态） |
| `pages/Index.ets` | 诗词检索页（当前为 @Entry，待接入底部导航） |

## 检索逻辑

1. 6×5 格子（6 列 5 行）填满 30 个汉字后点「开始检索」（未填满弹窗提示）
2. 一句诗（5 字）的所有汉字**全部出现在格子里即命中**
3. 不限行列、不要求顺序、不要求相邻
4. 重复汉字产生多种组合（笛卡尔积），各自独立展示
5. 命中格子变绿高亮；无结果弹窗提示「未找到匹配」

## 深色模式

- 所有颜色用 `$r('app.color.xxx')`，`base/dark` 成对定义，随系统自动切换
- 配色方案见 `docs/03-design-spec.md`

## 待办

- **阶段 5**：底部悬浮导航接入 —— `pages/Index.ets` 由 @Entry 改为普通组件，新建组合主页面
- **阶段 2**：`EntryAbility.ets` 窗口系统栏颜色仍为硬编码（沉浸式深色适配），待迁移为资源引用