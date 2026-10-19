/**
 * 6×5 字格提取器 — 把 OCR 认出的「一堆汉字 + 坐标」还原成字格
 *
 * 输入：整张图里 OCR 认出的所有汉字及其外接框（像素坐标）
 * 输出：按阅读顺序（从上到下、从左到右）排好的汉字串
 *
 * 为什么只对齐「顺序」而不对齐「格子」：
 * 诗词检索是**全局面集合匹配**（一句诗的五个字只要都在格子里就算命中，不分行列、不比相邻），
 * 所以真正决定检索结果的是「这 30 个字对不对」，而不是每个字落在哪一格。
 * 只要按阅读顺序填进 6×5 表格，30 个字就是对的；位置只影响绿色高亮落在哪里。
 *
 * 三步：
 *   1. `groupRows`    —— 按纵向重叠把字归成行（一行内的字按横坐标排序）
 *   2. `findBestBlock` —— 在连续行里找最像「5 行 6 列 / 6 行 5 列」的那一块
 *                        （判据：每行字数够、各列横坐标对齐、行间距均匀）
 *   3. 找不到规整字格时退化处理（`fallbackRows`）：取字数最多的一段连续行，
 *      按阅读顺序最多取 30 个字 —— 拍糊少认一两个字时仍能填进去大半
 */

/** OCR 认出的单个汉字（图片像素坐标；cx/cy 为外接框中心，w/h 为宽高） */
export class OcrChar {
  ch: string = ''
  cx: number = 0
  cy: number = 0
  w: number = 0
  h: number = 0

  constructor(ch: string, cx: number, cy: number, w: number, h: number) {
    this.ch = ch
    this.cx = cx
    this.cy = cy
    this.w = w
    this.h = h
  }
}

/** 提取结果 */
export class GridExtraction {
  /** 按阅读顺序排好的汉字（可能少于 30 个） */
  chars: string[] = []
  /**
   * 逐格结果（行主序，长度 30，空串表示这一格没认出来）
   *
   * 只有认出「5 行 6 列 / 6 行 5 列」这种整格结构时才填；长度不足 30 表示这次没对齐到格位。
   * 多尺度识别要靠它把几次结果按格合并（有了格位，某次少认一个字也不会让后面全体错位）。
   */
  cells: string[] = []
  /** 认出的行数 / 每行字数（0 表示没认出规整字格，走了退化路径） */
  rowCount: number = 0
  colCount: number = 0
  /** 是否命中规整字格（供 UI 提示识别质量） */
  isGrid: boolean = false

  /** 已认出的格子数 */
  get filled(): number {
    return this.chars.length
  }
}

/** 候选字格（内部用） */
class BlockCandidate {
  rows: OcrChar[][] = []
  cols: number = 0
  score: number = 0

  constructor(rows: OcrChar[][], cols: number, score: number) {
    this.rows = rows
    this.cols = cols
    this.score = score
  }
}

const TARGET_CELLS = 30   // 6×5

// ==================== 对外入口 ====================

/**
 * 从 OCR 汉字列表里还原 6×5 字格
 * @param chars 整张图认出的所有汉字
 * @returns 提取结果；一个字都没认出来时返回 null
 */
export function extractGrid(chars: OcrChar[]): GridExtraction | null {
  if (chars.length === 0) {
    return null
  }
  const rows = groupRows(chars)
  const block = findBestBlock(rows)
  if (block !== null) {
    return toExtraction(block.rows, block.cols, true)
  }
  // 退化：认不出规整字格（拍歪 / 糊了 / 表格被别的东西压住）
  const loose = fallbackRows(rows)
  if (loose !== null) {
    return toExtraction(loose, 0, false)
  }
  // 最后兜底：全部按阅读顺序取前 30 个
  return toExtraction(rows, 0, false)
}

// ==================== 第 1 步：归行 ====================

/**
 * 按纵向重叠归行
 *
 * 做法：先按 y 排序，再逐个判断「和当前行的平均中心差是否小于半个字高」。
 * 字格里的字等高同排，这一步很稳；正文段落的行距通常也大于半个字高，不会被并到一起。
 */
export function groupRows(chars: OcrChar[]): OcrChar[][] {
  const sorted: OcrChar[] = chars.slice()
  sorted.sort((a: OcrChar, b: OcrChar) => a.cy - b.cy)

  const rows: OcrChar[][] = []
  let cur: OcrChar[] = []
  let meanCy: number = 0
  let meanH: number = 0

  for (const c of sorted) {
    if (cur.length === 0) {
      cur.push(c)
      meanCy = c.cy
      meanH = c.h
      continue
    }
    const tol: number = Math.max(meanH, c.h) * 0.5
    if (Math.abs(c.cy - meanCy) <= tol) {
      cur.push(c)
      meanCy = meanCy + (c.cy - meanCy) / cur.length
      meanH = meanH + (c.h - meanH) / cur.length
    } else {
      rows.push(cur)
      cur = [c]
      meanCy = c.cy
      meanH = c.h
    }
  }
  if (cur.length > 0) {
    rows.push(cur)
  }

  for (const r of rows) {
    r.sort((a: OcrChar, b: OcrChar) => a.cx - b.cx)
  }
  return rows
}

// ==================== 第 2 步：找最像字格的连续几行 ====================

/** 可能的字格形状：5 行 6 列 / 6 行 5 列（都是 30 格） */
function findBestBlock(rows: OcrChar[][]): BlockCandidate | null {
  const shapes: number[][] = [[5, 6], [6, 5]]
  let best: BlockCandidate | null = null

  for (const shape of shapes) {
    const n: number = shape[0]
    const c: number = shape[1]
    if (rows.length < n) {
      continue
    }
    for (let i = 0; i + n <= rows.length; i++) {
      const picked = pickWindow(rows, i, n, c)
      if (picked === null) {
        continue
      }
      const cand = scoreBlock(picked, c)
      if (best === null || cand.score > best.score) {
        best = cand
      }
    }
  }

  if (best !== null && best.score > 0) {
    return best
  }
  return null
}

/**
 * 取第 start 行起的 n 行，每行挑出 c 个字
 *
 * 行的字数正好是 c 时整行照用；字数更多（同一高度上还有别的文字，如右侧按钮）时，
 * 以「字数正好为 c 的那一行」为参照，挑出横向对齐得最好的一段 —— 避免把旁边的说明文字算进去。
 */
function pickWindow(rows: OcrChar[][], start: number, n: number, c: number): OcrChar[][] | null {
  const window: OcrChar[][] = []
  for (let k = start; k < start + n; k++) {
    window.push(rows[k])
  }

  let ref: OcrChar[] | null = null
  for (const row of window) {
    if (row.length === c) {
      ref = row
      break
    }
  }

  const picked: OcrChar[][] = []
  for (const row of window) {
    const sub = chooseAligned(row, ref, c)
    if (sub === null) {
      return null
    }
    picked.push(sub)
  }
  return picked
}

/** 在一行里挑出与参照行横向对齐最好的 c 个字；字数不足 c 返回 null */
function chooseAligned(row: OcrChar[], ref: OcrChar[] | null, c: number): OcrChar[] | null {
  if (row.length < c) {
    return null
  }
  if (row.length === c) {
    return row
  }
  if (ref === null) {
    return row.slice(0, c)
  }
  let bestOffset: number = 0
  let bestErr: number = Number.MAX_VALUE
  for (let o = 0; o + c <= row.length; o++) {
    let err: number = 0
    for (let j = 0; j < c; j++) {
      err += Math.abs(row[o + j].cx - ref[j].cx) / Math.max(ref[j].w, 1)
    }
    if (err < bestErr) {
      bestErr = err
      bestOffset = o
    }
  }
  return row.slice(bestOffset, bestOffset + c)
}

/**
 * 给候选字格打分
 *
 * 扣分项：
 *   - 列不对齐（align：每列横坐标相对偏差的平均值，按字宽归一化）
 *   - 行间距不均匀（字格里每行等高同距；若把菜单里的几行文字当成字格，这一项会飙高）
 * 分数 ≤ 0 视为「不像字格」，由调用方走退化路径。
 */
function scoreBlock(picked: OcrChar[][], c: number): BlockCandidate {
  const ref: OcrChar[] = picked[0]
  let err: number = 0
  for (const row of picked) {
    for (let j = 0; j < c; j++) {
      err += Math.abs(row[j].cx - ref[j].cx) / Math.max(row[j].w, 1)
    }
  }
  const align: number = err / (picked.length * c)
  if (align >= 0.35) {
    return new BlockCandidate(picked, c, -1000)
  }

  const pitchErr: number = rowPitchError(picked)
  const score: number = 100 - align * 120 - pitchErr * 40
  return new BlockCandidate(picked, c, score)
}

/** 行间距不均匀度：相邻行中心的间隔，各自与中位间隔之差的平均相对偏差（0 = 完全等距） */
function rowPitchError(rows: OcrChar[][]): number {
  if (rows.length < 3) {
    return 0
  }
  const centers: number[] = []
  for (const row of rows) {
    let sum: number = 0
    for (const ch of row) {
      sum += ch.cy
    }
    centers.push(sum / row.length)
  }
  const gaps: number[] = []
  for (let i = 1; i < centers.length; i++) {
    gaps.push(centers[i] - centers[i - 1])
  }
  const sortedGaps: number[] = gaps.slice()
  sortedGaps.sort((a: number, b: number) => a - b)
  const median: number = sortedGaps[Math.floor(sortedGaps.length / 2)]
  if (median <= 0) {
    return 1
  }
  let sum: number = 0
  for (const g of gaps) {
    sum += Math.abs(g - median) / median
  }
  return sum / gaps.length
}

// ==================== 第 3 步：退化处理 ====================

/**
 * 认不出规整字格时的兜底：取字数最多的一段连续行（最多 8 行）
 *
 * 打分偏向「总字数接近 30」：45 个字的段落按 30 取会混进无关文字，29 个字的字格反而更可信。
 */
function fallbackRows(rows: OcrChar[][]): OcrChar[][] | null {
  let best: OcrChar[][] | null = null
  let bestScore: number = -1

  for (let i = 0; i < rows.length; i++) {
    let total: number = 0
    const acc: OcrChar[][] = []
    for (let n = 1; n <= 8 && i + n <= rows.length; n++) {
      const row: OcrChar[] = rows[i + n - 1]
      if (row.length < 2) {
        break
      }
      acc.push(row)
      total += row.length
      const score: number = total - Math.abs(total - TARGET_CELLS) * 2
      if (score > bestScore) {
        bestScore = score
        best = acc.slice()
      }
    }
  }
  return best
}

// ==================== 收尾 ====================

function toExtraction(rows: OcrChar[][], cols: number, isGrid: boolean): GridExtraction {
  const out = new GridExtraction()
  out.isGrid = isGrid
  out.rowCount = rows.length
  let colMax: number = 0
  const flat: OcrChar[] = []
  for (const row of rows) {
    if (row.length > colMax) {
      colMax = row.length
    }
    for (const ch of row) {
      flat.push(ch)
      if (out.chars.length < TARGET_CELLS) {
        out.chars.push(ch.ch)
      }
    }
  }
  // 列数：优先用「字格形状」给的列数；退化路径下按横坐标聚类反推（能推成 5/6 列就当作格位）
  let colCount: number = cols
  if (colCount <= 0) {
    const centers: number[] = columnCenters(flat)
    colCount = (centers.length === 5 || centers.length === 6) ? centers.length : colMax
  }
  out.colCount = colCount
  out.cells = assignCells(rows, flat, colCount)
  return out
}

/**
 * 把每个字对到「行 × 列」格位上（行主序，长度 30；对不上时返回空数组）
 *
 * 列号靠横坐标聚类得到：同一列的字横坐标几乎相同，列间距约等于 2 个字宽。
 * 有格位之后，「某次少认一个字」就不会让后面的字全体错位 —— 多尺度合并靠这个。
 */
function assignCells(rows: OcrChar[][], flat: OcrChar[], cols: number): string[] {
  if (rows.length * cols !== TARGET_CELLS || cols < 4) {
    return []
  }
  const centers: number[] = columnCenters(flat)
  if (centers.length !== cols) {
    return []
  }
  const cells: string[] = new Array<string>(TARGET_CELLS).fill('')
  for (let r = 0; r < rows.length; r++) {
    for (const ch of rows[r]) {
      let bestIdx: number = 0
      let bestErr: number = Number.MAX_VALUE
      for (let i = 0; i < centers.length; i++) {
        const err: number = Math.abs(ch.cx - centers[i])
        if (err < bestErr) {
          bestErr = err
          bestIdx = i
        }
      }
      const slot: number = r * cols + bestIdx
      if (slot >= 0 && slot < TARGET_CELLS && cells[slot] === '') {
        cells[slot] = ch.ch
      }
    }
  }
  return cells
}

/** 横坐标聚类：相邻差小于 0.6 个字宽算同一列，返回各列的中心横坐标（升序） */
function columnCenters(chars: OcrChar[]): number[] {
  if (chars.length === 0) {
    return []
  }
  const widths: number[] = chars.map((c: OcrChar) => c.w)
  widths.sort((a: number, b: number) => a - b)
  const wMed: number = widths[Math.floor(widths.length / 2)]
  const tol: number = Math.max(wMed * 0.6, 1)
  const xs: number[] = chars.map((c: OcrChar) => c.cx)
  xs.sort((a: number, b: number) => a - b)
  const centers: number[] = []
  let sum: number = xs[0]
  let count: number = 1
  for (let i = 1; i < xs.length; i++) {
    if (xs[i] - xs[i - 1] <= tol) {
      sum += xs[i]
      count++
    } else {
      centers.push(sum / count)
      sum = xs[i]
      count = 1
    }
  }
  centers.push(sum / count)
  return centers
}
