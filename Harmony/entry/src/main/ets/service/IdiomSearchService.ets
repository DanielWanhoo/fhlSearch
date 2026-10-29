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
 * 一次检索的全部条件（v3.2 起三组同时生效）
 *
 * 声调 / 拼音 / 单字三组输入互不排斥：同一位置可以只填其中一组、也可以三组都填，
 * 都填时要求三条同时成立；某个位置三组都留空则表示「这一位任意」。
 */
export class IdiomQuery {
  /** 四个字的声调（1~4），空串表示该位不限 */
  tones: string[] = ['', '', '', '']
  /** 四个字的拼音，空串表示该位不限 */
  pinyins: string[] = ['', '', '', '']
  /** 四个字本身，空串表示该位不限 */
  chars: string[] = ['', '', '', '']

  constructor(tones: string[], pinyins: string[], chars: string[]) {
    this.tones = tones
    this.pinyins = pinyins
    this.chars = chars
  }

  /** 12 个输入框是否全空 */
  get isEmpty(): boolean {
    return this.tones.every((v: string) => v.trim() === '') &&
      this.pinyins.every((v: string) => v.trim() === '') &&
      this.chars.every((v: string) => v.trim() === '')
  }

  /** 第 i 个字是否填了任意一组条件（结果卡据此高亮） */
  filledAt(i: number): boolean {
    return (this.tones[i] ?? '').trim() !== '' ||
      (this.pinyins[i] ?? '').trim() !== '' ||
      (this.chars[i] ?? '').trim() !== ''
  }
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
   * @param query 三组条件，留空当通配符
   * @returns 新的候选集
   */
  search(query: IdiomQuery): IdiomItem[] {
    const result = this.current.filter((item: IdiomItem) => this.matches(item, query))
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

  /**
   * 逐位置匹配：位置 i 的三组条件都为空则跳过（通配），
   * 否则同一位上的声调、拼音、单字必须同时成立。
   */
  private matches(item: IdiomItem, query: IdiomQuery): boolean {
    for (let i = 0; i < 4; i++) {
      const tone = (query.tones[i] ?? '').trim()
      if (tone !== '' && item.tones[i] !== Number(tone)) {
        return false
      }
      const pinyin = (query.pinyins[i] ?? '').trim()
      if (pinyin !== '' && !matchPinyin(item.plain[i], pinyin)) {
        return false
      }
      const ch = (query.chars[i] ?? '').trim()
      if (ch !== '' && item.chars[i] !== ch) {
        return false
      }
    }
    return true
  }
}
