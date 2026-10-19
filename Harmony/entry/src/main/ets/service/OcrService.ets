import { textRecognition } from '@kit.CoreVisionKit'
import { image } from '@kit.ImageKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { camera, cameraPicker } from '@kit.CameraKit'
import { common } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { i18n } from '@kit.LocalizationKit'
import { extractGrid, GridExtraction, OcrChar } from './OcrGridExtractor'

/**
 * 识图填字服务 — 拍照 / 相册取图 → 系统 OCR → 还原 6×5 字格
 *
 * OCR 用的是鸿蒙系统自带的 **Core Vision Kit** 文字识别（@kit.CoreVisionKit → textRecognition）：
 * - 完全在设备本地运行，不上传图片、不需要联网、不需要任何权限
 * - 返回「文本块 → 行 → 词」三层结构，每个词都带外接框（cornerPoints，顺时针四点）
 * - 单个字的坐标就是词框中心；若一行字被识别成一个词（字格里常见），按等宽把框切开分摊
 *
 * 取图两条路，都走系统自带界面，本应用不申请相机/相册权限：
 * - 拍照：cameraPicker.pick()（系统相机 picker；拍下的照片由系统存进相册）
 * - 相册：photoAccessHelper.PhotoViewPicker（系统图库 picker，只拿到用户选中的那一张）
 */

const DOMAIN = 0x0000
const TAG = 'CulturalSearch'
const MAX_SIDE = 2400          // 长边超过这个就等比缩小再识别：速度更快，字格几何关系不变
const MAX_PIXELS = 8000000     // 单次识别解码后的像素上限（预处理要多占一份内存，别太大）
const TARGET_CHAR_PX = 110     // 期望的字高（像素）：字比这个小才值得放大再认一遍
const CELLS = 30

/** 「识图」的最终结果 */
export class OcrOutcome {
  /** 还原出的字格（按阅读顺序，最多 30 个汉字） */
  grid: GridExtraction | null = null
  /** 整张图认出的汉字总数（含与字格无关的文字） */
  totalHanzi: number = 0
  /** 识别用的图片尺寸（缩放后） */
  imageWidth: number = 0
  imageHeight: number = 0
  /** 认出的字的中位高度（像素）：用来决定要不要放大再认一次 */
  charHeight: number = 0
  /** 实际执行了几次识别（多轮投票时会大于 1） */
  passes: number = 0
}

// ==================== 能力探测 ====================

/** 当前设备是否支持系统文字识别（模拟器 / 精简系统可能没有） */
export function isOcrSupported(): boolean {
  try {
    return canIUse('SystemCapability.AI.OCR.TextRecognition')
  } catch (err) {
    return false
  }
}

// ==================== 取图 ====================

/** 调起系统相机拍照；用户取消返回空串 */
export async function pickFromCamera(context: common.UIAbilityContext): Promise<string> {
  const profile: cameraPicker.PickerProfile = {
    cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK
  }
  const result: cameraPicker.PickerResult = await cameraPicker.pick(
    context, [cameraPicker.PickerMediaType.PHOTO], profile)
  if (result.resultCode === 0 && result.resultUri !== undefined && result.resultUri.length > 0) {
    return result.resultUri
  }
  return ''
}

/** 从系统图库选一张图；用户取消返回空串 */
export async function pickFromGallery(): Promise<string> {
  const options = new photoAccessHelper.PhotoSelectOptions()
  options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
  options.maxSelectNumber = 1
  const picker = new photoAccessHelper.PhotoViewPicker()
  const result: photoAccessHelper.PhotoSelectResult = await picker.select(options)
  if (result.photoUris !== undefined && result.photoUris.length > 0) {
    return result.photoUris[0]
  }
  return ''
}
// ==================== 识别 ====================

/**
 * 识别一张图里的 6×5 字格（图像增强 + 多尺度 + 按格投票）
 *
 * 实测（四张真实游戏截图，见 dev-logs/2026-10-19.md）：
 * - 原图直接丢给系统 OCR，30 个格子通常只认对 18~26 个，有时整行漏认；
 * - 先做**灰度 + 对比度拉伸**再识别，四张图里三张直接 30/30 全对；
 * - 剩下那张要**二值化**才对（引擎对带菱形花纹的浅米黄底更敏感）。
 *
 * 所以跑 3 个组合，再**按格投票**（同一格多数一致的取多数，平票取分辨率高的）：
 *   ① 灰度增强 @ 原尺寸  ② 灰度增强 @ 2 倍（字偏小时才跑）  ③ 二值化 @ 原尺寸
 * 每次识别 0.5~2 秒，通常 2~4 秒出结果（识别中界面有转圈提示）。
 * @param uri 图片 URI（相机 picker / 图库 picker 返回）
 */
export async function recognizeGrid(uri: string): Promise<OcrOutcome> {
  const file = fs.openSync(uri, fs.OpenMode.READ_ONLY)
  let source: image.ImageSource | undefined = undefined
  try {
    source = image.createImageSource(file.fd)
    return await recognizeSource(source)
  } finally {
    if (source !== undefined) {
      source.release()
    }
    fs.closeSync(file)
  }
}

/**
 * 对已创建的 ImageSource 做「增强 + 多尺寸 + 投票」识别（取图路径与自测脚本共用）
 * @param source 由 uri（fd）或图片字节创建的解码源
 */
export async function recognizeSource(source: image.ImageSource): Promise<OcrOutcome> {
  const info: image.ImageInfo = await source.getImageInfo()
  const base: number = Math.min(1, MAX_SIDE / Math.max(info.size.width, info.size.height))
  const baseW: number = Math.max(1, Math.round(info.size.width * base))
  const baseH: number = Math.max(1, Math.round(info.size.height * base))

  const outcomes: OcrOutcome[] = []
  // ① 灰度增强 @ 原尺寸
  const first: OcrOutcome = await decodeAndRecognize(source, baseW, baseH, MODE_ENHANCE)
  outcomes.push(first)

  // ② 灰度增强 @ 2 倍：只在「字还偏小」时才值得跑
  if (first.charHeight > 0 && first.charHeight < TARGET_CHAR_PX) {
    const w: number = baseW * 2
    const h: number = baseH * 2
    if (w * h <= MAX_PIXELS && Math.max(w, h) <= 6000) {
      try {
        outcomes.push(await decodeAndRecognize(source, w, h, MODE_ENHANCE))
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'ocr 2x failed: %{public}s', JSON.stringify(err))
      }
    }
  }

  // ③ 二值化 @ 原尺寸（对付带花纹的浅色底）
  //    省时间：前两轮都认满 30 格、且每一格结果完全一致时，就不必再跑一轮
  if (!agreeFully(outcomes)) {
    try {
      outcomes.push(await decodeAndRecognize(source, baseW, baseH, MODE_BINARY))
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'ocr binary failed: %{public}s', JSON.stringify(err))
    }
  }

  return mergeOutcomes(outcomes)
}

export const MODE_RAW: number = 0      // 原样（调试用）
export const MODE_ENHANCE: number = 1  // 灰度 + 对比度拉伸
export const MODE_BINARY: number = 2   // 灰度 + Otsu 二值化

/** 已有几轮结果是否「都认满 30 格且逐格完全一致」——一致就不必再跑下一轮 */
function agreeFully(list: OcrOutcome[]): boolean {
  if (list.length < 2) {
    return false
  }
  let ref: string[] | null = null
  for (const o of list) {
    const g = o.grid
    if (g === null || g.cells.length !== CELLS) {
      return false
    }
    for (const ch of g.cells) {
      if (ch === '') {
        return false
      }
    }
    if (ref === null) {
      ref = g.cells
    } else {
      for (let i = 0; i < CELLS; i++) {
        if (ref[i] !== g.cells[i]) {
          return false
        }
      }
    }
  }
  return true
}

/** 按指定尺寸解码 → 预处理 → 识别；PixelMap 用完立刻释放 */
async function decodeAndRecognize(source: image.ImageSource, width: number, height: number,
  mode: number): Promise<OcrOutcome> {
  const options: image.DecodingOptions = {
    editable: true,
    desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
    desiredSize: { width: width, height: height }
  }
  const pixelMap: image.PixelMap = await source.createPixelMap(options)
  let prepared: image.PixelMap | null = null
  try {
    prepared = await preprocess(pixelMap, mode)
    const outcome: OcrOutcome = await recognizePixelMap(prepared === null ? pixelMap : prepared)
    outcome.imageWidth = width
    outcome.imageHeight = height
    return outcome
  } finally {
    if (prepared !== null) {
      prepared.release()
    }
    pixelMap.release()
  }
}

// ==================== 图像预处理 ====================

/**
 * 把 PixelMap 处理成更适合识别的样子
 *
 * 游戏字格的底色是浅米黄、还带菱形花纹，字是深棕色 —— 直接识别时引擎常把字和花纹看混。
 * 灰度 + 对比度拉伸能把字压黑、底提白；二值化更激进，对花纹重的图更有效。
 * @returns 处理后的 PixelMap；处理不了时返回 null（调用方退回用原图）
 */
async function preprocess(src: image.PixelMap, mode: number): Promise<image.PixelMap | null> {
  if (mode === MODE_RAW) {
    return null
  }
  const info: image.ImageInfo = await src.getImageInfo()
  const w: number = info.size.width
  const h: number = info.size.height
  if (w <= 0 || h <= 0) {
    return null
  }
  const raw = new ArrayBuffer(w * h * 4)
  await src.readPixelsToBuffer(raw)
  const px = new Uint8Array(raw)

  const gray = new Uint8Array(w * h)
  const hist: number[] = new Array<number>(256).fill(0)
  for (let i = 0, p = 0; i < w * h; i++, p += 4) {
    const g: number = Math.round((px[p] * 299 + px[p + 1] * 587 + px[p + 2] * 114) / 1000)
    const v: number = g < 0 ? 0 : (g > 255 ? 255 : g)
    gray[i] = v
    hist[v]++
  }

  const out = new Uint8Array(w * h * 4)
  if (mode === MODE_BINARY) {
    const t: number = otsu(hist, w * h)
    for (let i = 0, p = 0; i < w * h; i++, p += 4) {
      const v: number = gray[i] > t ? 255 : 0
      out[p] = v
      out[p + 1] = v
      out[p + 2] = v
      out[p + 3] = 255
    }
  } else {
    // 对比度拉伸：把 2% / 98% 分位分别拉到 0 / 255
    const total: number = w * h
    let lo: number = 0
    let acc: number = 0
    for (let v = 0; v < 256; v++) {
      acc += hist[v]
      if (acc >= total * 0.02) {
        lo = v
        break
      }
    }
    let hi: number = 255
    acc = 0
    for (let v = 255; v >= 0; v--) {
      acc += hist[v]
      if (acc >= total * 0.02) {
        hi = v
        break
      }
    }
    const span: number = Math.max(1, hi - lo)
    for (let i = 0, p = 0; i < w * h; i++, p += 4) {
      const t: number = Math.round((gray[i] - lo) * 255 / span)
      const v: number = t < 0 ? 0 : (t > 255 ? 255 : t)
      out[p] = v
      out[p + 1] = v
      out[p + 2] = v
      out[p + 3] = 255
    }
  }

  const buffer: ArrayBuffer = out.buffer as ArrayBuffer
  return await image.createPixelMap(buffer, {
    size: { width: w, height: h },
    srcPixelFormat: image.PixelMapFormat.RGBA_8888,
    pixelFormat: image.PixelMapFormat.RGBA_8888,
    editable: false
  })
}

/** Otsu 阈值：让前景/背景两类之间的方差最大 */
function otsu(hist: number[], total: number): number {
  let sum: number = 0
  for (let v = 0; v < 256; v++) {
    sum += v * hist[v]
  }
  let sumB: number = 0
  let wB: number = 0
  let best: number = 128
  let bestVar: number = -1
  for (let v = 0; v < 256; v++) {
    wB += hist[v]
    if (wB === 0) {
      continue
    }
    const wF: number = total - wB
    if (wF === 0) {
      break
    }
    sumB += v * hist[v]
    const mB: number = sumB / wB
    const mF: number = (sum - sumB) / wF
    const between: number = wB * wF * (mB - mF) * (mB - mF)
    if (between > bestVar) {
      bestVar = between
      best = v
    }
  }
  return best
}
/**
 * 合并多轮识别的结果
 *
 * - 能对齐到格位的几轮（cells 满 30 格）按格投票：同一格多数一致的取多数；
 *   平票时取**分辨率更高**那轮（数组靠后的是放大后的）
 * - 对不齐格位时退回「认出字最多的那一次」
 */
function mergeOutcomes(list: OcrOutcome[]): OcrOutcome {
  if (list.length === 1) {
    list[0].passes = 1
    return list[0]
  }
  const merged = new OcrOutcome()
  merged.passes = list.length
  merged.imageWidth = list[0].imageWidth
  merged.imageHeight = list[0].imageHeight
  merged.charHeight = list[0].charHeight
  for (const o of list) {
    if (o.totalHanzi > merged.totalHanzi) {
      merged.totalHanzi = o.totalHanzi
    }
  }

  const aligned: GridExtraction[] = []
  for (const o of list) {
    if (o.grid !== null && o.grid.cells.length === CELLS) {
      aligned.push(o.grid)
    }
  }

  if (aligned.length >= 2) {
    const cells: string[] = new Array<string>(CELLS).fill('')
    for (let i = 0; i < CELLS; i++) {
      const votes = new Map<string, number>()
      for (let k = aligned.length - 1; k >= 0; k--) {
        const ch: string = aligned[k].cells[i]
        if (ch === '') {
          continue
        }
        const n: number | undefined = votes.get(ch)
        votes.set(ch, n === undefined ? 1 : n + 1)
      }
      let best: string = ''
      let bestCount: number = 0
      votes.forEach((count: number, ch: string) => {
        if (count > bestCount) {
          bestCount = count
          best = ch
        }
      })
      cells[i] = best
    }
    const grid = new GridExtraction()
    grid.cells = cells
    grid.isGrid = true
    grid.rowCount = aligned[0].rowCount
    grid.colCount = aligned[0].colCount
    for (const ch of cells) {
      if (ch !== '') {
        grid.chars.push(ch)
      }
    }
    merged.grid = grid
    hilog.info(DOMAIN, TAG, 'ocrMerged passes=%{public}d filled=%{public}d/30', aligned.length, grid.chars.length)
    return merged
  }

  // 对不齐格位：取认出字最多的一次
  let best: GridExtraction | null = null
  for (const o of list) {
    if (o.grid === null) {
      continue
    }
    if (best === null || o.grid.chars.length > best.chars.length) {
      best = o.grid
    }
  }
  merged.grid = best
  return merged
}

/**
 * 对一张已解码的 PixelMap 做文字识别并还原字格
 *
 * 独立成函数，便于「取图 / 预处理 / 识别」各自替换（也是自测脚本直接复用的入口）。
 * @param pixelMap 必须是 RGBA_8888 格式
 */
export async function recognizePixelMap(pixelMap: image.PixelMap): Promise<OcrOutcome> {
  const outcome = new OcrOutcome()
  const visionInfo: textRecognition.VisionInfo = { pixelMap: pixelMap }
  const config: textRecognition.TextRecognitionConfiguration = {
    // 拍照可能是横竖颠倒的：保留方向检测更稳（关掉能快一点，但拍歪就认不出行）
    isDirectionDetectionSupported: true
  }
  const result: textRecognition.TextRecognitionResult = await textRecognition.recognizeText(visionInfo, config)
  const chars: OcrChar[] = collectChars(result)
  outcome.totalHanzi = chars.length
  outcome.charHeight = medianHeight(chars)
  outcome.grid = extractGrid(chars)
  logOutcome(outcome)
  return outcome
}

/** 认出的字的中位高度（像素）：判断「字是不是太小、要不要放大再认」 */
function medianHeight(chars: OcrChar[]): number {
  if (chars.length === 0) {
    return 0
  }
  const hs: number[] = chars.map((c: OcrChar) => c.h)
  hs.sort((a: number, b: number) => a - b)
  return hs[Math.floor(hs.length / 2)]
}

/**
 * 把 OCR 的三层结果摊平成「汉字 + 外接框」列表
 *
 * 只取最底层的 words（blocks → lines → words），避免同一段文字在块/行/词三层各算一遍。
 * 某个行一个词都没有时退回用行本身。
 */
function collectChars(result: textRecognition.TextRecognitionResult): OcrChar[] {
  const out: OcrChar[] = []
  const blocks: textRecognition.TextBlock[] = result.blocks ?? []
  for (const block of blocks) {
    for (const line of block.lines ?? []) {
      const words: textRecognition.TextWord[] = line.words ?? []
      if (words.length > 0) {
        for (const word of words) {
          pushWord(out, word.value, word.cornerPoints)
        }
      } else {
        pushWord(out, line.value, line.cornerPoints)
      }
    }
  }
  return out
}

/** 一个词可能含多个汉字：一个字的直接用，多个字的按等宽（或等高）切开分摊坐标 */
function pushWord(out: OcrChar[], value: string, points: textRecognition.PixelPoint[]): void {
  const han: string = hanziOnly(toSimplified(value))
  if (han.length === 0 || points === undefined || points.length === 0) {
    return
  }
  const box: number[] = boundsOf(points)  // [x0, y0, x1, y1]
  const w: number = Math.max(box[2] - box[0], 1)
  const h: number = Math.max(box[3] - box[1], 1)
  const cy: number = (box[1] + box[3]) / 2

  if (han.length === 1) {
    out.push(new OcrChar(han, (box[0] + box[2]) / 2, cy, w, h))
    return
  }

  if (h > w * 1.4) {
    // 竖排：一个字在上一字之下
    const step: number = h / han.length
    for (let i = 0; i < han.length; i++) {
      out.push(new OcrChar(han.charAt(i), (box[0] + box[2]) / 2, box[1] + step * (i + 0.5), w, step))
    }
  } else {
    // 横排（字格里的常态）：等宽切分
    const step: number = w / han.length
    for (let i = 0; i < han.length; i++) {
      out.push(new OcrChar(han.charAt(i), box[0] + step * (i + 0.5), cy, step, h))
    }
  }
}

/** 四点多边形 → [x0, y0, x1, y1] 外接框 */
function boundsOf(points: textRecognition.PixelPoint[]): number[] {
  let x0: number = Number.MAX_VALUE
  let y0: number = Number.MAX_VALUE
  let x1: number = -Number.MAX_VALUE
  let y1: number = -Number.MAX_VALUE
  for (const p of points) {
    if (p.x < x0) x0 = p.x
    if (p.y < y0) y0 = p.y
    if (p.x > x1) x1 = p.x
    if (p.y > y1) y1 = p.y
  }
  return [x0, y0, x1, y1]
}
/**
 * 繁体 → 简体
 *
 * OCR 偶尔会吐出繁体字（例如把「页」认成「頁」），而题库全是简体，差一个字就搜不到。
 * 优先用系统的转换器（i18n.Transliterator），拿不到就退回内置对照表。
 */
let simpLoaded: boolean = false
let simpTrans: i18n.Transliterator | null = null
let simpTable: Map<string, string> | null = null

/** 内置兜底对照表（按「繁体简体」成对排列），覆盖古诗里繁简字形不同的常用字 */
const HANT_PAIRS: string =
  '頁页雲云樓楼濕湿裡里煙烟萬万與与無无為为國国過过這这來来時时見见車车門门風风飛飞鳥鸟魚鱼馬马龍龙鳳凤愛爱聽听說说語语書书長长東东樂乐學学問问開开關关點点聲声氣气歲岁歡欢憶忆夢梦處处從从對对將将尋寻歸归還还進进遠远邊边陽阳陰阴際际雙双難难離离滿满漢汉淺浅綠绿紅红絲丝斷断續续階阶隨随隱隐驚惊顧顾顯显餘余飲饮館馆齊齐齒齿龜龟鹽盐麗丽黃黄獨独讀读寫写畫画鐘钟間间閒闲現现環环節节範范簡简紙纸絕绝繼继練练總总聯联職职興兴舉举舊旧藝艺蘇苏蘭兰號号蟲虫術术衛卫補补裝装覺觉觀观計计訂订記记設设許许詩诗詞词試试話话該该詳详認认誰谁課课調调談谈請请論论諸诸謂谓講讲謝谢識识譯译議议護护變变讓让豐丰負负財财貢贡貴贵買买費费賀贺資资賓宾質质贊赞軍军輕轻載载較较輪轮輸输農农遊游運运達达遞递適适選选鄉乡釋释針针銀银錢钱鋼钢鍵键鏡镜閃闪閱阅陸陆隊队雖虽雜杂雞鸡靈灵靜静頂顶項项順顺須须預预領领頭头題题願愿類类顧顾飯饭餐餐駕驾騎骑驗验髮发鬥斗麥麦'

/** 把 OCR 认出的文本转成简体（逐字映射，长度不变） */
function toSimplified(text: string): string {
  if (!simpLoaded) {
    simpLoaded = true
    try {
      const ids: string[] = i18n.Transliterator.getAvailableIDs()
      for (const id of ids) {
        if (id === 'Traditional-Simplified') {
          simpTrans = i18n.Transliterator.getInstance(id)
          break
        }
      }
    } catch (err) {
      simpTrans = null
    }
    if (simpTrans === null) {
      const table = new Map<string, string>()
      for (let i = 0; i + 1 < HANT_PAIRS.length; i += 2) {
        table.set(HANT_PAIRS.charAt(i), HANT_PAIRS.charAt(i + 1))
      }
      simpTable = table
    }
  }
  if (simpTrans !== null) {
    try {
      const out: string = simpTrans.transform(text)
      if (out.length === text.length) {
        return out
      }
    } catch (err) {
      // 转换失败就用原文
    }
    return text
  }
  const t: Map<string, string> | null = simpTable
  if (t === null) {
    return text
  }
  let out: string = ''
  for (let i = 0; i < text.length; i++) {
    const mapped: string | undefined = t.get(text.charAt(i))
    out += mapped === undefined ? text.charAt(i) : mapped
  }
  return out
}

/** 只留 CJK 基本集汉字（与表格输入框的校验范围一致：0x4E00 ~ 0x9FFF） */
export function hanziOnly(text: string): string {
  let out: string = ''
  for (let i = 0; i < text.length; i++) {
    const code: number = text.charCodeAt(i)
    if (code >= 0x4E00 && code <= 0x9FFF) {
      out += text.charAt(i)
    }
  }
  return out
}

/** 把识别结果写进日志：调参、复盘识别质量时用（hilog -x | grep ocrGrid） */
function logOutcome(outcome: OcrOutcome): void {
  const g = outcome.grid
  if (g === null) {
    hilog.info(DOMAIN, TAG, 'ocrGrid=none totalHanzi=%{public}d', outcome.totalHanzi)
    return
  }
  hilog.info(DOMAIN, TAG,
    'ocrGrid isGrid=%{public}s rows=%{public}d cols=%{public}d n=%{public}d total=%{public}d chars=%{public}s',
    g.isGrid ? 'yes' : 'no', g.rowCount, g.colCount, g.chars.length, outcome.totalHanzi, g.chars.join(''))
}

/** 把异常整理成一句能读的中文（回调 UI 提示用） */
export function describeError(err: BusinessError): string {
  const code: number = err.code ?? 0
  if (code === 200) {
    return '识别超时，请重试'
  }
  if (code === 1001400001 || code === 1001400002) {
    return '识别服务暂时不可用，请稍后重试'
  }
  if (code === 401) {
    return '这张图片无法识别，请换一张'
  }
  // 不把英文报错原样丢给用户：绝大多数是「本机没有文字识别能力」这一类
  return '识别没有完成，请重试。若反复失败，可能是本机缺少系统文字识别能力'
}
