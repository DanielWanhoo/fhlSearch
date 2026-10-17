import { IdiomItem } from '../model/IdiomItem'

/**
 * 成语检索 — 三种检索模式
 */
export enum IdiomSearchMode {
  /** 无声调拼音：匹配无音调拼音（如 an du chen cang） */
  PINYIN = 'pinyin',
  /** 单字声调：匹配声调（如 4 4 2 1） */
  TONE = 'tone',
  /** 单字搜索：匹配汉字（如 暗 渡 陈 仓） */
  CHAR = 'char'
}

/**
 * 拼音归一化：转小写、去空格、ü 统一转 v（与输入做等价比较）。
 * 例："Lǚ" → "lv"、"lü" → "lv"、"lv" → "lv"，三者可互相匹配。
 */
function normalizePinyin(s: string): string {
  let out = ''
  for (let i = 0; i < s.length; i++) {
    const ch = s.charAt(i)
    if (ch === 'ü' || ch === 'Ü') {
      out += 'v'
    } else if (ch !== ' ' && ch !== '\t') {
      out += ch.toLowerCase()
    }
  }
  return out
}

/** 拼音声母（23 个）：输入命中则按「前缀」模糊匹配 */
const PINYIN_INITIALS: string[] = [
  'b', 'p', 'm', 'f', 'd', 't', 'n', 'l', 'g', 'k', 'h',
  'j', 'q', 'x', 'zh', 'ch', 'sh', 'r', 'z', 'c', 's', 'y', 'w'
]

/** 拼音韵母（36 个，ü 归一化为 v）：输入命中则按「后缀」模糊匹配 */
const PINYIN_FINALS: string[] = [
  'a', 'o', 'e', 'i', 'u', 'v', 'er',
  'ai', 'ei', 'ao', 'ou', 'ia', 'ie', 'iao', 'iu', 'ua', 'uo', 'uai', 'ui', 've',
  'an', 'en', 'in', 'un', 'vn', 'ian', 'uan', 'van',
  'ang', 'eng', 'ing', 'ong', 'iang', 'uang', 'ueng', 'iong'
]

/**
 * 拼音单格匹配：完整音节精确匹配；单个声母按前缀、单个韵母按后缀模糊匹配。
 * 两侧先归一化（转小写、去空格、ü↔v）。
 */
function matchPinyin(plain: string, input: string): boolean {
  const p = normalizePinyin(plain)
  const q = normalizePinyin(input)
  if (PINYIN_INITIALS.indexOf(q) !== -1) {
    return p.startsWith(q)
  }
  if (PINYIN_FINALS.indexOf(q) !== -1) {
    return p.endsWith(q)
  }
  return p === q
}

/**
 * 成语检索服务 — 维护「候选集 + 历史栈」。
 *
 * - 第 0 级候选集 = 完整题库
 * - 每次检索：在当前候选集内按模式逐位置匹配（留空当通配），命中集合压栈
 * - 清空当前检索 = 弹栈回到上一级
 * - 清空所有检索 = 清栈回到第 0 级
 */
export class IdiomSearchService {
  private db: IdiomItem[]
  private stack: IdiomItem[][] = []

  constructor(db: IdiomItem[]) {
    this.db = db
    this.stack = [db]
  }

  /** 当前候选集（栈顶） */
  get current(): IdiomItem[] {
    return this.stack[this.stack.length - 1]
  }

  /** 已进行的检索次数（栈深） */
  get depth(): number {
    return this.stack.length - 1
  }

  /** 清空所有检索：回到第 0 级（完整题库） */
  reset(): void {
    this.stack = [this.db]
  }

  /**
   * 执行一次检索（含二次检索）。
   * @param mode 检索模式
   * @param inputs 4 个输入，留空当通配符
   * @returns 新的候选集
   */
  search(mode: IdiomSearchMode, inputs: string[]): IdiomItem[] {
    const result = this.current.filter((item: IdiomItem) => this.matches(item, mode, inputs))
    this.stack.push(result)
    return result
  }

  /**
   * 清空当前检索：弹栈，回到上一级候选集。
   * @returns 回退后的候选集
   */
  undo(): IdiomItem[] {
    if (this.stack.length > 1) {
      this.stack.pop()
    }
    return this.current
  }

  /** 逐位置匹配：位置 i 为空则跳过（通配），非空则按模式精确匹配 */
  private matches(item: IdiomItem, mode: IdiomSearchMode, inputs: string[]): boolean {
    for (let i = 0; i < 4; i++) {
      const input = inputs[i] ?? ''
      if (input.trim() === '') {
        continue
      }
      if (mode === IdiomSearchMode.PINYIN) {
        if (!matchPinyin(item.plain[i], input)) {
          return false
        }
      } else if (mode === IdiomSearchMode.TONE) {
        if (item.tones[i] !== Number(input.trim())) {
          return false
        }
      } else {
        if (item.chars[i] !== input.trim()) {
          return false
        }
      }
    }
    return true
  }
}
