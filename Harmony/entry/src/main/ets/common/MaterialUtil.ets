/**
 * 沉浸光感材质工具类
 *
 * 系统「沉浸光感」材质由 HDS（UI Design Kit）提供，自 HarmonyOS 6.0.0(20) 起有 `HdsTabs`，
 * 自 6.1.0(23) 起提供 `hdsMaterial` 材质类型与 `barFloatingStyle.systemMaterialEffect`。
 * 本工程 compileSdkVersion 26、compatibleSdkVersion 24，可编译并运行该 API（`@since 23` ≤ 24）。
 *
 * 设备实际是否开启系统材质由系统策略决定（`hdsMaterial.getSystemMaterialTypes()` 返回可用材质类型列表）：
 * - 有返回值：使用 `IMMERSIVE`（沉浸光感材质，玻璃质感最强）
 * - 返回空：退回 `ADAPTIVE`（跟随系统材质策略，由系统给出该设备可用的等效效果）
 * 这样在支持与不支持沉浸光感的设备上都不会出现「页签栏消失/发虚」的降级事故。
 */
import { hdsMaterial, SystemMaterialParams } from '@kit.UIDesignKit'

export class MaterialUtil {
  // 系统材质能力只探测一次（结果缓存），避免每帧调用系统接口
  private static materialTypes: hdsMaterial.MaterialType[] | undefined = undefined

  /** 当前设备是否支持系统沉浸光感材质 */
  public static isImmersiveMaterialAvailable(): boolean {
    if (MaterialUtil.materialTypes === undefined) {
      try {
        MaterialUtil.materialTypes = hdsMaterial.getSystemMaterialTypes()
      } catch (err) {
        // 设备/系统版本不支持该系统能力：按「无材质」处理
        MaterialUtil.materialTypes = []
      }
    }
    return MaterialUtil.materialTypes.length > 0
  }

  /** 悬浮页签栏的材质参数：优先沉浸光感，不可用时跟随系统材质策略 */
  public static getBarMaterial(): SystemMaterialParams {
    if (MaterialUtil.isImmersiveMaterialAvailable()) {
      return {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      }
    }
    return {
      materialType: hdsMaterial.MaterialType.ADAPTIVE,
      materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
    }
  }
}
