import { MatchResult } from '../model/PoetryItem'
import { ResultCard } from './ResultCard'
import { EASE_OUT_STRONG, MOTION_BASE_MS, isReducedMotion, staggerDelay } from '../common/Motion'
import { ENTER_ALL_SHOWN, ENTER_OFFSET_X } from '../common/PageEnter'

/**
 * 匹配结果列表
 *
 * 滚动列表显示所有匹配到的诗词句。
 * 无结果时显示空状态提示。
 *
 * 切页进场（平板双栏右栏）：标题算第 0 项、卡片依次往后，各页把它交给外壳的
 * 「右栏错峰」那组序号统一驱动（enterShown / enterDir）；手机单栏整块处理，
 * 传默认值 999 时什么也不做。
 */

@Component
export struct ResultList {
  @Link results: MatchResult[]
  @Prop enterShown: number = ENTER_ALL_SHOWN  // 右栏已放出的项数（999 = 直接可见）
  @Prop enterSlots: number = 6                // 右栏参与错峰的项数：标题 + 前 5 张卡片
  @Prop enterDir: number = 1                  // 进场方向：+1 从右侧弹入，-1 从左侧弹入

  private shownAt(slot: number): boolean {
    return this.enterShown > Math.min(slot, this.enterSlots - 1)
  }

  private opacityAt(slot: number): number {
    return this.shownAt(slot) ? 1 : 0
  }

  private shiftAt(slot: number): number {
    return this.shownAt(slot) ? 0 : ENTER_OFFSET_X * this.enterDir
  }

  /**
   * 卡片进场：默认淡入 + 上滑 16vp；减弱动效时只留不透明度，不做位移
   */
  private cardTransition(): TransitionEffect {
    if (isReducedMotion()) {
      return TransitionEffect.OPACITY
    }
    return TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: 16 }))
  }

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
        .opacity(this.opacityAt(0))
        .translate({ x: this.shiftAt(0) })
      }

      if (this.results.length === 0) {
        // 空状态
        Column() {
          Text('暂无匹配结果')
            .fontSize(16)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 20 })
            .opacity(this.opacityAt(0))
            .translate({ x: this.shiftAt(0) })
          Text('请在表格中填满汉字后点击「开始检索」')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 8 })
            .opacity(this.opacityAt(1))
            .translate({ x: this.shiftAt(1) })
        }
        .width('100%')
        .padding(24)
      } else {
        // 结果列表（卡片错峰入场：每张延迟 25ms 依次淡入上滑，最多错 6 档）
        Column() {
          ForEach(this.results, (result: MatchResult, idx: number) => {
            ResultCard({ result: result })
              .margin({ bottom: 12 })
              .opacity(this.opacityAt(1 + idx))
              .translate({ x: this.shiftAt(1 + idx) })
              .transition(this.cardTransition()
                .animation({ duration: MOTION_BASE_MS, curve: EASE_OUT_STRONG, delay: staggerDelay(idx) }))
          }, (result: MatchResult) => result.id)
        }
        .width('100%')
      }
    }
    .width('100%')
  }
}
