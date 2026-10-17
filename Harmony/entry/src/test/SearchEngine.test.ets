import { describe, beforeEach, afterEach, it, expect } from '@ohos/hypium'
import { SearchEngine } from '../main/ets/engine/SearchEngine'
import { PoetryItem, GridCellData, GridPosition } from '../main/ets/model/PoetryItem'

/**
 * 构建一个 6×5 的测试网格（6 列 5 行）
 * @param chars 30 个字符组成的二维数组（5 行 × 6 列）
 */
function buildGrid(chars: string[][]): GridCellData[][] {
  const grid: GridCellData[][] = []
  for (let r = 0; r < 5; r++) {
    const row: GridCellData[] = []
    for (let c = 0; c < 6; c++) {
      const cell = new GridCellData(r, c)
      cell.char = chars[r][c]
      row.push(cell)
    }
    grid.push(row)
  }
  return grid
}

/**
 * 构建测试用的小题库
 */
function buildTestDb(): PoetryItem[] {
  return [
    {
      line: "床前明月光",
      title: "静夜思",
      author: "李白",
      chars: ["床", "前", "明", "月", "光"]
    },
    {
      line: "疑是地上霜",
      title: "静夜思",
      author: "李白",
      chars: ["疑", "是", "地", "上", "霜"]
    },
    {
      line: "低头思故乡",
      title: "静夜思",
      author: "李白",
      chars: ["低", "头", "思", "故", "乡"]
    },
    {
      line: "国破山河在",
      title: "春望",
      author: "杜甫",
      chars: ["国", "破", "山", "河", "在"]
    }
  ]
}

export default function searchEngineTest() {
  describe('SearchEngine', () => {

    // ==================== 测试 1：完全匹配 ====================
    it('should_match_when_all_chars_present', 0, () => {
      const grid = buildGrid([
        ['床', '前', '明', '月', '光', 'X'],
        ['X', 'X', 'X', 'X', 'X', 'X'],
        ['X', 'X', 'X', 'X', 'X', 'X'],
        ['X', 'X', 'X', 'X', 'X', 'X'],
        ['X', 'X', 'X', 'X', 'X', 'X']
      ])
      const engine = new SearchEngine(buildTestDb())
      const results = engine.search(grid)

      expect(results.length).assertEqual(1)
      expect(results[0].poetry.line).assertEqual('床前明月光')
      expect(results[0].positions.length).assertEqual(5)
    })

    // ==================== 测试 2：分散匹配（跨行跨列，含第 6 列） ====================
    it('should_match_scattered_chars_across_grid', 0, () => {
      const grid = buildGrid([
        ['床', 'X', 'X', 'X', 'X', 'X'],
        ['X', '前', 'X', 'X', 'X', 'X'],
        ['X', 'X', '明', 'X', 'X', 'X'],
        ['X', 'X', 'X', '月', 'X', 'X'],
        ['X', 'X', 'X', 'X', 'X', '光'] // 「光」落在第 6 列（列号 5）
      ])
      const engine = new SearchEngine(buildTestDb())
      const results = engine.search(grid)

      expect(results.length).assertEqual(1)
      expect(results[0].poetry.line).assertEqual('床前明月光')
      // 第 6 列（列号 5）参与匹配
      expect(results[0].positions.some((p: GridPosition) => p.col === 5)).assertTrue()
    })

    // ==================== 测试 3：不匹配（缺字） ====================
    it('should_not_match_when_char_missing', 0, () => {
      const grid = buildGrid([
        ['床', '前', '明', '月', 'X', 'X'], // 缺「光」
        ['X', 'X', 'X', 'X', 'X', 'X'],
        ['X', 'X', 'X', 'X', 'X', 'X'],
        ['X', 'X', 'X', 'X', 'X', 'X'],
        ['X', 'X', 'X', 'X', 'X', 'X']
      ])
      const engine = new SearchEngine(buildTestDb())
      const results = engine.search(grid)

      expect(results.length).assertEqual(0)
    })

    // ==================== 测试 4：多句同时匹配 ====================
    it('should_match_multiple_poems', 0, () => {
      const grid = buildGrid([
        ['床', '前', '明', '月', '光', 'X'],
        ['疑', '是', '地', '上', '霜', 'X'],
        ['X', 'X', 'X', 'X', 'X', 'X'],
        ['X', 'X', 'X', 'X', 'X', 'X'],
        ['X', 'X', 'X', 'X', 'X', 'X']
      ])
      const engine = new SearchEngine(buildTestDb())
      const results = engine.search(grid)

      expect(results.length).assertEqual(2)
    })

    // ==================== 测试 5：重复汉字产生多种匹配 ====================
    it('should_generate_multiple_combinations_for_duplicate_chars', 0, () => {
      // 「处」出现了2次 → 至少2种匹配组合
      const db: PoetryItem[] = [{
        line: "处处闻啼鸟",
        title: "春晓",
        author: "孟浩然",
        chars: ["处", "处", "闻", "啼", "鸟"]
      }]
      const grid = buildGrid([
        ['处', '处', '闻', '啼', '鸟', 'X'], // 两个「处」分别在 (0,0) 和 (0,1)
        ['X', 'X', 'X', 'X', 'X', 'X'],
        ['X', 'X', 'X', 'X', 'X', 'X'],
        ['X', 'X', 'X', 'X', 'X', 'X'],
        ['X', 'X', 'X', 'X', 'X', 'X']
      ])
      // 笛卡尔积: 处→[(0,0),(0,1)], 处→[(0,0),(0,1)], 闻→[(0,2)], 啼→[(0,3)], 鸟→[(0,4)]
      // 组合数 = 2×2×1×1×1 = 4
      const engine = new SearchEngine(db)
      const results = engine.search(grid)

      expect(results.length).assertEqual(4)
    })

    // ==================== 测试 6：空网格 ====================
    it('should_return_empty_for_blank_grid', 0, () => {
      const grid = buildGrid([
        ['', '', '', '', '', ''],
        ['', '', '', '', '', ''],
        ['', '', '', '', '', ''],
        ['', '', '', '', '', ''],
        ['', '', '', '', '', '']
      ])
      const engine = new SearchEngine(buildTestDb())
      const results = engine.search(grid)

      expect(results.length).assertEqual(0)
    })

    // ==================== 测试 7：highlightMatched 标注功能 ====================
    it('should_highlight_matched_cells', 0, () => {
      const grid = buildGrid([
        ['床', '前', '明', '月', '光', 'X'],
        ['X', 'X', 'X', 'X', 'X', 'X'],
        ['X', 'X', 'X', 'X', 'X', 'X'],
        ['X', 'X', 'X', 'X', 'X', 'X'],
        ['X', 'X', 'X', 'X', 'X', 'X']
      ])
      const engine = new SearchEngine(buildTestDb())
      const results = engine.search(grid)

      SearchEngine.highlightMatched(grid, results)

      // 前5个格子应该被标注
      expect(grid[0][0].isMatched).assertEqual(true)
      expect(grid[0][1].isMatched).assertEqual(true)
      expect(grid[0][2].isMatched).assertEqual(true)
      expect(grid[0][3].isMatched).assertEqual(true)
      expect(grid[0][4].isMatched).assertEqual(true)
      // 第 6 列未匹配，保持 false
      expect(grid[0][5].isMatched).assertEqual(false)
      // 未匹配的格子保持 false
      expect(grid[1][0].isMatched).assertEqual(false)
    })

  })
}
