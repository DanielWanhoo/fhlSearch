import { GridCellData } from '../model/PoetryItem'
import { GridCell } from './GridCell'

/**
 * 6×5 诗词填字表格（6 列 5 行，共 30 格）
 *
 * 从父组件接收 gridData，仅负责渲染。
 * 数据状态由 PoetrySearchPage.ets 统一管理。
 *
 * 布局要点：最外层 Column 用 aspectRatio(6/5) 定出「6 列 × 5 行」的矩形骨架
 * （单元格仍保持正方形），边框与内边距直接放外层；
 * 网格用 layoutWeight(1) 填满内容区（弹性布局会自动扣除 padding，不会像 height(100%) 那样溢出），
 * 保证最后一行格子的下边框完整可见。
 */

@Component
export struct PoetryGrid {
  @Link gridData: GridCellData[][]  // 从父组件传入
  onPasteText: (text: string) => void = () => {}  // 粘贴整段文本时上抛给父组件

  build() {
    Column() {
      Grid() {
        ForEach(this.gridData, (row: GridCellData[]) => {
          ForEach(row, (cell: GridCellData) => {
            GridItem() {
              GridCell({ cell: cell, onPasteText: this.onPasteText })
                .width('100%')
                .height('100%')
            }
          }, (cell: GridCellData) => `cell-${cell.row}-${cell.col}`)
        }, (row: GridCellData[]) => `row-${row[0]?.row ?? 0}`)
      }
      .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr')
      .rowsTemplate('1fr 1fr 1fr 1fr 1fr')
      .columnsGap(2)
      .rowsGap(2)
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .aspectRatio(1.2)
    .constraintSize({ maxWidth: 456 })
    .padding(8)
    .borderRadius(12)
    .border({
      width: 2,
      color: $r('app.color.primary'),
      style: BorderStyle.Solid
    })
    .backgroundColor($r('app.color.card_bg'))
  }
}
