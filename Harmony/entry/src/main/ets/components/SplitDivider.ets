/**
 * 可拖动分栏分隔条（带滑块手柄）
 *
 * 放在宽屏双栏（左输入 / 右结果）之间，拖动可调整左右两栏宽度比例。
 * ratio：左栏占比（0~1）；totalWidth：分栏总宽度（vp），用于把拖动距离换算成比例。
 * 视觉：一条居中细线作分界，中间一个圆角滑块手柄；悬停/拖动时手柄变主色提示可拖。
 * 热区宽 24vp（`DIVIDER_WIDTH`），方便手指按住手柄左右拖动。
 */

/** 分隔条占位宽度（vp）：与 Index 计算左栏宽度时用的常量保持一致 */
const DIVIDER_WIDTH: number = 24

@Component
export struct SplitDivider {
  @Prop ratio: number = 0.5
  @Prop totalWidth: number = 0
  onRatioChange: (ratio: number) => void = () => {}

  @State isHover: boolean = false
  @State isDragging: boolean = false
  private startRatio: number = 0.5

  private get isActive(): boolean {
    return this.isHover || this.isDragging
  }

  private clamp(v: number): number {
    return Math.max(0.25, Math.min(0.75, v))
  }

  build() {
    Stack() {
      // 分界细线
      Column()
        .width(2)
        .height('100%')
        .borderRadius(1)
        .backgroundColor($r('app.color.cell_border'))

      // 滑块手柄（圆角竖条，方便手指抓取）
      Column()
        .width(8)
        .height(48)
        .borderRadius(4)
        .backgroundColor(this.isActive ? $r('app.color.primary') : $r('app.color.cell_border'))
    }
    .width(DIVIDER_WIDTH)
    .height('100%')
    .accessibilityText('分栏分隔条')
    .accessibilityDescription('按住并向左或向右拖动，可调整左右两栏宽度比例')
    .onHover((isHover: boolean) => {
      this.isHover = isHover
    })
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 1 })
        .onActionStart(() => {
          this.isDragging = true
          this.startRatio = this.ratio
        })
        .onActionUpdate((event: GestureEvent) => {
          // 可用宽度 = 总宽 - 分隔条自身占位（页面用 layoutWeight 分配的就是这段），
          // 这样分隔条与手指严格 1:1，且与「左栏宽 = 比例 × 可用宽度」的口径一致
          const usable: number = this.totalWidth - DIVIDER_WIDTH
          if (usable > 0) {
            this.onRatioChange(this.clamp(this.startRatio + event.offsetX / usable))
          }
        })
        .onActionEnd(() => {
          this.isDragging = false
        })
        .onActionCancel(() => {
          this.isDragging = false
        })
    )
  }
}
