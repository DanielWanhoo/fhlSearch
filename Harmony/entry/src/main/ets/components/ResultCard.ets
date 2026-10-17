import { MatchResult } from '../model/PoetryItem'

/**
 * 单条匹配结果卡片
 *
 * 布局：
 * ┌──────────────────────────────────────┐
 * │ ▌ 床前明月光                         │
 * │   李白 · 静夜思                      │
 * └──────────────────────────────────────┘
 *
 * 左侧绿色竖线表示匹配标记
 */

@Component
export struct ResultCard {
  @Prop result: MatchResult

  build() {
    Row() {
      // 左侧绿色标记线
      Column()
        .width(3)
        .height('100%')
        .backgroundColor($r('app.color.match_highlight'))
        .borderRadius(2)

      // 文字区域
      Column() {
        // 诗词句原文
        Text(this.result.poetry.line)
          .fontSize(20)
          .fontWeight(600)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Blank(3)

        // 作者 + 篇名
        Text(`${this.result.poetry.author} · ${this.result.poetry.title}`)
          .fontSize(13)
          .fontWeight(400)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('app.color.card_bg'))
    .shadow({
      radius: 8,
      color: $r('app.color.card_shadow'),
      offsetX: 0,
      offsetY: 2
    })
    .accessibilityGroup(true)
    .accessibilityText(`${this.result.poetry.line}，${this.result.poetry.author}，${this.result.poetry.title}`)
  }
}
