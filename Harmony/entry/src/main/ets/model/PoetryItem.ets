/**
 * 诗词数据模型 — 「择字成诗」模块
 *
 * 对应题库（H:\projects\info\题库.xlsx）中一行数据，
 * 以及 6×5（6 列 5 行）填字检索过程中产生的中间数据。
 */

/**
 * 诗词条目：题库里的一句五言诗句
 */
export class PoetryItem {
  /** 诗句原文，如 "床前明月光" */
  line: string = ''
  /** 篇名（含书名号），如 "《静夜思》" */
  title: string = ''
  /** 作者，如 "李白" */
  author: string = ''
  /** 单字数组（5 个），如 ["床","前","明","月","光"] */
  chars: string[] = []
}

/**
 * 格子坐标（行、列，均取值 0~4）
 */
export class GridPosition {
  row: number = 0
  col: number = 0

  constructor(row: number, col: number) {
    this.row = row
    this.col = col
  }
}

/**
 * 单条匹配结果：某句诗命中后，每个字落在格子里的位置
 */
export class MatchResult {
  /** 命中的诗句 */
  poetry: PoetryItem = new PoetryItem()
  /** 每个汉字在 6×5 网格中的位置 */
  positions: GridPosition[] = []

  /** 用于 UI 列表渲染的唯一标识 */
  get id(): string {
    const posStr = this.positions
      .map(p => `${p.row}${p.col}`)
      .join('')
    return `${this.poetry.line}_${posStr}`
  }
}

/**
 * 单个格子的状态（@Observed 装饰，支持 ArkUI 响应式追踪）
 */
@Observed
export class GridCellData {
  row: number = 0
  col: number = 0
  /** 当前填入的汉字，空串表示未填 */
  char: string = ''
  /** 是否被检索命中（绿色高亮） */
  isMatched: boolean = false

  constructor(row: number, col: number) {
    this.row = row
    this.col = col
  }
}
