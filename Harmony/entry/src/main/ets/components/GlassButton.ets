import { curves } from '@kit.ArkUI'
import { Haptics } from '../common/Haptics'

/**
 * 「沉浸光感」玻璃按钮（三个检索页共用的自定义组件）
 *
 * 材质：与悬浮页签栏同一套系统语言，且**光感均匀分布**
 * - 通体等厚：`backgroundBlurStyle(COMPONENT_ULTRA_THICK)` 系统材质模糊 + 一层均匀半透明底
 *   （`glass_bg` 中性 / `glass_primary` 主色），**不做半截高度的高光色带**（避免上亮下暗的断层）
 * - 边缘提亮：整圈 1vp 发丝描边（`glass_edge` / `glass_primary_edge`），四边等宽等亮
 * - 柔和外发光：四周均匀扩散（offsetY 仅 2）
 *
 * 交互反馈（避免「按下瞬间生硬跳变」）：
 * - 按下：先触发一次轻触**震动反馈**（`Haptics.tick()`，系统柔和触感），随后 120ms 快速收缩到 0.94，
 *   同时内层高光淡入、投影收紧（“压进玻璃”的手感）；无马达的设备自动静默（如平板）
 * - 抬起：弹簧曲线回弹（`curves.springMotion(0.34, 0.66)` 略微过冲后归位），高光柔和淡出
 * - 组件内部维护按压状态并驱动动画，调用方无需关心
 *
 * 用法：`GlassButton({ label: '清空所有', primary: false, desc: '无障碍描述', action: () => { ... } })`
 * 注意：`layoutWeight(1)` 已内置（按钮在 Row 中等分槽位）；需要限宽时由调用方套一层带
 * `constraintSize` 的 Row。
 */
@Component
export struct GlassButton {
  @Prop label: string
  @Prop primary: boolean
  @Prop desc: string
  // 点击回调（由调用方传入；普通成员，避免 @Prop 不能承载函数类型）
  action: () => void = () => {}
  @State pressed: boolean = false      // 按压中：驱动缩放与投影
  @State highlight: number = 0         // 按压高光层不透明度（0~1）

  private onTouchEvent(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      // 按下：先给一下轻触震动（触觉先于视觉，按压更「实」）
      Haptics.tick()
      // 快速收缩 + 高光浮起
      this.getUIContext().animateTo({ duration: 120, curve: Curve.FastOutSlowIn }, () => {
        this.pressed = true
        this.highlight = 1
      })
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      // 抬起：弹簧回弹（略微过冲再归位）+ 高光柔和淡出
      this.getUIContext().animateTo({ duration: 400, curve: curves.springMotion(0.34, 0.66) }, () => {
        this.pressed = false
        this.highlight = 0
      })
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 按压高光层：内层均匀提亮（与整块材质同形，不产生局部亮斑）
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(21)
        .backgroundColor($r('app.color.glass_press'))
        .opacity(this.highlight)

      Text(this.label)
        .fontSize(14)
        .fontWeight(this.primary ? 600 : 500)
        .fontColor(this.primary ? $r('app.color.on_primary') : $r('app.color.text_primary'))
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 6, right: 6 })
    }
    .layoutWeight(1)
    .height(42)
    .borderRadius(21)
    .backgroundColor(this.primary ? $r('app.color.glass_primary') : $r('app.color.glass_bg'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK, {
      colorMode: ThemeColorMode.SYSTEM,
      adaptiveColor: AdaptiveColor.AVERAGE
    })
    .border({
      width: 1,
      color: this.primary ? $r('app.color.glass_primary_edge') : $r('app.color.glass_edge'),
      style: BorderStyle.Solid
    })
    .shadow({
      radius: this.pressed ? 6 : 10,
      color: this.primary ? $r('app.color.nav_glow') : $r('app.color.card_shadow'),
      offsetX: 0,
      offsetY: this.pressed ? 1 : 2
    })
    .scale({ x: this.pressed ? 0.94 : 1, y: this.pressed ? 0.94 : 1 })
    .accessibilityText(this.label)
    .accessibilityDescription(this.desc)
    .onTouch((event: TouchEvent) => {
      this.onTouchEvent(event)
    })
    .onClick(() => {
      this.action()
    })
  }
}
