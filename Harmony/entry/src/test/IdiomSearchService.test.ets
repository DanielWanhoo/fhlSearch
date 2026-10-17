import { describe, beforeEach, it, expect } from '@ohos/hypium'
import { IdiomSearchService, IdiomSearchMode } from '../main/ets/service/IdiomSearchService'
import { IdiomItem } from '../main/ets/model/IdiomItem'
import { IDIOM_DB } from '../main/ets/data/idiom_db'

/**
 * 构建测试用小题库（3 条，字段手工可控）
 */
function buildTestDb(): IdiomItem[] {
  return [
    {
      word: "暗渡陈仓",
      chars: ["暗", "渡", "陈", "仓"],
      plain: ["an", "du", "chen", "cang"],
      tones: [4, 4, 2, 1],
      pinyin: ["àn", "dù", "chén", "cāng"]
    },
    {
      word: "如履薄冰",
      chars: ["如", "履", "薄", "冰"],
      plain: ["ru", "lü", "bo", "bing"],
      tones: [2, 3, 2, 1],
      pinyin: ["rú", "lǚ", "bó", "bīng"]
    },
    {
      word: "灯红酒绿",
      chars: ["灯", "红", "酒", "绿"],
      plain: ["deng", "hong", "jiu", "lü"],
      tones: [1, 2, 3, 4],
      pinyin: ["dēng", "hóng", "jiǔ", "lǜ"]
    }
  ]
}

export default function idiomSearchServiceTest() {
  describe('IdiomSearchService', () => {
    let svc: IdiomSearchService

    beforeEach(() => {
      svc = new IdiomSearchService(buildTestDb())
    })

    // ==================== 三模式：完全匹配 ====================

    it('拼音模式_完全匹配', 0, () => {
      const r = svc.search(IdiomSearchMode.PINYIN, ["an", "du", "chen", "cang"])
      expect(r.length).assertEqual(1)
      expect(r[0].word).assertEqual('暗渡陈仓')
    })

    it('声调模式_完全匹配', 0, () => {
      const r = svc.search(IdiomSearchMode.TONE, ["4", "4", "2", "1"])
      expect(r.length).assertEqual(1)
      expect(r[0].word).assertEqual('暗渡陈仓')
    })

    it('单字模式_完全匹配', 0, () => {
      const r = svc.search(IdiomSearchMode.CHAR, ["暗", "渡", "陈", "仓"])
      expect(r.length).assertEqual(1)
      expect(r[0].word).assertEqual('暗渡陈仓')
    })

    // ==================== 留空通配 ====================

    it('拼音模式_留空通配', 0, () => {
      // 第 2 字拼音为 du → 只有暗渡陈仓
      const r = svc.search(IdiomSearchMode.PINYIN, ["", "du", "", ""])
      expect(r.length).assertEqual(1)
      expect(r[0].word).assertEqual('暗渡陈仓')
    })

    it('声调模式_留空通配', 0, () => {
      // 第 2 字声调为 3 → 只有如履薄冰
      const r = svc.search(IdiomSearchMode.TONE, ["", "3", "", ""])
      expect(r.length).assertEqual(1)
      expect(r[0].word).assertEqual('如履薄冰')
    })

    it('单字模式_留空通配', 0, () => {
      // 第 1 字为「暗」→ 只有暗渡陈仓
      const r = svc.search(IdiomSearchMode.CHAR, ["暗", "", "", ""])
      expect(r.length).assertEqual(1)
      expect(r[0].word).assertEqual('暗渡陈仓')
    })

    it('全部留空_返回完整候选集', 0, () => {
      const r = svc.search(IdiomSearchMode.PINYIN, ["", "", "", ""])
      expect(r.length).assertEqual(3)
    })

    // ==================== 拼音归一化（v ↔ ü、大小写、空格） ====================

    it('拼音归一化_v和ü等价', 0, () => {
      // 数据里存 ü，输入 v → 应命中
      let r = svc.search(IdiomSearchMode.PINYIN, ["ru", "lv", "bo", "bing"])
      expect(r.length).assertEqual(1)
      expect(r[0].word).assertEqual('如履薄冰')
    })

    it('拼音归一化_输入ü也能命中', 0, () => {
      let r = svc.search(IdiomSearchMode.PINYIN, ["ru", "lü", "bo", "bing"])
      expect(r.length).assertEqual(1)
      expect(r[0].word).assertEqual('如履薄冰')
    })

    it('拼音归一化_大写与空格', 0, () => {
      let r = svc.search(IdiomSearchMode.PINYIN, ["An", "DU ", " Chen", " cang"])
      expect(r.length).assertEqual(1)
      expect(r[0].word).assertEqual('暗渡陈仓')
    })

    // ==================== 拼音模糊检索（声母 / 韵母） ====================

    it('拼音模糊_单个声母前缀匹配', 0, () => {
      // 第 1 字声母 d → 灯红酒绿（deng）；暗渡陈仓首字 an、如履薄冰首字 ru 均不以 d 开头
      const r = svc.search(IdiomSearchMode.PINYIN, ["d", "", "", ""])
      expect(r.length).assertEqual(1)
      expect(r[0].word).assertEqual('灯红酒绿')
    })

    it('拼音模糊_韵母ang后缀匹配', 0, () => {
      // 第 4 字韵母 ang → 暗渡陈仓（cang）
      const r = svc.search(IdiomSearchMode.PINYIN, ["", "", "", "ang"])
      expect(r.length).assertEqual(1)
      expect(r[0].word).assertEqual('暗渡陈仓')
    })

    it('拼音模糊_韵母ing后缀匹配', 0, () => {
      // 第 4 字韵母 ing → 如履薄冰（bing）
      const r = svc.search(IdiomSearchMode.PINYIN, ["", "", "", "ing"])
      expect(r.length).assertEqual(1)
      expect(r[0].word).assertEqual('如履薄冰')
    })

    it('拼音模糊_完整音节仍精确匹配', 0, () => {
      // chen 既非声母也非韵母，应精确匹配，不误中 cheng
      const r = svc.search(IdiomSearchMode.PINYIN, ["", "", "chen", ""])
      expect(r.length).assertEqual(1)
      expect(r[0].word).assertEqual('暗渡陈仓')
    })

    it('拼音模糊_ü韵母归一化', 0, () => {
      // 第 4 字韵母 ü（输入 v）→ 灯红酒绿（lü）
      const r = svc.search(IdiomSearchMode.PINYIN, ["", "", "", "v"])
      expect(r.length).assertEqual(1)
      expect(r[0].word).assertEqual('灯红酒绿')
    })

    it('拼音模糊_声母与韵母混合', 0, () => {
      // 第 1 字声母 c + 第 3 字精确 chen + 第 4 字韵母 ang → 暗渡陈仓
      const r = svc.search(IdiomSearchMode.PINYIN, ["c", "", "chen", "ang"])
      expect(r.length).assertEqual(1)
      expect(r[0].word).assertEqual('暗渡陈仓')
    })

    // ==================== 结果三分支：0 / 1 / 多个 ====================

    it('无结果', 0, () => {
      const r = svc.search(IdiomSearchMode.PINYIN, ["zz", "zz", "zz", "zz"])
      expect(r.length).assertEqual(0)
    })

    it('多结果', 0, () => {
      // 第 3 字声调为 2 → 暗渡陈仓、如履薄冰（灯红酒绿第3字声调为3）
      const r = svc.search(IdiomSearchMode.TONE, ["", "", "2", ""])
      expect(r.length).assertEqual(2)
    })

    // ==================== 二次检索 + 历史栈回溯 ====================

    it('二次检索_逐步缩小范围', 0, () => {
      // 第一次：第 3 字声调 2 → 2 条（暗渡陈仓、如履薄冰）
      svc.search(IdiomSearchMode.TONE, ["", "", "2", ""])
      expect(svc.depth).assertEqual(1)

      // 第二次：第 3 字为「陈」→ 只剩暗渡陈仓
      const r = svc.search(IdiomSearchMode.CHAR, ["", "", "陈", ""])
      expect(r.length).assertEqual(1)
      expect(r[0].word).assertEqual('暗渡陈仓')
      expect(svc.depth).assertEqual(2)
    })

    it('清空当前检索_弹栈回上一级', 0, () => {
      svc.search(IdiomSearchMode.TONE, ["", "", "2", ""])
      svc.search(IdiomSearchMode.CHAR, ["", "", "陈", ""])
      expect(svc.depth).assertEqual(2)

      const r = svc.undo()
      expect(svc.depth).assertEqual(1)
      expect(r.length).assertEqual(2) // 回到上一级（2 条）
    })

    it('清空所有检索_回到完整题库', 0, () => {
      svc.search(IdiomSearchMode.TONE, ["", "", "2", ""])
      svc.search(IdiomSearchMode.CHAR, ["", "", "陈", ""])
      expect(svc.depth).assertEqual(2)

      const r = svc.reset()
      expect(svc.depth).assertEqual(0)
      expect(r.length).assertEqual(3) // 完整题库 3 条
    })

    it('多次清空当前_不会清到空', 0, () => {
      svc.search(IdiomSearchMode.PINYIN, ["an", "", "", ""])
      svc.undo()
      svc.undo()
      svc.undo() // 栈底保护
      expect(svc.depth).assertEqual(0)
      expect(svc.current.length).assertEqual(3)
    })

    // ==================== 集成测试：真实题库 + 数据链路 ====================

    it('集成_真实题库拼音检索命中暗渡陈仓', 0, () => {
      const s = new IdiomSearchService(IDIOM_DB)
      const r = s.search(IdiomSearchMode.PINYIN, ["an", "du", "chen", "cang"])
      expect(r.length).assertEqual(1)
      expect(r[0].word).assertEqual('暗渡陈仓')
      // 带声调拼音由脚本推导正确
      expect(r[0].pinyin[0]).assertEqual('àn')
      expect(r[0].pinyin[2]).assertEqual('chén')
    })

    it('集成_真实题库声调检索', 0, () => {
      const s = new IdiomSearchService(IDIOM_DB)
      const r = s.search(IdiomSearchMode.TONE, ["4", "4", "2", "1"])
      // 至少命中暗渡陈仓（可能还有其他同声调成语）
      expect(r.length).assertLarger(0)
      const found = r.some((item: IdiomItem) => item.word === '暗渡陈仓')
      expect(found).assertTrue()
    })

    it('集成_真实题库单字检索', 0, () => {
      const s = new IdiomSearchService(IDIOM_DB)
      const r = s.search(IdiomSearchMode.CHAR, ["暗", "渡", "陈", "仓"])
      expect(r.length).assertEqual(1)
      expect(r[0].word).assertEqual('暗渡陈仓')
    })

  })
}
