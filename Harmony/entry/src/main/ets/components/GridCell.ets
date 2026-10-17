import { KeyCode } from '@kit.InputKit'
import { GridCellData } from '../model/PoetryItem'

/**
 * 6×5 表格（6 列 5 行）中的单个输入格子
 *
 * 功能：
 * - 限制输入 1 个汉字
 * - 实时校验非汉字/多字输入
 * - 命中态绿色高亮、聚焦态主色边框
 * - @ObjectLink 自动同步外部数据变更（清空、检索标注等）
 */

// Unicode 范围：CJK 统一汉字基本集
const CJK_MIN = 0x4E00   // 一
const CJK_MAX = 0x9FFF   // 鿿

/**
 * 判断单个字符是否为 CJK 基本集汉字
 */
export function isValidHanzi(ch: string): boolean {
  if (ch.length !== 1) return false
  const code = ch.charCodeAt(0)
  return code >= CJK_MIN && code <= CJK_MAX
}

@Component
export struct GridCell {
  @ObjectLink cell: GridCellData          // 双向绑定数据
  @State isFocused: boolean = false       // 是否聚焦
  onPasteText: (text: string) => void = () => {}  // 粘贴整段文本时上抛给父组件统一填充

  /**
   * 校验输入并处理非法情况
   */
  private validateInput(value: string): void {
    // 用户删除清空了格子
    if (value.length === 0 || value === '') {
      this.cell.char = ''
      this.cell.isMatched = false
      return
    }

    // 情况 1：输入了多个字符（粘贴等）
    if (value.length > 1) {
      AlertDialog.show({
        title: '输入错误',
        message: '每个格子只能填写一个汉字',
        confirm: {
          value: '确定',
          action: () => {}
        }
      })
      this.cell.char = ''
      return
    }

    // 情况 2：输入了非汉字
    if (!isValidHanzi(value)) {
      AlertDialog.show({
        title: '输入错误',
        message: '请输入单个汉字',
        confirm: {
          value: '确定',
          action: () => {}
        }
      })
      this.cell.char = ''
      return
    }

    // 情况 3：合法输入
    this.cell.char = value
  }

  build() {
    Column() {
      TextInput({ text: this.cell.char })
        .width('100%')
        .height('100%')
        .maxLength(1)
        .fontSize(18)
        .fontWeight(500)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)
        .type(InputType.Normal)
        .backgroundColor(this.cell.isMatched ? $r('app.color.match_highlight_bg') : $r('app.color.cell_bg'))
        .borderRadius(8)
        .border({
          width: this.cell.isMatched ? 3 : this.isFocused ? 2 : 1.5,
          color: this.cell.isMatched ? $r('app.color.match_highlight') : this.isFocused ? $r('app.color.primary') : $r('app.color.cell_border'),
          style: BorderStyle.Solid
        })
        .padding(0)
        .caretColor($r('app.color.primary'))
        .onFocus(() => {
          this.isFocused = true
        })
        .onBlur(() => {
          this.isFocused = false
        })
        .animation({ duration: 150, curve: Curve.EaseOut })
        .id(`grid-${this.cell.row}-${this.cell.col}`)
        .onKeyEvent((event: KeyEvent) => {
          if (event.type !== KeyType.Down) {
            return false
          }
          let dr = 0
          let dc = 0
          if (event.keyCode === KeyCode.KEYCODE_DPAD_UP) {
            dr = -1
          } else if (event.keyCode === KeyCode.KEYCODE_DPAD_DOWN) {
            dr = 1
          } else if (event.keyCode === KeyCode.KEYCODE_DPAD_LEFT) {
            dc = -1
          } else if (event.keyCode === KeyCode.KEYCODE_DPAD_RIGHT) {
            dc = 1
          } else {
            return false
          }
          const nr = this.cell.row + dr
          const nc = this.cell.col + dc
          if (nr >= 0 && nr < 5 && nc >= 0 && nc < 6) {
            this.getUIContext().getFocusController().requestFocus(`grid-${nr}-${nc}`)
            return true
          }
          return false
        })
        .onChange((value: string) => {
          this.validateInput(value)
        })
        .onPaste((value: string, event: PasteEvent) => {
          if (event !== undefined && event.preventDefault) {
            event.preventDefault()
          }
          this.onPasteText(value)
        })
        .accessibilityText(`第${this.cell.row + 1}行第${this.cell.col + 1}列输入格`)
        .accessibilityDescription(this.cell.char === '' ? '当前为空' : `当前内容：${this.cell.char}${this.cell.isMatched ? '，已命中' : ''}`)
    }
    .width('100%')
    .height('100%')
  }
}
