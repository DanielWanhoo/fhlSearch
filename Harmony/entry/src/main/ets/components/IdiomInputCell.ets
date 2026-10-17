import { KeyCode } from '@kit.InputKit'
import { IdiomSearchMode } from '../service/IdiomSearchService'
import { isValidHanzi } from './GridCell'

/**
 * 成语检索 — 单个输入格
 *
 * 按检索模式切换键盘与校验：
 * - 拼音：字母键盘，自动转小写，仅保留 a-z（v 代表 ü）
 * - 声调：数字键盘，仅 1~4
 * - 单字：单汉字，maxLength 1
 */

@Component
export struct IdiomInputCell {
  @Prop value: string = ''
  @Prop mode: IdiomSearchMode = IdiomSearchMode.PINYIN
  @Prop index: number = 0
  @State isFocused: boolean = false  // 是否聚焦（聚焦边框变主色，与诗词格一致）
  onCellChange: (index: number, value: string) => void = () => {}

  private placeholder(): string {
    if (this.mode === IdiomSearchMode.PINYIN) {
      return '拼音'
    }
    if (this.mode === IdiomSearchMode.TONE) {
      return '声调'
    }
    return '字'
  }

  /**
   * 按当前模式校验并规整输入，返回合法的值（非法则返回空串）
   */
  private validate(v: string): string {
    if (v.length === 0) {
      return ''
    }
    if (this.mode === IdiomSearchMode.PINYIN) {
      // 仅保留小写 a-z，自动转小写（v 用于表示 ü）
      let out = ''
      for (let i = 0; i < v.length; i++) {
        const ch = v.charAt(i).toLowerCase()
        if (ch >= 'a' && ch <= 'z') {
          out += ch
        }
      }
      return out
    } else if (this.mode === IdiomSearchMode.TONE) {
      // 只保留最后一个字符，且必须为 1~4
      const ch = v.charAt(v.length - 1)
      return (ch >= '1' && ch <= '4') ? ch : ''
    } else {
      // 单字模式：必须为单个汉字
      return isValidHanzi(v) ? v : ''
    }
  }

  build() {
    TextInput({ text: this.value, placeholder: this.placeholder() })
      .width('100%')
      .height(52)
      .maxLength(this.mode === IdiomSearchMode.PINYIN ? 8 : 1)
      .type(this.mode === IdiomSearchMode.TONE ? InputType.Number : InputType.Normal)
      .fontSize(18)
      .fontWeight(500)
      .fontColor($r('app.color.text_primary'))
      .placeholderColor($r('app.color.text_secondary'))
      .textAlign(TextAlign.Center)
      .backgroundColor($r('app.color.cell_bg'))
      .borderRadius(8)
      .border({
        width: this.isFocused ? 2 : 1.5,
        color: this.isFocused ? $r('app.color.primary') : $r('app.color.cell_border'),
        style: BorderStyle.Solid
      })
      .caretColor($r('app.color.primary'))
      .animation({ duration: 150, curve: Curve.EaseOut })
      .onFocus(() => {
        this.isFocused = true
      })
      .onBlur(() => {
        this.isFocused = false
      })
      .accessibilityText(`第${this.index + 1}个字的${this.placeholder()}输入格`)
      .accessibilityDescription(this.value === '' ? '当前为空' : `当前内容：${this.value}`)
      .id(`idiom-cell-${this.index}`)
      .onKeyEvent((event: KeyEvent) => {
        if (event.type !== KeyType.Down) {
          return false
        }
        let target = -1
        if (event.keyCode === KeyCode.KEYCODE_DPAD_LEFT) {
          target = this.index - 1
        } else if (event.keyCode === KeyCode.KEYCODE_DPAD_RIGHT) {
          target = this.index + 1
        }
        if (target >= 0 && target <= 3) {
          this.getUIContext().getFocusController().requestFocus(`idiom-cell-${target}`)
          return true
        }
        return false
      })
      .onChange((v: string) => {
        this.onCellChange(this.index, this.validate(v))
      })
  }
}
