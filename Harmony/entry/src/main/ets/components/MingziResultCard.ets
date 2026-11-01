import { MingziItem } from '../model/MingziItem'

/**
 * 名士检索结果卡片
 *
 * 以「名士（朝代）」格式展示，如「嬴政（秦）」。
 */

@Component
export struct MingziResultCard {
  @Prop item: MingziItem
  /** 元素 id：详情弹窗会用它量出这张卡片的真实矩形，形变的起点就是卡片所在位置 */
  @Prop morphId: string = ''

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
    .padding({ left: 18, right: 18, top: 16, bottom: 16 })
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(18)
    .border({ width: 1, color: $r('app.color.cell_border'), style: BorderStyle.Solid })
    .shadow({ radius: 12, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 4 })
    // 详情弹窗按这个 id 量到卡片的真实矩形，形变的起点就是卡片所在位置
    .id(this.morphId)
    .accessibilityGroup(true)
    .accessibilityText(`${this.item.name}（${this.item.dynasty}）`)
  }
}
