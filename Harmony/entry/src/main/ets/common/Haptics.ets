import { vibrator } from '@kit.SensorServiceKit'

/**
 * 轻触震动反馈（按钮按压用）
 *
 * 手感设计：用**系统预置触感** `haptic.effect.soft`（柔和、低频、短促「嗒」一下），
 * 而不是自己拉一条定长震动——预置效果由系统按机型调校，观感更接近原生按钮。
 *
 * 依赖：`ohos.permission.VIBRATE`（已在 `module.json5` 声明，普通级权限、装包即授权，无需运行时申请）。
 *
 * 兜底（任何情况下都不允许影响界面与功能）：
 * - 设备**没有振动器**（如 MatePad Pro）→ 首次探测后直接跳过，不做任何无效调用、不刷错误日志；
 * - 设备不支持该预置触感 → 退化为 12ms 定长轻震；
 * - 系统拒绝 / 调用异常 → `try/catch` + `promise.catch` 静默忽略，按钮功能不受影响；
 * - 60ms 内的重复触发只算一次（连点、长按不会堆成一串连续震动）。
 *
 * 设备能力只探测一次（首次按压时），之后复用结果，避免每次点击都走一遍系统查询。
 */
const EFFECT_SOFT: string = vibrator.HapticFeedback.EFFECT_SOFT

export class Haptics {
  private static lastTick: number = 0       // 上次触发时间戳（节流）
  private static probed: boolean = false    // 是否已探测过设备能力
  private static motorReady: boolean = false // 本机是否有振动器
  private static presetOk: boolean = false   // 是否支持「柔和触感」预置效果

  /** 按钮按压：轻触一下 */
  static tick(): void {
    const now: number = Date.now()
    if (now - Haptics.lastTick < 60) {
      return
    }
    Haptics.lastTick = now
    if (!Haptics.probe()) {
      return  // 无振动器：静默跳过
    }
    if (Haptics.presetOk) {
      Haptics.firePreset()
    } else {
      Haptics.fireTime()
    }
  }

  /** 探测设备能力（仅首次执行，结果缓存） */
  private static probe(): boolean {
    if (Haptics.probed) {
      return Haptics.motorReady
    }
    Haptics.probed = true
    try {
      Haptics.motorReady = vibrator.getVibratorInfoSync().length > 0
    } catch (err) {
      Haptics.motorReady = false
    }
    if (!Haptics.motorReady) {
      return false
    }
    try {
      Haptics.presetOk = vibrator.isSupportEffectSync(EFFECT_SOFT)
    } catch (err) {
      Haptics.presetOk = false  // 不支持预置触感：退化为定长轻震
    }
    return true
  }

  private static firePreset(): void {
    try {
      vibrator.startVibration(
        { type: 'preset', effectId: EFFECT_SOFT, count: 1, intensity: 70 },
        { id: 0, usage: 'touch' }
      ).catch(() => {
        // 系统拒绝（无马达等）：静默忽略
      })
    } catch (err) {
      // 静默忽略
    }
  }

  private static fireTime(): void {
    try {
      vibrator.startVibration(
        { type: 'time', duration: 12 },
        { id: 0, usage: 'touch' }
      ).catch(() => {
        // 系统拒绝（无马达等）：静默忽略
      })
    } catch (err) {
      // 静默忽略
    }
  }
}
