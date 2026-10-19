import { bundleManager } from '@kit.AbilityKit'
import { Haptics } from '../common/Haptics'
import { IDIOM_DB } from '../data/idiom_db'
import { POETRY_DB } from '../data/poetry_db'
import { MINGZI_DB } from '../data/mingzi_db'

/**
 * 「信息」对话框 — 应用说明与使用方法（三个检索页共用）
 *
 * 入口：大标题右侧的圆形玻璃「信息」按钮（InfoButton.ets）
 * 内容参照 Windows 端「使用说明 + 关于题库」两段合并：
 *   本应用是什么 / 题库统计 / 三个模块怎么用 / 识图怎么用 / 隐私与权限 / 来源与版权
 *
 * 尺寸：88% 屏宽、85% 屏高，上限 560×640vp（与名士详情弹窗同一套规格）；
 * 正文可滚动，右上角关闭按钮与名士详情一致 —— 圆形系统材质玻璃 + 轻触震动。
 */

@CustomDialog
export struct AppInfoDialog {
  controller?: CustomDialogController
  @State version: string = '3.0.0'

  aboutToAppear(): void {
    this.version = AppInfoDialog.readVersion()
  }

  /** 版本号直接从应用包信息读，免得改了 app.json5 忘了改这里 */
  static readVersion(): string {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      return info.versionName
    } catch (err) {
      return '3.0.0'
    }
  }

  // ==================== UI 片段 ====================

  /** 一个小节：主色小标题 + 若干正文行 */
  @Builder
  Section(title: string, lines: string[]) {
    Column() {
      Text(title)
        .fontSize(15)
        .fontWeight(600)
        .fontColor($r('app.color.primary'))
        .width('100%')
        .margin({ bottom: 6 })

      ForEach(lines, (line: string) => {
        Text(line)
          .fontSize(14)
          .lineHeight(22)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .margin({ bottom: 4 })
      }, (line: string, idx: number) => `${title}-${idx}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: 18 })
  }

  /**
   * 说明里的小样图：等宽、圆角、细描边，下面跟一行灰色图注
   * @param src 图片资源
   * @param ratio 图片宽高比（显式给出，避免加载完成前高度跳动）
   * @param caption 图注
   */
  @Builder
  HelpImage(src: Resource, ratio: number, caption: string) {
    Column() {
      Image(src)
        .width('100%')
        .aspectRatio(ratio)
        .objectFit(ImageFit.Contain)
        .borderRadius(12)
        .border({ width: 1, color: $r('app.color.cell_border') })
        .interpolation(ImageInterpolation.High)
        .draggable(false)

      Text(caption)
        .fontSize(12)
        .lineHeight(18)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ top: 6 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: 18 })
  }

  build() {
    Column() {
      Row() {
        Text('信息')
          .fontSize(22)
          .fontWeight(700)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        // 关闭按钮：圆形「沉浸光感」玻璃底（与名士详情弹窗、玻璃按钮同一套系统材质语言）
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
        .accessibilityText('关闭')
        .accessibilityDescription('关闭信息窗口')
        .onClick(() => {
          Haptics.tick()
          this.controller?.close()
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(`忘川检索 · HarmonyOS 版　v${this.version}`)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ top: 2, bottom: 14 })

      Scroll() {
        Column() {
          this.Section('这是什么', [
            '忘川检索把《忘川风华录》「山石雅集」「众里寻他」三类检索题的题库内嵌进程序，填好条件一点就出结果，不用再一页页翻题库。',
            '全部离线运行：不联网、不要账号、没有广告。'
          ])

          this.Section('题库', [
            `成语检索　${IDIOM_DB.length} 条`,
            `诗词检索　${POETRY_DB.length} 句`,
            `名士检索　${MINGZI_DB.length} 位`,
            '题库随程序内嵌，第一次打开就能用，不需要下载。'
          ])

          this.Section('怎么切换模块', [
            '底部页签栏点「成语检索 / 诗词检索 / 名士检索」切换。',
            '手机上是单栏；平板横屏是左右双栏，中间的分隔条可以拖动调宽窄。'
          ])

          this.Section('成语检索 · 山石雅集第14题', [
            '四种格子对应成语的四个字，模式可选拼音 / 声调 / 单字。',
            '留空的格子表示这一位不限，只填一格也能查。',
            '点「检索」出结果，你填了条件的那几位会在成语、拼音、声调上同时标绿。'
          ])

          this.Section('诗词检索 · 山石雅集第15题', [
            '题目给一张 6×5 的字格（30 个字），要从里面找出能拼成的五言诗句。',
            '① 把格子里的字填进本页表格：点格子再用键盘打字，或整段粘贴进来；也可以点「识图」拍照或选图，让它自动填。',
            '② 30 格填满后点「开始检索」。一句诗的五个字只要都在格子里就算命中，不分顺序、不管相邻，所以一次往往能查出好几句。',
            '③ 点结果里的某一条，用到的那五格会标绿；再点另一条，高亮就换成它用的格子。',
            '④ 换题时点「清空」清掉整张表；只想改一两个字，直接点那一格重填即可。'
          ])

          this.HelpImage($r('app.media.help_poetry_result'), 1100 / 806,
            '样图：填满 30 个字后自动检索，命中的五格标绿（子／云／意／浮／游），右侧是查到的诗句')

          this.Section('识图填字（v3.0 新增）', [
            '诗词检索页点「识图」，可以拍照，也可以从图库选一张 6×5 字格的图片（游戏截图、别人分享的截图都行）。',
            '程序用系统 OCR 认出图中的汉字和位置，按原顺序填进表格并自动检索，不用再一个字一个字敲。',
            '· 识别全部在手机本地完成，图片不会上传到任何地方。',
            '· 认出 30 个字才会自动检索；不足 30 个会提示你补全。',
            '· 拍歪、模糊、字太小都可能认错，必要时手动改一两个字即可。',
            '· 拍照用的是系统相机，拍下的照片会存在系统相册里，可以自行删除。'
          ])

          this.HelpImage($r('app.media.help_poetry_grid'), 1000 / 783,
            '样图：这种 6×5 字格的图片都能识别（游戏截图、别人分享的截图都行）')

          this.Section('名士检索 · 众里寻他', [
            '九种条件可以叠加：朝代、品阶、职业、生逢、出身、技能、爱好、社团、其他描述。',
            '先填条件点「检索」；出结果后继续填新条件点「二次检索」，就在上一批结果里接着筛。',
            '同一个条件改选是按替换处理，不会筛出空集。',
            '点结果里的任意一行，弹出这位名士的全部信息，你填的关键词会绿色高亮。'
          ])

          this.Section('清空与返回', [
            '成语页「清空当前」退回上一次检索，「清空所有」回到初始状态。',
            '诗词页「清空」清掉整个表格。',
            '名士页「清空当前」退回上一级条件，「清空所有」回到初始状态。',
            '系统返回手势等同于当前页的「清空当前 / 清空 / 退回上一级」。'
          ])

          this.Section('隐私与权限', [
            '不联网、不收集任何信息、没有统计分析，也不读写相册里的其他内容。',
            '只申请了「震动反馈」一个普通权限，用于按钮点击和滚动换项时的轻触感。',
            '拍照和选图都走系统自带的界面，程序只拿到你这一次选中的那一张图。'
          ])

          this.Section('题库来源与版权', [
            '题库来源于微博 @蓝在寻 的整理。',
            '《忘川风华录》相关知识内容版权归网易所有。',
            '本程序为非商业同人工具，仅供个人学习交流，不含任何游戏美术、音频、立绘等资源。',
            '「识图」说明里的样图仅为演示识别效果之用。',
            '如权利人认为有不妥，请联系作者删除。'
          ])
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
