import { MingziItem } from '../model/MingziItem'

/**
 * 名士检索结果卡片
 *
 * 以「名士（朝代）」格式展示，如「嬴政（秦）」。
 */

@Component
export struct MingziResultCard {
  @Prop item: MingziItem

  build() {
    Row() {
      Text(this.item.name)
        .fontSize(18)
        .fontWeight(600)
        .fontColor($r('app.color.text_primary'))
      Blank(8)
      Text(`（${this.item.dynasty}）`)
        .fontSize(15)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(14)
    .border({ width: 1, color: $r('app.color.cell_border'), style: BorderStyle.Solid })
    .shadow({ radius: 6, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 2 })
    .accessibilityGroup(true)
    .accessibilityText(`${this.item.name}（${this.item.dynasty}）`)
  }
}
