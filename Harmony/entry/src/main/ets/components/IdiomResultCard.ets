import { IdiomItem } from '../model/IdiomItem'

/**
 * 成语检索结果卡片
 *
 * 布局：
 * ┌──────────────────────────────────────┐
 * │▌ 暗渡陈仓                            │
 * │  àn dù chén cāng                    │
 * │  声调：4 4 2 1                       │
 * └──────────────────────────────────────┘
 *
 * 左侧主色竖线用左描边实现（避免 height('100%') 撑高卡片导致上下留白）。
 * 被用户填写过的输入位置，其字 / 拼音 / 声调以绿色（match_highlight）整行标出。
 */

@Component
export struct IdiomResultCard {
  @Prop item: IdiomItem
  @Prop inputs: string[] = []  // 当前 4 个输入格内容，用于判断哪些位置被填写

  /** 第 i 个位置是否被用户填写（非空），是则整行标绿 */
  private isHighlighted(i: number): boolean {
    return (this.inputs[i] ?? '').trim() !== ''
  }

  build() {
    Row() {
      Column() {
        // 成语：逐字标色
        Row() {
          ForEach(this.item.chars, (ch: string, idx: number) => {
            Text(ch)
              .fontSize(20)
              .fontWeight(600)
              .fontColor(this.isHighlighted(idx) ? $r('app.color.match_highlight') : $r('app.color.text_primary'))
          }, (ch: string, idx: number) => idx.toString())
        }

        Blank(4)

        // 拼音：逐段标色
        Row() {
          ForEach(this.item.pinyin, (py: string, idx: number) => {
            Text(py)
              .fontSize(13)
              .fontWeight(400)
              .fontColor(this.isHighlighted(idx) ? $r('app.color.match_highlight') : $r('app.color.text_secondary'))
              .margin({ left: idx === 0 ? 0 : 6 })
          }, (py: string, idx: number) => idx.toString())
        }

        Blank(2)

        // 声调：逐项标色
        Row() {
          Text('声调：')
            .fontSize(12)
            .fontWeight(400)
            .fontColor($r('app.color.text_secondary'))
          ForEach(this.item.tones, (t: number, idx: number) => {
            Text(t.toString())
              .fontSize(12)
              .fontWeight(400)
              .fontColor(this.isHighlighted(idx) ? $r('app.color.match_highlight') : $r('app.color.text_secondary'))
              .margin({ left: idx === 0 ? 0 : 4 })
          }, (t: number, idx: number) => idx.toString())
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 12, top: 8, right: 12, bottom: 8 })
    .borderRadius(12)
    .backgroundColor($r('app.color.card_bg'))
    .border({ width: { left: 3 }, color: $r('app.color.primary') })
    .shadow({
      radius: 8,
      color: $r('app.color.card_shadow'),
      offsetX: 0,
      offsetY: 2
    })
    .accessibilityGroup(true)
    .accessibilityText(`${this.item.word}，拼音 ${this.item.pinyin.join(' ')}，声调 ${this.item.tones.join(' ')}`)
  }
}
