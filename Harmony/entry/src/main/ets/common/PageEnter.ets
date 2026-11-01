import { curves } from '@kit.ArkUI'

/**
 * 切页进场：页面元素自上而下错峰出现 + 左右回弹
 *
 * 外壳 Index.ets 在切页瞬间把对应页的 enterTick 加减一，页面收到后：
 * 先把所有元素藏起来（不透明度 0、横向偏移 ±16vp），再从第 0 项开始逐项放出一项 ——
 * 不透明度 0 → 1、偏移 → 0。曲线是一条欠阻尼弹簧（阻尼比约 0.54），
 * 落位时会越过原位 2vp 左右再收住，所以整片内容是「轻轻弹进来」的。
 * 偏移的正负跟随切页方向：往后切页从右侧弹入，往前切页从左侧弹入（见各页 enterDir）。
 *
 * 时间预算：整个切页固定 0.6s（含系统横向滑动），错峰必须挤在这个窗口里跑完，
 * 所以逐项间隔不是固定 50ms，而是按「项目数」算出来的（见 enterStepFor）。
 */

/** 切页总时长（ms）：与外壳 HdsTabs 的 animationDuration 同值 */
export const ENTER_TOTAL_MS: number = 600

/** 逐项间隔上限（ms）：项目数少的页面按 50ms 走 */
export const ENTER_STEP_MS: number = 50

/** 逐项间隔下限（ms）：项目多（名士页 14 项）时压缩到这么密，保证总时长不超 */
export const ENTER_MIN_STEP_MS: number = 8

/** 第一项的启动延迟（ms）：留一帧给「藏起来」那次渲染，否则第一项没有动画起点 */
export const ENTER_START_DELAY_MS: number = 16

/** 弹簧大致稳定的时长（ms）：用来给错峰留窗口 */
export const ENTER_SPRING_MS: number = 280

/** 收尾余量（ms）：最后一项落定后再稍等一会儿才把下标复位成哨兵值 */
export const ENTER_TAIL_MS: number = 80

/** 起始横向偏移（vp）：实际用值 = 它 × enterDir（+1 从右侧弹回原位，-1 从左侧） */
export const ENTER_OFFSET_X: number = 16

/** 哨兵值：全部已显示（静止态，也是「切页动画关闭」时直接落的终态） */
export const ENTER_ALL_SHOWN: number = 999

/** 平板右栏整块进场的起始横向偏移（vp）：与左栏同一方向（乘 enterDir） */
export const RIGHT_OFFSET_X: number = 22

/** 平板右栏整块进场的时长（ms） */
export const RIGHT_ENTER_MS: number = 340

/** 平板右栏背景「横隐遮罩」淡出的时长（ms）：比内容稍长，扫过去之后才露出内容 */
export const RIGHT_VEIL_MS: number = 520

/**
 * 进场弹簧：interpolatingSpring(初速度, 质量, 刚度, 阻尼)
 *
 * 阻尼比 ζ = 阻尼 / (2 * √(刚度 * 质量)) = 22 / (2 * √420) ≈ 0.54，过冲约 13%：
 * 16vp 的位移里只多走约 2vp 就收住，比早先那条（过冲 21%、约 4.8vp）明显收敛。
 */
export const ENTER_SPRING: ICurve = curves.interpolatingSpring(0, 1, 420, 22)

/**
 * 按项目数算出逐项间隔：让「最后一项落下」正好卡在 0.6s 窗口里
 *
 * 项目少（诗词 5 项、成语 7 项）时就是 50ms，落得早一点没关系；
 * 项目多（名士 14 项）时自动压密，不会超出总时长。
 */
export function enterStepFor(slots: number): number {
  if (slots <= 1) {
    return ENTER_STEP_MS
  }
  const window: number = ENTER_TOTAL_MS - ENTER_START_DELAY_MS - ENTER_SPRING_MS
  const raw: number = window / (slots - 1)
  return Math.max(ENTER_MIN_STEP_MS, Math.min(ENTER_STEP_MS, Math.floor(raw)))
}

/** 整轮错峰跑完（含收尾余量）的时长：页面据此安排「复位成哨兵值」的定时器 */
export function enterFinishMs(slots: number): number {
  const step: number = enterStepFor(slots)
  return ENTER_START_DELAY_MS + Math.max(0, slots - 1) * step + ENTER_SPRING_MS + ENTER_TAIL_MS
}
