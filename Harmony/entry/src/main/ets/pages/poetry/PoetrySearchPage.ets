import { GridCellData, MatchResult } from '../../model/PoetryItem'
import { PoetryGrid } from '../../components/PoetryGrid'
import { isValidHanzi } from '../../components/GridCell'
import { ResultList } from '../../components/ResultList'
import { GlassButton } from '../../components/GlassButton'
import { SplitDivider } from '../../components/SplitDivider'
import { SearchEngine } from '../../engine/SearchEngine'
import { POETRY_DB } from '../../data/poetry_db'
import { KeyCode } from '@kit.InputKit'

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

  // ==================== 生命周期 ====================

  aboutToAppear(): void {
    this.initGrid()
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

  private onSearch(): void {
    // 前置校验：必须填满所有格子
    if (!this.isGridComplete()) {
      AlertDialog.show({
        title: '填写不完整',
        message: '请填写完整后再检索',
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

    // 无结果时提示
    if (matchResults.length === 0) {
      AlertDialog.show({
        title: '未找到匹配',
        message: '当前表格中没有匹配到任何诗词句，请调整汉字后重试',
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

  private clearHighlights(): void {
    // 网格是 5 行 × 6 列：这里原来写成了 c < 5，最后一列的高亮清不掉
    for (let r = 0; r < 5; r++) {
      for (let c = 0; c < 6; c++) {
        this.gridData[r][c].isMatched = false
      }
    }
  }

  // ==================== 可复用 UI 片段 ====================

  @Builder
  Header() {
    Column() {
      Text('山石雅集第15题')
        .fontSize(24)
        .fontWeight(600)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 4 })

      Text('在表格中填入汉字，检索蕴含的诗词句')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: 32 })
  }

  @Builder
  ActionButtons() {
    Row() {
      // 「沉浸光感」玻璃按钮（与成语/名士页同一套）：限宽 200vp 居中排列
      Row() {
        GlassButton({ label: '清空', primary: false, desc: '清空整个 6×5 表格', action: () => { this.onClear() } })
      }
      .layoutWeight(1)
      .constraintSize({ maxWidth: 200 })

      Blank(8)

      Row() {
        GlassButton({ label: '开始检索', primary: true, desc: '检索当前表格中包含的所有诗词句', action: () => { this.onSearch() } })
      }
      .layoutWeight(1)
      .constraintSize({ maxWidth: 200 })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .margin({ top: 4 })
  }

  // ==================== UI 构建 ====================

  build() {
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
    .animation({ duration: 200, curve: Curve.EaseInOut })
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.windowWidth = newArea.width as number
    })
  }
}