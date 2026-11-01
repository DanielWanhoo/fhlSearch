/**
 * 环境光底衬（v3.3「沉浸光感」）
 *
 * 系统沉浸材质本身是半透明的，它能不能"看出玻璃感"，取决于它下面有没有值得折射的东西。
 * 官方示例把这一层叫做"光"：底色之上铺几团大范围的柔和径向光斑，
 * 上方的玻璃卡片、胶囊页签栏、输入格就会透出一点颜色与亮度层次，而不只是一块灰。
 *
 * 三团光的分工：
 * - 暖红（主色）在左上：托住大标题与第一组输入格，和品牌色呼应
 * - 金色在右上：给"检索 N 次"胶囊与信息按钮一点暖反光
 * - 青墨在底部：制造纵深，让页签栏浮在"有厚度的背景"上
 *
 * 全部用 radialGradient 从 alpha 渐变到 0，边缘完全透明，不会出现生硬的色块边界。
 * 这一层只做背景，不接收点击（放在页面 Stack 的最底层，内容在其之上）。
 */
@Component
export struct AmbientBackdrop {
  build() {
    Stack() {
      // 底色：浅色是暖米色、深色是暖黑，随系统深浅色自动切换
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background'))

      // ① 左上暖红光斑
      Column()
        .width('82%')
        .aspectRatio(1)
        .radialGradient({
          center: ['50%', '50%'],
          radius: '50%',
          colors: [
            [$r('app.color.glow_primary'), 0.0],
            [$r('app.color.glow_primary_clear'), 1.0]
          ]
        })
        .position({ x: '-26%', y: '-16%' })

      // ② 右上金色光斑
      Column()
        .width('64%')
        .aspectRatio(1)
        .radialGradient({
          center: ['50%', '50%'],
          radius: '50%',
          colors: [
            [$r('app.color.glow_gold'), 0.0],
            [$r('app.color.glow_gold_clear'), 1.0]
          ]
        })
        .position({ x: '58%', y: '6%' })

      // ③ 底部青墨纵深
      Column()
        .width('110%')
        .aspectRatio(1)
        .radialGradient({
          center: ['50%', '50%'],
          radius: '50%',
          colors: [
            [$r('app.color.glow_ink'), 0.0],
            [$r('app.color.glow_ink_clear'), 1.0]
          ]
        })
        .position({ x: '-5%', y: '66%' })
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }
}
