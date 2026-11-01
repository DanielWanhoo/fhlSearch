import { MingziItem } from '../../model/MingziItem'
import { MingziSearchMode, MingziSearchService } from '../../service/MingziSearchService'
import { MINGZI_DB } from '../../data/mingzi_db'
import { MingziResultCard } from '../../components/MingziResultCard'
import { GlassButton } from '../../components/GlassButton'
import { Haptics } from '../../common/Haptics'
import { ENTER_ALL_SHOWN, ENTER_OFFSET_X, ENTER_SPRING, ENTER_START_DELAY_MS, RIGHT_ENTER_MS, RIGHT_OFFSET_X, RIGHT_VEIL_MS, enterFinishMs, enterStepFor } from '../../common/PageEnter'
import { SplitDivider } from '../../components/SplitDivider'
import { InfoButton } from '../../components/InfoButton'
import { KeyCode } from '@kit.InputKit'
import { EASE_OUT_SOFT, EASE_OUT_STRONG, FRAME_MS, isReducedMotion, LAND_SPRING, LAND_SPRING_MS, MOTION_BASE_MS, MOTION_FAST_MS, MOTION_SLOW_MS, PANEL_COLLAPSE_STEP_MS, PANEL_COLLAPSE_TAIL_MS, staggerDelay } from '../../common/Motion'
import { curves } from '@kit.ArkUI'

/**
 * 名士检索页
 *
 * 9 种检索模式：朝代/爱好/社团/品阶（菜单选项）+ 职业/生逢/出身·身世/技能/其他描述（输入·模糊匹配）。
 * 模式以列表呈现（避免图标挤占）；结果三分支：唯一（完成检索）/ 多结果（三键）/ 未检索到。
 * 三键（清空所有 / 清空当前 / 二次检索）位于页面**上方**、检索条件之下，结果列表之前。
 * 支持二次检索（基于当前结果继续过滤）、返回上一级检索、清空所有检索。
 */

// ── 首次检索的退场：九行条件自上而下逐项向上收进摘要框中心 ──
const EXIT_STEP_MS: number = 20            // 逐项延迟（9 行 ×20ms，总时长仍在 400ms 内）
const EXIT_DURATION_MS: number = 150       // 单项退场时长（位移 + 缩小 + 淡出一起走）
const EXIT_SLOTS: number = 10         // 槽位数：9 行模式 + 检索键（最后一位）
/** 退场曲线：与全局动效令牌同一条强 ease-out（绝不用 ease-in） */
const EXIT_CURVE: ICurve = EASE_OUT_STRONG

// ── 摘要框与退场「同时」淡进 ──
const PANEL_INTRO_DELAY_MS: number = 40
const PANEL_INTRO_MS: number = 230
// ── 检索键：点击即上移 + 分裂成两枚（首检索后必有「清空所有 + 二次检索」） ──
const KEY_MORPH_MS: number = 330
const SPLIT_FRAME_MS: number = 16
const FLIP_MS: number = SPLIT_FRAME_MS + KEY_MORPH_MS
const HANDOFF_MS: number = 300
const KEY_GAP: number = 8
const PANEL_ROW_H: number = 56        // 摘要框收起态那一行的高度（分裂落点的纵向基准）
const PANEL_MARGIN_BOTTOM: number = 12

// ── 名士详情：卡片形变放大成居中弹窗 ──
const DETAIL_MORPH_MS: number = 380       // 形变时长：略长于落位弹簧的自然收敛时间
const DETAIL_DYN_MS: number = 220         // 「（朝代）」淡出 / 还原
const DETAIL_ROWS_DELAY_MS: number = 300 // 弹窗落定后才开始逐行淡进
const DETAIL_ROW_STEP_MS: number = 50     // 每行延迟（自上而下依次出现）
const DETAIL_ROW_MS: number = 200         // 单行淡进
const DETAIL_ROW_OUT_MS: number = 140     // 单行退场（关闭时反序）
const DETAIL_CLOSE_MS: number = 300       // 关闭键弹出 / 缩回
const DETAIL_OUT_MS: number = 180         // 关闭时「整块详细内容」淡出
const DETAIL_CARD_HOLD_MS: number = 60   // 内容淡出后再开始缩回卡片（错开一点更顺）
const DETAIL_HEADER_H: number = 40        // 标题行高度（名字 + 关闭键）
const DETAIL_BASE_H: number = 84          // 弹窗固定开销：上内边距 14 + 标题行 40 + 标题下间距 12 + 下内边距 16 + 描边 2
const DETAIL_LINE_H: number = 21          // 单行文字占高（值换行时按行数累加）
const DETAIL_LABEL_W: number = 100        // 标签列宽度
const DETAIL_ROW_GAP: number = 10         // 行间距（DlgRow 的 margin bottom）
const DETAIL_SECTION_H: number = 38       // 二级小标题占高：文字 20 + 上间距 8 + 下间距 10
const DETAIL_RADIUS_FROM: number = 18     // 起点圆角 = 结果卡圆角（MingziResultCard 18）
const DETAIL_RADIUS_TO: number = 20       // 终点圆角 = 弹窗圆角
const DETAIL_TITLE_MS: number = 230       // 标题换装时长：必须短于弹簧收敛（否则落地后还在挪字）

// ── 条件摘要框（Blur Glide Menu）展开 / 收起 ──
const PANEL_START_MS: number = 40
const PANEL_STEP_MS: number = 30      // 9 行 + 说明，间隔比成语页略小
const PANEL_ITEM_MS: number = 200
const PANEL_SLOTS: number = 10
// 展开区最高高度：九行条件比视口还高，超出就内部滚动 ——
// 否则整块长高会把下面的操作键顶到页签栏后面，用户看不到「二次检索」
const PANEL_MAX_H: number = 400        // 展开区项数：9 行模式 + 说明
const PANEL_DURATION_MS: number = 320
const PANEL_SPRING: ICurve = curves.interpolatingSpring(0, 1, 420, 34)  // ζ≈0.83 → 过冲 ≈1%

/** 副标题两段文案：切换时整段淡出→换字→淡入，不硬切 */
const SUB_EDIT: string = '选择或输入条件后，点「检索」开始检索'
const SUB_REFINE: string = '继续填写条件，点「二次检索」在上次结果中细查'

/** 展开区底部的说明（写成模块常量，@Builder 里直接读 getter 曾出现整行不渲染） */
const MODE_HINT: string = '九种条件可任意组合：填了几项就要同时满足，留空表示不限'

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

/** 详情里的一行：标签 + 值（朝代/品阶/…/描述N） */
interface RectLike {
  w: number
  h: number
  cx: number
  cy: number
}

interface DetailPair {
  label: string
  value: string
  section: boolean   // true = 二级小标题（如「其他描述」），不是「标签 + 值」行
}

@Component
export struct MingziSearchPage {
  @State results: MingziItem[] = []
  @State hasSearched: boolean = false
  @State searchCount: number = 0  // 检索次数（清空所有检索时清零）
  @State steps: SearchStep[] = []  // 已应用检索步骤（面包屑 + 返回上一级依据）
  @State selectedValues: string[] = ['', '', '', '', '', '', '', '', '']  // 各模式当前已选选项（与 MODES 顺序对应）
  @State detailItem: MingziItem = new MingziItem()  // 详情弹窗展示的名士
  @State detailQueries: string[] = []  // 详情弹窗高亮用的检索关键词
  // ── 卡片 → 弹窗 的形变动画（v3.3）──
  @State detailOpen: boolean = false      // 弹窗是否挂载（形变的目标节点）
  @State detailMorphId: string = ''       // 共享元素 id：卡片与弹窗同一个 id，几何过渡才连得上
  @State detailVeil: number = 0           // 背景「变暗 + 虚化」层的不透明度
  @State detailNameIn: number = 0         // 名字：卡片左侧 → 弹窗上部居中
  @State detailNameShift: number = 0      // 名字的横向偏移（vp，打开时从左往右归零）
  @State detailNameLift: number = 6       // 名字的纵向偏移（vp，打开时自下而上归零）
  @State detailDynFade: number = 1        // 「（朝代）」：随名字同层移动，落定前淡出
  @State detailDynShift: number = 0       // 「（朝代）」的纵向偏移（与名字方向相反，避免重叠）
  @State detailRows: number = 0           // 已淡入的详实行数（每行 50ms 依次出现）
  @State detailCloseShown: number = 0
  @State detailContentFade: number = 1   // 关闭时整块内容淡出用
  // 形变：从被点卡片的位置/尺寸长到最终弹窗（结束都是 1 / 0）
  @State detailW: number = 0       // 弹窗宽度（第一帧起就是终态宽，避免文字重排）
  @State detailH: number = 0       // 高度上限：卡片高度 → 展开后的高度（内容自适应，裁切实现「长高」）
  @State detailOX: number = 0      // 相对屏幕中心的横向偏移（起点 = 卡片中心）
  @State detailOY: number = 0      // 相对屏幕中心的纵向偏移（起点 = 卡片中心）
  @State detailRadius: number = 18 // 圆角：卡片 18 → 弹窗 20，跟着一起长
  @State detailHideCard: boolean = false  // 展开期间把列表里那张卡隐形，避免与浮层叠影
  @State detailTitleCard: number = 0      // 标题排版：0 = 弹窗（居中 22）、1 = 卡片（左 18 + 朝代靠右）
  @State detailNameW: number = 0          // 名字在弹窗排版（22 号）下的实测宽度
  @State detailDynW: number = 0           // 朝代实测宽度（两端都是 15 号，量到的宽度通用）
  @State windowHeight: number = 0         // 窗口高度（vp）：算弹窗最大高度 / 翻页区高度
  private detailTimers: number[] = []
  /** 展开起点矩形（点击时量下的卡片矩形，关闭时原路退回） */
  private detailFrom: RectLike = { w: 0, h: 0, cx: 0, cy: 0 }
  @State windowWidth: number = 0  // 窗口宽度，用于断点判断（≤600 单栏，>600 双栏）
  // 双栏左右宽度比例（0~1，左栏占比），可拖动调节；用 AppStorage 共享给主页面 —— 平板页签栏据此水平居中于左栏
  @StorageLink('splitRatio') splitRatio: number = 0.5
  @StorageProp('topInset') topInset: number = 0
  @StorageProp('barInset') barInset: number = 0  // 悬浮页签栏占位高度（vp，Index 发布）：滚动内容底部留白，内容可从玻璃下方穿过
  @Prop @Watch('onUndoCmd') undoCmd: number = 0  // 系统返回手势指令：变化时执行「返回上一级检索」
  onScrollOffset?: (yOffset: number) => void  // 滚动回调：Index 据此驱动悬浮页签栏下滚隐藏 / 上滚显示
  // ── 切页进场（v3.3）：元素自上而下每 50ms 放出一项，横向弹入 ──────────────
  @Prop @Watch('onEnterTick') enterTick: number = 0
  @State enterShown: number = ENTER_ALL_SHOWN  // 已放出的项数；0 = 全部藏起来，ENTER_ALL_SHOWN = 静止态
  @State enterDir: number = 1  // 进场方向：+1 从右侧弹入，-1 从左侧弹入（跟随切页方向）
  private lastEnterTick: number = 0  // 上一次收到的 enterTick：靠它的大小变化判断切页方向
  private enterTimers: number[] = []
  // 槽位数：0 标题 / 1 已检索条件 / 2 按键 / 3 提示 / 4~12 九行模式 / 13 结果
  private readonly ENTER_SLOTS: number = 14
  // 平板双栏时右栏（结果区）自己一组错峰：与左栏同时起步，标题 + 前 5 张卡片逐项放出
  @State enterShownR: number = ENTER_ALL_SHOWN
  // 平板右栏「整块」进场：1 = 静止，0 = 藏在起始位移上（不再逐项弹出）
  @State rightEnter: number = 1
  // 平板右栏背景的横向渐隐遮罩：1 = 整个盖住，0 = 已经扫开（只在切页那一下出现）
  @State rightVeil: number = 0
  private enterTimersR: number[] = []
  private readonly RIGHT_SLOTS: number = 6
  private service: MingziSearchService = new MingziSearchService(MINGZI_DB)
  private scroller: Scroller = new Scroller()
  // ── 检索后的条件摘要框（Blur Glide Menu） ──────────────────────────────
  // 检索一完成九行条件就收进摘要框（只留一行摘要），点框向下延伸继续改；
  // 窄屏与平板左栏同一套行为
  @State panelOpen: boolean = false
  @State panelShown: number = 0
  private panelTimers: number[] = []
  // ── 首次检索：条件区向上收进摘要框中心 ────────────────────────────────
  @State exitActive: boolean = false
  @State exitShown: number = 0
  private exitTimers: number[] = []
  private geoCenterY: number[] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  private panelAnchorY: number = 0
  @State panelIntro: number = 0
  // 预览层要显示的摘要文案：首次检索时 this.steps 还是空的，得先把这次的条目标题存下来
  @State pendingSummary: string = ''
  // 副标题：文字与不透明度分开存 —— 换字时先淡出、换完再淡入，整段渐进渐出
  @State subText: string = SUB_EDIT
  @State subOpacity: number = 1
  private subTimers: number[] = []
  @State splitP: number = 1
  @State splitY: number = 0
  @State keyLift: number = 0
  private keyPills: number = 2
  private keyWidth: number = 0
  private keyX: number = 0
  private actionX: number = 0
  private actionY: number = 0
  private actionW: number = 0
  private actionH: number = 0

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
    // 本页往往是在「切到这一页」的那一刻才被创建（HdsTabs 懒创建）：
    // 初始赋值不会触发 @Watch，所以要在这里补放一次进场，否则第一次切进来没有错峰动画
    if (this.enterTick !== 0) {
      this.onEnterTick()
    }
  }

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
      return '如：帝王、诗人'
    }
    if (mode === MingziSearchMode.BORN) {
      return '如：乱世'
    }
    if (mode === MingziSearchMode.ORIGIN) {
      return '如：出身显贵'
    }
    if (mode === MingziSearchMode.SKILL) {
      return '如：剑舞者'
    }
    return '如：诗仙'
  }

  /** 全部已应用的检索关键词（用于详情高亮） */
  private keyQueries(): string[] {
    return this.steps.map((s: SearchStep) => s.query)
  }

  // ─────────────────────── 名士详情：卡片 → 弹窗 ───────────────────────

  /** 清掉详情动画的计时器（重开 / 关闭 / 页面销毁时调用） */
  private clearDetailTimers(): void {
    for (const t of this.detailTimers) {
      clearTimeout(t)
    }
    this.detailTimers = []
  }

  /** 详情里的「标签 + 值」列表（朝代…其他描述…描述N），空值跳过 */
  private detailPairs(): DetailPair[] {
    const arr: DetailPair[] = []
    const push = (label: string, value: string) => {
      if (value.length > 0) {
        arr.push({ label: label, value: value, section: false })
      }
    }
    push('朝代', this.detailItem.dynasty)
    push('品阶', this.detailItem.rank)
    push('职业', this.detailItem.occupation)
    push('生逢（生于…）', this.detailItem.born)
    push('出身/身世', this.detailItem.origin)
    push('技能', this.detailItem.skill)
    push('爱好', this.detailItem.hobbies.join('、'))
    push('社团', this.detailItem.groups.join('、'))
    // 「描述N」是零散补充，归到「其他描述」这一组下：先立二级小标题，再逐条列
    const descs: DetailPair[] = []
    for (let i = 0; i < this.detailItem.descriptions.length; i++) {
      const text: string = this.detailItem.descriptions[i]
      if (text.length > 0) {
        descs.push({
          label: `描述${this.detailItem.descIndexes.length > i ? this.detailItem.descIndexes[i] : i + 1}`,
          value: text,
          section: false
        })
      }
    }
    if (descs.length > 0) {
      arr.push({ label: '其他描述', value: '', section: true })
      for (let i = 0; i < descs.length; i++) {
        arr.push(descs[i])
      }
    }
    return arr
  }

  /** 一行占多高：小标题固定高度；普通行 = 行数 × 行高 + 行间距 */
  private detailRowH(pair: DetailPair): number {
    if (pair.section) {
      return DETAIL_SECTION_H
    }
    return this.detailLines(pair.value) * DETAIL_LINE_H + DETAIL_ROW_GAP
  }

  /** 全部详细行加起来的高度（连续排版，不分页） */
  private detailAllRowsH(): number {
    const items: DetailPair[] = this.detailPairs()
    let h: number = 0
    for (let i = 0; i < items.length; i++) {
      h += this.detailRowH(items[i])
    }
    return h
  }

  /**
   * 内容区高度：行少时贴合内容（弹窗自己长到刚好这么大），
   * 超过「50% 屏高」上限后就固定在上限高度、内部连续滚动（无极翻页）。
   */
  private detailContentH(): number {
    const cap: number = this.detailPageHeight()
    const all: number = this.detailAllRowsH()
    const min: number = DETAIL_LINE_H + DETAIL_ROW_GAP
    return Math.max(min, Math.min(all, cap))
  }

  /** 内容是否超出上限：超了才需要滚动与上下边缘虚化 */
  private detailOverflow(): boolean {
    return this.detailAllRowsH() > this.detailPageHeight() + 0.5
  }

  /** 量取某个 id 元素的矩形（返回 vp 尺寸与中心点；量不到时退化成 0） */
  private cardRect(id: string): RectLike {
    try {
      const r = this.getUIContext().getComponentUtils().getRectangleById(id)
      if (r === undefined || r === null) {
        return { w: 0, h: 0, cx: 0, cy: 0 }
      }
      const w: number = px2vp(r.size.width)
      const h: number = px2vp(r.size.height)
      const cx: number = px2vp(r.screenOffset.x) + w / 2
      const cy: number = px2vp(r.screenOffset.y) + h / 2
      return { w: w, h: h, cx: cx, cy: cy }
    } catch (err) {
      return { w: 0, h: 0, cx: 0, cy: 0 }
    }
  }

  /** 展开期间把「被点的那张卡」隐形：浮层正好盖在上面，看不到叠影；缩回后再复现 */
  private cardVeil(item: MingziItem): number {
    return this.detailHideCard && this.detailMorphId === `mingzi-card-${item.name}` ? 0 : 1
  }

  /** 名字从「卡片左侧」滑到「弹窗居中」的横向距离（vp） */
  private detailNameShiftMax(): number {
    const cardNameX: number = 18
    const dlgW: number = this.detailBoxWidth()
    const dlgNameX: number = dlgW / 2 - 20   // 居中后名字左缘的近似位置
    return Math.max(24, dlgNameX - cardNameX)
  }

  /** 翻页区高度：弹窗最大 50% 屏高，扣掉标题行与内边距 */
  private detailPageHeight(): number {
    const cap: number = this.windowHeight > 0 ? this.windowHeight * 0.5 : 380
    return Math.max(160, cap - 104)
  }

  /** 标题可用宽度：弹窗宽度扣掉左右内边距 20x2 与两侧 32 */
  private titleCellW(): number {
    return this.detailBoxWidth() - 104
  }

  /** 名字宽度（只在弹窗排版下量；没量到就先按一个字宽估算） */
  private titleNameW(): number {
    return this.detailNameW > 0 ? this.detailNameW : this.titleCellW() * 0.22
  }

  /** 朝代宽度（两端都是 15 号，宽度通用；没量到时按「（先秦）」四字估算） */
  private titleDynW(): number {
    return this.detailDynW > 0 ? this.detailDynW : 62
  }

  /** 弹窗排版下「名字 + 6vp 间距 + 朝代」的总宽 */
  private titleContentW(): number {
    return this.titleNameW() + 6 + this.titleDynW()
  }

  /** 名字横向位移：弹窗排版把整条标题居中；落地时收到卡片文字区左缘（52 - 34 = 18vp） */
  private detailNameX(): number {
    const cellW: number = this.titleCellW()
    const centered: number = Math.max(0, (cellW - this.titleContentW()) / 2)
    return (1 - this.detailTitleCard) * centered + this.detailTitleCard * (-34)
  }

  /** 朝代横向位移：弹窗排版紧跟名字右侧 6vp；落地贴到卡片那一行的最右端（卡右侧内边距 18vp） */
  private detailDynX(): number {
    const t: number = this.detailTitleCard
    const centered: number = Math.max(0, (this.titleCellW() - this.titleContentW()) / 2)
    const followX: number = centered + this.titleNameW() + 6     // 跟着名字
    const dw: number = this.titleDynW()
    const cardX: number = this.detailW - 70 - dw                 // 52 + cardX = detailW - 18 - dw
    return (1 - t) * followX + t * cardX
  }

  /**
   * 弹窗宽度：始终是终态宽度（宽度不变才不会有文字重排）
   * 平板（宽屏）收窄到原来的 70%：一行字不会被拉得太开，视线不用左右来回跑
   */
  private detailBoxWidth(): number {
    const base: number = Math.min(this.windowWidth * 0.88, 720)
    return this.windowWidth > 600 ? base * 0.7 : base
  }

  /** 一行值会占几行：按「值列宽度 / 字号」估算，宽屏自动多容纳几个字 */
  private detailLines(value: string): number {
    const contentW: number = this.detailBoxWidth() - 40 - DETAIL_LABEL_W
    const perLine: number = Math.max(8, Math.floor(contentW / 15))
    return Math.max(1, Math.ceil(Math.max(1, value.length) / perLine))
  }

  /** 卡片展开后的高度：单页按行数累加；需要翻页时按「屏幕 50% 减标题行」限高 */
  private detailBoxHeight(): number {
    // 展开后不需要再裁：单页直接给到屏高的 96%，多页给「50% 限高 + 标题行」
    return this.windowHeight > 0 ? this.windowHeight * 0.96 : 800
  }

  /**
   * 打开详情：卡片「无缝」长成弹窗
   * 起点 = 被点卡片的真实矩形（宽、高、位置、圆角全对齐），所以第一帧就严丝合缝地盖住那张卡；
   * 然后在一条弹簧动画里把宽/高/位置/圆角一起长到终态，背景同时变暗虚化。
   */
  private openDetail(item: MingziItem, area: Area, wx: number, wy: number): void {
    if (this.detailOpen) {
      return
    }
    this.clearDetailTimers()
    this.detailItem = item
    this.detailQueries = this.keyQueries()
    this.detailMorphId = `mingzi-card-${item.name}`
    this.detailRows = 0
    this.detailCloseShown = 0
    // 第一帧标题保持「卡片排版」（名字 18 靠左 + 朝代在右），与卡片本身严丝合缝；
    // 下面和放大同一条动画里再滑到居中 22，交接才是连续的
    this.detailTitleCard = 1
    this.detailNameIn = 0
    this.detailNameShift = -this.detailNameShiftMax()
    this.detailNameLift = 8
    this.detailDynFade = 1
    this.detailDynShift = -10
    this.detailVeil = 0
    this.detailContentFade = 1

    // 起点矩形：宽高取 area（vp），位置用「点击点换算到窗口坐标」= windowX - x（= 被点卡片的左边）。
    // 坑 1：area.globalPosition 与 getRectangleById().windowOffset 在平板右栏这种滚动容器里给的都是
    //       「相对父容器」的值（实测 16vp，真实 650vp），拿它算会把起点算到左栏去。
    // 坑 2：弹窗宽度不能再套 560vp 硬上限，否则平板卡片比它宽，起点第一帧就盖不住卡片。
    const rw: number = area !== undefined && area !== null ? Number(area.width) : 0
    const rh: number = area !== undefined && area !== null ? Number(area.height) : 0
    const okStart: boolean = rw > 0 && rh > 0 && wx > 0 && wy > 0
    this.detailFrom = {
      w: okStart ? rw : 0,
      h: okStart ? rh : 0,
      cx: wx + rw / 2,
      cy: wy + rh / 2
    }
    this.detailW = okStart ? rw : this.detailBoxWidth()
    this.detailH = okStart ? rh : 62
    this.detailOX = okStart ? this.detailFrom.cx - this.windowWidth / 2 : 0
    this.detailOY = okStart ? this.detailFrom.cy - this.windowHeight / 2 : 0
    this.detailRadius = DETAIL_RADIUS_FROM
    Haptics.tick()

    if (isReducedMotion()) {
      this.detailHideCard = true
      this.detailOpen = true
      this.detailVeil = 1
      this.detailW = this.detailBoxWidth()
      this.detailH = this.detailBoxHeight()
      this.detailOX = 0
      this.detailOY = 0
      this.detailRadius = DETAIL_RADIUS_TO
      this.detailNameIn = 1
      this.detailNameShift = 0
      this.detailNameLift = 0
      this.detailDynFade = 0
      this.detailCloseShown = 1
      this.detailRows = 99
      return
    }

    // ① 第一帧：浮层以「卡片的宽/高/位置/圆角」出现，并让列表里那张卡先隐形（不会有叠影）
    this.detailHideCard = true
    this.detailOpen = true
    // ② 隔一帧再长：同帧改数值不会产生动画（起点取的是已渲染值）
    const tGrow = setTimeout(() => {
      this.getUIContext().animateTo({ duration: DETAIL_TITLE_MS, curve: EASE_OUT_STRONG }, () => {
        this.detailTitleCard = 0
      })
      this.getUIContext().animateTo({ duration: DETAIL_MORPH_MS, curve: LAND_SPRING }, () => {
        this.detailW = this.detailBoxWidth()
        this.detailH = this.detailBoxHeight()
        this.detailOX = 0
        this.detailOY = 0
        this.detailRadius = DETAIL_RADIUS_TO
        this.detailVeil = 1
        this.detailNameIn = 1
        this.detailNameShift = 0
        this.detailNameLift = 0
      })
    }, FRAME_MS * 2)
    this.detailTimers.push(tGrow as number)
    // ③ 「（朝代）」与名字同层跟过来，但先淡出并向下分离，落定前消失（不与名字重叠）
    this.getUIContext().animateTo({ duration: DETAIL_DYN_MS, curve: EASE_OUT_STRONG }, () => {
      this.detailDynFade = 0
      this.detailDynShift = 10
    })
    // ④ 落定后：详细行自上而下每行 50ms 依次淡进（一次性演完，之后滚动不再重演）
    const rowCount: number = this.detailPairs().length
    for (let i = 0; i < rowCount; i++) {
      const t = setTimeout(() => {
        this.getUIContext().animateTo({ duration: DETAIL_ROW_MS, curve: EASE_OUT_STRONG }, () => {
          this.detailRows = i + 1
        })
      }, DETAIL_ROWS_DELAY_MS + i * DETAIL_ROW_STEP_MS)
      this.detailTimers.push(t as number)
    }
    const tAll = setTimeout(() => {
      this.detailRows = 99
    }, DETAIL_ROWS_DELAY_MS + rowCount * DETAIL_ROW_STEP_MS + DETAIL_ROW_MS + 40)
    this.detailTimers.push(tAll as number)
    // ⑤ 关闭键在右上角弹出（同样 0.8% 过冲）
    const tClose = setTimeout(() => {
      this.getUIContext().animateTo({ duration: DETAIL_CLOSE_MS, curve: LAND_SPRING }, () => {
        this.detailCloseShown = 1
      })
    }, DETAIL_ROWS_DELAY_MS + 60)
    this.detailTimers.push(tClose as number)
  }

  /**
   * 关闭：详尽信息整块淡出 → 关闭键缩回 → 弹窗按原卡片的宽/高/位置缩回去 → 列表卡片复现
   * 复位放在「缩完并卸载之后」，避免内容在裁切框里闪一下。
   */
  private closeDetail(): void {
    if (!this.detailOpen) {
      return
    }
    this.clearDetailTimers()
    Haptics.tick()

    const resetAll = () => {
      this.detailOpen = false
      this.detailHideCard = false
      this.detailTitleCard = 0
      this.detailNameIn = 0
      this.detailNameShift = -this.detailNameShiftMax()
      this.detailNameLift = 8
      this.detailDynFade = 1
      this.detailDynShift = -10
      this.detailContentFade = 1
      this.detailRows = 0
      this.detailCloseShown = 0
    }

    if (isReducedMotion()) {
      this.detailVeil = 0
      resetAll()
      return
    }
    // ⓪ 卡片一直保持隐形到「缩完并卸载」的那一帧（浮层收缩途中并不总能盖住整张卡片，
    //    提前放出来会看到卡里的名字与浮层里的名字并排）；标题已换装成卡片排版，
    //    所以卸载瞬间卡片出现时看不出差别，也不会突然跳字
    // ① 详细行整块淡出（标题不淡：它要换装成卡片排版后一起缩回去）
    this.getUIContext().animateTo({ duration: DETAIL_OUT_MS, curve: EASE_OUT_STRONG }, () => {
      this.detailContentFade = 0
    })
    // ② 关闭键同时缩回右上角
    this.getUIContext().animateTo({ duration: DETAIL_CLOSE_MS, curve: LAND_SPRING }, () => {
      this.detailCloseShown = 0
    })
    // ③ 内容淡完：宽/高/位置/圆角一起退回原卡片矩形，背景复原
    const tMorph = setTimeout(() => {
      const from: RectLike = this.detailFrom
      this.getUIContext().animateTo({ duration: DETAIL_MORPH_MS, curve: LAND_SPRING }, () => {
        this.detailW = from.w > 0 ? from.w : this.detailW
        this.detailH = from.h > 0 ? from.h : this.detailH
        this.detailOX = from.w > 0 ? from.cx - this.windowWidth / 2 : this.detailOX
        this.detailOY = from.h > 0 ? from.cy - this.windowHeight / 2 : this.detailOY
        this.detailRadius = DETAIL_RADIUS_FROM
        this.detailVeil = 0
      })
      // 标题单独换装：几何用弹簧（起步很猛），标题若跟着弹簧会在头两帧就冲到终点，像「啪」地跳过去；
      // 换成同长的匀减速曲线，位移/字号/朝代的淡入都匀速滑到位，落到卡片尺寸时排版刚好也是卡片的样子
      // 时长比弹簧短：弹簧 ~250ms 就收敛到卡片尺寸，标题若更慢会在落地时还没排好、再补一段「挪字」
      this.getUIContext().animateTo({ duration: DETAIL_TITLE_MS, curve: EASE_OUT_STRONG }, () => {
        this.detailTitleCard = 1
      })
      const tHide = setTimeout(() => {
        resetAll()
      }, DETAIL_MORPH_MS)
      this.detailTimers.push(tHide as number)
    }, DETAIL_OUT_MS + DETAIL_CARD_HOLD_MS)
    this.detailTimers.push(tMorph as number)
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
  private applySteps(next: SearchStep[], handoff: boolean = false): void {
    if (handoff) {
      // 首次检索那次：摘要框的预览已经在屏幕上就位，这里「原地交班」——
      // 整块切换不做透明度过渡，否则预览刚消失、真框又从透明淡进，会看到一次发暗的闪
      this.results = this.search(next)
      this.hasSearched = this.steps.length > 0
      this.panelOpen = false
      this.panelShown = 0
      return
    }
    animateTo({ duration: MOTION_SLOW_MS, curve: EASE_OUT_STRONG }, () => {
      this.results = this.search(next)
      this.hasSearched = this.steps.length > 0
      this.panelOpen = false
    })
  }

  /** 按条件顺序重建检索（重置后依次叠加），结果与条件列表同步刷新 */
  private search(next: SearchStep[]): MingziItem[] {
    this.service.reset()
    let res: MingziItem[] = []
    for (const s of next) {
      res = this.service.search(s.mode, s.query)
    }
    this.steps = next
    this.searchCount = this.service.depth
    return res
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
    if (!this.hasSearched) {
      // 首次检索：条件区向上收进摘要框、检索键就地分裂（首检索后条件只有 1 条 →
      // 操作行是「清空所有 + 二次检索」两枚，所以分裂成两键）
      this.keyPills = 2
      this.playInputExit(staged)
      return
    }
    this.applySteps(staged)
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
      this.panelOpen = false
      this.panelShown = 0
      this.swapSubtitle()
    }
  }

  private onClearAll(): void {
    for (const t of this.exitTimers) {
      clearTimeout(t)
    }
    this.exitTimers = []
    for (const t of this.panelTimers) {
      clearTimeout(t)
    }
    this.panelTimers = []
    this.service.reset()
    // 复原的回弹：大「检索」键在检索后不存在，复原时让它**从操作行的位置落回原位**，
    // 走与分裂同一条落位弹簧（过冲 0.8%），于是「散开 / 合回」两端是同一套手感
    const gap: number = this.windowWidth > 600 ? 16 : 12
    const keyY: number = this.geoCenterY[EXIT_SLOTS - 1]
    const actY: number = this.actionCenterY(gap)
    const drop: number = (keyY > 0 && actY > 0) ? keyY - actY : 0
    const bounce: boolean = !isReducedMotion() && drop > 0
    if (bounce) {
      // 写在 animateTo 之前 —— 新树的第一帧就带着这个位移，不会先闪在原位
      this.keyLift = drop
    }
    // 回到初始界面是一次「整块换树」：放进 animateTo 里，结果淡出、九行条件淡入
    animateTo({ duration: MOTION_BASE_MS, curve: EASE_OUT_STRONG }, () => {
      this.results = []
      this.hasSearched = false
      this.searchCount = this.service.depth
      this.steps = []
      this.selectedValues = ['', '', '', '', '', '', '', '', '']
      this.panelOpen = false
      this.panelShown = 0
      this.exitActive = false
      this.exitShown = 0
    })
    this.swapSubtitle()
    if (bounce) {
      // 先让新树带着 keyLift 渲染一帧（animateTo 取「已渲染的值」），再弹回原位
      this.exitTimers.push(setTimeout(() => {
        this.getUIContext().animateTo({ duration: LAND_SPRING_MS, curve: LAND_SPRING }, () => {
          this.keyLift = 0
        })
      }, FRAME_MS))
    }
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
    if (this.panelOpen) {
      // 抽屉开着：先把展开区收回去（内容先退、框再缩），收完才落结果
      this.collapsePanel(() => {
        this.applySteps(merged)
      })
      return
    }
    this.applySteps(merged)
  }

  // 系统返回手势指令：执行「返回上一级检索」
  onUndoCmd(): void {
    this.onUndo()
  }

  // ==================== UI 片段 ====================

  // 大标题区（v3.3 空间化排版）：标题放大加粗，「检索 N 次」升级为玻璃胶囊
  @Builder
  Header() {
    Row() {
      Column() {
        Text('众里寻他')
          .fontSize(26)
          .fontWeight(700)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 6 })
        Text(this.subText)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .opacity(this.subOpacity)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 检索次数胶囊：半透明玻璃底 + 细描边
      Row() {
        Text(`检索 ${this.searchCount} 次`)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
      }
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .borderRadius(999)
      .backgroundColor($r('app.color.glass_card_bg'))
      .border({ width: 1, color: $r('app.color.glass_card_edge') })

      Blank(8)

      // 大标题右侧的「信息」按钮：应用说明与使用方法（三个检索页共用同一个对话框）
      InfoButton()
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .margin({ bottom: 16 })
    .opacity(this.enterOpacity(0))
    .translate({ x: this.enterShift(0) })
    // 量一下标题底边：摘要框就贴在它下面，退场元素的消失点由它推算（见 noteAnchor）
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.noteAnchor(newArea)
    })
  }

  /**
   * 首次检索键：条件填好后点它开始检索
   * 检索开始后自动隐藏（由三键接手），「清空所有」回到初始状态时重新出现
   */
  /**
   * 首次检索键：条件填好后点它开始检索
   *
   * 首次检索时它不是飞进摘要框，而是「就地分裂」：整块上移到操作行的位置并淡出，
   * 同时真正的两枚按键从它的中心散开、长到各自槽位上（终点取真实按钮的矩形）。
   */
  @Builder
  SearchButton() {
    Row() {
      GlassButton({ label: '检索', primary: true, desc: '按已填写的条件开始检索', action: () => {
        this.onStartSearch()
      } })
    }
    .width('100%')
    // 大键淡出让位；整块的不透明度不走退场（那样会直接消失、把分裂过程掐断）
    .opacity(this.enterOpacity(2) * this.splitP)
    .translate({ x: this.enterShift(2), y: this.keyLift })
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.noteCenter(EXIT_SLOTS - 1, newArea)
      this.keyWidth = newArea.width as number
      this.keyX = newArea.globalPosition.x as number
    })
  }

  /**
   * 条件摘要框（Blur Glide Menu）
   *
   * 收起时只有一行摘要；点一下框向下延伸，把九行条件「包在同一个圆角矩形里」展开，
   * 里面的元素自上而下逐项淡进；再点一下反向收起。
   * 外壳始终是同一个框、半径不变，只是高度在变（带一点回弹），像菜单从摘要条里滑出来。
   */
  @Builder
  ConditionPanel() {
    Column() {
      // 摘要行：点它开合（恒定 56 高，不参与展开区的懒加载，避免开合时抖一下）
      this.PanelSummaryRow(true, this.summaryText())

      if (this.panelOpen) {
        Stack({ alignContent: Alignment.Bottom }) {
          Scroll() {
            Column() {
              ForEach(this.MODES, (def: ModeDef, idx: number) => {
                this.PanelModeRow(def, idx)
              }, (def: ModeDef) => def.mode)
              Text(MODE_HINT)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
                .textAlign(TextAlign.Center)
                .opacity(this.panelOpacity(PANEL_SLOTS - 1))
                .translate({ y: this.panelShift(PANEL_SLOTS - 1) })
            }
            .width('100%')
          }
          .width('100%')
          .constraintSize({ maxHeight: PANEL_MAX_H })
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .padding({ left: 14, right: 14, bottom: 14 })

          // 底部渐隐：九行比框高时提示「下面还有」，避免被框边直接切断
          Column()
            .width('100%')
            .height(20)
            .linearGradient({
              angle: 180,
              colors: [[$r('app.color.panel_bg_clear'), 0], [$r('app.color.panel_bg'), 1]]
            })
            .hitTestBehavior(HitTestMode.None)
            .opacity(this.panelShown > 2 ? 1 : 0)
        }
        .width('100%')
        // 展开区自己也有一次淡入：块整体出现时别硬切
        .transition(TransitionEffect.OPACITY.animation({ duration: MOTION_BASE_MS, curve: EASE_OUT_STRONG }))
      }
    }
    .width('100%')
    .margin({ bottom: PANEL_MARGIN_BOTTOM })
    .borderRadius(14)
    // 暖色半透明底 + backdropBlur（只虚化背后内容，不叠系统材质那层灰白纱）
    .backgroundColor($r('app.color.panel_bg'))
    .backdropBlur(20)
    .border({ width: 1, color: $r('app.color.glass_card_edge') })
    .clip(true)
    // 首次检索：条件区收进摘要框之后，摘要框自己淡进。
    // 只做不透明度 —— 预览层已经占在同一位置，再加 6vp 位移会看到框「抽一下」
    .transition(TransitionEffect.OPACITY
      .animation({ duration: MOTION_BASE_MS, curve: EASE_OUT_STRONG }))
    .opacity(this.enterOpacity(1))
    .translate({ x: this.enterShift(1) })
  }

  /** 摘要行的内容（收起态那一行）；tapable = 预览态要关掉点击 */
  @Builder
  PanelSummaryRow(tapable: boolean, text: string) {
    Row() {
      Column() {
        Text('检索条件')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
        Blank(2)
        Text(text)
          .fontSize(14)
          .fontWeight(500)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Row({ space: 2 }) {
        Text(this.panelOpen ? '收起' : '展开修改')
          .fontSize(12)
          .fontColor($r('app.color.primary'))
        SymbolGlyph(this.panelOpen ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
          .fontSize(13)
          .fontColor([$r('app.color.primary')])
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(PANEL_ROW_H)
    .padding({ left: 14, right: 14 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (tapable) {
        this.togglePanel()
      }
    })
  }

  /**
   * 首次检索：摘要框在条件区退场「同时」浮上来
   *
   * 绝对定位压在槽位左上角（= 真摘要框将来所在的位置），只演一次；位置、圆角、底、
   * 模糊、描边都与 ConditionPanel 一致，退场结束整块交班时看不出换过
   */
  @Builder
  PanelPreview() {
    Column() {
      this.PanelSummaryRow(false, this.pendingSummary)
    }
    .width('100%')
    .borderRadius(14)
    .backgroundColor($r('app.color.panel_bg'))
    .backdropBlur(20)
    .border({ width: 1, color: $r('app.color.glass_card_edge') })
    .clip(true)
    .opacity(this.panelIntro)
    .hitTestBehavior(HitTestMode.None)
    .position({ x: 0, y: 0 })
  }

  @Builder
  MenuModeRow(def: ModeDef, slot: number) {
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
    .accessibilityText(`${def.label}检索模式，已选 ${this.selectedOf(def.mode)}`)
    .accessibilityDescription('点击弹出滑动选择器，上下滑动选择选项')
    .onClick(() => {
      this.openOptionPicker(def.mode)
    })
    .margin({ bottom: 8 })
    .opacity(this.enterOpacity(slot))
    .translate({ x: this.enterShift(slot) })
  }

  /**
   * 输入模式行（v3.2.2）：直接在行里填，不再弹底部面板
   *
   * 左侧是模式名，右侧是 TextInput（右对齐，和原来「值显示在右边」的观感一致）；
   * 边打字边写回 selectedValues，点「检索 / 二次检索」时才真正应用。
   */
  @Builder
  InputModeRow(def: ModeDef, slot: number) {
    Row() {
      Text(def.label)
        .fontSize(15)
        .fontWeight(500)
        .fontColor($r('app.color.text_primary'))
        .margin({ right: 8 })
      TextInput({ text: this.selectedOf(def.mode), placeholder: this.inputPlaceholder(def.mode) })
        .layoutWeight(1)
        .height(44)
        .padding({ left: 0, right: 0 })
        .fontSize(15)
        .fontWeight(this.selectedOf(def.mode).length > 0 ? 600 : 400)
        .fontColor(this.selectedOf(def.mode).length > 0 ? $r('app.color.match_highlight') : $r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_secondary'))
        .placeholderFont({ size: 14 })
        .textAlign(TextAlign.End)
        .maxLength(20)
        .backgroundColor(Color.Transparent)
        .onChange((v: string) => {
          this.stage(def.mode, v)
        })
    }
    .width('100%')
    .height(48)
    .padding({ left: 14, right: 14 })
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.cell_border'), style: BorderStyle.Solid })
    .margin({ bottom: 8 })
    .opacity(this.enterOpacity(slot))
    .translate({ x: this.enterShift(slot) })
    .accessibilityText(`${def.label}检索条件，当前 ${this.selectedOf(def.mode)}`)
    .accessibilityDescription('直接在行内输入关键词')
  }

  @Builder
  ModeList() {
    Column() {
      ForEach(this.MODES, (def: ModeDef, idx: number) => {
        this.ModeListItem(def, idx)
      }, (def: ModeDef) => def.mode)
    }
    .width('100%')
  }

  /** 一行模式的「退场外壳」：正常态下它承担向上收进摘要框的位移 / 缩放 / 淡出 */
  @Builder
  ModeListItem(def: ModeDef, idx: number) {
    Column() {
      if (def.isMenu) {
        this.MenuModeRow(def, 4 + idx)
      } else {
        this.InputModeRow(def, 4 + idx)
      }
    }
    .width('100%')
    .opacity(this.exitOpacity(idx))
    .translate({ y: this.exitShiftY(idx) })
    .scale({ x: this.exitScale(idx), y: this.exitScale(idx) })
    // 量一下自己在窗口里的中心：退场时要沿这段距离向上收（见 exitShiftY）
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.noteCenter(idx, newArea)
    })
  }

  /** 展开区里的一行：跟着框一起向下延伸，逐项淡进 */
  @Builder
  PanelModeRow(def: ModeDef, idx: number) {
    Column() {
      if (def.isMenu) {
        this.MenuModeRow(def, 4 + idx)
      } else {
        this.InputModeRow(def, 4 + idx)
      }
    }
    .width('100%')
    .opacity(this.panelOpacity(idx))
    .translate({ y: this.panelShift(idx) })
  }

  @Builder
  ResultArea(rightSide: boolean) {
    Column() {
      if (this.results.length === 0) {
        // 未检索到该名士（空状态：图标 + 文案）
        Column() {
          SymbolGlyph($r('sys.symbol.person_crop_circle_fill'))
            .fontSize(40)
            .fontColor([$r('app.color.text_secondary')])
            .opacity(rightSide ? this.enterROpacity(0) : 1)
            .translate({ x: rightSide ? this.enterRShift(0) : 0 })
          Blank(12)
          Text('未检索到该名士')
            .fontSize(18)
            .fontWeight(600)
            .fontColor($r('app.color.text_primary'))
            .opacity(rightSide ? this.enterROpacity(1) : 1)
            .translate({ x: rightSide ? this.enterRShift(1) : 0 })
          Blank(8)
          Text('请调整检索条件后重试')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .opacity(rightSide ? this.enterROpacity(2) : 1)
            .translate({ x: rightSide ? this.enterRShift(2) : 0 })
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
            .opacity(rightSide ? this.enterROpacity(0) : 1)
            .translate({ x: rightSide ? this.enterRShift(0) : 0 })
          Blank(12)
          MingziResultCard({ item: this.results[0], morphId: `mingzi-card-${this.results[0].name}` })
            .opacity((rightSide ? this.enterROpacity(1) : 1) * this.cardVeil(this.results[0]))
            .translate({ x: rightSide ? this.enterRShift(1) : 0 })
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.scale({ x: 0.94, y: 0.94 }))
              .animation({ duration: MOTION_SLOW_MS, curve: EASE_OUT_STRONG }))
            .onClick((event: ClickEvent) => {
              this.openDetail(this.results[0], event.target.area, event.windowX - event.x, event.windowY - event.y)
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      } else {
        // 多结果：列表（卡片错峰入场：每张延迟 25ms 依次淡入上滑，最多错 6 档）
        Column() {
          Text(`匹配结果 (${this.results.length})`)
            .fontSize(16)
            .fontWeight(500)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .margin({ bottom: 8 })
            .opacity(rightSide ? this.enterROpacity(0) : 1)
            .translate({ x: rightSide ? this.enterRShift(0) : 0 })

          ForEach(this.results, (item: MingziItem, idx: number) => {
            MingziResultCard({ item: item, morphId: `mingzi-card-${item.name}` })
              .margin({ bottom: 8 })
              .opacity((rightSide ? this.enterROpacity(1 + idx) : 1) * this.cardVeil(item))
              .translate({ x: rightSide ? this.enterRShift(1 + idx) : 0 })
              .transition(TransitionEffect.OPACITY
                .combine(TransitionEffect.translate({ y: 16 }))
                .animation({ duration: MOTION_BASE_MS, curve: EASE_OUT_STRONG, delay: staggerDelay(idx) }))
              .onClick((event: ClickEvent) => {
                this.openDetail(item, event.target.area, event.windowX - event.x, event.windowY - event.y)
              })
          }, (item: MingziItem) => item.name)
        }
        .width('100%')
      }
    }
    .width('100%')
    .opacity(rightSide ? 1 : this.enterOpacity(13))
    .translate({ x: rightSide ? 0 : this.enterShift(13) })
  }

  // 检索后的操作键（与成语页同一套「沉浸光感」玻璃按钮）
  //
  // 首次检索时这套按键在退场一开始就挂上（此时 opacity = 0，看不见），
  // 好处是：① 它们量到的矩形就是最终布局；② 换画面时这棵子树不重建，不会有掉帧的接缝。
  // 位移必须挂在「外层容器」上，不能直接链在 GlassButton 上 —— 自定义组件外侧再加属性会套一层
  // 包装节点，玻璃按钮内置的 layoutWeight(1) 便失去参照，每颗都会被撑成整行宽。
  @Builder
  ActionButtons() {
    Row({ space: KEY_GAP }) {
      Row() {
        GlassButton({ label: '清空所有', primary: false, desc: '清除所有检索结果，恢复初始状态', action: () => {
          this.onClearAll()
        } })
      }
      .layoutWeight(1)
      .translate({ x: this.enterShift(2) + this.splitDx(0), y: this.splitY })

      // 「清空当前」= 撤销一层检索条件（没有上一层时就不显示）
      if (this.steps.length >= 2) {
        Row() {
          GlassButton({ label: '清空当前', primary: false, desc: '仅清除当前这次检索，返回上一级检索结果', action: () => {
            this.onUndo()
          } })
        }
        .layoutWeight(1)
        .translate({ x: this.enterShift(2) + this.splitDx(1), y: this.splitY })
      }

      // 「二次检索」恒显示：它是「应用新填写条件」的唯一入口
      Row() {
        GlassButton({ label: '二次检索', primary: true, desc: '把新填写的条件叠加到上次检索结果之上', action: () => {
          // 摘要框收起时条件一个字都没改，直接再检索等于白跑一次 —— 先把框展开让用户改
          if (!this.panelOpen) {
            this.expandPanel()
            return
          }
          this.onSecondSearch()
        } })
      }
      .layoutWeight(1)
      .translate({ x: this.enterShift(2) + this.splitDx(this.steps.length >= 2 ? 2 : 1), y: this.splitY })
    }
    .width('100%')
    // 换画面那一刻按键还在检索键的位置上（不可见），随后一边上飞一边淡入
    .opacity(this.exitActive ? 1 - this.splitP : 1)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.actionX = newArea.globalPosition.x as number
      this.actionY = newArea.globalPosition.y as number
      this.actionW = newArea.width as number
      this.actionH = newArea.height as number
    })
  }

  // ==================== 检索退场 / 摘要框开合 ====================

  /**
   * 记录「摘要框中心」的窗口 y —— 首次检索时条件区就收进这一点
   *
   * 摘要框紧跟在标题下方、恒定 56 高（标题 margin 下 16），所以中心 = 标题底边 + 16 + 28。
   * 用标题量而不是直接量摘要框：退场发生时摘要框还没被创建出来。
   */
  private noteAnchor(area: Area): void {
    this.panelAnchorY = (area.globalPosition.y as number) + (area.height as number) + 44
  }

  /** 记录某个元素中心的窗口 y：退场时它要向上走这么多才落到摘要框中心 */
  private noteCenter(slot: number, area: Area): void {
    this.geoCenterY[slot] = (area.globalPosition.y as number) + (area.height as number) / 2
  }

  /** 该项是否已经退场 */
  private exited(slot: number): boolean {
    return this.exitActive && this.exitShown > slot
  }

  private exitOpacity(slot: number): number {
    return this.exited(slot) ? 0 : 1
  }

  /** 退场时轻微缩小，配合向上位移读起来像「被吸进摘要框」而不是单纯上滑 */
  private exitScale(slot: number): number {
    return this.exited(slot) ? 0.9 : 1
  }

  /** 退场纵向位移（负 = 向上）：距离就是「自己中心 → 摘要框中心」；量不到时按序号兜底 */
  private exitShiftY(slot: number): number {
    if (!this.exited(slot)) {
      return 0
    }
    const center: number = this.geoCenterY[slot]
    if (this.panelAnchorY > 0 && center > 0) {
      return -(center - this.panelAnchorY)
    }
    return -(56 + slot * 60)
  }

  /**
   * 按键落点的中心 Y（vp）——用解析式算，不用「当前布局实测」
   *
   * 退场期间九行条件仍在布局里占位（只是淡出），此刻量到的操作行位置还在下面；
   * 换画面后条件区消失、摘要框 56 高就位，操作行会整体跳上来。
   * 直接按「面板顶 + 摘要行 + 下边距 + 槽位间距 + 按钮半高」推最终位置，
   * 按键在整个分裂过程中就能连续飞过去，换画面时不会再有跳动。
   */
  private actionCenterY(gap: number): number {
    const h: number = this.actionH > 0 ? this.actionH : 48
    // panelAnchorY 是摘要框的**中心**，所以先退回半行高度，再往下堆
    return this.panelAnchorY + PANEL_ROW_H / 2 + PANEL_MARGIN_BOTTOM + gap + h / 2
  }

  /** 第 index 枚按键相对自己槽位的横向偏移：起点全叠在检索键正中，终点是各自槽位 */
  private splitDx(index: number): number {
    if (this.actionW <= 0 || this.keyWidth <= 0) {
      return 0
    }
    const n: number = this.keyPills
    const pw: number = (this.actionW - (n - 1) * KEY_GAP) / n
    const myCenter: number = this.actionX + index * (pw + KEY_GAP) + pw / 2
    const keyCenter: number = this.keyX + this.keyWidth / 2
    // 只有演出期间才带偏移：splitP = 1 时整排叠在检索键正中，收到 0 时各回各的槽位；
    // 演出结束后 splitP 会复位为 1（大键还要用），所以这里必须靠 exitActive 归零
    const k: number = this.exitActive ? this.splitP : 0
    return (keyCenter - myCenter) * k
  }

  private clearPanelTimers(): void {
    for (const t of this.panelTimers) {
      clearTimeout(t)
    }
    this.panelTimers = []
  }

  /** 展开区第 slot 项是否已放出 */
  private panelOpacity(slot: number): number {
    return this.panelShown > slot ? 1 : 0
  }

  /** 展开区第 slot 项的起始位移：从上方 10vp 滑下来，跟着框一起向下延伸 */
  private panelShift(slot: number): number {
    return this.panelShown > slot ? 0 : -10
  }

  /** 摘要行文案：把已应用的条件按顺序连起来 */
  private summaryText(): string {
    if (this.steps.length === 0) {
      return '未填条件'
    }
    return this.steps.map((s: SearchStep) => s.label).join(' · ')
  }

  /**
   * 展开：框先开始长高（弹簧，带一点回弹），随后里面九行自上而下逐项淡进
   *
   * 先让框动、内容晚 40ms 才出现：否则内容会和还在长高的框边缘打架。
   */
  private expandPanel(): void {
    this.clearPanelTimers()
    if (isReducedMotion()) {
      this.panelShown = PANEL_SLOTS
      this.panelOpen = true
      return
    }
    this.panelShown = 0
    this.getUIContext().animateTo({ curve: PANEL_SPRING, duration: PANEL_DURATION_MS }, () => {
      this.panelOpen = true
    })
    for (let i = 0; i < PANEL_SLOTS; i++) {
      this.panelTimers.push(setTimeout(() => {
        this.getUIContext().animateTo({ duration: PANEL_ITEM_MS, curve: EXIT_CURVE }, () => {
          this.panelShown = i + 1
        })
      }, PANEL_START_MS + i * PANEL_STEP_MS))
    }
  }

  /**
   * 收起：内容自下而上先退（后进先出），最后框再缩回收起态
   *
   * onDone：框开始缩回时回调（二次检索要在收完之后才落结果）。
   */
  private collapsePanel(onDone?: () => void): void {
    this.clearPanelTimers()
    if (isReducedMotion()) {
      this.panelOpen = false
      this.panelShown = 0
      if (onDone !== undefined) {
        onDone()
      }
      return
    }
    for (let i = PANEL_SLOTS; i > 0; i--) {
      const delay: number = (PANEL_SLOTS - i) * PANEL_COLLAPSE_STEP_MS
      this.panelTimers.push(setTimeout(() => {
        this.getUIContext().animateTo({ duration: MOTION_FAST_MS, curve: EASE_OUT_STRONG }, () => {
          this.panelShown = i - 1
        })
      }, delay))
    }
    this.panelTimers.push(setTimeout(() => {
      this.getUIContext().animateTo({ curve: PANEL_SPRING, duration: PANEL_DURATION_MS }, () => {
        this.panelOpen = false
      })
      this.panelShown = 0
      if (onDone !== undefined) {
        onDone()
      }
    }, (PANEL_SLOTS - 1) * PANEL_COLLAPSE_STEP_MS + PANEL_COLLAPSE_TAIL_MS))
  }

  private togglePanel(): void {
    Haptics.tick()
    if (this.panelOpen) {
      this.collapsePanel()
    } else {
      this.expandPanel()
    }
  }

  /**
   * 首次检索的退场演出
   *
   * 时间线：
   *   0ms       点「检索」——这一帧就开始分裂
   *   16→346ms  两枚按键一边上飞一边淡入，大键同速上浮、同时淡出（splitP 1 → 0）
   *   0→310ms   九行条件自上而下每 20ms 淡出（与分裂同时进行）
   *   40→270ms  摘要框预览浮上来（换画面之前就淡完，交班时看不出换过）
   *   346ms     按键已落位 → 换画面：条件区退场、摘要框 56 高就位，布局整体上移；
   *             同一帧 splitY 归零，一加一减正好抵消，按键停着不动；结果在这之后才出现
   *   346→646ms 摘要框预览与真摘要框交班，随后撤掉预览层、临时态复位
   */
  /** 副标题换字：整段淡出（110ms）→ 换文案 → 淡入（200ms），不硬切 */
  private swapSubtitle(): void {
    const next: string = this.hasSearched ? SUB_REFINE : SUB_EDIT
    if (next === this.subText) {
      return
    }
    for (const t of this.subTimers) {
      clearTimeout(t)
    }
    this.subTimers = []
    if (isReducedMotion()) {
      this.subText = next
      this.subOpacity = 1
      return
    }
    this.getUIContext().animateTo({ duration: MOTION_FAST_MS, curve: EASE_OUT_STRONG }, () => {
      this.subOpacity = 0
    })
    this.subTimers.push(setTimeout(() => {
      this.subText = next
      this.getUIContext().animateTo({ duration: MOTION_BASE_MS, curve: EASE_OUT_STRONG }, () => {
        this.subOpacity = 1
      })
    }, MOTION_FAST_MS + 20))
  }

  private playInputExit(next: SearchStep[]): void {
    for (const t of this.exitTimers) {
      clearTimeout(t)
    }
    this.exitTimers = []
    // 系统「减弱动画」开着：这套位移 + 缩放整支跳过，结果直接到位
    if (isReducedMotion()) {
      this.exitActive = false
      this.splitP = 1
      this.panelIntro = 0
      this.applySteps(next, true)
      this.swapSubtitle()
      return
    }
    this.exitActive = true
    this.exitShown = 0
    this.pendingSummary = next.length > 0 ? next.map((s: SearchStep) => s.label).join(' · ') : '未填条件'
    this.panelIntro = 0
    this.splitP = 1
    this.splitY = 0
    this.keyLift = 0
    // ① 点击「检索」的这一帧就开始分裂：检索键与按键此刻叠在同一个槽位，
    //    把按键的终点先算成「换画面之后它们的中心」，位移量 = 终点 − 当前中心（负数 = 向上）
    const gap: number = this.windowWidth > 600 ? 16 : 12
    const key: number = this.geoCenterY[EXIT_SLOTS - 1]
    const target: number = this.actionCenterY(gap)
    const rise: number = (key > 0 && target > 0) ? target - key : 0
    this.exitTimers.push(setTimeout(() => {
      // 纵向交给落位弹簧：飞到终点时会过冲约 0.8% 再收回，落位那一下有「弹」的感觉
      this.getUIContext().animateTo({ duration: KEY_MORPH_MS, curve: LAND_SPRING }, () => {
        this.splitY = rise
        this.keyLift = rise
      })
      // 横向扩散与淡出仍用 ease-out：不透明度不该有过冲（过冲会闪）
      this.getUIContext().animateTo({ duration: KEY_MORPH_MS, curve: EXIT_CURVE }, () => {
        this.splitP = 0
      })
    }, SPLIT_FRAME_MS))
    // ② 条件区同时淡出：每 20ms 一行，按键落位之前正好淡完
    for (let i = 0; i < EXIT_SLOTS - 1; i++) {
      this.exitTimers.push(setTimeout(() => {
        this.getUIContext().animateTo({ duration: EXIT_DURATION_MS, curve: EXIT_CURVE }, () => {
          this.exitShown = i + 1
        })
      }, i * EXIT_STEP_MS))
    }
    // ③ 摘要框预览与淡出同时浮上来
    this.exitTimers.push(setTimeout(() => {
      this.getUIContext().animateTo({ duration: PANEL_INTRO_MS, curve: EASE_OUT_SOFT }, () => {
        this.panelIntro = 1
      })
    }, PANEL_INTRO_DELAY_MS))
    // ④ 按键落位之后再换画面：布局整体上移，同时 splitY 归零 —— 两者抵消，按键停在原地
    this.exitTimers.push(setTimeout(() => {
      this.applySteps(next, true)
      this.exitShown = 0
      this.splitY = 0
      this.keyLift = 0
    }, FLIP_MS))
    // ⑤ 交班：预览层撤掉、各种临时态复位（splitP 要给下次检索留着）
    this.exitTimers.push(setTimeout(() => {
      this.exitActive = false
      this.panelIntro = 0
      this.splitP = 1
      this.splitY = 0
      this.keyLift = 0
      // 副标题等整套动画放完再整段换字（淡出→淡入）
      this.swapSubtitle()
    }, FLIP_MS + HANDOFF_MS))
  }

  // ==================== 切页进场（v3.3） ====================

  private clearEnterTimers(): void {
    for (const t of this.enterTimers) {
      clearTimeout(t)
    }
    this.enterTimers = []
    for (const t of this.enterTimersR) {
      clearTimeout(t)
    }
    this.enterTimersR = []
  }

  /** 第 slot 项是否已经放出：用下标比较，逐项自增，后一道令不会重写前一项的终值 */
  private enterShownAt(slot: number): boolean {
    return this.enterShown > slot
  }

  private enterOpacity(slot: number): number {
    return this.enterShownAt(slot) ? 1 : 0
  }

  /** 起始横向偏移（vp）：正数 = 从右侧弹回来 */
  private enterShift(slot: number): number {
    return this.enterShownAt(slot) ? 0 : ENTER_OFFSET_X * this.enterDir
  }

  /** 右栏第 slot 项是否已放出；超出项数的按最后一项算，免得末尾忽然整片弹出 */
  private enterShownRAt(slot: number): boolean {
    return this.enterShownR > Math.min(slot, this.RIGHT_SLOTS - 1)
  }

  private enterROpacity(slot: number): number {
    return this.enterShownRAt(slot) ? 1 : 0
  }

  private enterRShift(slot: number): number {
    return this.enterShownRAt(slot) ? 0 : ENTER_OFFSET_X * this.enterDir
  }

  /**
   * 右栏背景遮罩的横向渐变：不透明的一端放在「进场来的那一侧」，
   * 淡出时就像从那一侧向另一侧扫开（方向与左栏的横向位移一致）
   */
  private rightVeilColors(): Array<[ResourceColor, number]> {
    return this.enterDir > 0
      // 往右切页（enterDir +1）：左半边先盖着、右半边先露出来 —— 揭开的方向也是从右往左
      ? [[$r('app.color.background'), 0], [$r('app.color.veil_clear'), 1]]
      : [[$r('app.color.veil_clear'), 0], [$r('app.color.background'), 1]]
  }

  /**
   * 收到外壳的进场指令：先无动画藏起全部元素，再每 50ms 放出一项
   *
   * 一项一条 animateTo：动画参数不能攒在一条里分批触发；
   * 每道令改的又是不同的下标（enterShown = i + 1），所以不会互相覆盖。
   */
  onEnterTick(): void {
    this.clearEnterTimers()
    // 方向看序号是变大还是变小：往后切页（序号变大）从右侧弹入，往前切页从左侧弹入，
    // 与系统横向平移的方向一致，元素不会逆着页面滑动的方向进场
    this.enterDir = this.enterTick > this.lastEnterTick ? 1 : -1
    this.lastEnterTick = this.enterTick
    this.enterShown = 0
    this.enterShownR = 0
    const step: number = enterStepFor(this.ENTER_SLOTS)
    for (let i = 0; i < this.ENTER_SLOTS; i++) {
      this.enterTimers.push(setTimeout(() => {
        this.getUIContext().animateTo({ curve: ENTER_SPRING }, () => {
          this.enterShown = i + 1
        })
      }, ENTER_START_DELAY_MS + i * step))
    }
    this.enterTimers.push(setTimeout(() => {
      this.enterShown = ENTER_ALL_SHOWN
    }, enterFinishMs(this.ENTER_SLOTS)))
    // 平板右栏：**整块**进场，不再逐项 —— 与左栏同一时刻起步、同一方向；
    // 底下再压一层横向渐隐的底色，扫过去之后才露出内容（「左右淡进淡出」）
    this.enterShownR = ENTER_ALL_SHOWN
    if (this.windowWidth > 600) {
      this.rightEnter = 0
      this.rightVeil = 1
      this.enterTimersR.push(setTimeout(() => {
        this.getUIContext().animateTo({ duration: RIGHT_ENTER_MS, curve: EASE_OUT_STRONG }, () => {
          this.rightEnter = 1
        })
      }, ENTER_START_DELAY_MS))
      this.enterTimersR.push(setTimeout(() => {
        this.getUIContext().animateTo({ duration: RIGHT_VEIL_MS, curve: EASE_OUT_STRONG }, () => {
          this.rightVeil = 0
        })
      }, ENTER_START_DELAY_MS + 40))
    }
  }

  // ==================== 页面构建 ====================

  @Builder
  NarrowLayout() {
    Column() {
      if (!this.hasSearched) {
        // 未检索：标题 + 九行条件 + 大「检索」键**整体可滚动**。
        // 小窗（悬浮窗 / 分屏）里视口很矮，九行条件本身就超过一屏；
        // 若用固定 Column，会把「检索」键顶到屏幕外，而且没法滚动 —— 这里统一放进 Scroll。
        Scroll() {
          Column() {
            this.Header()
            // 条件槽位：未检索时是九行模式；首次检索时靠预览层交班
            Stack({ alignContent: Alignment.TopStart }) {
              Column() {
                this.ModeList()
              }
              .width('100%')

              // 首次检索：摘要框预览层（绝对定位，不参与布局，退场一开始就浮上来）
              if (this.exitActive) {
                this.PanelPreview()
              }
            }
            .width('100%')
            Blank(12)
            // 操作槽位：初始只有一枚大「检索」键；首次检索时它一边上移一边淡出，
            // 同时两枚真按键从它的中心散开落到这里（zIndex 让它们从结果区上方飞过）
            // 两枚操作键与检索键**同层叠加**：分裂落位的位移补偿以检索键中心为基准，
            // 若把操作键排在检索键下面（Column），落点会整体低一个按钮高（实测差约 48vp）
            Stack({ alignContent: Alignment.TopStart }) {
              this.SearchButton()
              if (this.exitActive) {
                this.ActionButtons()
              }
            }
            .width('100%')
            .zIndex(2)
            Blank(12)
          }
          .width('100%')
          // minHeight 铺满视口：Scroll 默认会把「比视口小的子组件」垂直居中，这里靠上对齐
          .constraintSize({ minHeight: '100%' })
          // 底部留白 = 悬浮页签栏高度：内容能一直滚到页签栏上方
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
          this.Header()
          // 条件槽位：已检索时是条件摘要框（点开向下延伸）
          Stack({ alignContent: Alignment.TopStart }) {
            Column() {
              this.ConditionPanel()
            }
            .width('100%')

            // 首次检索：摘要框预览层（绝对定位，不参与布局，退场一开始就浮上来）
            if (this.exitActive) {
              this.PanelPreview()
            }
          }
          .width('100%')
          Blank(12)
          // 操作槽位：清空 / 二次检索（两枚按键与检索键同层叠加，见上面的说明）
          Stack({ alignContent: Alignment.TopStart }) {
            this.ActionButtons()
          }
          .width('100%')
          .zIndex(2)
          Blank(12)
          // 结果区（可滚动）
          Scroll(this.scroller) {
            Column() {
              this.ResultArea(false)
            }
            .width('100%')
            // minHeight 铺满视口：Scroll 默认会把「比视口小的子组件」垂直居中，这里靠上对齐
            .constraintSize({ minHeight: '100%' })
            // 底部留白 = 悬浮页签栏高度：内容能一直滚到页签栏上方
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
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: this.topInset + 16 })
  }

  @Builder
  WideLayout() {
    Row() {
      // 左栏：检索模式选择区（顶部对齐；窗口矮时可上下滚动，9 行模式不会被页签栏挡住）
      Column() {
        Scroll() {
          Column() {
            this.Header()
            // 条件槽位：未检索时九行模式，检索后换成条件摘要框（首次检索时靠预览层交班）
            Stack({ alignContent: Alignment.TopStart }) {
              Column() {
                if (this.hasSearched) {
                  this.ConditionPanel()
                } else {
                  this.ModeList()
                }
              }
              .width('100%')

              if (this.exitActive) {
                this.PanelPreview()
              }
            }
            .width('100%')
            Blank(16)
            // 操作槽位：与窄屏同一套「大键分裂成按键」的演出，操作键落在摘要框下面
            // 同上：操作键与检索键同层叠加，落点才与检索键中心对齐
            Stack({ alignContent: Alignment.TopStart }) {
              if (!this.hasSearched) {
                this.SearchButton()
              }
              if (this.hasSearched || this.exitActive) {
                this.ActionButtons()
              }
            }
            .width('100%')
            .zIndex(2)
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

      // 右栏：结果区
      // 平板切页时右栏**整块**淡进（不再逐项），底下压一层横向渐隐的底色随之扫开；
      // 左栏仍然是逐项错峰 —— 两栏各自在自己的地里长出来，中间分栏线不动
      Column() {
        Stack({ alignContent: Alignment.TopStart }) {
          Column() {

        if (this.hasSearched) {
          // 操作键统一放在左栏摘要框下面（见 WideLayout 左栏），右栏只显示结果
          Scroll() {
            // 底部留白 = 悬浮页签栏高度：结果列表能一直滚到页签栏上方
            Column() {
              this.ResultArea(true)
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
          .width('100%')
          .height('100%')
          .opacity(this.rightEnter)
          .translate({ x: RIGHT_OFFSET_X * this.enterDir * (1 - this.rightEnter) })

          // 背景横隐遮罩：只在切页那一下盖住，随后从一侧扫开；不参与点击
          Column()
            .width('100%')
            .height('100%')
            .linearGradient({ angle: 90, colors: this.rightVeilColors() })
            .opacity(this.rightVeil)
            .hitTestBehavior(HitTestMode.None)
        }
        .width('100%')
        .height('100%')
      }
      .layoutWeight(1 - this.splitRatio)
      .height('100%')
      .padding({ left: 16, right: 24, top: this.topInset + 24 })
    }
    .width('100%')
    .height('100%')
  }

  // ─────────────────────── 详情弹窗（页内浮层，便于做共享元素形变）───────────────────────

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
    for (const q of this.detailQueries) {
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

  @Builder
  DlgHighlight(value: string) {
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

  /** 详情的一行：普通行是「标签 + 值」，小标题行是「其他描述」这样的分组名；按行号错峰淡进 */
  @Builder
  DlgRow(pair: DetailPair, idx: number) {
    if (pair.section) {
      Text(pair.label)
        .fontSize(15)
        .fontWeight(600)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .height(20)
        .margin({ top: 8, bottom: 10 })
        .opacity(this.detailRows > idx ? 1 : 0)
        .translate({ y: this.detailRows > idx ? 0 : 8 })
    } else {
      Row() {
        Text(pair.label)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width(100)
        Column() {
          this.DlgHighlight(pair.value)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .margin({ bottom: 10 })
      .opacity(this.detailRows > idx ? 1 : 0)
      .translate({ y: this.detailRows > idx ? 0 : 8 })
    }
  }

  @Builder
  DetailCard() {
    Column() {
      // 标题行：名字居中；「（朝代）」跟着名字同层移动、落定前淡出；关闭键从右上角弹出
      Row() {
        // 左占位与关闭键等宽：名字才会真正居中
        Blank().width(32)
        Stack({ alignContent: Alignment.Start }) {
          // 名字与朝代各自插值定位（字号、字重、位置都跟着 detailTitleCard 走），
          // 单层渲染：两层交叉淡入会同时看到两个名字 / 两个朝代
          Text(this.detailItem.name)
            .fontSize(22 - 4 * this.detailTitleCard)
            .fontWeight(this.detailTitleCard > 0.02 ? 600 : 700)
            .fontColor($r('app.color.text_primary'))
            .opacity(this.detailNameIn)
            .translate({ x: this.detailNameX(), y: -7 * this.detailTitleCard })
            .onAreaChange((oldArea: Area, newArea: Area) => {
              // 只在弹窗排版（22 号）下量宽：卡片排版是 18 号，拿那个宽度算居中会偏
              if (this.detailTitleCard < 0.02) {
                this.detailNameW = Number(newArea.width)
              }
            })
          // 朝代：弹窗里紧跟名字右侧；收回卡片时一路滑到卡片那一行的最右边
          //（卡片行里 Blank 把它顶到右端，所以终点是「卡片右内边距 18vp」而不是名字后面）
          Text(`（${this.detailItem.dynasty}）`)
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
            .opacity(Math.max(this.detailDynFade, this.detailTitleCard))
            .translate({ x: this.detailDynX(), y: -7 * this.detailTitleCard })
            .onAreaChange((oldArea: Area, newArea: Area) => {
              this.detailDynW = Number(newArea.width)
            })
        }
        .layoutWeight(1)
        .height(DETAIL_HEADER_H)

        // 关闭键：从右上角弹出 / 缩回（0.8% 过冲）
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor([$r('app.color.text_secondary')])
        }
        .width(32)
        .height(32)
        .borderRadius(16)
        .backgroundColor($r('app.color.glass_card_bg'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK, {
          colorMode: ThemeColorMode.SYSTEM,
          adaptiveColor: AdaptiveColor.AVERAGE
        })
        .border({ width: 1, color: $r('app.color.glass_card_edge'), style: BorderStyle.Solid })
        .scale({ x: this.detailCloseShown, y: this.detailCloseShown })
        .opacity(this.detailCloseShown)
        .accessibilityText('关闭')
        .onClick(() => {
          this.closeDetail()
        })
      }
      .width('100%')
      .height(DETAIL_HEADER_H)
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 12 })

      // 内容：一列连续排版（不再分页），超过「50% 屏高」上限后内部无极滚动。关闭时整块淡出
      Column() {
        Stack({ alignContent: Alignment.TopStart }) {
          Scroll() {
            Column() {
              ForEach(this.detailPairs(), (pair: DetailPair, idx: number) => {
                this.DlgRow(pair, idx)
              }, (pair: DetailPair, idx: number) => idx.toString())
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({
              top: this.detailOverflow() ? 24 : 0,
              bottom: this.detailOverflow() ? 24 : 0
            })
          }
          .width('100%')
          .height(this.detailContentH())
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .scrollable(ScrollDirection.Vertical)

          // 上下边缘虚化：提示「还有内容可以滑」（只有真超出一屏时才出现）
          if (this.detailOverflow()) {
            Column()
              .width('100%')
              .height(24)
              .position({ x: 0, y: 0 })
              .linearGradient({ angle: 180, colors: [[$r('app.color.card_bg'), 0], [$r('app.color.card_bg_clear'), 1]] })
              .hitTestBehavior(HitTestMode.None)
            Column()
              .width('100%')
              .height(24)
              .position({ x: 0, y: this.detailContentH() - 24 })
              .linearGradient({ angle: 0, colors: [[$r('app.color.card_bg'), 0], [$r('app.color.card_bg_clear'), 1]] })
              .hitTestBehavior(HitTestMode.None)
          }
        }
        .width('100%')
      }
      .width('100%')
      .opacity(this.detailContentFade)
    }
    .width(this.detailW)
    .constraintSize({ maxHeight: this.detailH })
    .translate({ x: this.detailOX, y: this.detailOY })
    .borderRadius(this.detailRadius)
    .padding({ left: 20, right: 20, top: 14, bottom: 16 })
    .backgroundColor($r('app.color.card_bg'))
    .border({ width: 1, color: $r('app.color.cell_border') })
    // 与结果卡同款的投影：缩回卡片时连阴影一起对上，交接那一帧看不出差别
    .shadow({ radius: 12, color: $r('app.color.card_shadow'), offsetX: 0, offsetY: 4 })
    .clip(true)
    .onClick(() => {
    })
  }

  /** 页内浮层：背景变暗 + 虚化，中间是形变出来的详情弹窗 */
  @Builder
  DetailOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      // 变暗与虚化放同一层：整体用不透明度淡入，「其他内容同步变暗虚化」
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.scrim'))
        .backdropBlur(12)
        .opacity(this.detailVeil)
        .onClick(() => {
          this.closeDetail()
        })

      this.DetailCard()
    }
    .width('100%')
    .height('100%')
  }
  build() {
    // v3.3：背景与环境光衬由外壳 Index.ets 铺在页签容器最底层、**不参与切页动画**；
    // 本页只画内容，整层透明，切页时背景不动、只有内容在动。
    Stack() {
      Column() {
        if (this.windowWidth === 0 || this.windowWidth <= 600) {
          this.NarrowLayout()
        } else {
          this.WideLayout()
        }
      }
      .width('100%')
      .height('100%')
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
        const w: number = newArea.width as number
        const h: number = newArea.height as number
        // 高度只用于详情弹窗的「50% 屏高」上限，变了就记一下（不影响整页重建的判断）
        this.windowHeight = h
        if (Math.abs(w - this.windowWidth) < 0.5) {
          return   // 面积没真变（切页签、弹出层都会触发一次）：直接返回，省一次整页重建
        }
        this.windowWidth = w
      })

      // 详情浮层：盖在整页之上（含页签栏区域由外壳负责，这里只覆盖页面内容）
      if (this.detailOpen) {
        this.DetailOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }
}
