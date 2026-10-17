import { MingziItem } from '../../model/MingziItem'
import { MingziSearchMode, MingziSearchService } from '../../service/MingziSearchService'
import { MINGZI_DB } from '../../data/mingzi_db'
import { MingziResultCard } from '../../components/MingziResultCard'
import { GlassButton } from '../../components/GlassButton'
import { Haptics } from '../../common/Haptics'
import { SplitDivider } from '../../components/SplitDivider'
import { KeyCode } from '@kit.InputKit'

/**
 * 名士检索页
 *
 * 9 种检索模式：朝代/爱好/社团/品阶（菜单选项）+ 职业/生逢/出身·身世/技能/其他描述（输入·模糊匹配）。
 * 模式以列表呈现（避免图标挤占）；结果三分支：唯一（完成检索）/ 多结果（三键）/ 未检索到。
 * 三键（清空所有 / 清空当前 / 二次检索）位于页面**上方**、检索条件之下，结果列表之前。
 * 支持二次检索（基于当前结果继续过滤）、返回上一级检索、清空所有检索。
 */

interface ModeDef {
  label: string
  mode: MingziSearchMode
  isMenu: boolean
}

interface SearchStep {
  mode: MingziSearchMode
  query: string
  label: string
}

interface Seg {
  text: string
  hit: boolean
}

@Component
export struct MingziSearchPage {
  @State results: MingziItem[] = []
  @State hasSearched: boolean = false
  @State searchCount: number = 0  // 检索次数（清空所有检索时清零）
  @State steps: SearchStep[] = []  // 已应用检索步骤（面包屑 + 返回上一级依据）
  @State selectedValues: string[] = ['', '', '', '', '', '', '', '', '']  // 各模式当前已选选项（与 MODES 顺序对应）
  @State detailItem: MingziItem = new MingziItem()  // 详情对话框展示的名士
  @State detailQueries: string[] = []  // 详情对话框高亮用的检索关键词
  // 注意：@CustomDialog 组件不能在字段中 new 实例，须在 controller builder 内构造（避免 controller 未绑定崩溃）
  private detailDialogCtrl: CustomDialogController = new CustomDialogController({
    builder: MingziDetailDialog({
      item: $detailItem,
      queries: $detailQueries
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: true
  })
  @State showInputSheet: boolean = false  // 输入模式底部面板
  @State inputMode: MingziSearchMode = MingziSearchMode.OCCUPATION  // 当前输入模式
  @State inputValue: string = ''  // 输入面板中的关键词
  @State windowWidth: number = 0  // 窗口宽度，用于断点判断（≤600 单栏，>600 双栏）
  // 双栏左右宽度比例（0~1，左栏占比），可拖动调节；用 AppStorage 共享给主页面 —— 平板页签栏据此水平居中于左栏
  @StorageLink('splitRatio') splitRatio: number = 0.5
  @StorageProp('topInset') topInset: number = 0
  @StorageProp('barInset') barInset: number = 0  // 悬浮页签栏占位高度（vp，Index 发布）：滚动内容底部留白，内容可从玻璃下方穿过
  @Prop @Watch('onUndoCmd') undoCmd: number = 0  // 系统返回手势指令：变化时执行「返回上一级检索」
  onScrollOffset?: (yOffset: number) => void  // 滚动回调：Index 据此驱动悬浮页签栏下滚隐藏 / 上滚显示
  private service: MingziSearchService = new MingziSearchService(MINGZI_DB)
  private scroller: Scroller = new Scroller()

  // 菜单选项顺序：朝代按时间序（梦排最末）；爱好/社团按首字拼音 A~Z（乐舞的乐读 yuè，排 Y 组弈棋之后）
  private readonly DYNASTY_OPTIONS: string[] = ['先秦', '秦', '西楚', '汉', '三国', '晋', '南北朝', '唐', '五代十国', '宋', '辽', '元', '明', '清', '梦']
  private readonly HOBBY_OPTIONS: string[] = ['博文', '品茗', '赏玩', '食珍', '书画', '雅宴', '演武', '弈棋', '乐舞', '妆饰']
  private readonly GROUP_OPTIONS: string[] = ['百家书院', '金戈馆', '千工苑', '容华社', '棠梨坊', '饕餮居', '无', '五湖商社', '逸趣社']
  private readonly RANK_OPTIONS: string[] = ['天', '地', '玄']

  private readonly MODES: ModeDef[] = [
    { label: '朝代', mode: MingziSearchMode.DYNASTY, isMenu: true },
    { label: '爱好', mode: MingziSearchMode.HOBBY, isMenu: true },
    { label: '社团', mode: MingziSearchMode.GROUP, isMenu: true },
    { label: '品阶', mode: MingziSearchMode.RANK, isMenu: true },
    { label: '职业', mode: MingziSearchMode.OCCUPATION, isMenu: false },
    { label: '生逢（生于…）', mode: MingziSearchMode.BORN, isMenu: false },
    { label: '出身/身世', mode: MingziSearchMode.ORIGIN, isMenu: false },
    { label: '技能', mode: MingziSearchMode.SKILL, isMenu: false },
    { label: '其他描述', mode: MingziSearchMode.DESC, isMenu: false }
  ]

  // ==================== 业务逻辑 ====================

  private modeLabel(mode: MingziSearchMode): string {
    switch (mode) {
      case MingziSearchMode.DYNASTY:
        return '朝代'
      case MingziSearchMode.HOBBY:
        return '爱好'
      case MingziSearchMode.GROUP:
        return '社团'
      case MingziSearchMode.RANK:
        return '品阶'
      case MingziSearchMode.OCCUPATION:
        return '职业'
      case MingziSearchMode.BORN:
        return '生逢'
      case MingziSearchMode.ORIGIN:
        return '出身/身世'
      case MingziSearchMode.SKILL:
        return '技能'
      case MingziSearchMode.DESC:
        return '其他描述'
      default:
        return ''
    }
  }

  /** 模式在 MODES 数组中的索引（与 selectedValues 对齐） */
  private modeIndex(mode: MingziSearchMode): number {
    for (let i = 0; i < this.MODES.length; i++) {
      if (this.MODES[i].mode === mode) {
        return i
      }
    }
    return 0
  }

  /** 当前模式已选选项（空串表示未选） */
  private selectedOf(mode: MingziSearchMode): string {
    return this.selectedValues[this.modeIndex(mode)]
  }

  private optionsFor(mode: MingziSearchMode): string[] {
    if (mode === MingziSearchMode.DYNASTY) {
      return this.DYNASTY_OPTIONS
    }
    if (mode === MingziSearchMode.HOBBY) {
      return this.HOBBY_OPTIONS
    }
    if (mode === MingziSearchMode.GROUP) {
      return this.GROUP_OPTIONS
    }
    if (mode === MingziSearchMode.RANK) {
      return this.RANK_OPTIONS
    }
    return []
  }

  private inputPlaceholder(mode: MingziSearchMode): string {
    if (mode === MingziSearchMode.OCCUPATION) {
      return '请输入职业，如：帝王、诗人'
    }
    if (mode === MingziSearchMode.BORN) {
      return '请输入生逢（生于…）描述，如：乱世'
    }
    if (mode === MingziSearchMode.ORIGIN) {
      return '请输入出身/身世，如：出身显贵'
    }
    if (mode === MingziSearchMode.SKILL) {
      return '请输入技能，如：剑舞者'
    }
    return '请输入其他描述，如：诗仙'
  }

  private hasHan(s: string): boolean {
    for (let i = 0; i < s.length; i++) {
      const code = s.charCodeAt(i)
      if (code >= 0x4E00 && code <= 0x9FFF) {
        return true
      }
    }
    return false
  }

  /** 全部已应用的检索关键词（用于详情高亮） */
  private keyQueries(): string[] {
    return this.steps.map((s: SearchStep) => s.query)
  }

  private openDetail(item: MingziItem): void {
    this.detailItem = item
    this.detailQueries = this.keyQueries()
    this.detailDialogCtrl.open()
  }

  private onOpenInput(mode: MingziSearchMode): void {
    this.inputMode = mode
    this.inputValue = ''
    this.showInputSheet = true
  }

  /**
   * 菜单模式选定：只**记录**条件（行内绿色显示），不立即检索
   * —— 由用户点「检索」或「二次检索」时才真正执行（新一轮交互约定）
   */
  private onMenuSelect(mode: MingziSearchMode, opt: string): void {
    this.stage(mode, opt)
  }

  /** 把条件写入对应模式行，等待用户点「检索 / 二次检索」应用 */
  private stage(mode: MingziSearchMode, value: string): void {
    this.selectedValues[this.modeIndex(mode)] = value
  }

  /**
   * 打开菜单模式的「文本滑动选择器」弹窗（系统 TextPicker 对话框：UIContext.showTextPickerDialog）
   *
   * - range = 当前模式的选项列表（朝代按时间序、爱好/社团按拼音序、品阶「天/地/玄」）
   * - 默认停在「该模式当前已选的选项」上，改选时不用重新滑一大截
   * - 只有点「确定」才执行检索；单纯滑动不会触发，避免误触
   * - 文字/按钮样式全部取 base-dark 成对颜色资源，随系统深浅色自动切换
   * - enableHapticFeedback = 滚动滚轮每换一项轻微震动一次（触感刻度）
   *   该能力由系统 Picker 组件内部触发，前提是 module.json5 已声明 ohos.permission.VIBRATE
   */
  private openOptionPicker(mode: MingziSearchMode): void {
    const options: string[] = this.optionsFor(mode)
    if (options.length === 0) {
      return
    }
    const selectedIndex: number = options.indexOf(this.selectedOf(mode))
    this.getUIContext().showTextPickerDialog({
      range: options,
      selected: selectedIndex >= 0 ? selectedIndex : 0,
      defaultPickerItemHeight: 40,
      canLoop: true,
      // 震动反馈：滚轮每滑过一项触发一次系统触感（依赖 module.json5 的 VIBRATE 权限）
      enableHapticFeedback: true,
      backgroundColor: $r('app.color.card_bg'),
      textStyle: { color: $r('app.color.text_primary'), font: { size: 17 } },
      selectedTextStyle: { color: $r('app.color.primary'), font: { size: 20, weight: FontWeight.Medium } },
      disappearTextStyle: { color: $r('app.color.text_secondary'), font: { size: 15 } },
      acceptButtonStyle: { fontColor: $r('app.color.primary'), fontSize: 16, fontWeight: FontWeight.Medium },
      cancelButtonStyle: { fontColor: $r('app.color.text_secondary'), fontSize: 16 },
      onAccept: (result: TextPickerResult) => {
        const value: string = result.value as string
        if (value.length > 0) {
          this.onMenuSelect(mode, value)
        }
      }
    })
  }

  private confirmInput(): void {
    const v = this.inputValue.trim()
    if (v === '') {
      AlertDialog.show({
        title: '请填写检索内容',
        message: `请输入${this.modeLabel(this.inputMode)}关键词`,
        confirm: {
          value: '确定',
          action: () => {}
        }
      })
      return
    }
    if (!this.hasHan(v)) {
      AlertDialog.show({
        title: '请输入中文关键词',
        message: '检索会忽略标点符号、空格等非汉字字符',
        confirm: {
          value: '确定',
          action: () => {}
        }
      })
      return
    }
    this.showInputSheet = false
    // 同样只记录条件，等用户点「检索 / 二次检索」
    this.stage(this.inputMode, v)
  }

  /** 某模式**已应用**的检索条件（尚未应用过则返回空串） */
  private appliedQueryOf(mode: MingziSearchMode): string {
    for (const s of this.steps) {
      if (s.mode === mode) {
        return s.query
      }
    }
    return ''
  }

  /** 当前已填写的全部条件（按页面从上到下的模式顺序，空条件跳过） */
  private stagedSteps(): SearchStep[] {
    const staged: SearchStep[] = []
    for (const def of this.MODES) {
      const v: string = this.selectedOf(def.mode)
      if (v.length > 0) {
        staged.push({ mode: def.mode, query: v, label: `${def.label}：${v}` })
      }
    }
    return staged
  }

  /** 已填写但**尚未应用**（或与已应用值不同）的条件 —— 二次检索的依据 */
  private pendingSteps(): SearchStep[] {
    const pending: SearchStep[] = []
    for (const def of this.MODES) {
      const v: string = this.selectedOf(def.mode)
      if (v.length > 0 && v !== this.appliedQueryOf(def.mode)) {
        pending.push({ mode: def.mode, query: v, label: `${def.label}：${v}` })
      }
    }
    return pending
  }

  /**
   * 按给定条件（有序）重建检索：重置候选集后依次叠加，结果与「已检索」面包屑同步刷新
   * @param next 本轮要应用的全部条件
   */
  private applySteps(next: SearchStep[]): void {
    this.service.reset()
    let res: MingziItem[] = []
    for (const s of next) {
      res = this.service.search(s.mode, s.query)
    }
    this.results = res
    this.steps = next
    this.searchCount = this.service.depth
    this.hasSearched = next.length > 0
  }

  /** 大「检索」键：按当前填写的全部条件开始检索（检索开始后该键自动隐藏） */
  private onStartSearch(): void {
    const staged: SearchStep[] = this.stagedSteps()
    if (staged.length === 0) {
      AlertDialog.show({
        title: '请先填写检索条件',
        message: '请先选择或输入至少一个条件，再点击「检索」',
        confirm: {
          value: '知道了',
          action: () => {}
        }
      })
      return
    }
    // 结果入场：错峰淡入上滑（见 ResultArea 中各卡片 transition）
    animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
      this.applySteps(staged)
    })
  }

  private onUndo(): void {
    this.results = this.service.undo()
    this.searchCount = this.service.depth
    if (this.steps.length > 0) {
      const step = this.steps[this.steps.length - 1]
      this.steps.pop()
      const idx = this.modeIndex(step.mode)
      if (this.selectedValues[idx] === step.query) {
        this.selectedValues[idx] = ''
      }
    }
    if (this.service.depth === 0) {
      this.results = []
      this.hasSearched = false
    }
  }

  private onClearAll(): void {
    this.service.reset()
    this.results = []
    this.hasSearched = false
    this.searchCount = this.service.depth
    this.steps = []
    this.selectedValues = ['', '', '', '', '', '', '', '', '']
  }

  /**
   * 「二次检索」键：把**新填写的条件**叠加到上一次检索的结果之上
   *
   * - 只应用「已填写但尚未应用（或与已应用值不同）」的条件，已生效的条件保持不动
   * - 同一模式改选（例如把「朝代：先秦」改成「朝代：汉」）= 替换该条件，而不是与旧值求交集
   * - 合并后按页面从上到下的模式顺序排好，保证叠加顺序稳定、结果可复现
   */
  private onSecondSearch(): void {
    const pending: SearchStep[] = this.pendingSteps()
    if (pending.length === 0) {
      AlertDialog.show({
        title: '请先填写新的检索条件',
        message: '请在下方选择或输入一个与上次不同的条件，再点击「二次检索」',
        confirm: {
          value: '知道了',
          action: () => {}
        }
      })
      return
    }
    // 被新条件覆盖的旧条件先剔除
    const kept: SearchStep[] = []
    for (const s of this.steps) {
      let replaced: boolean = false
      for (const p of pending) {
        if (p.mode === s.mode) {
          replaced = true
        }
      }
      if (!replaced) {
        kept.push(s)
      }
    }
    // 合并后按模式顺序重排
    const merged: SearchStep[] = []
    for (const def of this.MODES) {
      for (const p of pending) {
        if (p.mode === def.mode) {
          merged.push(p)
        }
      }
      for (const k of kept) {
        if (k.mode === def.mode) {
          merged.push(k)
        }
      }
    }
    animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
      this.applySteps(merged)
    })
  }

  // 系统返回手势指令：执行「返回上一级检索」
  onUndoCmd(): void {
    this.onUndo()
  }

  // ==================== UI 片段 ====================

  @Builder
  Header() {
    Row() {
      Column() {
        Text('众里寻他')
          .fontSize(24)
          .fontWeight(600)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 4 })
        Text(this.hasSearched ? '继续填写条件，点「二次检索」在上次结果中细查' : '选择或输入条件后，点「检索」开始检索')
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

  /**
   * 首次检索键：条件填好后点它开始检索
   * 检索开始后自动隐藏（由三键接手），「清空所有」回到初始状态时重新出现
   */
  @Builder
  SearchButton() {
    Row() {
      GlassButton({ label: '检索', primary: true, desc: '按已填写的条件开始检索', action: () => {
        this.onStartSearch()
      } })
    }
    .width('100%')
  }

  @Builder
  CriteriaBar() {
    if (this.hasSearched && this.steps.length > 0) {
      Row() {
        Text('已检索：')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        Text(this.steps.map((s: SearchStep) => s.label).join('  →  '))
          .fontSize(12)
          .fontColor($r('app.color.primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 10 })
    }
  }

  @Builder
  MenuModeRow(def: ModeDef) {
    Row() {
      Text(def.label)
        .fontSize(15)
        .fontWeight(500)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Text(this.selectedOf(def.mode).length > 0 ? this.selectedOf(def.mode) : '选择')
        .fontSize(13)
        .fontWeight(this.selectedOf(def.mode).length > 0 ? 600 : 400)
        .fontColor(this.selectedOf(def.mode).length > 0 ? $r('app.color.match_highlight') : $r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '55%' })
        .margin({ right: 6 })
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(13)
        .fontColor([$r('app.color.text_secondary')])
    }
    .width('100%')
    .height(44)
    .padding({ left: 14, right: 14 })
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.cell_border'), style: BorderStyle.Solid })
    .margin({ bottom: 8 })
    .accessibilityText(`${def.label}检索模式，已选 ${this.selectedOf(def.mode)}`)
    .accessibilityDescription('点击弹出滑动选择器，上下滑动选择选项')
    .onClick(() => {
      this.openOptionPicker(def.mode)
    })
  }

  @Builder
  InputModeRow(def: ModeDef) {
    Row() {
      Text(def.label)
        .fontSize(15)
        .fontWeight(500)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Text(this.selectedOf(def.mode).length > 0 ? this.selectedOf(def.mode) : '输入')
        .fontSize(13)
        .fontWeight(this.selectedOf(def.mode).length > 0 ? 600 : 400)
        .fontColor(this.selectedOf(def.mode).length > 0 ? $r('app.color.match_highlight') : $r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '55%' })
        .margin({ right: 6 })
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(13)
        .fontColor([$r('app.color.text_secondary')])
    }
    .width('100%')
    .height(44)
    .padding({ left: 14, right: 14 })
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.cell_border'), style: BorderStyle.Solid })
    .margin({ bottom: 8 })
    .accessibilityText(`${def.label}检索模式，已选 ${this.selectedOf(def.mode)}`)
    .accessibilityDescription('点击输入关键词')
    .onClick(() => {
      this.onOpenInput(def.mode)
    })
  }

  @Builder
  ModeList() {
    Column() {
      ForEach(this.MODES, (def: ModeDef) => {
        if (def.isMenu) {
          this.MenuModeRow(def)
        } else {
          this.InputModeRow(def)
        }
      }, (def: ModeDef) => def.mode)
    }
    .width('100%')
  }

  @Builder
  ResultArea() {
    Column() {
      if (this.results.length === 0) {
        // 未检索到该名士（空状态：图标 + 文案）
        Column() {
          SymbolGlyph($r('sys.symbol.person_crop_circle_fill'))
            .fontSize(40)
            .fontColor([$r('app.color.text_secondary')])
          Blank(12)
          Text('未检索到该名士')
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
        // 唯一结果：完成检索（卡片弹入）
        Column() {
          Text('完成检索')
            .fontSize(14)
            .fontWeight(600)
            .fontColor($r('app.color.match_highlight'))
          Blank(12)
          MingziResultCard({ item: this.results[0] })
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.scale({ x: 0.9, y: 0.9 }))
              .animation({ duration: 250, curve: Curve.EaseOut }))
            .onClick(() => {
              this.openDetail(this.results[0])
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      } else {
        // 多结果：列表（卡片错峰入场：每张延迟 45ms 依次淡入上滑）
        Column() {
          Text(`匹配结果 (${this.results.length})`)
            .fontSize(16)
            .fontWeight(500)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .margin({ bottom: 8 })

          ForEach(this.results, (item: MingziItem, idx: number) => {
            MingziResultCard({ item: item })
              .margin({ bottom: 8 })
              .transition(TransitionEffect.OPACITY
                .combine(TransitionEffect.translate({ y: 16 }))
                .animation({ duration: 250, curve: Curve.EaseOut, delay: idx * 45 }))
              .onClick(() => {
                this.openDetail(item)
              })
          }, (item: MingziItem) => item.name)
        }
        .width('100%')
      }
    }
    .width('100%')
  }

  // 检索后三键（与成语页同一套「沉浸光感」玻璃按钮）
  @Builder
  ActionButtons() {
    Row({ space: 8 }) {
      GlassButton({ label: '清空所有', primary: false, desc: '清除所有检索结果，恢复初始状态', action: () => {
        this.onClearAll()
      } })

      // 「清空当前」= 撤销一层检索条件（没有上一层时就不显示）
      if (this.steps.length >= 2) {
        GlassButton({ label: '清空当前', primary: false, desc: '仅清除当前这次检索，返回上一级检索结果', action: () => {
          this.onUndo()
        } })
      }

      // 「二次检索」恒显示：它是「应用新填写条件」的唯一入口，
      // 结果只有 1 条或 0 条时同样需要（否则新填的条件没有地方生效）
      GlassButton({ label: '二次检索', primary: true, desc: '把新填写的条件叠加到上次检索结果之上', action: () => {
        this.onSecondSearch()
      } })
    }
    .width('100%')
  }

  // ==================== 页面构建 ====================

  @Builder
  NarrowLayout() {
    Column() {
      Column() {
        this.Header()
        this.CriteriaBar()
        // 检索后的三键移到上方（原底部固定栏取消）：条件 → 操作 → 结果自上而下一条视线，
        // 按钮不再贴着底部手势条，也不再占用结果区的滚动空间
        if (this.hasSearched) {
          // 检索后：大「检索」键隐藏，由三键接手
          this.ActionButtons()
          Blank(10)
        } else {
          // 初始状态：条件填好后点「检索」开始检索
          this.SearchButton()
          Blank(10)
        }
        // 模式列表始终可见，检索完成后可直接切换模式进行二次检索
        Scroll(this.scroller) {
          Column() {
            if (this.hasSearched) {
              Text('选择下一个检索条件（二次检索）')
                .fontSize(13)
                .fontWeight(500)
                .fontColor($r('app.color.primary'))
                .width('100%')
                .margin({ bottom: 8 })
            }
            this.ModeList()
            if (this.hasSearched) {
              Blank(10)
              this.ResultArea()
            }
          }
          .width('100%')
          // 底部留白 = 悬浮页签栏高度：模式列表/结果能一直滚到页签栏上方
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
      // 左栏：检索模式选择区（顶部对齐；窗口矮时可上下滚动，9 行模式不会被页签栏挡住）
      Column() {
        Scroll() {
          Column() {
            this.Header()
            this.CriteriaBar()
            if (!this.hasSearched) {
              // 初始状态：左栏条件区下方出现「检索」键（检索后交给右栏顶部三键）
              this.SearchButton()
              Blank(10)
            }
            this.ModeList()
          }
          .width('100%')
          // minHeight 铺满视口：Scroll 默认会把「比视口小的子组件」垂直居中，这里靠上对齐
          .constraintSize({ minHeight: '100%' })
          // 页签栏避让留白放在可滚动内容内部（放容器上会留出空白带、把内容切断）
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
      // 底部预留悬浮页签栏高度（平板页签栏居中于左栏）
      // 注意：容器**不留**底部避让，留白在滚动内容内部（否则页签栏附近会出现一条空白带）
      .padding({ left: 24, right: 16, top: this.topInset + 24 })

      // 可拖动分栏分隔条
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
          // 三键在上：与窄屏一致，操作按钮位于结果列表上方
          this.ActionButtons()
          Blank(10)
          Scroll() {
            // 底部留白 = 悬浮页签栏高度：结果列表能一直滚到页签栏上方
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
            SymbolGlyph($r('sys.symbol.person_2_fill'))
              .fontSize(36)
              .fontColor([$r('app.color.text_secondary')])
            Blank(10)
            Text('填写条件后点「检索」，检索结果将显示在这里')
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

  @Builder
  InputSheet() {
    Column() {
      Text(`${this.modeLabel(this.inputMode)}检索`)
        .fontSize(18)
        .fontWeight(600)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      TextInput({ placeholder: this.inputPlaceholder(this.inputMode) })
        .width('100%')
        .height(44)
        .margin({ top: 16 })
        .backgroundColor($r('app.color.cell_bg'))
        .borderRadius(10)
        .onChange((v: string) => {
          this.inputValue = v
        })
      Row() {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor($r('app.color.cell_bg'))
          .borderRadius(20)
          .onClick(() => {
            this.showInputSheet = false
          })
        Blank(12)
        Button('确定')
          .layoutWeight(1)
          .height(40)
          .fontSize(15)
          .fontColor($r('app.color.on_primary'))
          .backgroundColor($r('app.color.primary'))
          .borderRadius(20)
          .onClick(() => {
            this.confirmInput()
          })
      }
      .width('100%')
      .margin({ top: 20 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 24 })
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
      // Esc 键：返回上一级检索
      if (event.keyCode === KeyCode.KEYCODE_ESCAPE) {
        this.onUndo()
        return true
      }
      return false
    })
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.windowWidth = newArea.width as number
    })
    .bindSheet($$this.showInputSheet, this.InputSheet(), {
      height: 220,
      showClose: true,
      backgroundColor: $r('app.color.card_bg')
    })
  }
}

/**
 * 名士详情对话框 — 居中弹窗（CustomDialog，手机/平板均居中）
 *
 * 展示名士全部信息；检索关键词以绿色加粗高亮；
 * 其他描述每条另起一行并标注表格列号（描述1~15）。
 * 尺寸：88% 屏宽 / 85% 屏高，上限 560×640vp（平板不超限），细线描边。
 */
@CustomDialog
export struct MingziDetailDialog {
  controller?: CustomDialogController
  @Link item: MingziItem
  @Link queries: string[]

  private isHan(code: number): boolean {
    return code >= 0x4E00 && code <= 0x9FFF
  }

  private normalizeQuery(s: string): string {
    let out = ''
    for (let i = 0; i < s.length; i++) {
      const code = s.charCodeAt(i)
      if (this.isHan(code)) {
        out += s.charAt(i)
      }
    }
    return out
  }

  /** 计算 text 中每个字符是否命中任一关键词（命中可跳过非汉字字符） */
  private mergeMarked(text: string): boolean[] {
    const marked: boolean[] = new Array<boolean>(text.length).fill(false)
    for (const q of this.queries) {
      const qq = this.normalizeQuery(q)
      if (qq.length === 0) {
        continue
      }
      for (let i = 0; i < text.length; i++) {
        let qi = 0
        let j = i
        while (j < text.length && qi < qq.length) {
          const code = text.charCodeAt(j)
          if (this.isHan(code)) {
            if (text.charAt(j) === qq.charAt(qi)) {
              qi++
            } else {
              break
            }
          }
          j++
        }
        if (qi === qq.length) {
          for (let k = i; k < j; k++) {
            if (this.isHan(text.charCodeAt(k))) {
              marked[k] = true
            }
          }
        }
      }
    }
    return marked
  }

  /** 把文本按命中情况切分为连续段 */
  private segmentsFor(text: string): Seg[] {
    const marked = this.mergeMarked(text)
    const segs: Seg[] = []
    let cur = ''
    let curHit = false
    for (let i = 0; i < text.length; i++) {
      const m = marked[i]
      if (cur.length === 0) {
        cur = text.charAt(i)
        curHit = m
      } else if (m === curHit) {
        cur += text.charAt(i)
      } else {
        segs.push({ text: cur, hit: curHit })
        cur = text.charAt(i)
        curHit = m
      }
    }
    if (cur.length > 0) {
      segs.push({ text: cur, hit: curHit })
    }
    return segs
  }

  /** 描述条目的表格列号（描述1~15） */
  private descNum(idx: number): number {
    if (idx < this.item.descIndexes.length) {
      return this.item.descIndexes[idx]
    }
    return idx + 1
  }

  @Builder
  HighlightText(value: string) {
    Text() {
      ForEach(this.segmentsFor(value), (seg: Seg, idx: number) => {
        Span(seg.text)
          .fontSize(15)
          .fontColor(seg.hit ? $r('app.color.match_highlight') : $r('app.color.text_primary'))
          .fontWeight(seg.hit ? 600 : 400)
      }, (seg: Seg, idx: number) => idx.toString())
    }
    .width('100%')
  }

  @Builder
  DetailRow(label: string, value: string) {
    if (value.length > 0) {
      Row() {
        Text(label)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width(100)
        Column() {
          this.HighlightText(value)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .margin({ bottom: 10 })
    }
  }

  build() {
    Column() {
      Row() {
        Text(this.item.name)
          .fontSize(22)
          .fontWeight(700)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        // 关闭按钮：圆形「沉浸光感」玻璃底 —— 与页签栏、玻璃按钮同一套系统材质语言
        // （通体等厚半透明底 + 系统材质模糊 + 整圈 1vp 发丝描边），按下同样带一下轻触震动
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor([$r('app.color.text_secondary')])
        }
        .width(32)
        .height(32)
        .borderRadius(16)
        // 弹窗底色是「卡片」（浅色主题下几乎是白的）：白玻璃叠白卡片等于看不见，
        // 所以这里用「卡片上的玻璃」配色 —— 浅色主题取暖墨半透明（比卡片暗），深色主题仍是白色半透明
        .backgroundColor($r('app.color.glass_card_bg'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK, {
          colorMode: ThemeColorMode.SYSTEM,
          adaptiveColor: AdaptiveColor.AVERAGE
        })
        .border({ width: 1, color: $r('app.color.glass_card_edge'), style: BorderStyle.Solid })
        .accessibilityText('关闭')
        .accessibilityDescription('关闭名士详情')
        .onClick(() => {
          Haptics.tick()
          this.controller?.close()
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 16 })

      Scroll() {
        Column() {
          this.DetailRow('朝代', this.item.dynasty)
          this.DetailRow('品阶', this.item.rank)
          this.DetailRow('职业', this.item.occupation)
          this.DetailRow('生逢（生于…）', this.item.born)
          this.DetailRow('出身/身世', this.item.origin)
          this.DetailRow('技能', this.item.skill)
          this.DetailRow('爱好', this.item.hobbies.join('、'))
          this.DetailRow('社团', this.item.groups.join('、'))

          if (this.item.descriptions.length > 0) {
            Blank(6)
            Text('其他描述')
              .fontSize(15)
              .fontWeight(600)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
              .margin({ bottom: 8 })

            // 每条描述另起一行，标号对应表格中的描述1~15
            ForEach(this.item.descriptions, (d: string, idx: number) => {
              Row() {
                Text(`描述${this.descNum(idx)}`)
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .width(100)
                Column() {
                  this.HighlightText(d)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)
              .margin({ bottom: 8 })
            }, (d: string, idx: number) => idx.toString())
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
    }
    .width('88%')
    .height('85%')
    .constraintSize({ maxWidth: 560, maxHeight: 640 })
    .padding({ left: 20, right: 20, top: 16, bottom: 20 })
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(20)
    .border({ width: 1, color: $r('app.color.cell_border') })
  }
}