# 忘川检索 fhlSearch

《忘川风华录》「山石雅集」与「众里寻他」三类检索题的**离线查询小工具**。

按平台分目录存放，目前有：

| 平台 | 目录 | 说明 |
| --- | --- | --- |
| Windows | [`Windows/`](Windows/) | C# / WinForms，单个 exe 绿色免安装，支持 Windows 7 SP1 及以上 |
| Android | [`Android/`](Android/) | Kotlin，单个 apk 离线安装，支持 Android 10 及以上手机 / 平板 |

---

## 下载

不想看代码的话，直接拿编译好的程序：

| 平台 | 下载 | 说明 |
| --- | --- | --- |
| Windows | **[`Windows/dist/忘川检索.exe`](Windows/dist/忘川检索.exe)** | 双击就能用。不联网、不写注册表、不需要安装。Win7 需要系统已装 .NET Framework 4.0+，Win10 / Win11 系统自带 |
| Android | **[`Android/dist/忘川检索.apk`](Android/dist/忘川检索.apk)** | 传到手机 / 平板点一下安装（需允许「安装未知应用」）。不联网、不要任何权限，Android 10 及以上 |

| Windows 版 | Android 版 |
| --- | --- |
| ![成语检索](Windows/docs/screenshots/01-idiom.png) | ![成语检索](Android/docs/screenshots/01-idiom.png) |

---

## 它做什么

题库内嵌在程序里，完全离线，用来快速定位三类检索题的答案：

- **成语检索** —— 319 条成语，按拼音 / 声调 / 单字查，命中位置标绿
- **诗词检索** —— 282 条五言诗句，6×5 字格填字，自动拼出能组成的诗句
- **名士检索** —— 115 位名士，9 种条件（朝代 / 爱好 / 社团 / 品阶 / 职业 …）筛选

「检索」与「二次检索」是一对动作按钮：先在全库里查，出了结果之后就用「二次检索」
在上一批结果里接着筛，一层层缩小范围。

更多截图和完整说明见 [`Windows/README.md`](Windows/README.md) 与 [`Android/README.md`](Android/README.md)。

---

## 许可

程序代码以 **MIT** 协议开源，见 [`Windows/LICENSE`](Windows/LICENSE) 与 [`Android/LICENSE`](Android/LICENSE)。

题库数据（`Windows/data/`、`Android/data/` 下的 Excel 与内嵌题库）**不在 MIT 授权范围内** ——
题库来源于微博 @蓝在寻，《忘川风华录》相关内容版权归网易所有。
详见 [`Windows/NOTICE.md`](Windows/NOTICE.md) 与 [`Android/NOTICE.md`](Android/NOTICE.md)。

本仓库是**非商业同人项目**，没有广告、赞助或任何收费入口。
**如权利人认为此处有不妥，请开 Issue 或联系作者，我会立即移除。**
