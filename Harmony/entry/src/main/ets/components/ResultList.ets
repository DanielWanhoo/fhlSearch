import { MatchResult } from '../model/PoetryItem'
import { ResultCard } from './ResultCard'

/**
 * 匹配结果列表
 *
 * 滚动列表显示所有匹配到的诗词句。
 * 无结果时显示空状态提示。
 */

@Component
export struct ResultList {
  @Link results: MatchResult[]

  build() {
    Column() {
      // 标题
      if (this.results.length > 0) {
        Row() {
          Text(`匹配结果 (${this.results.length})`)
            .fontSize(16)
            .fontWeight(500)
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')
        .margin({ bottom: 12 })
      }

      if (this.results.length === 0) {
        // 空状态
        Column() {
          Text('暂无匹配结果')
            .fontSize(16)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 20 })
          Text('请在表格中填满汉字后点击「开始检索」')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 8 })
        }
        .width('100%')
        .padding(24)
      } else {
        // 结果列表（卡片错峰入场：每张延迟 45ms 依次淡入上滑）
        Column() {
          ForEach(this.results, (result: MatchResult, idx: number) => {
            ResultCard({ result: result })
              .margin({ bottom: 12 })
              .transition(TransitionEffect.OPACITY
                .combine(TransitionEffect.translate({ y: 16 }))
                .animation({ duration: 250, curve: Curve.EaseOut, delay: idx * 45 }))
          }, (result: MatchResult) => result.id)
        }
        .width('100%')
      }
    }
    .width('100%')
  }
}
