import { accessibility } from '@kit.AccessibilityKit'
import { curves } from '@kit.ArkUI'

/**
 * 动效令牌（v3.3 统一）
 *
 * 为什么要有这个文件：
 * - 早先把曲线和时长散落在各处（`Curve.EaseOut` 出现十几次、250/180/160/140/120 各写一遍），
 *   同一件事在不同页面用不同节奏 —— 成语页结果卡 180ms、名士页 250ms，切页时能感觉到「两个 App」。
 * - 这里收成一份：**曲线只留两条、时长只留四档**，各页从常量引用，不再手写数字。
 *
 * 取值依据（Emil Kowalski 的动效规范）：
 * - 进场 / 退场一律 ease-out（起步就快，用户盯的那一帧不掉速），且曲线要比系统自带的更「利」；
 * - UI 动画不超过 300ms；
 * - 按压反馈要做成非对称：按下 110ms 立刻给到，抬起 240ms 弹簧归位（响应快、回落稳）。
 */

/** 强 ease-out：进场、退场、错峰淡进统一用它（0.23, 1, 0.32, 1） */
export const EASE_OUT_STRONG: ICurve = curves.cubicBezierCurve(0.23, 1, 0.32, 1)

/** 柔和 ease-out：纯不透明度交叉淡入（不需要爆发力，避免边缘过硬） */
export const EASE_OUT_SOFT: ICurve = curves.cubicBezierCurve(0.33, 1, 0.68, 1)

/** 1 帧（ms）：改完状态先渲染一帧再起动画，animateTo 才会拿到正确的起点 */
export const FRAME_MS: number = 16

// ── 四档时长 ──
/** 极快：按压反馈 */
export const MOTION_FAST_MS: number = 110
/** 基准：卡片 / 小元素进场 */
export const MOTION_BASE_MS: number = 200
/** 稍慢：整块内容切换 */
export const MOTION_SLOW_MS: number = 250
/** 按压回弹：比按下慢一倍，手感「按下即响应、抬起有余韵」 */
export const MOTION_PRESS_UP_MS: number = 240

/** 按压回弹曲线：springMotion(响应时长 s, 阻尼比)，阻尼 0.72 只轻微过冲 */
export const PRESS_SPRING: ICurve = curves.springMotion(0.26, 0.72)

/**
 * 落位回弹（按钮分裂归位 / 内容复原）：interpolatingSpring(初速, 质量, 刚度, 阻尼)
 *
 * 阻尼 41 + 刚度 600 → ζ = 41 / (2√600) ≈ 0.837，
 * 过冲 = exp(−πζ/√(1−ζ²)) ≈ **0.8%**（392vp 的行程 ≈ 3vp，刚好看得见一下）。
 * 用在「有实际行程」的纵向位移上；纯不透明度不要用它（会闪）。
 */
export const LAND_SPRING: ICurve = curves.interpolatingSpring(0, 1, 600, 41)

/** 落位回弹的时长：与上面弹簧的自然收敛时间对齐（约 0.3s） */
export const LAND_SPRING_MS: number = 300

/** 列表错峰：每张卡延迟 25ms，最多错 6 档（否则长列表尾部会等到 1 秒后） */
export const STAGGER_STEP_MS: number = 25
export const STAGGER_CAP: number = 6

/** 第 idx 项的错峰延迟（ms），已封顶 */
export function staggerDelay(idx: number): number {
  return Math.min(idx, STAGGER_CAP) * STAGGER_STEP_MS
}

/** 条件面板收起：每格往回缩 26ms（比展开的 30ms 略快，收的时候越往下越赶） */
export const PANEL_COLLAPSE_STEP_MS: number = 26
/** 条件面板收起尾巴：最后一格起步后等 150ms，再让整块回弹收拢 */
export const PANEL_COLLAPSE_TAIL_MS: number = 150

let reduceCache: boolean | undefined = undefined

/**
 * 系统「减弱动画」开关（设置 → 无障碍 → 减少动态效果）
 *
 * 开启时：位移类动画（大段位移、缩放、高度伸缩）整支跳过，只保留「内容直接到位」；
 * 按压反馈这类帮助理解操作是否生效的动画不砍。
 * 只读一次并缓存：这个值在一次会话里不会变，反复走 IPC 会拖慢每次点击。
 */
export function isReducedMotion(): boolean {
  if (reduceCache === undefined) {
    try {
      reduceCache = accessibility.isAnimationReduceEnabledSync()
    } catch (err) {
      reduceCache = false
    }
  }
  return reduceCache === true
}
