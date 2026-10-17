/**
 * 名士数据模型 — 名士检索模块
 *
 * 对应名士题库（众里寻他.xlsx）中一条名士记录，
 * 字段由 scripts/excel_to_mingzi.py 生成。
 */

export class MingziItem {
  /** 名士姓名，如 "嬴政" */
  name: string = ''
  /** 朝代（已规范化，如 "五代十国"） */
  dynasty: string = ''
  /** 爱好列表，如 ["演武", "赏玩"]（奕棋已规范为弈棋） */
  hobbies: string[] = []
  /** 社团列表，如 ["金戈馆", "百家书院"] */
  groups: string[] = []
  /** 品阶：天 / 地 / 玄 */
  rank: string = ''
  /** 职业，如 "帝王" */
  occupation: string = ''
  /** 生逢（生于...），如 "乱世" */
  born: string = ''
  /** 出身/身世，如 "出身显贵" */
  origin: string = ''
  /** 技能，如 "剑舞者" */
  skill: string = ''
  /** 其他描述（描述1~15），如 ["求仙问道", ...] */
  descriptions: string[] = []
  /** 各条描述对应的表格列号（描述1~15），与 descriptions 一一对应，如 [1, 3, 4] */
  descIndexes: number[] = []
}
