import { IdiomSearchPage } from './idiom/IdiomSearchPage'
import { PoetrySearchPage } from './poetry/PoetrySearchPage'
import { MingziSearchPage } from './mingzi/MingziSearchPage'
import { SymbolGlyphModifier, window } from '@kit.ArkUI'
import { accessibility } from '@kit.AccessibilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { HdsAnimationMode, HdsTabs, HdsTabsController, HdsTabsFloatingStyle } from '@kit.UIDesignKit'
import { AmbientBackdrop } from '../common/AmbientBackdrop'
import { MaterialUtil, LEVEL_GENTLE } from '../common/MaterialUtil'
import { Haptics } from '../common/Haptics'

// ── 切页过渡（v3.3）：背景不动，内容「自上而下错峰出现 + 横向回弹」 ──────────
// 背景与环境光衬（AmbientBackdrop）铺在本页最底层，不参与切页动画 ——
// 切页时背景一动都不动，动的只有页面内容（标题、图标、输入格、文字）。
//
// 内容分两层，互不干扰：
// 1) 系统 HdsTabs 的横向平移（220ms，cubic-bezier(0.2, 0, 0.1, 1)）把整页带进来；
// 2) 页面内部再按「从上到下」逐项进场：第 k 项等 k×50ms 再出现，横向从 +22vp 弹回原位，
//    用欠阻尼弹簧（interpolatingSpring，阻尼比约 0.43）→ 越过原位约 4~5vp 再收住 = 左右回弹。
// 具体实现落在三个检索页里（本页只负责「切到哪一页就把那一页的进场序号 +1」）。
const ENTER_TICK_DEBOUNCE_MS: number = 80  // onContentWillChange 同一次切换会连发两次（实测间隔 3ms）

interface DockTab {
  label: string
  symbol: Resource
}

/**
 * 主页面 — 组合主页面：成语检索 + 诗词检索 + 名士检索
 *
 * 「沉浸光感」悬浮页签栏（HarmonyOS 官方 HDS 设计体系组件，替代旧版手写 Dock）：
 * - `HdsTabs`（@kit.UIDesignKit，API 23 起提供）负责绘制页签栏：自适应宽度、悬浮胶囊、
 *   图标/文字选中态、按压与切换动效全部按 HDS 规范由系统实现
 * - `barFloatingStyle.systemMaterialEffect` = 系统「沉浸光感」材质
 *   （`hdsMaterial.MaterialType.IMMERSIVE` + `MaterialLevel.ADAPTIVE`）：玻璃质感实时折射背后内容，
 *   自动跟随系统深浅色、系统材质等级与功耗/温度策略；设备不支持时由 MaterialUtil 降级为 ADAPTIVE 跟随系统策略
 * - `barOverlap(true)`：页签栏悬浮在内容之上（`barOverlap(false)` 会退化成贴底实心栏，无悬浮胶囊与光感）
 * - `barBottomMargin` 避让底部手势条（`bottomInset`，页面加载后读取的真实安全区）
 * - `adaptToHandedness`：宽屏跟随握持手左右自适应，单手可达
 * - 手机/平板统一使用底部悬浮页签栏（HdsTabs 的 `vertical` 垂直模式为「贴边实心栏 + 分隔线」，
 *   没有悬浮胶囊与材质，故不用于平板；平板由 HdsTabs 按宽度断点自适应胶囊宽度）
 * - 平板横屏（双栏）：页签栏**水平居中于左栏**而不是整屏居中。HdsTabs 的悬浮页签栏固定居中于组件布局盒，
 *   没有「水平偏移」参数，故把**布局盒**加宽左移（盒中心 = 左栏中心、盒右边 = 屏幕右边），内容层再右移补回：
 *   见 `barBoxWidth()` / `barBoxOffset()` / `contentShift()` / `wideBarWidth()`
 *   （盒几何随分栏比例实时变化：拖动分隔条页签栏跟着走；胶囊宽度也随左栏收窄而收窄，不会顶出屏幕）
 * - 内容让位：`barOverlap(true)` 时系统不再自动扣减页签栏占位，改由 TabContent 内部留白
 *   （`contentReserve()` = 页签栏高 + 间隙 + 手势条）承担，三个检索页**布局零改动**
 *   （仅各新增 1 个 `onScrollOffset` 回调用于下面这条滚动联动）
 * - 滚动收起/浮出：检索页 Scroll 的 `onScrollFrameBegin` → `onPageScroll()` →
 *   `applyHideAnimation / applyShowAnimation(SCROLL_ANIMATION)`
 * - 「光感」底衬：页签栏浮起的空档处铺一层暖色光晕（`dock_glow` 渐变），玻璃材质折射这层光后
 *   形成可见的光感（纯底色上玻璃几乎看不见）
 *
 * 注：旧版手写 Dock（Stack 叠加隐藏 Tabs + backgroundBlurStyle 模糊）已由本组件取代；
 * 旧实现见 dev-logs/backup-2026-09-10/Index.ets。
 */

@Entry
@Component
struct Index {
  @State currentIndex: number = 0
  @State isWide: boolean = false  // 平板横屏（>600vp）：页签栏水平居中于左栏、禁用左右滑动切页
  @State windowWidth: number = 0  // 窗口宽度（vp）：计算左栏中心，用于页签栏水平位移
  @StorageProp('splitRatio') splitRatio: number = 0.5  // 双栏比例（检索页写入）：页签栏跟随分隔条移动
  @State idiomUndoCmd: number = 0    // 成语页「清空当前」指令（返回手势触发）
  @State poetryClearCmd: number = 0  // 诗词页「清空」指令（返回手势触发）
  @State mingziUndoCmd: number = 0   // 名士页「返回上一级检索」指令（返回手势触发）
  @StorageProp('bottomInset') @Watch('onBottomInsetChange') bottomInset: number = 0  // 系统导航条高度（vp），页签栏离底避让
  // 光感强度档位（V3.3）：在「信息」弹窗里切换，持久化保存。
  // 它只影响页签栏材质的等级（EXQUISITE / GENTLE / SMOOTH），变化时让下面的样式缓存失效重建。
  @StorageProp('materialLevel') materialLevel: string = LEVEL_GENTLE
  private controller: HdsTabsController = new HdsTabsController()      // 竖屏：底部悬浮页签栏
  // 滚动回调提成字段：每帧都传给三个检索页，现造箭头函数会让子组件每次 build 都拿到“新参数”
  private scrollHandler: (y: number) => void = (y: number) => { this.onPageScroll(y) }
  private isBarHidden: boolean = false  // 页签栏是否已随滚动收起
  // 切页进场序号（v3.3）：切到某一页就把它的序号 +1，该页据此重放「元素错峰进场」。
  // 不能用 currentIndex 判断：HdsTabs 的 onChange 在切换**动画结束**时才回调，
  // 动画期间 currentIndex 还是旧页，按它触发进场会把「正在滑出的旧页」重放一遍（已实测踩到）。
  @State enterTickIdiom: number = 0
  @State enterTickPoetry: number = 0
  @State enterTickMingzi: number = 0
  private lastEnterIndex: number = -1      // 上一次触发进场的页 + 时刻：用于压掉同一轮里的重复回调
  private lastEnterAt: number = 0
  private reduceMotion: boolean = false  // 系统「减弱动画」开关（无障碍），开启时不做过渡
  private readonly dockTabs: DockTab[] = [
    { label: '成语检索', symbol: $r('sys.symbol.book') },
    { label: '诗词检索', symbol: $r('sys.symbol.square_grid_2x2') },
    { label: '名士检索', symbol: $r('sys.symbol.person_2') }
  ]

  // 页面加载后（窗口已就绪）读取真实安全区高度，存入 AppStorage，
  // 供本页页签栏离底避让与子页面标题「铺满到屏幕边缘」时避让系统栏图标。
  // 注意：EntryAbility 的 onWindowStageCreate 阶段窗口未就绪，getWindowAvoidArea 会返回 0。
  aboutToAppear(): void {
    // 系统「减弱动画」（设置 → 无障碍）开启时，切页只保留系统自带的滑动，不再叠淡入
    try {
      this.reduceMotion = accessibility.isAnimationReduceEnabledSync()
    } catch (err) {
      this.reduceMotion = false
    }
    // 先把当前占位高度发布给检索页（安全区读取是异步的，读到后再刷新一次）
    this.publishBarInset()
    window.getLastWindow(getContext(this)).then((win: window.Window) => {
      const systemArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
      const navArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR)
      AppStorage.setOrCreate<number>('topInset', px2vp(systemArea.topRect.height))
      AppStorage.setOrCreate<number>('bottomInset', px2vp(navArea.bottomRect.height))
      // 调优用：确认设备是否支持系统沉浸光感材质、以及真实安全区高度（hilog -x | grep immersiveMaterial）
      hilog.info(0x0000, 'CulturalSearch',
        'immersiveMaterial=%{public}s topInset=%{public}d bottomInset=%{public}d',
        MaterialUtil.isImmersiveMaterialAvailable() ? 'yes' : 'no',
        px2vp(systemArea.topRect.height), px2vp(navArea.bottomRect.height))
    })
  }

  // 安全区高度变化 → 重新发布页签栏占位高度
  onBottomInsetChange(): void {
    this.publishBarInset()
  }

  // 把页签栏占位高度发布到 AppStorage：三个检索页据此在「可滚动内容内部」留白，
  // 内容因此可以一直滚到页签栏上方，其余部分从玻璃材质下方穿过（不再被一条空白带截断）
  private publishBarInset(): void {
    // 底部悬浮页签栏（手机竖屏 / 平板横屏一致）→ 检索页在滚动内容里留出其高度
    AppStorage.setOrCreate<number>('barInset', this.contentReserve())
  }

  // 系统返回手势（@Entry 页面生命周期回调）：拦截（不退出应用），
  // 按当前页分发「清空当前 / 清空 / 返回上一级检索」指令。
  onBackPress(): boolean {
    if (this.currentIndex === 0) {
      this.idiomUndoCmd++
    } else if (this.currentIndex === 1) {
      this.poetryClearCmd++
    } else {
      this.mingziUndoCmd++
    }
    return true
  }

  // 页签样式：图标（未选中辅色 / 选中主色，均为 base-dark 成对资源）+ 文字，
  // 颜色由系统页签栏按选中态切换，随系统深浅色自动取值。
  //
  // ⚠️ 性能：这三个样式对象**只建一次**。早先是每次 build() 现造（切页签 → currentIndex 变化
  // → 整个 build 重跑 → 新建 3 个 BottomTabBarStyle + 6 个 SymbolGlyphModifier），
  // 系统页签栏会当成「样式变了」重新配置一遍，切页时正好卡在动画里，表现就是掉帧。
  private tabStyles: BottomTabBarStyle[] = []

  private tabBarStyle(index: number): BottomTabBarStyle {
    if (this.tabStyles.length === 0) {
      for (let i = 0; i < this.dockTabs.length; i++) {
        const tab = this.dockTabs[i]
        this.tabStyles.push(new BottomTabBarStyle({
          normal: new SymbolGlyphModifier(tab.symbol)
            .fontColor([$r('app.color.text_secondary')]),
          selected: new SymbolGlyphModifier(tab.symbol)
            .fontColor([$r('app.color.primary')])
        }, tab.label)
          .labelStyle({
            unselectedColor: $r('app.color.text_secondary'),
            selectedColor: $r('app.color.primary')
          }))
      }
    }
    return this.tabStyles[index]
  }

  // 确保页签栏处于显示状态（平板常驻 / 从收起态恢复时调用）
  private showBarIfHidden(): void {
    if (this.isBarHidden) {
      this.isBarHidden = false
      this.controller.applyShowAnimation(HdsAnimationMode.SCROLL_ANIMATION)
    }
  }

  // 切页进场的「发令」：只是按方向增减进场页的序号，具体「元素自上而下错峰出现 + 横向回弹」
  // 由各检索页自己做（页面里知道自己的元素顺序）。
  // 系统「减弱动画」开启时整支不发令，切页只剩系统自带滑动。
  private preparePageEnter(comingIndex: number): void {
    if (this.reduceMotion) {
      return
    }
    // onContentWillChange 对同一次切换会连发两次（实测间隔 3ms）：同一页的重复回调压掉，
    // 否则刚藏好的元素会被第二道令重新藏一次、动画从头开始
    const now: number = Date.now()
    if (comingIndex === this.lastEnterIndex && now - this.lastEnterAt < ENTER_TICK_DEBOUNCE_MS) {
      return
    }
    this.lastEnterIndex = comingIndex
    this.lastEnterAt = now
    // 序号按「切页方向」加减，而不是一律 +1：页面据序号的变化判断从左侧还是右侧弹入。
    // 此刻 currentIndex 还是旧页（动画没结束），正好拿来比大小。
    const dir: number = comingIndex < this.currentIndex ? -1 : 1
    if (comingIndex === 0) {
      this.enterTickIdiom += dir
    } else if (comingIndex === 1) {
      this.enterTickPoetry += dir
    } else if (comingIndex === 2) {
      this.enterTickMingzi += dir
    }
  }

  // 滚动方向驱动页签栏「下滚隐藏 / 上滚显示」（HDS 沉浸动效 SCROLL_ANIMATION）。
  // 方向约定与系统一致：内容向上滚（offset > 0，看后面的内容）时收起页签栏，向下滚时重新浮出。
  // 平板双栏例外：页签栏**常驻**——它居中在左栏，随右栏结果列表滚动而收起/浮出会让人找不到导航（用户要求）
  private onPageScroll(yOffset: number): void {
    if (this.isWide) {
      this.showBarIfHidden()
      return
    }
    if (yOffset > 0 && !this.isBarHidden) {
      this.isBarHidden = true
      this.controller.applyHideAnimation(HdsAnimationMode.SCROLL_ANIMATION)
    } else if (yOffset < 0 && this.isBarHidden) {
      this.isBarHidden = false
      this.controller.applyShowAnimation(HdsAnimationMode.SCROLL_ANIMATION)
    }
  }

  // 页签栏占位高度（vp）：悬浮页签栏高约 56 + 上下间隙 + 底部手势条高度
  private contentReserve(): number {
    return 76 + this.bottomInset
  }

  /**
   * 平板横屏「页签栏居中于左栏」的几何实现（关键：不能裁到内容）
   *
   * 悬浮页签栏固定居中于 HdsTabs 的**布局盒**，组件没有「水平偏移」参数。
   * 若只把组件整体平移（translate），组件布局盒还在原位，内容与玻璃就会各自跑到盒子外面，
   * 结果「页签栏被屏幕左边裁掉 + 右栏内容被盒子右边裁掉」（已踩过这个坑）。
   *
   * 正解：把**布局盒本身**加宽并左移 —— 取「以左栏中心为中心、且完整覆盖整屏 [0, W] 的最小盒」：
   *   盒宽 L = 2W - 左栏宽，盒左边缘 = 左栏宽 - W（负数，左侧伸出屏幕外）
   * 此时盒中心 = 左栏中心，页签栏自然落在左栏正中；盒右边缘正好 = W，右栏内容完整可见。
   * 内容层再右移 (W - 左栏宽) 回到屏幕 [0, W]，且始终落在盒内 → 页签栏与内容都不被裁切。
   * 手机竖屏：左栏宽 = 整屏宽 → L = W、左边缘 0、内容位移 0，全部退化为居中（同一套公式）。
   */

  // 左栏实际宽度（vp）：双栏 = 比例 ×（窗口宽 - 分隔条 24vp，与 SplitDivider 的 width 一致）；单栏 = 整屏
  private leftColumnWidth(): number {
    const w: number = this.windowWidth
    return this.isWide ? this.splitRatio * (w - 24) : w
  }

  // 页签栏布局盒宽度 = 2W - 左栏宽（窄屏退化为 W）
  private barBoxWidth(): Length {
    if (this.windowWidth <= 0) {
      return '100%'
    }
    return 2 * this.windowWidth - this.leftColumnWidth()
  }

  // 页签栏布局盒左边缘（负值 = 左侧伸出屏幕外；窄屏为 0）
  private barBoxOffset(): number {
    return this.leftColumnWidth() - this.windowWidth
  }

  // 内容层右移量：把内容从「布局盒左边缘」挪回屏幕 [0, W]（窄屏为 0）
  private contentShift(): number {
    return this.windowWidth - this.leftColumnWidth()
  }

  // 内容层宽度：固定为窗口宽（宽屏时布局盒比窗口宽，不能用 100%，否则页面按盒宽排版）
  private contentWidth(): Length {
    return this.windowWidth > 0 ? this.windowWidth : '100%'
  }

  // 平板页签栏胶囊宽度：不超过左栏宽度，避免左栏被拖窄后页签栏顶出屏幕左边缘
  private wideBarWidth(): number {
    return Math.max(200, Math.min(520, this.leftColumnWidth() - 24))
  }

  // 悬浮页签栏样式：系统沉浸光感材质 + 避让底部手势条 + 跟随握持手 + 按断点自适应胶囊宽度
  //
  // ⚠️ 性能：这个对象同样**缓存**。它里面带系统材质（沉浸光感）与渐变遮罩，每次 build() 现造的话，
  // 切页签时系统会重新配置整条玻璃页签栏（材质重置 + 遮罩重建），一帧就撑不住了。
  // 只有它真正的输入（宽屏与否 / 手势条高度 / 窗口宽 / 分栏比例）变了才重建。
  private barStyle: HdsTabsFloatingStyle = {}
  private barStyleKey: string = ''

  private floatingStyle(): HdsTabsFloatingStyle {
    // 缓存键里带上「光感强度」：档位一变就重建材质参数，页签栏立刻按新等级重新渲染
    const key: string =
      `${this.isWide}|${this.bottomInset}|${Math.round(this.windowWidth)}|${this.splitRatio.toFixed(3)}|${this.materialLevel}`
    if (this.barStyleKey !== key) {
      this.barStyleKey = key
      this.barStyle = this.buildFloatingStyle()
    }
    return this.barStyle
  }

  private buildFloatingStyle(): HdsTabsFloatingStyle {
    return {
      // 手机用系统默认宽度（居中、比例由 HDS 规范给出，实测约屏宽 65%，与两侧留白协调）；
      // 中大屏用固定宽度（避免平板上一颗小胶囊挤在屏幕中间），但**不超过左栏宽度**——
      // 页签栏居中于左栏，胶囊比左栏宽就会顶出屏幕左边缘被裁掉
      barWidth: this.isWide
        ? { mediumWidth: this.wideBarWidth(), largeWidth: this.wideBarWidth() }
        : { mediumWidth: 400, largeWidth: 520 },
      barBottomMargin: this.bottomInset > 0 ? this.bottomInset : $r('sys.float.padding_level8'),
      // 仅宽屏跟随握持手（单手可达）；手机保持居中，避免胶囊左右漂移
      adaptToHandedness: this.isWide,
      // 光感颜色：主色（朱砂红）的极淡版本，玻璃材质据此吐出暖色光泽
      lightColor: $r('app.color.nav_glow'),
      // 页签栏附近的「沉浸」过渡：内容越靠近页签栏越淡（HDS 官方渐变遮罩），
      // 玻璃胶囊浮在一层柔和的底色上，不再是「内容被硬切在胶囊边缘」
      gradientMask: {
        maskColor: $r('app.color.bar_scrim'),
        maskHeight: 130
      },
      systemMaterialEffect: MaterialUtil.getBarMaterial()
    }
  }

  /**
   * 三个检索页（横竖屏共用，避免两份 TabContent 重复）
   *
   * ⚠️ 性能：几何补偿用的两层 Column + translate **只在宽屏才加**。
   * 手机上「页签栏布局盒」就是整屏，补偿量恒为 0，那两层容器和一个 transform 层纯属浪费 ——
   * 切页时整页会作为独立图层反复重绘，手机上就是这个最吃帧。
   */
  @Builder
  TabsContent() {
    TabContent() {
      if (this.isWide) {
        // 宽屏：外层铺满「页签栏布局盒」，内层固定窗口宽 + 右移补回屏幕坐标（见 barBoxWidth 注释）
        Column() {
          Column() {
            IdiomSearchPage({ undoCmd: this.idiomUndoCmd, onScrollOffset: this.scrollHandler, enterTick: this.enterTickIdiom })
          }
          .width(this.contentWidth())
          .height('100%')
          .translate({ x: this.contentShift() })
        }
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.Start)
      } else {
        // 手机：整屏即窗口，直接放页面
        IdiomSearchPage({ undoCmd: this.idiomUndoCmd, onScrollOffset: this.scrollHandler, enterTick: this.enterTickIdiom })
      }
    }
    .tabBar(this.tabBarStyle(0))

    TabContent() {
      if (this.isWide) {
        Column() {
          Column() {
            PoetrySearchPage({ clearCmd: this.poetryClearCmd, onScrollOffset: this.scrollHandler, enterTick: this.enterTickPoetry })
          }
          .width(this.contentWidth())
          .height('100%')
          .translate({ x: this.contentShift() })
        }
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.Start)
      } else {
        PoetrySearchPage({ clearCmd: this.poetryClearCmd, onScrollOffset: this.scrollHandler, enterTick: this.enterTickPoetry })
      }
    }
    .tabBar(this.tabBarStyle(1))

    TabContent() {
      if (this.isWide) {
        Column() {
          Column() {
            MingziSearchPage({ undoCmd: this.mingziUndoCmd, onScrollOffset: this.scrollHandler, enterTick: this.enterTickMingzi })
          }
          .width(this.contentWidth())
          .height('100%')
          .translate({ x: this.contentShift() })
        }
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.Start)
      } else {
        MingziSearchPage({ undoCmd: this.mingziUndoCmd, onScrollOffset: this.scrollHandler, enterTick: this.enterTickMingzi })
      }
    }
    .tabBar(this.tabBarStyle(2))
  }


  build() {
    // 背景 + 环境光衬铺在最底层、**不参与切页动画**：
    // 三个检索页只画内容，所以切页时背景纹丝不动（早先每页各带一份底衬，切页会整块推走）。
    Stack() {
      AmbientBackdrop()

      Column() {
        // 手机竖屏 / 平板横屏统一使用底部悬浮页签栏（HDS 沉浸光感材质）
        // 内容铺满整屏：检索内容一直滚到页签栏上方，其余部分从玻璃材质下方穿过
        HdsTabs({ barPosition: BarPosition.End, index: this.currentIndex, controller: this.controller }) {
          this.TabsContent()
        }
        .barOverlap(true)
        // ⚠️ 自带的「左右滑动切页」关掉：
        // 它的拖动过渡会把整页做成带透视的斜切/缩放，慢拖时画面又歪又抖 —— 这就是用户反馈的「一顿一顿」。
        // 用户后来要求只保留点页签栏切换，所以连自己的横向手势也一并去掉了。
        .scrollable(false)
        // 切页滑动时长：手机 220（系统只负责横向滑入，进场由各页错峰演出）；
        // ⚠️ 平板双栏设为 0：整页横向滑动会把中间的分栏线一起推走，而分栏线必须原地不动 ——
        // 关掉之后两栏各自在原地「长出来」（左栏逐项错峰、右栏整块淡进），互不牵连
        .animationDuration(this.isWide ? 0 : 220)
        .barBackgroundColor(Color.Transparent)
        .barFloatingStyle(this.floatingStyle())
        // 平板：布局盒整体加宽并左移，让盒中心 = 左栏中心（页签栏随之居中于左栏）；
        // 盒右边缘仍 = 屏幕右边缘，故内容不会被裁（见 barBoxWidth 注释）；窄屏两项分别退化为 100% / 0
        .width(this.barBoxWidth())
        .height('100%')
        .margin({ left: this.barBoxOffset() })
        .clip(false)
        // 切页过渡：新页面**即将显示**时先把它压到「淡入起点 + 下移 16vp」，
        // 下一帧再用弹簧曲线拉起。放在 willChange 而不是 onChange，是为了让第一帧就已经是起点，
        // 不会先满不透明度闪一下。返回 true = 允许切换。
        .onContentWillChange((currentIndex: number, comingIndex: number) => {
          if (comingIndex !== currentIndex) {
            this.preparePageEnter(comingIndex)
          }
          return true
        })
        .onChange((index: number) => {
          // 仅同步 currentIndex（点页签栏切换后由 Tabs 回传）
          this.currentIndex = index
        })
        // 切页只走页签栏：左右滑动切页已按用户要求移除（滑动易误触，且与平板左右两栏的拖拽冲突）
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .onAreaChange((oldArea: Area, newArea: Area) => {
        const w: number = newArea.width as number
        if (Math.abs(w - this.windowWidth) < 0.5) {
          return   // 面积没真变（切页签、弹出层都会触发一次）：直接返回，别让整页重算
        }
        this.windowWidth = w
        // 发布给三个检索页：它们首次显示时先拿到真实宽度，就不用「先按 0 排一遍再重排一遍」
        AppStorage.setOrCreate<number>('winWidth', w)
        const wide: boolean = this.windowWidth > 600
        if (wide && !this.isWide) {
          // 竖屏（会随滚动收起）切到平板双栏（常驻）→ 立刻把页签栏浮出来
          this.isWide = wide
          this.showBarIfHidden()
        } else {
          this.isWide = wide
        }
      })
    }
    .width('100%')
    .height('100%')
  }
}