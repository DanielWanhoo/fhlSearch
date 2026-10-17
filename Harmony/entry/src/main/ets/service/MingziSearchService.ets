import { MingziItem } from '../model/MingziItem'

/**
 * 名士检索模式 — 共 9 种
 * - 菜单模式（选项固定）：朝代 / 爱好 / 社团 / 品阶
 * - 输入模式（对话框输入，模糊匹配）：职业 / 生逢 / 出身·身世 / 技能 / 其他描述
 */
export enum MingziSearchMode {
  /** 朝代（菜单）：汉 明 秦 三国 宋 唐 五代十国 西楚 晋 先秦 梦 南北朝 清 元 辽 */
  DYNASTY = 'dynasty',
  /** 爱好（菜单）：博文 乐舞 品茗 赏玩 食珍 书画 雅宴 演武 弈棋 妆饰 */
  HOBBY = 'hobby',
  /** 社团（菜单）：百家书院 千工苑 金戈馆 容华社 棠梨坊 饕餮居 五湖商社 逸趣社 无 */
  GROUP = 'group',
  /** 品阶（菜单）：天 地 玄 */
  RANK = 'rank',
  /** 职业（输入·模糊） */
  OCCUPATION = 'occupation',
  /** 生逢·生于...（输入·模糊） */
  BORN = 'born',
  /** 出身/身世（输入·模糊） */
  ORIGIN = 'origin',
  /** 技能（输入·模糊） */
  SKILL = 'skill',
  /** 其他描述（输入·模糊，检索描述1~15列） */
  DESC = 'desc'
}

/**
 * 汉字归一化：仅保留汉字（0x4E00~0x9FFF），
 * 忽略标点符号、空格及其他非汉字字符。
 * 例："出生于 乱世。" → "出生于乱世"
 */
function normalizeHan(s: string): string {
  let out = ''
  for (let i = 0; i < s.length; i++) {
    const code = s.charCodeAt(i)
    if (code >= 0x4E00 && code <= 0x9FFF) {
      out += s.charAt(i)
    }
  }
  return out
}

/**
 * 模糊匹配：检索词作为整体（不拆分），
 * 归一化后目标文本包含检索词即为命中。
 */
function fuzzyMatch(text: string, query: string): boolean {
  const t = normalizeHan(text)
  const q = normalizeHan(query)
  if (q.length === 0) {
    return false
  }
  return t.indexOf(q) !== -1
}

/**
 * 名士检索服务 — 维护「候选集 + 历史栈」。
 *
 * - 第 0 级候选集 = 完整题库
 * - 每次检索：在当前候选集内按模式过滤，命中集合压栈（二次检索天然成立）
 * - 返回上一级检索 = 弹栈回到上一级候选集
 * - 清空所有检索 = 清栈回到第 0 级
 */
export class MingziSearchService {
  private db: MingziItem[]
  private stack: MingziItem[][] = []

  constructor(db: MingziItem[]) {
    this.db = db
    this.stack = [db]
  }

  /** 当前候选集（栈顶） */
  get current(): MingziItem[] {
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
   * @param query 菜单选项 / 输入关键词
   * @returns 新的候选集
   */
  search(mode: MingziSearchMode, query: string): MingziItem[] {
    const result = this.current.filter((item: MingziItem) => this.matches(item, mode, query))
    this.stack.push(result)
    return result
  }

  /**
   * 返回上一级检索：弹栈，回到上一级候选集。
   * @returns 回退后的候选集
   */
  undo(): MingziItem[] {
    if (this.stack.length > 1) {
      this.stack.pop()
    }
    return this.current
  }

  /** 按模式匹配单条名士 */
  private matches(item: MingziItem, mode: MingziSearchMode, query: string): boolean {
    switch (mode) {
      case MingziSearchMode.DYNASTY:
        return item.dynasty === query
      case MingziSearchMode.HOBBY:
        return item.hobbies.indexOf(query) !== -1
      case MingziSearchMode.GROUP:
        return item.groups.indexOf(query) !== -1
      case MingziSearchMode.RANK:
        return item.rank === query
      case MingziSearchMode.OCCUPATION:
        return fuzzyMatch(item.occupation, query)
      case MingziSearchMode.BORN:
        return fuzzyMatch(item.born, query)
      case MingziSearchMode.ORIGIN:
        return fuzzyMatch(item.origin, query)
      case MingziSearchMode.SKILL:
        return fuzzyMatch(item.skill, query)
      case MingziSearchMode.DESC:
        for (const d of item.descriptions) {
          if (fuzzyMatch(d, query)) {
            return true
          }
        }
        return false
      default:
        return false
    }
  }
}
