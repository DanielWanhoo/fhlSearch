import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  /**
   * 读取颜色资源并转为 #RRGGBB 十六进制字符串。
   * 颜色通过 $r 引用 base/dark 成对资源，随系统深色模式自动取值。
   */
  private getColorHex(resId: number): string {
    const color = this.context.resourceManager.getColorSync(resId);
    const rgb = color & 0xFFFFFF;
    return '#' + rgb.toString(16).padStart(6, '0').toUpperCase();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // 配置窗口背景色和系统栏颜色（颜色随深色模式自动切换，避免硬编码）
    // 沉浸式：setWindowLayoutFullScreen(true) 让整个窗口布局铺满整屏（含状态栏/导航条），
    // 页面内容自然延伸到边缘，再由页面 topInset/bottomInset 手动避让系统图标与手势条。
    // 这是「整应用沉浸」的官方做法，也能消灭底部白条（非全屏布局会自动避让底部 AI 横条）。
    try {
      const windowClass = windowStage.getMainWindowSync();
      const barColor = this.getColorHex($r('app.color.background').id);
      const contentColor = this.getColorHex($r('app.color.text_primary').id);

      windowClass.setWindowLayoutFullScreen(true);
      windowClass.setWindowBackgroundColor(barColor);
      windowClass.setWindowSystemBarProperties({
        statusBarColor: '#00FFFFFF',
        statusBarContentColor: contentColor,
        navigationBarColor: '#00FFFFFF',
        navigationBarContentColor: contentColor
      });

      // 注意：此处窗口尚未就绪，getWindowAvoidArea 会返回 0。
      // 真实安全区高度改在 Index 页 aboutToAppear（页面加载后）读取并存入 AppStorage。
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to configure window. Cause: %{public}s', JSON.stringify(err));
    }

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
