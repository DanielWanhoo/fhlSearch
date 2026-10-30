# 忘川检索 · fhlSearch（Android 版）

> 面向 **Android 10（API 29）及以上**手机与平板 ｜ **完全离线**：不联网、不要任何权限
> 题库已内嵌在安装包里，装好即用，不需要 Excel、不需要网络。

**当前版本：3.2（versionCode 5）**

---

## 一、我要装它 → 拿这个文件

| 文件 | 路径 |
| --- | --- |
| **安装包** | `dist\fhlSearch_v3.2.apk`（约 44 MB —— 含约 30 MB 的中文 OCR 模型，识别全在本机跑） |

传到手机/平板上点一下安装即可。图标是**朱砂圆印**，名字叫「忘川检索」。

**v3.2（本轮）三处改进**：

- **成语检索**：不再"先选模式再输入"，声调 / 拼音 / 单字**三组 12 格同屏**，想填哪组填哪组，
  三组内容同时参与检索；结果按**列对齐**（上：声调小标签 → 中：拼音 → 下：成语），
  命中的位次整列标绿；手机出结果后条件区**自动折叠成一行摘要**（可展开继续改），按键照留。
- **诗词图片识别**：选完图先进**裁剪面板** —— 自动框出 6×5 字格，可拖动框体/四角自由调比例，
  点「确认裁切」才识别；结果区格子下方显示**裁好的那张图**，点一下可重新裁。
  裁切面板按图片宽高比自动调高度（横向字格图不再上下留黑边），三个键底边对齐。
- **名士检索**：滚轮选项重排 —— 朝代按**历史时间顺序**（"梦"压最末），
  爱好 / 社团 / 品阶按**拼音首字母 A~Z**。

**v3.1**：图片识别大改 —— 复杂图片识别率明显提高，6 张样例图**全部 30/30 填满、全部直接给出
诗句**（v3.0 是 5/6）。做法：等距点阵切格、逐格抗装饰取字、三趟识别投票、繁体归简，
以及"认错一个字就按题库对一遍"的补救。

**v3.0 新增**：

- **诗词检索 · 图片识别** —— 点「拍照识别 / 相册识别」把题目截图丢进去，
  自动找出 6×5 字格、认出 30 个汉字填进格子，并**直接开始检索**；
- **每页大标题右边的 ⓘ 信息** —— 软件版本、题库条数、三大模块用法、版权与隐私说明。

**用法看这个** → `docs\使用说明.md`

---

## 二、我要改题库 / 重新出包 → 双击一个脚本

1. 改这三份 Excel（路径不要动）：

   | 文件 | 位置 |
   | --- | --- |
   | 成语检索.xlsx | `data/\成语检索.xlsx` |
   | 诗词检索.xlsx | `data/\诗词检索.xlsx` |
   | 名士检索.xlsx | `data/\名士检索.xlsx` |

2. 双击 **`android\一键重新打包apk.bat`**（会自动：读 Excel → 生成内嵌数据 → 编译 → 签名 → 复制到 `dist\`）
3. 等 40 秒～2 分钟，新的 `dist\fhlSearch.apk` 就好了（按版本号归档时另存为 `dist\fhlSearch_v3.x.apk`）。

---

## 三、目录里都有什么

```

├─ dist\fhlSearch_v3.2.apk    ← 交付的安装包（按版本号归档）
├─ dist\fhlSearch.apk          ← 最近一次打包的输出（不入库，见 .gitignore）
├─ 图标\                       ← 应用图标的 PNG 导出（1024/512/256/192、圆形、自适应图层、单色）
├─ android\                    ← 全部源码工程
│   ├─ 一键重新打包apk.bat      ← 改完题库双击这个
│   ├─ keystore\ + keystore.properties  ← 签名密钥（勿外传；已在 .gitignore 中，不进版本库）
│   └─ app\src\main\
│       ├─ java\...\           ← Kotlin 源码
│       │   ├─ logic\          ← 检索逻辑（纯函数，好测）
│       │   ├─ ocr\            ← **v3.0：图片识别**（PoemOcr 取字流水线 + ML Kit 封装 + 繁简表）
│       │   ├─ widget\         ← **v3.2：裁剪面板** CropView（拖动框体/四角，自由比例）
│       │   ├─ ui\             ← 三个模块的界面 + ui\sheet\ 居中弹窗（含信息面板 / 识别等待）
│       │   ├─ widget\         ← 6×5 字格、滚轮选择器等自绘控件
│       │   └─ util\           ← 拼音标调、图片加载（降采样 + EXIF 摆正）
│       ├─ res\                ← 布局、文案、配色（layout\ 手机版，layout-sw600dp\ 平板版）
│       └─ assets\tiku_*.json  ← 内嵌题库（由 tools\build_tiku.py 从 Excel 生成）
├─ docs\                       ← 文档
│   ├─ 使用说明.md              ← 给你看的用法说明
│   ├─ 需求梳理_Android.md       ← 需求与逐轮改动记录（含每轮验收结果）
│   ├─ 界面文案与配色规范.md      ← 所有界面文字与色值的唯一出处
│   ├─ Android构建环境验证.md     ← 工具链踩坑记录
│   ├─ 现状核查与交接.md          ← 接手时的现状核查
│   ├─ icons\                  ← 图标方案对比与预览
│   └─ shots\                  ← 手机/平板/Android 10 的全流程截图
└─ tools\                      ← 数据管道、验证与回归脚本
    ├─ build_tiku.py           ← Excel → assets JSON
    ├─ reference_logic.py      ← 检索语义的 Python 基准实现（--selftest 全通过）
    ├─ drive_app.py            ← 自动走一遍全流程并抓图（可指定设备与 apk）
    ├─ validate_res.py         ← 资源/XML/引用静态校验
    ├─ gen_app_icon.py         ← 生成各密度图标
    ├─ export_app_icon.py      ← 导出图标 PNG 到 图标\
    └─ test_*.py / audit_*.py  ← 回归脚本（见下）
```

---

## 四、我要改代码 → 怎么构建

```powershell
# 构建（本机 JDK 25 实测可用；工程内也带了一份 JDK 21 在 _spike\jdk21）
$env:JAVA_HOME='C:\Program Files\Java\jdk-25'
cd 项目根目录
.\gradlew.bat :app:testDebugUnitTest --console=plain   # 单元测试（20 项）
.\gradlew.bat :app:assembleDebug      --console=plain   # debug 包
.\gradlew.bat :app:assembleRelease    --console=plain   # 正式包（自动签名）
```

装机与自动化验证：

```powershell
$env:PYTHONIOENCODING='utf-8'
# 走一遍全流程并抓图（模拟器上要先装好 app；脚本会自己装 debug 包）
python tools\drive_app.py emulator-5554 phone
# 想验证正式包：先设 $env:FHL_APK=<仓库根>\dist\fhlSearch_v3.2.apk
```

> ⚠️ 装机坑：设备上如果装的是 **release 签名**包，直接 `adb install -r` debug 包会报
> `INSTALL_FAILED_UPDATE_INCOMPATIBLE`，必须先 `adb uninstall`。

---

## 五、回归脚本一览（tools\）

| 脚本 | 干什么 | 用法 |
| --- | --- | --- |
| `validate_res.py` | 资源/XML/引用静态校验（当前 **749 处引用**全通过） | `python tools\validate_res.py` |
| `reference_logic.py --selftest` | 三大模块检索语义的基准自测 | `python tools\reference_logic.py --selftest` |
| `drive_app.py` | 全流程自动走一遍 + 抓图 + 崩溃检查 | `python tools\drive_app.py <设备> phone\|tablet\|api29` |
| `test_shici_focus.py` | 字格**选中框与输入焦点是否同步**（9 项） | `python tools\test_shici_focus.py <设备>` |
| `test_ms_dialogs.py` | 名士三个窗口**是否屏幕居中** | `python tools\test_ms_dialogs.py <设备> [标签]` |
| `test_ms_search_btn.py` | 名士**检索键显隐** 10 个状态 | `python tools\test_ms_search_btn.py <设备>` |
| `test_cy_search_btn.py` | 成语**三组同屏 / 折叠展开 / 逐字对齐 / 内容保留**（14 项，手机含折叠、平板只查常显） | `python tools\test_cy_search_btn.py <设备>` |
| `test_cy_second_search.py` | 成语**二次检索 / 清空当前 / 清空所有** 的层级与标注 | `python tools\test_cy_second_search.py <设备>` |
| `test_ms_options_order.py` | 名士滚轮**选项顺序**（朝代时间序、其余拼音序，逐项比到末项） | `python tools\test_ms_options_order.py <设备>` |
| `test_ocr.py` | **图片识别**：6 张样例图逐张识别 + 与 Windows 端对照 + 是否直接出诗句 | `python tools\test_ocr.py <设备> [标签]` |
| `test_ocr_gallery.py` | 图片识别的**系统通道**：相册选择器 / 相机能否拉起并回到 App | `python tools\test_ocr_gallery.py <设备> [标签]` |
| `test_info.py` | 三个模块的**信息面板**（弹出 / 居中 / 版本 / 正文 / 关闭） | `python tools\test_info.py <设备> [标签]` |
| `test_font_scale.py` | **2 倍系统字号**压力测试 | `python tools\test_font_scale.py 2.0` |
| `measure_layout.py` | 量关键控件的真实坐标（改布局时用） | `python tools\measure_layout.py <设备>` |
| `audit_pinyin.py` | 审计拼音标调在**全题库**上的表现、题库完整性 | `python tools\audit_pinyin.py` |
| `gen_app_icon.py` / `export_app_icon.py` | 生成/导出图标 | `python tools\export_app_icon.py` |
| `gen_t2s.py` | 生成**繁→简小表** `ocr/T2S.kt`（改了题库才需要重跑） | `python tools\gen_t2s.py` |
| `ocr_probe.py` | 图片识别**只算几何**：面板/切格/点阵/每格墨迹（不装机、秒出） | `python tools\ocr_probe.py <图片>` |
| `ocr_one.py` | 图片识别**单张排查**：真机跑一张 + 打全过程日志 + 拉回拼板 | `python tools\ocr_one.py <设备> <图片> --dump` |
| `montage_cell.py` | 看拼板里某一格**送进 ML Kit 的实际图形**（ASCII） | `python tools\montage_cell.py <拼板.png> 7,14` |

> 图片识别出问题时的排查顺序见 [`docs/图片识别调试.md`](docs/图片识别调试.md)：
> 先分清"格子切歪 / 取字失败 / 字认错"三类，再对症调参。

---

## 六、当前状态

| 项 | 结果 |
| --- | --- |
| 单元测试 | **25 项全绿**（`SearchLogicTest` 19 + `PinyinToneTest` 6） |
| 资源校验 | **749 处引用全通过** |
| 实机验证 | **Android 10（API 29）** 手机 ／ **Android 15（API 37）** 手机 ／ 平板 —— 三个模块全流程 + 全部回归脚本均通过、无崩溃 |
| 安装包 | `minSdk 29` / `targetSdk 37` / **版本 3.2** / 已签名 / 44.3 MB（arm64-v8a + armeabi-v7a + x86_64）；**一个权限都没申请**（拍照走系统相机 + FileProvider，选图走系统选择器），**不联网** |
| 题库 | 成语 319 条 · 诗词 282 条 · 名士 115 位（合计 135.3 KB，已内嵌） |
| 图片识别（v3.2） | 6 张样例图：**全部 30/30 填满、6 张都直接给出诗句**（落日故人情 / 气蒸云梦泽 / 依楼似月悬 / 别有千金笑 / 浮云游子意 ×2），其中 2 张靠"按题库补 1 个字"；与 Windows 端逐格一致率 66~100%。新增裁切面板后**识别结果不变**（自动框选框住的就是原来整图定位的那块） |
| 信息面板（v3.2） | 三个模块的 ⓘ 都能弹出、屏幕居中、显示版本 3.2 与用法正文、可滚动、可关闭 |
| 成语三组同屏（v3.2） | 手机 1080×2400 / 平板 1600×2560 / API29 1080×1920 三台设备全通过：三组 12 格常显、出结果折叠成摘要（平板双栏不折叠）、展开可继续改、框里内容全程保留、结果四列逐字对齐 |
| 裁切面板（v3.2 打磨） | 三键同一行、底边对齐（手机 y=2064~2190 等高）；面板高度按图片比例算：平板画布 792×1972 → **792×620**、手机 931×1663 → **931×729**，均与图片比例一致 |
| 名士选项排序（v3.2） | 三台设备逐项核对：朝代 15 项「先秦 → … → 清 → 梦」、爱好 / 社团 / 品阶均按首字母 A~Z |

> 逐轮改动与每轮的验收数据见 `docs\需求梳理_Android.md`（第一 ~ 二十五节）。
