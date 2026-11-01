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
 *
 * v3.3 起增加「光感强度」三档（对应示例工程里的材质等级菜单）：
 * - EXQUISITE 精致：材质最厚重，玻璃层次最明显
 * - GENTLE    均衡（默认）：强度适中，兼顾可读性与质感
 * - SMOOTH    柔和：材质最轻薄，界面最接近纯色
 * 等级存于 AppStorage（由 EntryAbility 用 PersistentStorage 持久化），三个检索页的「信息」弹窗都能改。
 */
import { hdsMaterial, SystemMaterialParams } from '@kit.UIDesignKit'

/** 「光感强度」在 AppStorage 里的键名（EntryAbility 中注册为持久化属性） */
export const LEVEL_STORAGE_KEY: string = 'materialLevel'
/** 精致 */
export const LEVEL_EXQUISITE: string = 'EXQUISITE'
/** 均衡（默认） */
export const LEVEL_GENTLE: string = 'GENTLE'
/** 柔和 */
export const LEVEL_SMOOTH: string = 'SMOOTH'

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

  /** 当前「光感强度」档位名（非法值一律回落「均衡」） */
  public static getLevelName(): string {
    const value: string | undefined = AppStorage.get<string>(LEVEL_STORAGE_KEY)
    if (value === LEVEL_EXQUISITE || value === LEVEL_SMOOTH) {
      return value
    }
    return LEVEL_GENTLE
  }

  /** 切换「光感强度」：写入 AppStorage，页签栏与各处材质随即按新等级重建 */
  public static setLevelName(name: string): void {
    AppStorage.setOrCreate<string>(LEVEL_STORAGE_KEY, name)
  }

  /** 档位对应的中文标签（用于「信息」弹窗里的三档胶囊） */
  public static getLevelLabel(name: string): string {
    if (name === LEVEL_EXQUISITE) {
      return '精致'
    }
    if (name === LEVEL_SMOOTH) {
      return '柔和'
    }
    return '均衡'
  }

  /** 三档的档位名，按「从强到弱」排列（弹窗从左到右渲染） */
  public static getLevelNames(): string[] {
    return [LEVEL_EXQUISITE, LEVEL_GENTLE, LEVEL_SMOOTH]
  }

  /** 档位名 → HDS 材质等级 */
  private static toMaterialLevel(name: string): hdsMaterial.MaterialLevel {
    if (name === LEVEL_EXQUISITE) {
      return hdsMaterial.MaterialLevel.EXQUISITE
    }
    if (name === LEVEL_SMOOTH) {
      return hdsMaterial.MaterialLevel.SMOOTH
    }
    return hdsMaterial.MaterialLevel.GENTLE
  }

  /** 悬浮页签栏的材质参数：优先沉浸光感，不可用时跟随系统材质策略；等级取用户选择的档位 */
  public static getBarMaterial(): SystemMaterialParams {
    const level: hdsMaterial.MaterialLevel = MaterialUtil.toMaterialLevel(MaterialUtil.getLevelName())
    if (MaterialUtil.isImmersiveMaterialAvailable()) {
      return {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: level
      }
    }
    return {
      materialType: hdsMaterial.MaterialType.ADAPTIVE,
      materialLevel: level
    }
  }
}
