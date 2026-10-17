import { PoetryItem, MatchResult, GridPosition, GridCellData } from '../model/PoetryItem'

/**
 * 诗词检索引擎 — 「择字成诗」
 *
 * 匹配规则：全局集合匹配
 * - 一句诗的所有汉字只要全部出现在 6×5 表格（6 列 5 行）中，即视为命中
 * - 不限行列、不要求顺序、不要求相邻
 * - 重复汉字会产生多种匹配组合，每种独立展示
 */
export class SearchEngine {
  private poetryDb: PoetryItem[]

  constructor(poetryDb: PoetryItem[]) {
    this.poetryDb = poetryDb
  }

  /**
   * 对 6×5 网格执行检索
   * @param grid 6×5 格子数据（二维数组，5 行 6 列）
   * @returns 所有匹配结果
   */
  search(grid: GridCellData[][]): MatchResult[] {
    // 步骤 1：构建「汉字 → 坐标列表」映射，空格跳过
    const charMap = new Map<string, GridPosition[]>()
    for (let r = 0; r < 5; r++) {
      for (let c = 0; c < 6; c++) {
        const ch = grid[r][c].char
        if (ch === '') continue
        if (!charMap.has(ch)) {
          charMap.set(ch, [])
        }
        charMap.get(ch)!.push(new GridPosition(r, c))
      }
    }

    // 步骤 2：遍历题库，逐条匹配，汇总结果
    const results: MatchResult[] = []
    for (const poetry of this.poetryDb) {
      results.push(...this.matchOne(poetry, charMap))
    }
    return results
  }

  /**
   * 匹配单句诗，返回该句的所有匹配组合
   */
  private matchOne(
    poetry: PoetryItem,
    charMap: Map<string, GridPosition[]>
  ): MatchResult[] {
    // 收集每个字在网格中的可选坐标；有字缺失则整句不匹配
    const posLists: GridPosition[][] = []
    for (const ch of poetry.chars) {
      const positions = charMap.get(ch)
      if (!positions || positions.length === 0) {
        return []
      }
      posLists.push(positions)
    }

    // 笛卡尔积：每种坐标组合对应一条匹配结果
    return cartesianProduct(posLists).map(combo => {
      const result = new MatchResult()
      result.poetry = poetry
      result.positions = combo
      return result
    })
  }

  /**
   * 标记网格中命中的格子（绿色高亮）
   */
  static highlightMatched(
    grid: GridCellData[][],
    results: MatchResult[]
  ): void {
    for (let r = 0; r < 5; r++) {
      for (let c = 0; c < 6; c++) {
        grid[r][c].isMatched = false
      }
    }
    for (const result of results) {
      for (const pos of result.positions) {
        grid[pos.row][pos.col].isMatched = true
      }
    }
  }
}

/**
 * 笛卡尔积：传入多个坐标列表，返回所有组合
 *
 * 例：
 *   [[(0,0), (2,2)], [(0,1)]] → [[(0,0),(0,1)], [(2,2),(0,1)]]
 */
function cartesianProduct(lists: GridPosition[][]): GridPosition[][] {
  if (lists.length === 0) return []

  let result: GridPosition[][] = [[]]

  for (const list of lists) {
    const next: GridPosition[][] = []
    for (const combo of result) {
      for (const pos of list) {
        next.push([...combo, pos])
      }
    }
    result = next
  }

  return result
}
