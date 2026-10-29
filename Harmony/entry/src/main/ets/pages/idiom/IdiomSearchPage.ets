import { IdiomQuery, IdiomSearchMode, IdiomSearchService } from '../../service/IdiomSearchService'
import { IdiomItem } from '../../model/IdiomItem'
import { IDIOM_DB } from '../../data/idiom_db'
import { IdiomInputCell } from '../../components/IdiomInputCell'
import { IdiomResultCard } from '../../components/IdiomResultCard'
import { GlassButton } from '../../components/GlassButton'
import { SplitDivider } from '../../components/SplitDivider'
import { InfoButton } from '../../components/InfoButton'
import { Haptics } from '../../common/Haptics'
import { KeyCode } from '@kit.InputKit'

/**
 * 成语检索页
 *
 * 三组条件同时检索（声调 / 拼音 / 单字，自上而下排列）+ 留空通配 + 二次检索。
 * 一次检索会把 12 个输入框的内容全部算进去：同一位置填了多组条件时要求同时满足。
 * 结果三分支：唯一（完成所有检索）/ 多结果（列表 + 三键）/ 未找到。
 */

/** 三组输入框下方的说明（写成模块常量：@Builder 里直接读 getter 常量曾出现整行不渲染） */
const SUBTITLE_HINT: string = '三组可任意组合：同一位置填了多种时需同时满足，整组留空表示不限'

interface InputGroupOption {
  /** 分组名（声调 / 拼音 / 单字） */
  label: string
  /** 分组说明（写在名字右侧的小字） */
  hint: string
  /** 该组的输入模式：同时决定占位符、键盘类型与输入校验 */
  mode: IdiomSearchMode
}

@Component
export struct IdiomSearchPage {
  // v3.2：三组条件同时展示、同时生效，每组四位
  @State tones: string[] = ['', '', '', '']
  @State pinyins: string[] = ['', '', '', '']
  @State chars: string[] = ['', '', '', '']
  @State results: IdiomItem[] = []
  @State hasSearched: boolean = false
  @State searchCount: number = 0  // 检索次数（同步自 service.depth，@State 驱动 UI 刷新）
  @State windowWidth: number = 0  // 窗口宽度，用于断点判断（≤600 单栏，>600 双栏）
  // 窄屏专用：检索完成后把三组输入框收起来（只留一行条件摘要 + 按键），把屏幕空间让给结果；
  // 宽屏左栏与右栏并排本来就够用，不看这个标志
  @State inputsCollapsed: boolean = false
  // 双栏左右宽度比例（0~1，左栏占比），可拖动调节；用 AppStorage 共享给主页面 —— 平板页签栏据此水平居中于左栏
  @StorageLink('splitRatio') splitRatio: number = 0.5
  @StorageProp('topInset') topInset: number = 0  // 状态栏高度（vp），铺满边缘时避让系统图标
  @StorageProp('barInset') barInset: number = 0  // 悬浮页签栏占位高度（vp，Index 发布）：滚动内容底部留白，内容可从玻璃下方穿过
  @Prop @Watch('onUndoCmd') undoCmd: number = 0  // 系统返回手势指令：变化时执行「清空当前」
  onScrollOffset?: (yOffset: number) => void  // 滚动回调：Index 据此驱动悬浮页签栏下滚隐藏 / 上滚显示
  private service: IdiomSearchService = new IdiomSearchService(IDIOM_DB)

  // 显示顺序即自上而下的排列顺序：声调 → 拼音 → 单字
  private readonly GROUPS: InputGroupOption[] = [
    { label: '声调', hint: '每字 1~4', mode: IdiomSearchMode.TONE },
    { label: '拼音', hint: '完整拼音，也可只填声母 / 韵母', mode: IdiomSearchMode.PINYIN },
    { label: '单字', hint: '每字一个汉字', mode: IdiomSearchMode.CHAR }
  ]

  /**
   * 当前 12 个输入框组成的检索条件
   *
   * 写成普通方法而不是 getter：@Component struct 里的 getter 在真机上不会被调用，
   * 读出来是 undefined（点击「检索」直接 TypeError 闪退），方法调用才可靠。
   */
  private buildQuery(): IdiomQuery {
    return new IdiomQuery(this.tones.slice(), this.pinyins.slice(), this.chars.slice())
  }

  /** 取某组输入格的内容 */
  private valuesOf(mode: IdiomSearchMode): string[] {
    if (mode === IdiomSearchMode.TONE) {
      return this.tones
    }
    if (mode === IdiomSearchMode.PINYIN) {
      return this.pinyins
    }
    return this.chars
  }

  /**
   * 首次显示前先取真实窗口宽（Index 已发布到 AppStorage）
   *
   * 否则会「按 0 排一遍 → onAreaChange 改成真实宽度 → 再整页重排一遍」，
   * 首次切到本页时这一下正好卡在切页动画里，看着就是掉帧。
   */
  aboutToAppear(): void {
    const w: number | undefined = AppStorage.get<number>('winWidth')
    if (w !== undefined && w > 0) {
      this.windowWidth = w
    }
  }

  // ==================== 业务逻辑 ====================

  private onChangeInput(mode: IdiomSearchMode, index: number, value: string): void {
    this.valuesOf(mode)[index] = value
  }

  private onSearch(): void {
    const q: IdiomQuery = this.buildQuery()
    if (q.isEmpty) {
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
      this.results = this.service.search(q)
      this.hasSearched = true
      this.searchCount = this.service.depth
      // 窄屏：检索一有结果就折叠输入区，先让用户看到结果（点条件摘要条可随时展开改）
      this.inputsCollapsed = true
    })
  }

  private onClearAll(): void {
    this.service.reset()
    this.tones = ['', '', '', '']
    this.pinyins = ['', '', '', '']
    this.chars = ['', '', '', '']
    this.results = []
    this.hasSearched = false
    this.inputsCollapsed = false
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

      Blank(8)

      // 大标题右侧的「信息」按钮：应用说明与使用方法（三个检索页共用同一个对话框）
      InfoButton()
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .margin({ bottom: 16 })
  }

  // 一组输入格：左侧分组名 + 右侧说明小字，下面并排四个输入框
  // v3.2 起三组同时展示（声调 / 拼音 / 单字），不再手动切换
  /**
   * 已填条件的单行摘要（折叠检索框时显示在条件条上）
   *
   * 写成普通方法而非 getter：@Component struct 里的 getter 在真机上读出来是 undefined
   */
  private summaryText(): string {
    const parts: string[] = []
    for (let i = 0; i < 4; i++) {
      const seg: string[] = []
      if (this.tones[i].length > 0) {
        seg.push(`声 ${this.tones[i]}`)
      }
      if (this.pinyins[i].length > 0) {
        seg.push(`拼 ${this.pinyins[i]}`)
      }
      if (this.chars[i].length > 0) {
        seg.push(`字 ${this.chars[i]}`)
      }
      if (seg.length > 0) {
        parts.push(`第 ${i + 1} 位 ${seg.join(' ')}`)
      }
    }
    return parts.length > 0 ? parts.join(' · ') : '未填条件'
  }

  @Builder
  CollapsedBar() {
    Row() {
      Column() {
        Text('检索条件')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
        Blank(2)
        Text(this.summaryText())
          .fontSize(14)
          .fontWeight(500)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Row({ space: 2 }) {
        Text(this.inputsCollapsed ? '展开修改' : '收起')
          .fontSize(12)
          .fontColor($r('app.color.primary'))
        SymbolGlyph(this.inputsCollapsed ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_up'))
          .fontSize(13)
          .fontColor([$r('app.color.primary')])
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(56)
    .margin({ bottom: 12 })
    .padding({ left: 14, right: 14 })
    .borderRadius(14)
    .backgroundColor($r('app.color.cell_bg'))
    .border({ width: 1, color: $r('app.color.cell_border') })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      Haptics.tick()
      animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
        this.inputsCollapsed = !this.inputsCollapsed
      })
    })
  }

  @Builder
  InputGroup(group: InputGroupOption) {
    Column() {
      Row() {
        Text(group.label)
          .fontSize(13)
          .fontWeight(500)
          .fontColor($r('app.color.text_primary'))
        Blank(6)
        Text(group.hint)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 6 })

      this.InputCells(group)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: 12 })
  }

  @Builder
  InputCells(group: InputGroupOption) {
    // 间距用「每格自己的左右内边距」实现（不能用 Row 的 space，也不能给格子加外边距）：
    // 带 layoutWeight(1) 的子组件，其 margin、以及 Row 的 space **都不参与分宽**，
    // 于是整行会比容器宽出「间距总量」，最后一个格的右边框正好落到滚动容器裁剪边界之外
    // —— 表现就是「聚焦的输入框右侧像被挡住 / 缺一条边」
    Row() {
      ForEach([0, 1, 2, 3], (index: number) => {
        Column() {
          IdiomInputCell({
            value: this.valuesOf(group.mode)[index],
            mode: group.mode,
            groupKey: group.mode,
            index: index,
            onCellChange: (i: number, v: string) => {
              this.onChangeInput(group.mode, i, v)
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
    Text(SUBTITLE_HINT)
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
          // 窄屏折叠状态下条件一个字都没改，直接再检索等于白跑一次 —— 先把输入区展开让用户改
          if (this.inputsCollapsed && (this.windowWidth === 0 || this.windowWidth <= 600)) {
            animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
              this.inputsCollapsed = false
            })
            return
          }
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
          IdiomResultCard({
            item: this.results[0],
            toneInputs: this.tones,
            pinyinInputs: this.pinyins,
            charInputs: this.chars
          })
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
            IdiomResultCard({
              item: item,
              toneInputs: this.tones,
              pinyinInputs: this.pinyins,
              charInputs: this.chars
            })
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
        // 窄屏检索后有结果时常驻一行条件摘要：点它可在「展开输入区 / 收起」之间来回切换
        // （检索完成时自动处于收起态，把屏幕高度让给结果列表）
        if (this.hasSearched) {
          this.CollapsedBar()
        }
        if (!this.hasSearched || !this.inputsCollapsed) {
          this.InputGroup(this.GROUPS[0])
          this.InputGroup(this.GROUPS[1])
          this.InputGroup(this.GROUPS[2])
          this.Subtitle()
        }
        Blank(12)
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
            // minHeight 铺满视口：Scroll 默认把「比视口小的内容」垂直居中，
            // 折叠检索框后结果变少就会飘到屏幕中间，这里强制靠上对齐
            .constraintSize({ minHeight: '100%' })
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
            this.InputGroup(this.GROUPS[0])
            this.InputGroup(this.GROUPS[1])
            this.InputGroup(this.GROUPS[2])
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
      const w: number = newArea.width as number
      if (Math.abs(w - this.windowWidth) < 0.5) {
        return   // 面积没真变（切页签、弹出层都会触发一次）：直接返回，省一次整页重建
      }
      this.windowWidth = w
    })
  }
}