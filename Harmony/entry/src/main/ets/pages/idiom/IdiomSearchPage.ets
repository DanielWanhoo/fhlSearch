import { IdiomSearchMode, IdiomSearchService } from '../../service/IdiomSearchService'
import { IdiomItem } from '../../model/IdiomItem'
import { IDIOM_DB } from '../../data/idiom_db'
import { IdiomInputCell } from '../../components/IdiomInputCell'
import { IdiomResultCard } from '../../components/IdiomResultCard'
import { GlassButton } from '../../components/GlassButton'
import { SplitDivider } from '../../components/SplitDivider'
import { KeyCode } from '@kit.InputKit'

/**
 * 成语检索页
 *
 * 三模式检索（拼音 / 声调 / 单字）+ 留空通配 + 二次检索。
 * 结果三分支：唯一（完成所有检索）/ 多结果（列表 + 三键）/ 未找到。
 */

interface ModeOption {
  label: string
  mode: IdiomSearchMode
}

@Component
export struct IdiomSearchPage {
  @State mode: IdiomSearchMode = IdiomSearchMode.PINYIN
  @State inputs: string[] = ['', '', '', '']
  @State results: IdiomItem[] = []
  @State hasSearched: boolean = false
  @State searchCount: number = 0  // 检索次数（同步自 service.depth，@State 驱动 UI 刷新）
  @State windowWidth: number = 0  // 窗口宽度，用于断点判断（≤600 单栏，>600 双栏）
  // 双栏左右宽度比例（0~1，左栏占比），可拖动调节；用 AppStorage 共享给主页面 —— 平板页签栏据此水平居中于左栏
  @StorageLink('splitRatio') splitRatio: number = 0.5
  @StorageProp('topInset') topInset: number = 0  // 状态栏高度（vp），铺满边缘时避让系统图标
  @StorageProp('barInset') barInset: number = 0  // 悬浮页签栏占位高度（vp，Index 发布）：滚动内容底部留白，内容可从玻璃下方穿过
  @Prop @Watch('onUndoCmd') undoCmd: number = 0  // 系统返回手势指令：变化时执行「清空当前」
  onScrollOffset?: (yOffset: number) => void  // 滚动回调：Index 据此驱动悬浮页签栏下滚隐藏 / 上滚显示
  private service: IdiomSearchService = new IdiomSearchService(IDIOM_DB)

  private readonly MODES: ModeOption[] = [
    { label: '拼音', mode: IdiomSearchMode.PINYIN },
    { label: '声调', mode: IdiomSearchMode.TONE },
    { label: '单字', mode: IdiomSearchMode.CHAR }
  ]

  private get subtitle(): string {
    if (this.mode === IdiomSearchMode.PINYIN) {
      return '输入完整拼音，或只填声母/韵母模糊匹配（如 c、ang），留空表示任意'
    }
    if (this.mode === IdiomSearchMode.TONE) {
      return '输入每字声调（1~4），如 4 4 2 1，留空表示任意'
    }
    return '输入每字汉字，如 暗 渡 陈 仓，留空表示任意'
  }

  // ==================== 业务逻辑 ====================

  private onChangeInput(index: number, value: string): void {
    this.inputs[index] = value
  }

  private isAllEmpty(): boolean {
    return this.inputs.every((s: string) => s.trim() === '')
  }

  private onModeChange(next: IdiomSearchMode): void {
    if (this.mode === next) {
      return
    }
    this.mode = next
    // 切换模式只清空输入格（输入格式不同），保留已有检索结果与检索历史
    this.inputs = ['', '', '', '']
  }

  private onSearch(): void {
    if (this.isAllEmpty()) {
      AlertDialog.show({
        title: '请填写检索条件',
        message: '请至少填写一个格子，留空的格子表示任意匹配',
        confirm: {
          value: '确定',
          action: () => {}
        }
      })
      return
    }
    // 结果入场：卡片错峰淡入上滑（见 ResultArea 中各卡片的 transition）
    animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
      this.results = this.service.search(this.mode, this.inputs)
      this.hasSearched = true
      this.searchCount = this.service.depth
    })
  }

  private onClearAll(): void {
    this.service.reset()
    this.inputs = ['', '', '', '']
    this.results = []
    this.hasSearched = false
    this.searchCount = this.service.depth
  }

  private onUndo(): void {
    this.results = this.service.undo()
    this.searchCount = this.service.depth
    if (this.service.depth === 0) {
      this.results = []
      this.hasSearched = false
    }
  }

  // 系统返回手势指令：执行「清空当前」（撤销一步检索）
  onUndoCmd(): void {
    this.onUndo()
  }

  // ==================== UI 片段 ====================

  @Builder
  Header() {
    Row() {
      Column() {
        Text('山石雅集第14题')
          .fontSize(24)
          .fontWeight(600)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 4 })
        Text('按拼音 / 声调 / 单字检索成语')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(`检索 ${this.searchCount} 次`)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .margin({ bottom: 16 })
  }

  // 模式切换（拼音 / 声调 / 单字）——「沉浸光感」玻璃分段控件：
  // 整条为一块系统材质玻璃底（与页签栏/玻璃按钮同一套材质语言），选中项是一枚主色玻璃胶囊
  @Builder
  ModeSwitcher() {
    Row() {
      ForEach(this.MODES, (opt: ModeOption) => {
        Text(opt.label)
          .fontSize(15)
          .fontWeight(500)
          .fontColor(this.mode === opt.mode ? $r('app.color.on_primary') : $r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .height(36)
          .layoutWeight(1)
          .borderRadius(11)
          .backgroundColor(this.mode === opt.mode ? $r('app.color.glass_primary') : Color.Transparent)
          .border({
            width: 1,
            color: this.mode === opt.mode ? $r('app.color.glass_primary_edge') : Color.Transparent,
            style: BorderStyle.Solid
          })
          .animation({ duration: 180, curve: Curve.FastOutSlowIn })
          .accessibilityText(`${opt.label}检索模式`)
          .accessibilityDescription(this.mode === opt.mode ? '已选中' : '未选中，点击切换')
          .onClick(() => {
            this.onModeChange(opt.mode)
          })
      }, (opt: ModeOption) => opt.mode)
    }
    .width('100%')
    .padding(3)
    .borderRadius(14)
    // 沉浸光感：系统材质玻璃底（实时折射背后内容、跟随系统深浅色）+ 整圈 1vp 发丝描边
    .backgroundColor($r('app.color.glass_bg'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK, {
      colorMode: ThemeColorMode.SYSTEM,
      adaptiveColor: AdaptiveColor.AVERAGE
    })
    .border({ width: 1, color: $r('app.color.glass_edge'), style: BorderStyle.Solid })
  }

  @Builder
  InputCells() {
    // 间距用「每格自己的左右内边距」实现（不能用 Row 的 space，也不能给格子加外边距）：
    // 带 layoutWeight(1) 的子组件，其 margin、以及 Row 的 space **都不参与分宽**，
    // 于是整行会比容器宽出「间距总量」，最后一个格的右边框正好落到滚动容器裁剪边界之外
    // —— 表现就是「聚焦的输入框右侧像被挡住 / 缺一条边」
    Row() {
      ForEach([0, 1, 2, 3], (index: number) => {
        Column() {
          IdiomInputCell({
            value: this.inputs[index],
            mode: this.mode,
            index: index,
            onCellChange: (i: number, v: string) => {
              this.onChangeInput(i, v)
            }
          })
        }
        .layoutWeight(1)
        .padding({ left: index === 0 ? 0 : 4, right: index === 3 ? 0 : 4 })
      }, (index: number) => index.toString())
    }
    .width('100%')
  }

  @Builder
  Subtitle() {
    Text(this.subtitle)
      .fontSize(13)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .textAlign(TextAlign.Center)
  }

  // 检索主按钮（沉浸光感·主色玻璃）
  @Builder
  SearchButton() {
    Row() {
      GlassButton({ label: '检索', primary: true, desc: '按当前输入条件执行检索，留空的格子表示任意匹配', action: () => {
        this.onSearch()
      } })
    }
    .width('100%')
  }

  // 检索后的三键（沉浸光感玻璃）：清空所有 / 清空当前 / 二次检索（多结果时）
  @Builder
  ActionButtons() {
    Row({ space: 8 }) {
      GlassButton({ label: '清空所有', primary: false, desc: '清空输入与全部检索历史，回到初始状态', action: () => {
        this.onClearAll()
      } })
      GlassButton({ label: '清空当前', primary: false, desc: '撤销当前这次检索，回到上一级检索结果', action: () => {
        this.onUndo()
      } })
      if (this.results.length >= 2) {
        GlassButton({ label: '二次检索', primary: true, desc: '在上一次结果范围内继续检索', action: () => {
          this.onSearch()
        } })
      }
    }
    .width('100%')
  }

  @Builder
  ResultArea() {
    Column() {
      if (this.results.length === 0) {
        // 未找到（空状态：图标 + 文案）
        Column() {
          SymbolGlyph($r('sys.symbol.book'))
            .fontSize(40)
            .fontColor([$r('app.color.text_secondary')])
          Blank(12)
          Text('未找到该成语')
            .fontSize(18)
            .fontWeight(600)
            .fontColor($r('app.color.text_primary'))
          Blank(8)
          Text('请调整检索条件后重试')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .padding({ top: 40 })
      } else if (this.results.length === 1) {
        // 唯一结果：完成所有检索（卡片弹入）
        Column() {
          Text('完成所有检索')
            .fontSize(14)
            .fontWeight(600)
            .fontColor($r('app.color.match_highlight'))
          Blank(12)
          IdiomResultCard({ item: this.results[0], inputs: this.inputs })
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.scale({ x: 0.9, y: 0.9 }))
              .animation({ duration: 250, curve: Curve.EaseOut }))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      } else {
        // 多结果：列表（三键已移到页面底部固定栏，避免被悬浮导航遮挡）
        // 卡片错峰入场：每张延迟 45ms 依次淡入上滑
        Column() {
          Text(`匹配结果 (${this.results.length})`)
            .fontSize(16)
            .fontWeight(500)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .margin({ bottom: 8 })

          ForEach(this.results, (item: IdiomItem, idx: number) => {
            IdiomResultCard({ item: item, inputs: this.inputs })
              .margin({ bottom: 8 })
              .transition(TransitionEffect.OPACITY
                .combine(TransitionEffect.translate({ y: 16 }))
                .animation({ duration: 250, curve: Curve.EaseOut, delay: idx * 45 }))
          }, (item: IdiomItem) => item.word)
        }
        .width('100%')
      }
    }
    .width('100%')
  }

  // ==================== 页面构建 ====================

  @Builder
  NarrowLayout() {
    Column() {
      Column() {
        this.Header()
        this.ModeSwitcher()
        Blank(12)
        this.InputCells()
        Blank(6)
        this.Subtitle()
        Blank(14)
        // 「检索」按钮与检索后的三键共用同一位置：检索开始后按钮就地换成三键（不再另设底部操作栏）
        if (this.hasSearched) {
          this.ActionButtons()
        } else {
          this.SearchButton()
        }
        Blank(12)

        if (this.hasSearched) {
          Scroll() {
            // 底部留白 = 悬浮页签栏高度：结果列表能一直滚到页签栏上方，其余内容从玻璃材质下方穿过
            Column() {
              this.ResultArea()
            }
            .width('100%')
            .padding({ bottom: this.barInset })
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .onScrollFrameBegin((offset: number) => {
            // 交给主页面驱动悬浮页签栏「下滚隐藏 / 上滚显示」
            this.onScrollOffset?.(offset)
            return { offsetRemain: offset }
          })
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 16, right: 16, top: this.topInset + 16 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  WideLayout() {
    Row() {
      // 左栏：检索输入区（靠上对齐，与诗词/名士页一致；窗口矮时可上下滚动）
      Column() {
        Scroll() {
          Column() {
            this.Header()
            this.ModeSwitcher()
            Blank(16)
            this.InputCells()
            Blank(8)
            this.Subtitle()
            Blank(16)
            // 与窄屏一致：「检索」按钮位置在检索开始后换成三键
            if (this.hasSearched) {
              this.ActionButtons()
            } else {
              this.SearchButton()
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          // minHeight 铺满视口：Scroll 默认会把「比视口小的子组件」垂直居中，这里靠上对齐；
          // 内容超过一屏时 Column 自然变高，照常可以滚动
          .constraintSize({ minHeight: '100%' })
          // 页签栏避让留白放在**可滚动内容内部**（放容器上会留出一条空白带、把内容切断）；
          // 滚动时内容可从页签栏玻璃下方穿过，滚到底最后一行恰好停在页签栏上方
          .padding({ bottom: this.barInset + 24 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .onScrollFrameBegin((offset: number) => {
          this.onScrollOffset?.(offset)
          return { offsetRemain: offset }
        })
      }
      .layoutWeight(this.splitRatio)
      .height('100%')
      // 底部预留悬浮页签栏高度（平板页签栏居中于左栏），左栏内容不会被玻璃盖住
      // 注意：容器**不留**底部避让，留白在滚动内容内部（否则页签栏附近会出现一条空白带）
      .padding({ left: 24, right: 16, top: this.topInset + 24 })

      // 可拖动分栏分隔条：拖动调整左右两栏宽度比例
      SplitDivider({
        ratio: this.splitRatio,
        totalWidth: this.windowWidth,
        onRatioChange: (r: number) => {
          this.splitRatio = r
        }
      })

      // 右栏：检索结果区
      Column() {
        if (this.hasSearched) {
          Scroll() {
            // 底部留白 = 悬浮页签栏高度：结果列表能一直滚到页签栏上方，其余内容从玻璃材质下方穿过
            Column() {
              this.ResultArea()
            }
            .width('100%')
            .padding({ bottom: this.barInset })
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .onScrollFrameBegin((offset: number) => {
            // 交给主页面驱动悬浮页签栏「下滚隐藏 / 上滚显示」
            this.onScrollOffset?.(offset)
            return { offsetRemain: offset }
          })
        } else {
          Column() {
            SymbolGlyph($r('sys.symbol.book'))
              .fontSize(36)
              .fontColor([$r('app.color.text_secondary')])
            Blank(10)
            Text('填写检索条件后点击「检索」')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          // 空状态提示同样抬高到悬浮页签栏之上，避免贴到屏幕底边被裁切
          .padding({ bottom: this.barInset })
        }
      }
      .layoutWeight(1 - this.splitRatio)
      .height('100%')
      .padding({ left: 16, right: 24, top: this.topInset + 24 })
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Column() {
      if (this.windowWidth === 0 || this.windowWidth <= 600) {
        this.NarrowLayout()
      } else {
        this.WideLayout()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
    .onKeyEvent((event: KeyEvent) => {
      if (event.type !== KeyType.Down) {
        return false
      }
      // 回车键：执行检索 / 二次检索
      if (event.keyCode === KeyCode.KEYCODE_ENTER) {
        this.onSearch()
        return true
      }
      // Esc 键：清空当前（撤销一步检索）
      if (event.keyCode === KeyCode.KEYCODE_ESCAPE) {
        this.onUndo()
        return true
      }
      return false
    })
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.windowWidth = newArea.width as number
    })
  }
}