import { Haptics } from '../common/Haptics'
import { AppInfoDialog } from './AppInfoDialog'

/**
 * 「信息」圆形玻璃图标按钮 — 三个检索页大标题右侧共用
 *
 * 外观：与名士详情弹窗的关闭按钮同一套「沉浸光感」语言
 * （圆角正方的玻璃底 + 系统材质模糊 + 整圈 1vp 发丝描边），尺码 32×32（vp）。
 * 配色用「卡片上的玻璃」（glass_card_bg / glass_card_edge）：页面底色与卡片都偏浅，
 * 白玻璃叠上去几乎看不见，故浅色主题改用暖墨半透明。
 *
 * 交互：按下 120ms 收缩到 0.9 + 一下轻触震动，抬起弹簧回弹；点击打开「信息」对话框。
 * 用法：在页面 Header 的标题行右侧放 `InfoButton()` 即可。
 */
@Component
export struct InfoButton {
  @State pressed: boolean = false
  private dialogCtrl: CustomDialogController = new CustomDialogController({
    builder: AppInfoDialog(),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: true
  })

  build() {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph($r('sys.symbol.info_circle'))
        .fontSize(17)
        .fontColor([$r('app.color.text_secondary')])
    }
    .width(32)
    .height(32)
    .borderRadius(16)
    .backgroundColor($r('app.color.glass_card_bg'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK, {
      colorMode: ThemeColorMode.SYSTEM,
      adaptiveColor: AdaptiveColor.AVERAGE
    })
    .border({ width: 1, color: $r('app.color.glass_card_edge'), style: BorderStyle.Solid })
    .scale({ x: this.pressed ? 0.9 : 1, y: this.pressed ? 0.9 : 1 })
    .animation({ duration: 120, curve: Curve.FastOutSlowIn })
    .accessibilityText('信息')
    .accessibilityDescription('查看应用信息与使用方法')
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        Haptics.tick()
        this.pressed = true
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressed = false
      }
    })
    .onClick(() => {
      this.dialogCtrl.open()
    })
  }
}
