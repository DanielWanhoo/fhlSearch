/**
 * 成语数据模型 — 成语检索模块
 *
 * 对应成语题库（成语检索.xlsx）中一行数据，
 * 字段由 scripts/excel_to_idiom.py 生成。
 */

export class IdiomItem {
  /** 完整成语，如 "暗渡陈仓" */
  word: string = ''
  /** 4 个单字，如 ["暗","渡","陈","仓"] */
  chars: string[] = []
  /** 无音调拼音，如 ["an","du","chen","cang"]（ü 用 ü 表示） */
  plain: string[] = []
  /** 声调（1~4），如 [4,4,2,1] */
  tones: number[] = []
  /** 带声调拼音，如 ["àn","dù","chén","cāng"] */
  pinyin: string[] = []
}
