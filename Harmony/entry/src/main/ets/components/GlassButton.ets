import { Haptics } from '../common/Haptics'
import { EASE_OUT_STRONG, MOTION_FAST_MS, MOTION_PRESS_UP_MS, PRESS_SPRING } from '../common/Motion'

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
 * - 按下：先触发一次轻触**震动反馈**（`Haptics.tick()`），随后 110ms 收缩到 0.96（强 ease-out，起步即动），
 *   同时内层高光淡入、投影收紧（“压进玻璃”的手感）；无马达的设备自动静默（如平板）
 * - 抬起：240ms 弹簧回弹（`PRESS_SPRING`，只轻微过冲），高光柔和淡出 —— 比按下慢一倍，
 *   手感是「按下即响应、抬起有余韵」，而不是按一下弹半天
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
      this.getUIContext().animateTo({ duration: MOTION_FAST_MS, curve: EASE_OUT_STRONG }, () => {
        this.pressed = true
        this.highlight = 1
      })
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      // 抬起：弹簧回弹（略微过冲再归位）+ 高光柔和淡出
      this.getUIContext().animateTo({ duration: MOTION_PRESS_UP_MS, curve: PRESS_SPRING }, () => {
        this.pressed = false
        this.highlight = 0
      })
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 顶部反光（v3.3）：从顶边向下淡出的一层白，让胶囊看起来是「有厚度的弧面」。
      // 用同色 alpha=0 的收尾（surface_sheen_clear）而不是 Color.Transparent，
      // 避免渐变到「透明黑」而出现一层灰雾。
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(24)
        .linearGradient({
          angle: 180,
          colors: [
            [$r('app.color.surface_sheen'), 0.0],
            [$r('app.color.surface_sheen_clear'), 0.6]
          ]
        })

      // 按压高光层：内层均匀提亮（与整块材质同形，不产生局部亮斑）
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(24)
        .backgroundColor($r('app.color.glass_press'))
        .opacity(this.highlight)

      Text(this.label)
        .fontSize(15)
        .fontWeight(this.primary ? 600 : 500)
        .fontColor(this.primary ? $r('app.color.on_primary') : $r('app.color.text_primary'))
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 6, right: 6 })
    }
    .layoutWeight(1)
    .height(48)
    .borderRadius(24)
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
    .scale({ x: this.pressed ? 0.96 : 1, y: this.pressed ? 0.96 : 1 })
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
