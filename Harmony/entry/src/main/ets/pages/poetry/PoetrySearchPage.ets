import { GridCellData, MatchResult } from '../../model/PoetryItem'
import { PoetryGrid } from '../../components/PoetryGrid'
import { isValidHanzi } from '../../components/GridCell'
import { ResultList } from '../../components/ResultList'
import { GlassButton } from '../../components/GlassButton'
import { SplitDivider } from '../../components/SplitDivider'
import { SearchEngine } from '../../engine/SearchEngine'
import { POETRY_DB } from '../../data/poetry_db'
import { InfoButton } from '../../components/InfoButton'
import { Haptics } from '../../common/Haptics'
import { OcrOutcome, describeError, isOcrSupported, pickFromCamera, pickFromGallery, recognizeGrid } from '../../service/OcrService'
import { KeyCode } from '@kit.InputKit'
import { common } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'

/**
 * 诗词检索页 — 「择字成诗」
 *
 * 6×5 填字表格（6 列 5 行），填满后检索蕴含的五言诗句。
 * 响应式布局：窄屏（≤600vp）单栏上下堆叠；宽屏双栏左右分列。
 */

@Component
export struct PoetrySearchPage {
  @State gridData: GridCellData[][] = []
  @State results: MatchResult[] = []
  @State hasSearched: boolean = false  // 是否已执行过检索
  @State windowWidth: number = 0  // 窗口宽度，用于断点判断
  // 双栏左右宽度比例（0~1，左栏占比），可拖动调节；用 AppStorage 共享给主页面 —— 平板页签栏据此水平居中于左栏
  @StorageLink('splitRatio') splitRatio: number = 0.5
  @StorageProp('topInset') topInset: number = 0  // 状态栏高度（vp），铺满边缘时避让系统图标
  @StorageProp('barInset') barInset: number = 0  // 悬浮页签栏占位高度（vp，Index 发布）：滚动内容底部留白，内容可从玻璃下方穿过
  @Prop @Watch('onClearCmd') clearCmd: number = 0  // 系统返回手势指令：变化时执行「清空」
  onScrollOffset?: (yOffset: number) => void  // 滚动回调：Index 据此驱动悬浮页签栏下滚隐藏 / 上滚显示
  private engine: SearchEngine = new SearchEngine(POETRY_DB)
  private highlightToken: number = 0  // 高亮批次令牌：清空表格后旧批次的延迟高亮自动作废
  // ---- 识图填字（v3.0）----
  @State showOcrSheet: boolean = false   // 「识图」来源选择面板（拍照 / 图库）
  @State isRecognizing: boolean = false  // 识别中：蒙层 + 转圈，期间不接受点击
  @State ocrNote: string = ''            // 识别结果的一行小注（填在标题下方，清空时复位）

  // ==================== 生命周期 ====================

  aboutToAppear(): void {
    this.initGrid()
    this.seedWidth()
  }

  /**
   * 首次显示前先取真实窗口宽（Index 已发布到 AppStorage）
   *
   * 否则会「按 0 排一遍 → onAreaChange 改成真实宽度 → 再整页重排一遍」，
   * 首次切到本页时这一下正好卡在切页动画里，看着就是掉帧。
   */
  private seedWidth(): void {
    const w: number | undefined = AppStorage.get<number>('winWidth')
    if (w !== undefined && w > 0) {
      this.windowWidth = w
    }
  }

  // ==================== 数据初始化 ====================

  private initGrid(): void {
    const data: GridCellData[][] = []
    for (let r = 0; r < 5; r++) {
      const row: GridCellData[] = []
      for (let c = 0; c < 6; c++) {
        row.push(new GridCellData(r, c))
      }
      data.push(row)
    }
    this.gridData = data
  }

  // ==================== 业务逻辑 ====================

  private isGridComplete(): boolean {
    for (let r = 0; r < 5; r++) {
      for (let c = 0; c < 6; c++) {
        if (this.gridData[r][c].char === '') {
          return false
        }
      }
    }
    return true
  }

  private onSearch(fromOcr: boolean = false): void {
    // 前置校验：必须填满所有格子
    if (!this.isGridComplete()) {
      AlertDialog.show({
        title: '填写不完整',
        message: fromOcr ? '识别到的字不足 30 个，请补全空格子后再检索' : '请填写完整后再检索',
        confirm: {
          value: '确定',
          action: () => {}
        }
      })
      return
    }

    // 执行检索
    const matchResults = this.engine.search(this.gridData)

    // 标注匹配的格子：按命中顺序错峰点亮（每批间隔 45ms，180ms 绿色渐入）。
    // 令牌防串台：清空/重新检索后，旧批次尚未执行的延迟高亮自动作废。
    const token = ++this.highlightToken
    this.clearHighlights()
    let order = 0
    for (const result of matchResults) {
      for (const pos of result.positions) {
        if (pos.row >= 0 && pos.row < 5 && pos.col >= 0 && pos.col < 6) {
          const r = pos.row
          const c = pos.col
          const delay = order * 45
          order++
          setTimeout(() => {
            if (token !== this.highlightToken) {
              return
            }
            animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
              this.gridData[r][c].isMatched = true
            })
          }, delay)
        }
      }
    }

    // 更新结果：卡片错峰淡入上滑（见 ResultList 中各卡片的 transition）
    animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
      this.results = matchResults
      this.hasSearched = true
    })

    // 无结果时提示（识图路径额外给出「只差一两个字」的疑似候选，帮用户定位识别偏差）
    if (matchResults.length === 0) {
      const near: string[] = fromOcr ? this.nearMissHints(3) : []
      AlertDialog.show({
        title: '未找到匹配',
        message: fromOcr
          ? (near.length > 0
            ? `没有完全匹配。最接近的有：\n${near.join('\n')}\n可能是这几个字识别有偏差，核对一下表格里的字`
            : '已识别并填入 30 个字，但没有匹配到诗句。可能是识别有偏差，请核对表格里的字')
          : '当前表格中没有匹配到任何诗词句，请调整汉字后重试',
        confirm: {
          value: '确定',
          action: () => {}
        }
      })
    }
  }

  private onClear(): void {
    this.highlightToken++  // 作废所有尚未执行的延迟高亮
    for (let r = 0; r < 5; r++) {
      for (let c = 0; c < 6; c++) {
        this.gridData[r][c].char = ''
      }
    }
    this.clearHighlights()
    this.results = []
    this.hasSearched = false
    this.ocrNote = ''
  }

  // 一键粘贴：去除非汉字符号后，按从左到右、从上到下填入 30 格
  private fillFromPaste(text: string): void {
    // 1. 只保留 CJK 基本集汉字
    let hanzi = ''
    for (let i = 0; i < text.length; i++) {
      const ch = text.charAt(i)
      if (isValidHanzi(ch)) {
        hanzi += ch
      }
    }
    // 2. 依次填入；不足留空，超出只取前 30
    let idx = 0
    for (let r = 0; r < 5; r++) {
      for (let c = 0; c < 6; c++) {
        this.gridData[r][c].char = idx < hanzi.length ? hanzi.charAt(idx) : ''
        this.gridData[r][c].isMatched = false
        idx++
      }
    }
    // 3. 内容已变，清空上次检索结果，并作废未执行的延迟高亮
    this.highlightToken++
    this.results = []
    this.hasSearched = false
  }

  // 系统返回手势指令：执行「清空」（清空整个表格）
  onClearCmd(): void {
    this.onClear()
  }

  /**
   * 识图专用：找出「只差一两个字」的诗句，帮用户定位识别偏差
   *
   * OCR 认错一两个字时，真正的答案会以「缺 1~2 个字」的形态出现；
   * 把这些候选摆出来，比干巴巴一句「未找到匹配」有用得多。
   * @param limit 最多给几条
   */
  private nearMissHints(limit: number): string[] {
    const present = new Set<string>()
    for (let r = 0; r < 5; r++) {
      for (let c = 0; c < 6; c++) {
        const ch: string = this.gridData[r][c].char
        if (ch !== '') {
          present.add(ch)
        }
      }
    }
    // 先只缺 1 个字的（最可能），再缺 2 个字的
    for (let maxMissing = 1; maxMissing <= 2; maxMissing++) {
      const tier: string[] = []
      for (const poem of POETRY_DB) {
        const missing: string[] = []
        for (const ch of poem.chars) {
          if (!present.has(ch) && missing.indexOf(ch) < 0) {
            missing.push(ch)
          }
        }
        if (missing.length === maxMissing) {
          tier.push(`${poem.line}（缺「${missing.join('、')}」）`)
        }
      }
      if (tier.length > 0) {
        return tier.slice(0, limit)
      }
    }
    return []
  }

  private clearHighlights(): void {
    // 网格是 5 行 × 6 列：这里原来写成了 c < 5，最后一列的高亮清不掉
    for (let r = 0; r < 5; r++) {
      for (let c = 0; c < 6; c++) {
        this.gridData[r][c].isMatched = false
      }
    }
  }

  // ==================== 识图填字（v3.0） ====================

  /** 打开「识图」来源面板 */
  private openOcrSheet(): void {
    if (this.isRecognizing) {
      return
    }
    if (!isOcrSupported()) {
      this.showError('设备不支持', '当前设备没有系统文字识别能力，无法识图。请手动填写表格')
      return
    }
    this.showOcrSheet = true
  }

  /** 拍照 → 识别 */
  private async captureAndRecognize(): Promise<void> {
    this.showOcrSheet = false
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const uri: string = await pickFromCamera(context)
      if (uri.length === 0) {
        return  // 用户取消了拍照
      }
      await this.runOcr(uri)
    } catch (e) {
      this.reportOcrError(e, '打开相机失败')
    }
  }

  /** 图库选图 → 识别 */
  private async pickAndRecognize(): Promise<void> {
    this.showOcrSheet = false
    try {
      const uri: string = await pickFromGallery()
      if (uri.length === 0) {
        return  // 用户取消了选图
      }
      await this.runOcr(uri)
    } catch (e) {
      this.reportOcrError(e, '打开图库失败')
    }
  }

  /** 识别一张图：识别中显示蒙层，完成后填入表格 */
  private async runOcr(uri: string): Promise<void> {
    this.isRecognizing = true
    try {
      const outcome: OcrOutcome = await recognizeGrid(uri)
      this.isRecognizing = false
      this.applyOcr(outcome)
    } catch (e) {
      this.isRecognizing = false
      this.reportOcrError(e, '识别失败')
    }
  }

  /**
   * 把识别结果填进 6×5 表格
   *
   * 识别结果已按阅读顺序排好（见 service/OcrGridExtractor），顺序填格即可：
   * 30 个字全部认出 → 直接自动检索；不足 30 个 → 已认出的先填上，提示用户补全。
   */
  private applyOcr(outcome: OcrOutcome): void {
    const grid = outcome.grid
    if (grid === null || grid.chars.length === 0) {
      this.showError('没有认出汉字', '这张图里没有识别到汉字。请换一张字格清楚、没有大面积遮挡的图片')
      return
    }

    // 填表：能对齐到格位就「按格位填」（缺的格子留空、位置不乱），否则按阅读顺序顺次填
    const positional: boolean = grid.cells.length === 30 && grid.rowCount === 5 && grid.colCount === 6
    const chars: string[] = grid.chars
    let filled: number = 0
    let idx: number = 0
    for (let r = 0; r < 5; r++) {
      for (let c = 0; c < 6; c++) {
        const cell: GridCellData = this.gridData[r][c]
        cell.char = positional ? grid.cells[r * 6 + c] : (idx < chars.length ? chars[idx] : '')
        cell.isMatched = false
        if (cell.char !== '') {
          filled++
        }
        idx++
      }
    }
    this.highlightToken++  // 作废尚未执行的延迟高亮
    this.results = []
    this.hasSearched = false
    Haptics.tick()

    if (filled >= 30) {
      this.ocrNote = '已识别 30 个字，自动检索'
      this.onSearch(true)   // 认出满 30 个字：直接出结果
    } else {
      this.ocrNote = `已识别 ${filled} 个字`
      // 缺字时把「只差一两个字的诗句」列出来，用户照着补空格外即可
      const near: string[] = this.nearMissHints(3)
      const tail: string = near.length > 0
        ? `\n\n最接近的诗句：\n${near.join('\n')}\n\n照此补上空着的格子后再点「开始检索」。`
        : '\n\n请补全空格子后再点「开始检索」。'
      AlertDialog.show({
        title: '识别不完整',
        message: `只认出 ${filled} 个字（应为 30 个），已按原样填入。${tail}`,
        confirm: {
          value: '确定',
          action: () => {}
        }
      })
    }
  }

  /** 统一的错误提示（相机/图库打不开、识别服务异常都走这里） */
  private reportOcrError(e: object, title: string): void {
    const err = e as BusinessError
    hilog.error(0x0000, 'CulturalSearch', 'ocr error: %{public}d %{public}s',
      err.code ?? -1, err.message ?? '')
    this.showError(title, describeError(err))
  }

  private showError(title: string, message: string): void {
    AlertDialog.show({
      title: title,
      message: message,
      confirm: {
        value: '确定',
        action: () => {}
      }
    })
  }

  // ==================== 可复用 UI 片段 ====================

  @Builder
  Header() {
    Row() {
      Column() {
        Text('山石雅集第15题')
          .fontSize(24)
          .fontWeight(600)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 4 })

        // 副标题平时是操作提示；识图填字后换成识别结果小注（清空时复位）
        Text(this.ocrNote.length > 0 ? this.ocrNote : '在表格中填入汉字，检索蕴含的诗词句')
          .fontSize(13)
          .fontColor(this.ocrNote.length > 0 ? $r('app.color.match_highlight') : $r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 大标题右侧的「信息」按钮：应用说明与使用方法（三个检索页共用同一个对话框）
      InfoButton()
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .margin({ bottom: 32 })
  }

  @Builder
  ActionButtons() {
    Row() {
      // 「沉浸光感」玻璃按钮（与成语/名士页同一套）：限宽 200vp 居中排列
      Row() {
        GlassButton({
          label: '识图',
          primary: false,
          desc: '拍照或从图库导入 6×5 字格图片，自动识别并填表',
          action: () => { this.openOcrSheet() }
        })
      }
      .layoutWeight(1)
      .constraintSize({ maxWidth: 200 })

      Blank(8)

      Row() {
        GlassButton({ label: '清空', primary: false, desc: '清空整个 6×5 表格', action: () => { this.onClear() } })
      }
      .layoutWeight(1)
      .constraintSize({ maxWidth: 200 })

      Blank(8)

      Row() {
        GlassButton({
          label: '开始检索',
          primary: true,
          desc: '检索当前表格中包含的所有诗词句',
          action: () => { this.onSearch() }
        })
      }
      .layoutWeight(1)
      .constraintSize({ maxWidth: 200 })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .margin({ top: 4 })
  }

  /**
   * 「识图」来源面板（页面内自绘，底部弹出）
   *
   * 早先用的是系统 `bindSheet`，但它在平板上会缩成一张很窄的小卡片，
   * 系统自带的关闭键还会压在正文上 —— 改成自己画的卡片：手机铺满宽度、平板限宽居中，
   * 关闭键自己放在标题行右侧，不压正文。
   */
  @Builder
  OcrSheet() {
    Column() {
      Row() {
        Text('识图填字')
          .fontSize(18)
          .fontWeight(600)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        // 关闭键：与信息弹窗同一套圆形玻璃小键
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(14)
            .fontColor([$r('app.color.text_secondary')])
        }
        .width(28)
        .height(28)
        .borderRadius(14)
        .backgroundColor($r('app.color.glass_card_bg'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK, {
          colorMode: ThemeColorMode.SYSTEM,
          adaptiveColor: AdaptiveColor.AVERAGE
        })
        .border({ width: 1, color: $r('app.color.glass_card_edge'), style: BorderStyle.Solid })
        .accessibilityText('关闭')
        .accessibilityDescription('关闭识图面板')
        .onClick(() => {
          Haptics.tick()
          this.showOcrSheet = false
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text('拍一张或选一张带 6×5 字格的图片，自动认出图中的字并填表检索')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ top: 4, bottom: 16 })

      this.SheetAction($r('sys.symbol.camera'), '拍照识别', '调起系统相机，对着题目拍一张',
        () => { this.captureAndRecognize() })

      Blank(10)

      this.SheetAction($r('sys.symbol.picture'), '从图库选择', '选一张已有的字格截图',
        () => { this.pickAndRecognize() })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 20, right: 20, top: 16, bottom: 20 })
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(20)
    .border({ width: 1, color: $r('app.color.cell_border') })
    .shadow({ radius: 24, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 8 })
  }

  @Builder
  SheetAction(symbol: Resource, label: string, desc: string, action: () => void) {
    Row() {
      SymbolGlyph(symbol)
        .fontSize(20)
        .fontColor([$r('app.color.primary')])

      Column() {
        Text(label)
          .fontSize(15)
          .fontWeight(500)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text(desc)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([$r('app.color.text_secondary')])
    }
    .width('100%')
    .height(60)
    .padding({ left: 14, right: 14 })
    .backgroundColor($r('app.color.cell_bg'))
    .borderRadius(14)
    .border({ width: 1, color: $r('app.color.cell_border'), style: BorderStyle.Solid })
    .accessibilityText(label)
    .accessibilityDescription(desc)
    .onClick(() => {
      Haptics.tick()
      action()
    })
  }

  /** 识别中蒙层：挡住误触，给一句「慢是正常的」预告 */
  @Builder
  OcrProgress() {
    Column() {
      LoadingProgress()
        .width(44)
        .height(44)
        .color($r('app.color.primary'))
      Blank(12)
      Text('正在识别…')
        .fontSize(15)
        .fontWeight(500)
        .fontColor($r('app.color.text_primary'))
      Blank(4)
      Text('会按几种方式各认一遍再取最准的，通常几秒')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
    }
    .width(230)
    .padding({ left: 20, right: 20, top: 24, bottom: 24 })
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(20)
    .border({ width: 1, color: $r('app.color.cell_border') })
    .shadow({ radius: 24, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 8 })
  }

  // ==================== UI 构建 ====================

  build() {
    // 根节点用 Stack：正常内容是里层 Column，识别中在最上层压一层蒙层
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        if (this.windowWidth === 0 || this.windowWidth <= 600) {
          // ---- 窄屏：单栏布局（上下堆叠） ----
          Column() {
            this.Header()
            PoetryGrid({ gridData: $gridData, onPasteText: (t: string) => { this.fillFromPaste(t) } })
            this.ActionButtons()

            Blank(12)

            // 结果区（可滚动，占据剩余空间）
            if (this.hasSearched || this.results.length > 0) {
              Scroll() {
                // 底部留白 = 悬浮页签栏高度：结果列表能一直滚到页签栏上方
                Column() {
                  ResultList({ results: $results })
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
        } else {
          // ---- 宽屏：双栏布局（左输入 + 右结果） ----
          Row() {
            // 左栏：输入区（窗口矮时可上下滚动）
            Column() {
              Scroll() {
                Column() {
                  this.Header()
                  PoetryGrid({ gridData: $gridData, onPasteText: (t: string) => { this.fillFromPaste(t) } })
                  this.ActionButtons()
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

            // 可拖动分栏分隔条：拖动调整左右两栏宽度比例
            SplitDivider({
              ratio: this.splitRatio,
              totalWidth: this.windowWidth,
              onRatioChange: (r: number) => {
                this.splitRatio = r
              }
            })

            // 右栏：结果区
            Column() {
              if (this.hasSearched || this.results.length > 0) {
                Scroll() {
                  // 底部留白 = 悬浮页签栏高度：结果列表能一直滚到页签栏上方
                  Column() {
                    ResultList({ results: $results })
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
                  SymbolGlyph($r('sys.symbol.square_grid_2x2'))
                    .fontSize(36)
                    .fontColor([$r('app.color.text_secondary')])
                  Blank(10)
                  Text('在表格中填入汉字后点击「开始检索」')
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
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'))
      .onKeyEvent((event: KeyEvent) => {
        if (event.type !== KeyType.Down) {
          return false
        }
        // Esc 键：清空整个表格
        if (event.keyCode === KeyCode.KEYCODE_ESCAPE) {
          this.onClear()
          return true
        }
        return false
      })
      // ⚠️ 性能：这里原先有一层「整页 .animation()」隐式动画 —— 切页签、状态变化时
      // 整棵子树（诗词页 30 个输入框）都会被纳入动画，掉帧明显。动画改用各组件自己的
      // animateTo / transition，这里不再整页挂隐式动画。
      .onAreaChange((oldArea: Area, newArea: Area) => {
        const w: number = newArea.width as number
        if (Math.abs(w - this.windowWidth) < 0.5) {
          return   // 面积没真变就别改状态，省一次整页重建
        }
        this.windowWidth = w
      })
      // 识别中蒙层：盖住整页，避免重复点按钮
      if (this.isRecognizing) {
        Column() {
          this.OcrProgress()
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.bar_scrim'))
        .onClick(() => {})
      }

      // 「识图」来源面板：点面板外的暗色区域收起；面板本身手机铺满、平板限宽居中
      if (this.showOcrSheet) {
        Column() {
          Column()
            .width('100%')
            .layoutWeight(1)
            .onClick(() => {
              this.showOcrSheet = false
            })

          Row() {
            Column() {
              this.OcrSheet()
            }
            .layoutWeight(1)
            .constraintSize({ maxWidth: 460 })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ left: 12, right: 12, bottom: this.barInset + 8 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.scrim'))
        .transition(TransitionEffect.OPACITY.animation({ duration: 160 }))
      }
    }
    .width('100%')
    .height('100%')
  }
}
