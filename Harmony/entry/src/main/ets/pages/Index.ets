import { IdiomSearchPage } from './idiom/IdiomSearchPage'
import { PoetrySearchPage } from './poetry/PoetrySearchPage'
import { MingziSearchPage } from './mingzi/MingziSearchPage'
import { SymbolGlyphModifier, window } from '@kit.ArkUI'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { HdsAnimationMode, HdsTabs, HdsTabsController, HdsTabsFloatingStyle } from '@kit.UIDesignKit'
import { MaterialUtil } from '../common/MaterialUtil'
import { Haptics } from '../common/Haptics'

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
  private controller: HdsTabsController = new HdsTabsController()      // 竖屏：底部悬浮页签栏
  // 滚动回调提成字段：每帧都传给三个检索页，现造箭头函数会让子组件每次 build 都拿到“新参数”
  private scrollHandler: (y: number) => void = (y: number) => { this.onPageScroll(y) }
  private isBarHidden: boolean = false  // 页签栏是否已随滚动收起
  private readonly dockTabs: DockTab[] = [
    { label: '成语检索', symbol: $r('sys.symbol.book') },
    { label: '诗词检索', symbol: $r('sys.symbol.square_grid_2x2') },
    { label: '名士检索', symbol: $r('sys.symbol.person_2') }
  ]

  // 页面加载后（窗口已就绪）读取真实安全区高度，存入 AppStorage，
  // 供本页页签栏离底避让与子页面标题「铺满到屏幕边缘」时避让系统栏图标。
  // 注意：EntryAbility 的 onWindowStageCreate 阶段窗口未就绪，getWindowAvoidArea 会返回 0。
  aboutToAppear(): void {
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
    const key: string = `${this.isWide}|${this.bottomInset}|${Math.round(this.windowWidth)}|${this.splitRatio.toFixed(3)}`
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
            IdiomSearchPage({ undoCmd: this.idiomUndoCmd, onScrollOffset: this.scrollHandler })
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
        IdiomSearchPage({ undoCmd: this.idiomUndoCmd, onScrollOffset: this.scrollHandler })
      }
    }
    .tabBar(this.tabBarStyle(0))

    TabContent() {
      if (this.isWide) {
        Column() {
          Column() {
            PoetrySearchPage({ clearCmd: this.poetryClearCmd, onScrollOffset: this.scrollHandler })
          }
          .width(this.contentWidth())
          .height('100%')
          .translate({ x: this.contentShift() })
        }
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.Start)
      } else {
        PoetrySearchPage({ clearCmd: this.poetryClearCmd, onScrollOffset: this.scrollHandler })
      }
    }
    .tabBar(this.tabBarStyle(1))

    TabContent() {
      if (this.isWide) {
        Column() {
          Column() {
            MingziSearchPage({ undoCmd: this.mingziUndoCmd, onScrollOffset: this.scrollHandler })
          }
          .width(this.contentWidth())
          .height('100%')
          .translate({ x: this.contentShift() })
        }
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.Start)
      } else {
        MingziSearchPage({ undoCmd: this.mingziUndoCmd, onScrollOffset: this.scrollHandler })
      }
    }
    .tabBar(this.tabBarStyle(2))
  }


  build() {
    Column() {
      // 手机竖屏 / 平板横屏统一使用底部悬浮页签栏（HDS 沉浸光感材质）
      // 内容铺满整屏：检索内容一直滚到页签栏上方，其余部分从玻璃材质下方穿过
      HdsTabs({ barPosition: BarPosition.End, index: this.currentIndex, controller: this.controller }) {
        this.TabsContent()
      }
      .barOverlap(true)
      // ⚠️ 自带的「左右滑动切页」关掉（原因见下面的 PanGesture）：
      // 它的拖动过渡会把整页做成带透视的斜切/缩放，慢拖时画面又歪又抖 —— 这就是用户反馈的「一顿一顿」。
      // 现在改为「自己的横向手势 → 改 currentIndex」，走的是点页签那条干净的横向滑动过渡。
      .scrollable(false)
      .animationDuration(220)   // 切页滑动时长：300 → 220，缩短「整页在动」的高开销窗口
      .barBackgroundColor(Color.Transparent)
      .barFloatingStyle(this.floatingStyle())
      // 平板：布局盒整体加宽并左移，让盒中心 = 左栏中心（页签栏随之居中于左栏）；
      // 盒右边缘仍 = 屏幕右边缘，故内容不会被裁（见 barBoxWidth 注释）；窄屏两项分别退化为 100% / 0
      .width(this.barBoxWidth())
      .height('100%')
      .margin({ left: this.barBoxOffset() })
      .clip(false)
      .onChange((index: number) => {
        // 仅同步 currentIndex（点页签栏、或下面的手势改 currentIndex 都会走到这里）
        this.currentIndex = index
      })
      // 手机上的「左右滑动切页」：只认横向、够 60vp 才切，切页走点页签那套干净过渡。
      // 平板不加（左右两栏 + 分栏分隔条，滑动容易误触）。
      .gesture(
        PanGesture({ direction: PanDirection.Horizontal, distance: 30 })
          .onActionEnd((event: GestureEvent) => {
            if (this.isWide) {
              return
            }
            const dx: number = event.offsetX
            if (Math.abs(dx) < 60) {
              return
            }
            const next: number = dx < 0 ? this.currentIndex + 1 : this.currentIndex - 1
            if (next >= 0 && next < this.dockTabs.length && next !== this.currentIndex) {
              Haptics.tick()
              this.currentIndex = next
            }
          })
      )
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.background'))
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
}