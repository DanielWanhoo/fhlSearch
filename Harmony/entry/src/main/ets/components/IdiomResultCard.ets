import { IdiomItem } from '../model/IdiomItem'

/**
 * 成语检索结果卡片
 *
 * 布局（v3.2.2：每个字一列、整排靠左，自上而下 = 声调 → 拼音 → 汉字）：
 * ┌──────────────────────────────────────┐
 * │▌(4)  (4)   (2)   (1)                 │
 * │ àn   dù    chén  cāng                │
 * │ 暗   渡    陈    仓                  │
 * └──────────────────────────────────────┘
 *
 * 左侧主色竖线用左描边实现（避免 height('100%') 撑高卡片导致上下留白）。
 * 声调用 cell_bg 底色的小方块标出。被用户填写过的条件（单字 / 拼音 / 声调）在对应位置标绿：
 * 只填了拼音的那一格，只有那一列的拼音变绿，字与声调仍是常规色。
 */

@Component
export struct IdiomResultCard {
  @Prop item: IdiomItem
  // 三组输入格内容（v3.2 起声调 / 拼音 / 单字同时可填），逐行判断哪些位置被填写
  @Prop toneInputs: string[] = []
  @Prop pinyinInputs: string[] = []
  @Prop charInputs: string[] = []

  private static filled(list: string[], i: number): boolean {
    return (list[i] ?? '').trim() !== ''
  }

  /** 该字是否被「单字」条件命中 */
  private charFilled(i: number): boolean {
    return IdiomResultCard.filled(this.charInputs, i)
  }

  /** 该字是否被「拼音」条件命中 */
  private pinyinFilled(i: number): boolean {
    return IdiomResultCard.filled(this.pinyinInputs, i)
  }

  /** 该字是否被「声调」条件命中 */
  private toneFilled(i: number): boolean {
    return IdiomResultCard.filled(this.toneInputs, i)
  }

  build() {
    // 每个字一列、整排靠左；列宽跟着内容走（不再均分宽度，避免字与字之间留一大片空白）
    Row({ space: 8 }) {
      ForEach(this.item.chars, (ch: string, idx: number) => {
        Column() {
          // ① 声调
          Text((this.item.tones[idx] ?? 0).toString())
            .fontSize(10)
            .fontWeight(500)
            .height(15)
            .width(18)
            .textAlign(TextAlign.Center)
            .borderRadius(4)
            .backgroundColor($r('app.color.cell_bg'))
            .fontColor(this.toneFilled(idx) ? $r('app.color.match_highlight') : $r('app.color.text_secondary'))

          // ② 拼音
          Text(this.item.pinyin[idx] ?? '')
            .fontSize(12)
            .fontWeight(400)
            .height(17)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor(this.pinyinFilled(idx) ? $r('app.color.match_highlight') : $r('app.color.text_secondary'))

          // ③ 汉字
          Text(ch)
            .fontSize(20)
            .fontWeight(600)
            .height(28)
            .fontColor(this.charFilled(idx) ? $r('app.color.match_highlight') : $r('app.color.text_primary'))
        }
        .alignItems(HorizontalAlign.Center)
      }, (ch: string, idx: number) => idx.toString())
    }
    .justifyContent(FlexAlign.Start)
    .alignItems(VerticalAlign.Top)
    .width('100%')
    .padding({ left: 14, top: 12, right: 14, bottom: 12 })
    .borderRadius(18)
    .backgroundColor($r('app.color.card_bg'))
    // 左侧主色竖线（3vp）：结果卡与「当前检索方向」的视觉连接，保留
    .border({ width: { left: 3 }, color: $r('app.color.primary') })
    .shadow({
      radius: 14,
      color: $r('app.color.card_shadow'),
      offsetX: 0,
      offsetY: 4
    })
    .accessibilityGroup(true)
    .accessibilityText(`${this.item.word}，拼音 ${this.item.pinyin.join(' ')}，声调 ${this.item.tones.join(' ')}`)
  }
}
