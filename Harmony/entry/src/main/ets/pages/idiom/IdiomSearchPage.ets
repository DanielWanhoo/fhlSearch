import { IdiomQuery, IdiomSearchMode, IdiomSearchService } from '../../service/IdiomSearchService'
import { IdiomItem } from '../../model/IdiomItem'
import { IDIOM_DB } from '../../data/idiom_db'
import { IdiomInputCell } from '../../components/IdiomInputCell'
import { IdiomResultCard } from '../../components/IdiomResultCard'
import { GlassButton } from '../../components/GlassButton'
import { SplitDivider } from '../../components/SplitDivider'
import { InfoButton } from '../../components/InfoButton'
import { Haptics } from '../../common/Haptics'
import { ENTER_ALL_SHOWN, ENTER_OFFSET_X, ENTER_SPRING, ENTER_START_DELAY_MS, RIGHT_ENTER_MS, RIGHT_OFFSET_X, RIGHT_VEIL_MS, enterFinishMs, enterStepFor } from '../../common/PageEnter'
import { KeyCode } from '@kit.InputKit'
import { curves } from '@kit.ArkUI'
import { EASE_OUT_SOFT, EASE_OUT_STRONG, FRAME_MS, isReducedMotion, LAND_SPRING, LAND_SPRING_MS, MOTION_BASE_MS, MOTION_FAST_MS, MOTION_SLOW_MS, PANEL_COLLAPSE_STEP_MS, PANEL_COLLAPSE_TAIL_MS, staggerDelay } from '../../common/Motion'

/**
 * 成语检索页
 *
 * 三组条件同时检索（声调 / 拼音 / 单字，自上而下排列）+ 留空通配 + 二次检索。
 * 一次检索会把 12 个输入框的内容全部算进去：同一位置填了多组条件时要求同时满足。
 * 结果三分支：唯一（完成所有检索）/ 多结果（列表 + 三键）/ 未找到。
 */

/** 三组输入框下方的说明（写成模块常量：@Builder 里直接读 getter 常量曾出现整行不渲染） */
const SUBTITLE_HINT: string = '三组可任意组合：同一位置填了多种时需同时满足，整组留空表示不限'

// ── 首次检索的退场：声调 → 拼音 → 单字 → 说明，逐项向上收进摘要框中心 ──
// 检索键不再往上飞进框里：它就地「上移到操作行 + 分裂成三个按键」（见 KEY_MORPH_MS）
const EXIT_STEP_MS: number = 34            // 逐项延迟（30→34；再快就读起来赶了）
const EXIT_DURATION_MS: number = 170       // 单项退场时长（位移 + 缩小 + 淡出一起走）
const EXIT_SLOTS: number = 5          // 槽位数：声调 / 拼音 / 单字 / 说明 / 检索键
/** 退场曲线：与全局动效令牌同一条强 ease-out（绝不用 ease-in） */
const EXIT_CURVE: ICurve = EASE_OUT_STRONG

// ── 摘要框与退场「同时」淡进：不再等退场演完才出现 ──
const PANEL_INTRO_DELAY_MS: number = 40    // 声调组一开始淡，框就跟着浮上来
const PANEL_INTRO_MS: number = 230         // 框淡进时长（要在换画面之前淡完）
// ── 检索键：点击即上移 + 分裂成三个按键 ──
const KEY_MORPH_MS: number = 330           // 大键上移 + 分裂成三键的时长（含落位回弹的收敛时间）
const SPLIT_FRAME_MS: number = 16          // 先隔一帧再起动画（animateTo 取「已渲染的值」）
// 换画面（输入区 → 摘要框 + 结果）的时刻：三键**已经落位**之后再换
// 落位早于换画面，换画面时布局整体上移、位移同时归零，两者互相抵消，所以看不出跳动，
// 结果则跟在按键动画之后才出现（用户要求：按键先动，结果随后加载）
const FLIP_MS: number = SPLIT_FRAME_MS + KEY_MORPH_MS
const HANDOFF_MS: number = 300             // 换画面后再过一会儿才撤掉摘要框预览层
const KEY_GAP: number = 8                 // 分裂出来的按键间距（与 ActionButtons 的 Row space 一致）
// ── 结果分批上屏 ──
// 一次 ForEach 插入 90+ 张卡片会在同一帧里测量 + 布局：实测「换画面」到内容真正出现要 460ms
// （2 条结果只要 22ms），这段空白就是「分裂演完了、结果还没来」的那一下。
// 先铺半屏、其余每帧补一批，首屏立刻可见。
const RESULTS_FIRST_BATCH: number = 6
const RESULTS_BATCH_STEP: number = 30
const PANEL_ROW_H: number = 56            // 摘要框收起态那一行的高度（分裂落点的纵向基准）
const PANEL_MARGIN_BOTTOM: number = 12    // ConditionPanel 自带的下边距（落点算漏过它一次）

// ── 条件摘要框（Blur Glide Menu）展开 / 收起 ──
const PANEL_START_MS: number = 40     // 展开区第一项的启动延迟：框刚起步内容就跟着来，避免露出大片空白
const PANEL_STEP_MS: number = 40      // 展开区逐项延迟
const PANEL_ITEM_MS: number = 200     // 展开区单项淡进时长
const PANEL_SLOTS: number = 4         // 展开区项数：声调 / 拼音 / 单字 / 说明
const PANEL_DURATION_MS: number = 320 // 框高度伸缩时长
/**
 * 框高度伸缩的弹簧：interpolatingSpring(初速度, 质量, 刚度, 阻尼)
 * ζ = 33 / (2 * √420) ≈ 0.81，过冲约 1.5% —— 只回弹一丝，框几乎是一路推到位
 */
const PANEL_SPRING: ICurve = curves.interpolatingSpring(0, 1, 420, 34)  // ζ≈0.83 → 过冲 ≈1%

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
  // ── 检索后的条件摘要框（Blur Glide Menu） ──────────────────────────────
  // 检索一完成三组输入就收进摘要框（只留一行摘要），把屏幕空间让给结果；
  // 点摘要框可以像抽屉一样向下延伸（框整体变高、圆角不变）继续改条件 ——
  // 窄屏与宽屏左栏同一套行为，不再区分
  @State panelOpen: boolean = false   // 摘要框是否展开（展开 = 露出声调/拼音/单字）
  @State panelShown: number = 0       // 展开区已放出的项数（0~PANEL_SLOTS），驱动内部逐项淡进
  private panelTimers: number[] = []
  // ── 首次检索：输入区向上收进摘要框中心 ────────────────────────────────
  @State exitActive: boolean = false  // 退场演出进行中
  @State exitShown: number = 0        // 已退场的项数（0 = 全在，EXIT_SLOTS = 全没）
  private exitTimers: number[] = []
  private appendTimers: number[] = []
  @State shownCount: number = 0           // 结果卡片已上屏的张数（分批铺，避免一帧插 90+ 张卡住）
  private geoCenterY: number[] = [0, 0, 0, 0, 0]
  private panelAnchorY: number = 0               // 摘要框中心的窗口 y：退场元素的消失点
  @State panelIntro: number = 0                  // 摘要框预览的不透明度（首次检索时与退场同时淡进）
  @State splitP: number = 1                      // 1 = 还叠在检索键上，0 = 三键就位（同时管淡化）
  @State splitY: number = 0                      // 分裂期三键的纵向位移（vp，动画直接读它）
  @State keyLift: number = 0                     // 分裂期大检索键的纵向位移（vp）
  private keyPills: number = 3                   // 检索键分裂成几个按键（命中 ≥ 2 条时为三键）
  private keyWidth: number = 0                   // 检索键的宽度（vp）
  private keyX: number = 0                       // 检索键左边界的窗口 x
  // 操作行（三键）的真实布局矩形：分裂终点直接取它，量出多少就落多少，不再用公式推算
  private actionX: number = 0
  private actionY: number = 0
  private actionW: number = 0
  private actionH: number = 0
  // 双栏左右宽度比例（0~1，左栏占比），可拖动调节；用 AppStorage 共享给主页面 —— 平板页签栏据此水平居中于左栏
  @StorageLink('splitRatio') splitRatio: number = 0.5
  @StorageProp('topInset') topInset: number = 0  // 状态栏高度（vp），铺满边缘时避让系统图标
  @StorageProp('barInset') barInset: number = 0  // 悬浮页签栏占位高度（vp，Index 发布）：滚动内容底部留白，内容可从玻璃下方穿过
  @Prop @Watch('onUndoCmd') undoCmd: number = 0  // 系统返回手势指令：变化时执行「清空当前」
  onScrollOffset?: (yOffset: number) => void  // 滚动回调：Index 据此驱动悬浮页签栏下滚隐藏 / 上滚显示
  // ── 切页进场（v3.3）：元素自上而下每 50ms 放出一项，横向弹入 ──────────────
  // 外壳 Index.ets 切页时把 enterTick 加一，本页收到后把元素重新放一遍
  @Prop @Watch('onEnterTick') enterTick: number = 0
  @State enterShown: number = ENTER_ALL_SHOWN  // 已放出的项数；0 = 全部藏起来，ENTER_ALL_SHOWN = 静止态
  @State enterDir: number = 1  // 进场方向：+1 从右侧弹入，-1 从左侧弹入（跟随切页方向）
  private lastEnterTick: number = 0  // 上一次收到的 enterTick：靠它的大小变化判断切页方向
  private enterTimers: number[] = []
  // 本页参与错峰进场的槽位数：0 标题 / 1 条件条或声调组 / 2 拼音组 / 3 单字组 / 4 说明 / 5 按键 / 6 结果
  private readonly ENTER_SLOTS: number = 7
  // 平板双栏时右栏（结果区）自己一组错峰：与左栏同时起步，标题 + 前 5 张卡片逐项放出
  @State enterShownR: number = ENTER_ALL_SHOWN
  // 平板右栏「整块」进场：1 = 静止，0 = 藏在起始位移上（不再逐项弹出）
  @State rightEnter: number = 1
  // 平板右栏背景的横向渐隐遮罩：1 = 整个盖住，0 = 已经扫开（只在切页那一下出现）
  @State rightVeil: number = 0
  private enterTimersR: number[] = []
  private readonly RIGHT_SLOTS: number = 6
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
    // 本页往往是在「切到这一页」的那一刻才被创建（HdsTabs 懒创建）：
    // 初始赋值不会触发 @Watch，所以要在这里补放一次进场，否则第一次切进来没有错峰动画
    if (this.enterTick !== 0) {
      this.onEnterTick()
    }
  }

  // ==================== 业务逻辑 ====================

  private onChangeInput(mode: IdiomSearchMode, index: number, value: string): void {
    this.valuesOf(mode)[index] = value
  }

  /**
   * 按下「检索」：先把输入区演走，再落结果
   *
   * ① 还没检索过（初始界面）→ 三组 + 说明自上而下每 25ms 淡出、摘要框同时淡进；
   *    输入区淡完的那一刻就换画面（结果此刻出现），检索键正往上飞、分裂成三键，
   *    所以结果是「跟着按键一起加载」，不是等按键落位再出来（见 playInputExit）；
   * ② 已检索过、且摘要框正展开着（用户点开来改了条件）→ 先把展开区收回去，再检索；
   * ③ 已检索过、摘要框本来就是收起的 → 直接检索，不做多余动画。
   */
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
    if (!this.hasSearched) {
      // 先数一遍命中数（不落栈、不改候选集）：决定检索键分裂成两键还是三键
      this.keyPills = this.service.preview(q) >= 2 ? 3 : 2
      this.playInputExit(q)
      return
    }
    if (this.panelOpen) {
      this.collapsePanel(() => {
        this.applySearch(q)
      })
      return
    }
    this.applySearch(q)
  }

  /**
   * 真正执行检索：结果卡片自带错峰淡入（见 ResultArea 里的 transition）
   *
   * handoff = 首次检索那次：摘要框的预览已经在屏幕上就位，这里要「原地交班」——
   * 整块切换不做透明度过渡，否则预览刚消失、真框又从透明淡进，会看到一次发暗的闪
   */
  private applySearch(q: IdiomQuery, handoff: boolean = false): void {
    if (handoff) {
      this.results = this.service.search(q)
      this.hasSearched = true
      this.searchCount = this.service.depth
      this.panelOpen = false
      this.panelShown = 0
      // 交班后按键数跟着真实结果走（分裂期用的是 preview 的预测值）
      this.keyPills = this.results.length >= 2 ? 3 : 2
      this.revealResults()
      return
    }
    this.getUIContext().animateTo({ duration: MOTION_SLOW_MS, curve: EASE_OUT_STRONG }, () => {
      this.results = this.service.search(q)
      this.hasSearched = true
      this.searchCount = this.service.depth
      this.panelOpen = false
      this.keyPills = this.results.length >= 2 ? 3 : 2
      this.revealResults()
    })
  }

  /**
   * 结果分批上屏：先出 RESULTS_FIRST_BATCH 张，其余每帧补 RESULTS_BATCH_STEP 张。
   * 目的见常量处注释 —— 卡片的构建/测量成本很高，一次性全插会把换画面那一帧堵住。
   */
  private revealResults(): void {
    for (const t of this.appendTimers) {
      clearTimeout(t)
    }
    this.appendTimers = []
    const total: number = this.results.length
    this.shownCount = Math.min(total, RESULTS_FIRST_BATCH)
    const step = () => {
      if (this.shownCount >= total) {
        return
      }
      this.shownCount = Math.min(total, this.shownCount + RESULTS_BATCH_STEP)
      if (this.shownCount < total) {
        this.appendTimers.push(setTimeout(step, FRAME_MS))
      }
    }
    if (this.shownCount < total) {
      this.appendTimers.push(setTimeout(step, FRAME_MS))
    }
  }

  /**
   * 首次检索的退场演出（总长约 420ms）
   *
   * 时间线：
   *   0ms      点「检索」——这一帧就开始分裂（不再等退场演完）
   *   16→176ms 三键一边上飞一边淡入，大键同速上浮、同时淡出（splitP 1 → 0）
   *   0→175ms  三组输入 + 说明自上而下每 25ms 淡出（与分裂同时进行）
   *   20→160ms 摘要框预览浮上来（换画面之前就淡完，交班时看不出换过）
   *   200ms    三键已落位 → 换画面：输入区退场、摘要框 56 高就位，布局整体上移；
   *            同一帧 splitY 归零，一加一减正好抵消，三键停着不动；结果在这之后才放出来
   *   200→420ms 摘要框预览与新摘要框交班，随后撤掉预览层、临时态复位
   *
   * 为什么「先落位、后换画面」：三键的落点是用解析式算出来的（见 actionCenterY），
   * 换画面只是把布局挪到同一个点上，所以换与不换在视觉上没有差别 —— 这样按键动画可以先演，
   * 结果跟在后面加载（用户 2026-10-31 的要求）。
   */
  private playInputExit(q: IdiomQuery): void {
    for (const t of this.exitTimers) {
      clearTimeout(t)
    }
    this.exitTimers = []
    // 系统「减弱动画」开着：这套位移 + 缩放整支跳过，结果直接到位（不做「退回原位」的补偿动作）
    if (isReducedMotion()) {
      this.exitActive = false
      this.splitP = 1
      this.panelIntro = 0
      this.applySearch(q, true)
      return
    }
    this.exitActive = true
    this.exitShown = 0
    this.panelIntro = 0
    this.splitP = 1
    this.splitY = 0
    this.keyLift = 0
    // ① 点击「检索」的这一帧就开始分裂：
    //    检索键与三键此刻叠在同一个槽位，把三键的终点先算成「换画面之后它们的中心」（解析式），
    //    位移量 = 终点 − 当前中心（负数 = 向上），于是三键一边上飞、大键一边同速上浮并淡出。
    const gap: number = this.windowWidth > 600 ? 16 : 12
    const key: number = this.geoCenterY[4]
    const target: number = this.actionCenterY(gap)
    const rise: number = (key > 0 && target > 0) ? target - key : 0
    this.exitTimers.push(setTimeout(() => {
      // 纵向交给落位弹簧：飞到终点时会过冲约 0.8%（≈3vp）再收回，落位那一下有「弹」的感觉
      this.getUIContext().animateTo({ duration: KEY_MORPH_MS, curve: LAND_SPRING }, () => {
        this.splitY = rise
        this.keyLift = rise
      })
      // 横向扩散与淡出仍用 ease-out：不透明度不该有过冲（过冲会闪）
      this.getUIContext().animateTo({ duration: KEY_MORPH_MS, curve: EXIT_CURVE }, () => {
        this.splitP = 0
      })
    }, SPLIT_FRAME_MS))
    // ② 输入区同时淡出：25ms 一项，三键落位之前正好淡完（slot 0 = 检索键不参与淡出）
    for (let i = 0; i < EXIT_SLOTS; i++) {
      this.exitTimers.push(setTimeout(() => {
        this.getUIContext().animateTo({ duration: EXIT_DURATION_MS, curve: EXIT_CURVE }, () => {
          this.exitShown = i + 1
        })
      }, i * EXIT_STEP_MS))
    }
    // ③ 摘要框预览与淡出同时浮上来（换画面之前就淡完，交班时看不出换过）
    this.exitTimers.push(setTimeout(() => {
      this.getUIContext().animateTo({ duration: PANEL_INTRO_MS, curve: EASE_OUT_SOFT }, () => {
        this.panelIntro = 1
      })
    }, PANEL_INTRO_DELAY_MS))
    // ④ 三键落位之后再换画面：
    //    布局此刻整体上移（输入区退场、摘要框 56 高就位），同时 splitY 归零 ——
    //    两者一加一减正好抵消，三键停在原地不动；结果在这之后才放出来。
    this.exitTimers.push(setTimeout(() => {
      this.applySearch(q, true)
      this.exitShown = 0
      this.splitY = 0
      this.keyLift = 0
    }, FLIP_MS))
    // ⑤ 交班：预览层撤掉、各种临时态复位（大键的 splitP 要给下次检索留着）
    this.exitTimers.push(setTimeout(() => {
      this.exitActive = false
      this.panelIntro = 0
      this.splitP = 1
      this.splitY = 0
      this.keyLift = 0
    }, FLIP_MS + HANDOFF_MS))
  }

  private onClearAll(): void {
    for (const t of this.appendTimers) {
      clearTimeout(t)
    }
    this.appendTimers = []
    for (const t of this.exitTimers) {
      clearTimeout(t)
    }
    this.exitTimers = []
    this.service.reset()
    // 复原的回弹：大「检索」键在检索后不存在，复原时让它**从三键的位置落回原位**，
    // 走与分裂同一条落位弹簧（过冲 0.8%），于是「散开 / 合回」两端是同一套手感。
    const gap: number = this.windowWidth > 600 ? 16 : 12
    const keyY: number = this.geoCenterY[4]
    const actY: number = this.actionCenterY(gap)
    const drop: number = (keyY > 0 && actY > 0) ? keyY - actY : 0
    const bounce: boolean = !isReducedMotion() && drop > 0
    // 回到初始界面是一次「整块换树」：放进 animateTo 里，检索结果淡出、三组输入格淡入，
    // 不做的话列表是硬切没有的（用户点「清空所有」时最明显的突兀感就在这）
    if (bounce) {
      // 关键：写在 animateTo 之前 —— 新树的第一帧就带着这个位移，不会先闪在原位
      this.keyLift = drop
    }
    this.getUIContext().animateTo({ duration: MOTION_BASE_MS, curve: EASE_OUT_STRONG }, () => {
      this.tones = ['', '', '', '']
      this.pinyins = ['', '', '', '']
      this.chars = ['', '', '', '']
      this.results = []
      this.shownCount = 0
      this.hasSearched = false
      this.panelOpen = false
      this.panelShown = 0
      this.exitActive = false
      this.exitShown = 0
      this.searchCount = this.service.depth
    })
    if (bounce) {
      // 先让新树带着 keyLift 渲染一帧（animateTo 取「已渲染的值」），再弹回原位
      this.exitTimers.push(setTimeout(() => {
        this.getUIContext().animateTo({ duration: LAND_SPRING_MS, curve: LAND_SPRING }, () => {
          this.keyLift = 0
        })
      }, FRAME_MS))
    }
  }

  private onUndo(): void {
    this.results = this.service.undo()
    this.searchCount = this.service.depth
    if (this.service.depth === 0) {
      this.results = []
      this.hasSearched = false
      this.panelOpen = false
      this.panelShown = 0
    }
  }

  // 系统返回手势指令：执行「清空当前」（撤销一步检索）
  onUndoCmd(): void {
    this.onUndo()
  }

  // ==================== UI 片段 ====================

  // 大标题区（v3.3 空间化排版）：标题放大加粗、副标题拉开行距、
  // 「检索 N 次」从裸文字升级为玻璃胶囊，与右侧信息按钮组成一个轻量的控制区
  @Builder
  Header() {
    Row() {
      Column() {
        Text('山石雅集第14题')
          .fontSize(26)
          .fontWeight(700)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 6 })
        Text('按拼音 / 声调 / 单字检索成语')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 检索次数胶囊：半透明玻璃底 + 细描边，安静地挂在标题右侧
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

  /**
   * 条件摘要框（Blur Glide Menu）
   *
   * 收起时只有一行摘要；点一下框向下延伸，把声调 / 拼音 / 单字「包在同一个圆角矩形里」展开，
   * 里面的元素自上而下逐项淡进；再点一下反向收起。
   * 外壳始终是同一个框、半径不变，只是高度在变（带一点回弹），像菜单从摘要条里滑出来。
   * 玻璃底 + 背景模糊：透过它能看见后面的环境光衬，所以叫 Blur。
   */
  @Builder
  ConditionPanel() {
    Column() {
      // 摘要行：点它开合（恒定 56 高，不参与展开区的懒加载，避免开合时抖一下）
      this.PanelSummaryRow(true)

      if (this.panelOpen) {
        Column() {
          this.PanelGroup(this.GROUPS[0], 0)
          this.PanelGroup(this.GROUPS[1], 1)
          this.PanelGroup(this.GROUPS[2], 2)
          Text(SUBTITLE_HINT)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .opacity(this.panelOpacity(3))
            .translate({ y: this.panelShift(3) })
        }
        .width('100%')
        .padding({ left: 14, right: 14, bottom: 14 })
        // 展开区自己也有一次淡入：块整体出现时别硬切
        .transition(TransitionEffect.OPACITY.animation({ duration: MOTION_BASE_MS, curve: EASE_OUT_STRONG }))
      }
    }
    .width('100%')
    .margin({ bottom: 12 })
    .borderRadius(14)
    // 暖色半透明底 + 背景模糊：底色用专门的暖色 panel_bg，
    // 模糊改用 backdropBlur（只虚化背后内容，不叠系统材质的那层灰白纱），
    // 这样浅色页面上不会变成「灰块」，玻璃感还在
    .backgroundColor($r('app.color.panel_bg'))
    .backdropBlur(20)
    .border({ width: 1, color: $r('app.color.glass_card_edge') })
    .clip(true)
    // 首次检索：输入区收进摘要框之后，摘要框自己淡进。
    // 只做不透明度 —— 预览层已经占在同一位置，再加 6vp 位移会看到框「抽一下」
    .transition(TransitionEffect.OPACITY
      .animation({ duration: MOTION_BASE_MS, curve: EASE_OUT_STRONG }))
    .opacity(this.enterOpacity(1))
    .translate({ x: this.enterShift(1) })
  }

  /**
   * 摘要行的内容（收起态那一行）
   *
   * tapable = 预览态要关掉点击：首次检索时输入区还没演完，提前放出来的这层只是
   * 「框的形状预告」，位置与真摘要框重合，演完就交班给它
   */
  @Builder
  PanelSummaryRow(tapable: boolean) {
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
    .height(56)
    .padding({ left: 14, right: 14 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (tapable) {
        this.togglePanel()
      }
    })
  }

  /**
   * 首次检索：摘要框在输入区退场「同时」浮上来
   *
   * 绝对定位压在槽位左上角（= 真摘要框将来所在的位置），只演 400ms；
   * 位置、圆角、底、模糊、描边都与 ConditionPanel 一致，退场结束整块交班时看不出换过
   */
  @Builder
  PanelPreview() {
    Column() {
      this.PanelSummaryRow(false)
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

  /** 展开区里的一组（同 GroupBody，只是外面多一层「逐项淡进」的壳） */
  @Builder
  PanelGroup(group: InputGroupOption, slot: number) {
    Column() {
      this.GroupBody(group)
    }
    .width('100%')
    .margin({ bottom: 10 })
    .opacity(this.enterOpacity(slot + 1) * this.panelOpacity(slot))
    .translate({ y: this.panelShift(slot) })
  }

  /** 初始界面上的一组：切页进场 + 检索退场都作用在这一层 */
  @Builder
  InputGroup(group: InputGroupOption, slot: number) {
    Column() {
      this.GroupBody(group)
    }
    .width('100%')
    .margin({ bottom: 12 })
    .opacity(this.enterOpacity(slot) * this.exitOpacity(slot - 1))
    .translate({ x: this.enterShift(slot), y: this.exitShiftY(slot - 1) })
    .scale({ x: this.exitScale(slot - 1), y: this.exitScale(slot - 1) })
    // 量一下自己在窗口里的中心：退场时要沿这段距离向上收（见 exitShiftY）
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.noteCenter(slot - 1, newArea)
    })
  }

  /** 一组输入框的本体：左侧分组名 + 右侧说明小字，下面并排四个输入格 */
  @Builder
  GroupBody(group: InputGroupOption) {
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
      .opacity(this.enterOpacity(4) * this.exitOpacity(3))
      .translate({ x: this.enterShift(4), y: this.exitShiftY(3) })
      .scale({ x: this.exitScale(3), y: this.exitScale(3) })
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.noteCenter(3, newArea)
      })
  }

  /**
   * 检索主按钮（沉浸光感·主色玻璃）
   *
   * 首次检索时它不是飞进摘要框，而是「就地分裂」：整块上移到操作行的位置并淡出，
   * 同时真正的三键（ActionButtons）从它的中心散开、长到各自槽位上。
   * 三键用的就是最终那三个真按钮，终点取它们量出来的矩形，所以落位分毫不差，
   * 也不会在交班时换一棵子树（那是之前「卡一下」的来源）。
   */
  @Builder
  SearchButton(gap: number) {
    Row() {
      GlassButton({ label: '检索', primary: true, desc: '按当前输入条件执行检索，留空的格子表示任意匹配', action: () => {
        this.onSearch()
      } })
    }
    .width('100%')
    // 大键淡出让位；整块的不透明度不走退场（那样会在第 5 槽直接消失、把分裂过程掐断）
    .opacity(this.enterOpacity(5) * this.splitP)
    .translate({ x: this.enterShift(5), y: this.keyLift })
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.noteCenter(4, newArea)
      this.keyWidth = newArea.width as number
      this.keyX = newArea.globalPosition.x as number
    })
  }

  // 检索后的三键（沉浸光感玻璃）：清空所有 / 清空当前 / 二次检索（多结果时）
  //
  // 首次检索时这套三键在退场一开始就挂上（此时 opacity = 0，看不见），
  // 好处是：① 它们量到的矩形就是最终布局；② 换画面时这棵子树不重建，不会有掉帧的接缝。
  @Builder
  ActionButtons(gap: number) {
    Row({ space: KEY_GAP }) {
      // 注意：位移必须挂在「外层容器」上，不能直接链在 GlassButton 上 ——
      // 自定义组件外侧再加属性会套一层包装节点，玻璃按钮内置的 layoutWeight(1) 便失去参照，
      // 每颗都会被撑成整行宽、后面的挤到屏幕外（2026-10-31 回归实证）。
      Row() {
        GlassButton({ label: '清空所有', primary: false, desc: '清空输入与全部检索历史，回到初始状态', action: () => {
          this.onClearAll()
        } })
      }
      .layoutWeight(1)
      .translate({ x: this.enterShift(5) + this.splitDx(0), y: this.splitY })

      Row() {
        GlassButton({ label: '清空当前', primary: false, desc: '撤销当前这次检索，回到上一级检索结果', action: () => {
          this.onUndo()
        } })
      }
      .layoutWeight(1)
      .translate({ x: this.enterShift(5) + this.splitDx(1), y: this.splitY })

      if (this.results.length >= 2 || this.keyPills >= 3) {
        Row() {
          GlassButton({ label: '二次检索', primary: true, desc: '在上一次结果范围内继续检索', action: () => {
            // 摘要框收起时条件一个字都没改，直接再检索等于白跑一次 —— 先把框展开让用户改
            if (!this.panelOpen) {
              this.expandPanel()
              return
            }
            this.onSearch()
          } })
        }
        .layoutWeight(1)
        .translate({ x: this.enterShift(5) + this.splitDx(2), y: this.splitY })
      }
    }
    .width('100%')
    // 换画面那一刻三键还在检索键的位置上（不可见），随后一边上飞一边淡入
    // splitP 由 1 收到 0，所以不透明度是 1 - splitP
    .opacity(this.exitActive ? 1 - this.splitP : 1)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.actionX = newArea.globalPosition.x as number
      this.actionY = newArea.globalPosition.y as number
      this.actionW = newArea.width as number
      this.actionH = newArea.height as number
    })
  }

  /**
   * 空状态 / 唯一结果 / 结果列表 三态之间的切换：交叉淡入 + 轻微缩放
   * （减弱动效时只留不透明度，不做缩放）
   */
  private stateTransition(): TransitionEffect {
    if (isReducedMotion()) {
      return TransitionEffect.OPACITY
    }
    return TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.98, y: 0.98 }))
  }

  @Builder
  ResultArea(rightSide: boolean) {
    Column() {
      if (this.results.length === 0) {
        // 未找到（空状态：图标 + 文案）
        Column() {
          SymbolGlyph($r('sys.symbol.book'))
            .fontSize(40)
            .fontColor([$r('app.color.text_secondary')])
            .opacity(rightSide ? this.enterROpacity(0) : 1)
            .translate({ x: rightSide ? this.enterRShift(0) : 0 })
          Blank(12)
          Text('未找到该成语')
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
        .transition(this.stateTransition().animation({ duration: MOTION_BASE_MS, curve: EASE_OUT_STRONG }))
      } else if (this.results.length === 1) {
        // 唯一结果：完成所有检索（卡片弹入）
        Column() {
          Text('完成所有检索')
            .fontSize(14)
            .fontWeight(600)
            .fontColor($r('app.color.match_highlight'))
            .opacity(rightSide ? this.enterROpacity(0) : 1)
            .translate({ x: rightSide ? this.enterRShift(0) : 0 })
          Blank(12)
          IdiomResultCard({
            item: this.results[0],
            toneInputs: this.tones,
            pinyinInputs: this.pinyins,
            charInputs: this.chars
          })
            .opacity(rightSide ? this.enterROpacity(1) : 1)
            .translate({ x: rightSide ? this.enterRShift(1) : 0 })
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.scale({ x: 0.94, y: 0.94 }))
              .animation({ duration: MOTION_SLOW_MS, curve: EASE_OUT_STRONG }))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .transition(this.stateTransition().animation({ duration: MOTION_BASE_MS, curve: EASE_OUT_STRONG }))
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
            .opacity(rightSide ? this.enterROpacity(0) : 1)
            .translate({ x: rightSide ? this.enterRShift(0) : 0 })

          ForEach(this.results.slice(0, this.shownCount), (item: IdiomItem, idx: number) => {
            IdiomResultCard({
              item: item,
              toneInputs: this.tones,
              pinyinInputs: this.pinyins,
              charInputs: this.chars
            })
              .margin({ bottom: 8 })
              .opacity(rightSide ? this.enterROpacity(1 + idx) : 1)
              .translate({ x: rightSide ? this.enterRShift(1 + idx) : 0 })
              .transition(TransitionEffect.OPACITY
                .combine(TransitionEffect.translate({ y: 16 }))
                .animation({
                  duration: MOTION_BASE_MS,
                  curve: EASE_OUT_STRONG,
                  // 首批错峰出场（与按键落位的节奏接上）；后续批次已经在屏幕外，不再等
                  delay: idx < RESULTS_FIRST_BATCH ? staggerDelay(idx) : 0
                }))
          }, (item: IdiomItem) => item.word)
        }
        .width('100%')
        .transition(this.stateTransition().animation({ duration: MOTION_BASE_MS, curve: EASE_OUT_STRONG }))
      }
    }
    .width('100%')
    .opacity(rightSide ? 1 : this.enterOpacity(6))
    .translate({ x: rightSide ? 0 : this.enterShift(6) })
  }

  // ==================== 检索退场 / 摘要框开合 ====================

  /**
   * 记录「摘要框中心」的窗口 y —— 首次检索时输入区就收进这一点
   *
   * 摘要框紧跟在标题下方、恒定 56 高（margin 上 0、上一个标题 margin 下 16），
   * 所以中心 = 标题底边 + 16 + 28。用标题量而不是直接量摘要框：
   * 退场发生时摘要框还没被创建出来。
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
    return -(56 + slot * 88)
  }

  /**
   * 分裂落点的中心 Y（vp）——用解析式算，不用「当前布局实测」
   *
   * 退场期间三组输入框仍在布局里占位（只是淡出），所以此刻量到的操作行位置还在屏幕下方；
   * 换画面后输入区消失、摘要框 56 高就位，操作行会整体跳到面板下方。
   * 直接按「面板顶 + 摘要行 + 下边距 + 槽位间距 + 按钮半高」推最终位置，
   * 三键与检索键在整个分裂过程中就能连续飞过去，换画面时不会再有「突然出现在上方」的跳动。
   */
  private actionCenterY(gap: number): number {
    const h: number = this.actionH > 0 ? this.actionH : 48
    // panelAnchorY 是摘要框的**中心**，所以先退回半行高度，再往下堆：
    // 半行(28) + 框的下边距(12) + 槽位间距(gap) + 按钮半高
    return this.panelAnchorY + PANEL_ROW_H / 2 + PANEL_MARGIN_BOTTOM + gap + h / 2
  }

  /**
   * 第 index 枚按键相对自己槽位的横向偏移：起点全叠在检索键正中，终点是各自槽位
   *
   * 槽位坐标由操作行的真实矩形推算（等分 layoutWeight + KEY_GAP），
   * 所以 splitP 收到 0 时偏移恰好为 0，落位与真实布局完全重合。
   */
  private splitDx(index: number): number {
    if (this.actionW <= 0 || this.keyWidth <= 0) {
      return 0
    }
    const n: number = this.keyPills
    const pw: number = (this.actionW - (n - 1) * KEY_GAP) / n
    const myCenter: number = this.actionX + index * (pw + KEY_GAP) + pw / 2
    const keyCenter: number = this.keyX + this.keyWidth / 2
    // 只有演出期间才带偏移：splitP = 1 时整排叠在检索键正中，收到 0 时各回各的槽位；
    // 演出结束后 splitP 会复位为 1（大键还要用），所以这里必须靠 exitActive/splitActive 归零
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

  /**
   * 展开：框先开始长高（弹簧，带一点回弹），随后里面三组 + 说明自上而下每 45ms 淡进一项
   *
   * 先让框动、内容晚 90ms 才出现：否则内容会和还在长高的框边缘打架。
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
   * 一项一条 animateTo：动画参数（曲线、时长）不能攒在一条里分批触发；
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
    // 收尾：弹簧跑完后把下标复位成哨兵值，之后新增的元素（检索结果卡片）直接可见
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
        // 未检索：标题 + 三组条件 + 说明 + 「检索」键**整体可滚动**。
        // 小窗 / 分屏下窗口变矮时，固定 Column 会把检索键顶到窗口外且无法滚动 —— 统一放进 Scroll。
        Scroll() {
          Column() {
            this.Header()
            // 槽位套一层 Stack：退场期间摘要框预览压在输入区上面（position 出流，不影响布局）
            Stack({ alignContent: Alignment.TopStart }) {
              Column() {
                this.InputGroup(this.GROUPS[0], 1)
                this.InputGroup(this.GROUPS[1], 2)
                this.InputGroup(this.GROUPS[2], 3)
                this.Subtitle()
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)

              if (this.exitActive) {
                this.PanelPreview()
              }
            }
            .width('100%')
            Blank(12)
            // 「检索」按钮与检索后的三键叠在同一个槽位：检索时大键上移淡出让位，
            // 三键从大键中心散开（它们的终点就是自己的布局位置，见 ActionButtons）
            Stack({ alignContent: Alignment.TopStart }) {
              this.SearchButton(12)
              if (this.exitActive) {
                this.ActionButtons(12)
              }
            }
            .width('100%')
            // 分裂中的按键要盖在结果之上：它们像「从结果区里升起来」，被卡片压住会像掉下去了
            .zIndex(2)
            Blank(12)
          }
          .width('100%')
          // minHeight 铺满视口：Scroll 默认把「比视口小的内容」垂直居中，这里强制靠上对齐
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
          // 检索完成后三组条件收进摘要框（Blur Glide Menu）：点框向下延伸就能继续改，
          // 收起态把屏幕高度让给结果列表。
          Stack({ alignContent: Alignment.TopStart }) {
            Column() {
              this.ConditionPanel()
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            if (this.exitActive) {
              this.PanelPreview()
            }
          }
          .width('100%')
          Blank(12)
          // 三键（清空 / 二次检索等）
          Stack({ alignContent: Alignment.TopStart }) {
            this.ActionButtons(12)
          }
          .width('100%')
          .zIndex(2)
          Blank(12)
          Scroll() {
            // 底部留白 = 悬浮页签栏高度：结果列表能一直滚到页签栏上方，其余内容从玻璃材质下方穿过
            Column() {
              this.ResultArea(false)
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
      // 左栏：检索输入区（靠上对齐，与诗词/名士页一致；窗口矮时可上下滚动）
      Column() {
        Scroll() {
          Column() {
            this.Header()
            // 与窄屏一致：检索完成后条件收进摘要框，点框展开继续改；
            // 槽位同样套 Stack，退场期间摘要框预览压在输入区上面
            Stack({ alignContent: Alignment.TopStart }) {
              Column() {
                if (this.hasSearched) {
                  this.ConditionPanel()
                } else {
                  this.InputGroup(this.GROUPS[0], 1)
                  this.InputGroup(this.GROUPS[1], 2)
                  this.InputGroup(this.GROUPS[2], 3)
                  this.Subtitle()
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)

              if (this.exitActive) {
                this.PanelPreview()
              }
            }
            .width('100%')
            Blank(16)
            // 与窄屏一致：检索键与三键同槽叠放，检索时大键上移淡出、三键自中心散开
            Stack({ alignContent: Alignment.TopStart }) {
              if (!this.hasSearched) {
                this.SearchButton(16)
              }
              if (this.exitActive || this.hasSearched) {
                this.ActionButtons(16)
              }
            }
            .width('100%')
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
      // 平板切页时右栏**整块**淡进（不再逐项），底下压一层横向渐隐的底色随之扫开；
      // 左栏仍然是逐项错峰 —— 两栏各自在自己的地里长出来，中间分栏线不动
      Column() {
        Stack({ alignContent: Alignment.TopStart }) {
          Column() {
        if (this.hasSearched) {
          Scroll() {
            // 底部留白 = 悬浮页签栏高度：结果列表能一直滚到页签栏上方，其余内容从玻璃材质下方穿过
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

  build() {
    // v3.3：背景与环境光衬（暖红光斑 + 金色反光 + 底部青墨纵深）由外壳 Index.ets
    // 铺在页签容器最底层，**不参与切页动画**；本页只画内容，整层保持透明，
    // 所以切页时背景不动、只有内容在动。
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
    .width('100%')
    .height('100%')
  }
}