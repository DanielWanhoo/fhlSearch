import { KeyCode } from '@kit.InputKit'
import { EASE_OUT_STRONG, MOTION_BASE_MS } from '../common/Motion'
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
  /**
   * 输入组标识（v3.2：声调 / 拼音 / 单字三行同时展示）
   *
   * 三行输入格的位置索引都是 0~3，组件 id 必须带上组前缀才不会互相覆盖，
   * 左右方向键的焦点跳转也只在本行内移动。
   */
  @Prop groupKey: string = ''
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
      .height(56)
      .maxLength(this.mode === IdiomSearchMode.PINYIN ? 8 : 1)
      .type(this.mode === IdiomSearchMode.TONE ? InputType.Number : InputType.Normal)
      .fontSize(19)
      .fontWeight(600)
      .fontColor($r('app.color.text_primary'))
      .placeholderColor($r('app.color.text_secondary'))
      .textAlign(TextAlign.Center)
      // 格的底（v3.3）：自上而下由亮到暗的极淡渐变（cell_top → cell_bottom），
      // 让每一格像一块微微凸起的浅色玻璃片；聚焦时再叠主色描边与外发光
      .linearGradient({
        angle: 180,
        colors: [
          [$r('app.color.cell_top'), 0.0],
          [$r('app.color.cell_bottom'), 1.0]
        ]
      })
      .borderRadius(14)
      // 边框宽度**保持 1vp 不变**（改宽度会让每次点格子都触发一次布局），
      // 聚焦的那圈主色改由 outline 画在盒子外面：只重绘、不动布局
      .border({ width: 1, color: $r('app.color.cell_border'), style: BorderStyle.Solid })
      .outline({
        width: this.isFocused ? 2 : 0,
        color: $r('app.color.primary'),
        radius: 14,
        style: OutlineStyle.SOLID
      })
      .shadow({
        radius: this.isFocused ? 14 : 0,
        color: $r('app.color.focus_glow'),
        offsetX: 0,
        offsetY: 0
      })
      .caretColor($r('app.color.primary'))
      .animation({ duration: MOTION_BASE_MS, curve: EASE_OUT_STRONG })
      .onFocus(() => {
        this.isFocused = true
      })
      .onBlur(() => {
        this.isFocused = false
      })
      .accessibilityText(`第${this.index + 1}个字的${this.placeholder()}输入格`)
      .accessibilityDescription(this.value === '' ? '当前为空' : `当前内容：${this.value}`)
      .id(`idiom-cell-${this.groupKey}-${this.index}`)
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
          this.getUIContext().getFocusController()
            .requestFocus(`idiom-cell-${this.groupKey}-${target}`)
          return true
        }
        return false
      })
      .onChange((v: string) => {
        this.onCellChange(this.index, this.validate(v))
      })
  }
}
