# 维护者备忘：把这个仓库发布到 GitHub

本仓库 = `H:\projects\fhlSearch_github`，按平台分三个目录，**各自是一个完整工程**，
互不依赖，可以只编译其中任意一个：

| 目录 | 内容 | 编译器 | 产物 |
| --- | --- | --- | --- |
| `Windows/` | C# / WinForms 桌面版 | `dotnet build` | 单个 exe，绿色免安装 |
| `Android/` | Kotlin 安卓版 | `gradlew` | 单个已签名 apk |
| `Harmony/` | ArkTS + ArkUI 鸿蒙版 | DevEco Studio / `hvigorw` | hap（**未签名**，需侧载） |

仓库**已经发布**：<https://github.com/DanielWanhoo/fhlSearch>（Public），
本地 `origin` 指向 `https://github.com/DanielWanhoo/fhlSearch.git`，`main` 已与远端同步。
下面第一节、第二节是当初建库与首推的步骤，留作备查；日常更新直接跳到第四节。

> ⚠️ **HarmonyOS 版发的是未签名 hap**：当前在 `Harmony/dist/fhlSearch_v3.2.3.hap`。
> 华为装包必须签名，所以它不是"点开即装"，用户得用**小白调试助手 / DevEco Studio** 之类的工具侧载，
> 并自备华为开发者账号（官网自行认证）+ 设备开开发者模式 —— 具体说明写在各 README 里，别再改回"不放安装包"。
> 这个 hap 是从 `H:\projects\CulturalSearch` 出包后复制的（同 bundleName，版本 **3.2.3**）。
> 每次重新出包记得按版本号另存一份并同步替换。

### 关于 `dist/` 的命名约定（v3.2 起）

- **带版本号的归档文件入库**：`fhlSearch_v3.1.0.exe`、`fhlSearch_v3.2.apk`、`fhlSearch_v3.2.3.hap`，
  旧版（`fhlSearch_v3.1.apk`、`fhlSearch_v3.0.0.hap`）一并留着，方便回退对照。
- **不带版本号的是本机输出，不入库**：`Windows/dist/fhlSearch.exe`、`Android/dist/fhlSearch.apk`、
  `Harmony/dist/fhlSearch.hap` —— 这三个名字已写进各端 `.gitignore`，重新构建 / 打包时会被覆盖也不影响仓库。
- 各端 README 里的下载链接指向**带版本号的那个**。发新版时记得把 README 里的文件名一起改掉。

---

## 一、在 GitHub 上建一个空仓库（✅ 已完成，备查）

1. 浏览器打开 <https://github.com/new>
2. **Repository name** 填一个名字，例如 `fhlSearch`
3. 选 **Public**（公开）或 **Private**（私有）都行
4. ⚠️ 下面的 `Add a README file`、`Add .gitignore`、`Choose a license`
   **一个都不要勾** —— 本地这些文件都已经有了，勾了推送时会冲突
5. 点 **Create repository**

---

## 二、把本地代码推上去（✅ 已完成，备查）

在 `H:\projects\fhlSearch_github` 目录里打开 PowerShell（或 Git Bash），依次执行
（把 `<你的用户名>` 和仓库名换成你自己的）：

```bash
git remote add origin https://github.com/<你的用户名>/fhlSearch.git
git push -u origin main
```

第一次推送会弹出 GitHub 登录窗口：

- 用**浏览器授权**（Git Credential Manager）最省事，点一下就行；
- 如果开了**两步验证**、又选了用密码登录，密码处要填 **Personal Access Token**
  （GitHub 网页 → 右上角头像 → Settings → Developer settings → Personal access tokens），
  不是你的登录密码。

推送成功后再刷新仓库页面，就能看到 README 了。

> 想改用 SSH：先把 `https://github.com/...` 换成 `git@github.com:...`，
> 并把自己的 SSH 公钥加到 GitHub（Settings → SSH and GPG keys）。

### 本机首次推送踩过的坑（新机器复现时照抄）

本机 HTTPS 经本地代理，且 SteamTools 对部分域名做证书替换，git 默认的 schannel 后端会报
`CRYPT_E_NO_REVOCATION_CHECK (0x80092012)`，推送直接失败。解决办法是**只在本仓库**改用 openssl 后端
并指定完整 CA 包（不要用 `http.sslVerify=false` 关掉校验）：

```bash
cd H:\projects\fhlSearch_github
git config http.sslBackend openssl
git config http.sslCAInfo "C:/Users/wtswg/.workbuddy/system-ca-bundle-combined.pem"
```

**关于那个合并 CA 包**：原来指向的 `system-ca-bundle.pem`（39 张证书）到 v3 推送时已不够用，
会报 `unable to get local issuer certificate (20)`。改成"Windows 证书存储 + 原 Mozilla 包"的合并版
（220 张、约 353 KB）后正常。重建命令（**留着备用，换机器/证书过期时重跑**）：

```powershell
$sb = New-Object System.Text.StringBuilder
foreach ($store in 'Cert:\LocalMachine\Root','Cert:\LocalMachine\CA','Cert:\CurrentUser\Root','Cert:\CurrentUser\CA') {
    foreach ($c in Get-ChildItem $store) {
        [void]$sb.AppendLine('-----BEGIN CERTIFICATE-----')
        [void]$sb.AppendLine([Convert]::ToBase64String($c.RawData,'InsertLineBreaks'))
        [void]$sb.AppendLine('-----END CERTIFICATE-----')
    }
}
$combined = $sb.ToString() + "`n" + (Get-Content 'C:\Users\wtswg\.workbuddy\system-ca-bundle.pem' -Raw)
[System.IO.File]::WriteAllText('C:\Users\wtswg\.workbuddy\system-ca-bundle-combined.pem',
    $combined, (New-Object System.Text.UTF8Encoding($false)))
```

注意：`http.schannelCheckRevoke=false` 对本机代理**无效**，别在这上面浪费时间。

另外这台机器**链路抖动很厉害**：`Recv failure: Connection was reset`、`Could not connect to server`
会随机出现（和证书无关）。**原样重试 2~6 次通常就成功**，不必改任何配置 ——
上次推 `main` 试了 2 次、推 `v3.1.0` 标签试了 4 次才过。若重试仍失败，先 `git ls-remote --heads origin`
确认连通，再推。

---

## 三、发一个 Release，把安装包挂上去

### ✅ 当前要发的版本：v3.2.0

> **当前状态**：代码与附注标签 `v3.2.0` 已推到 `origin/main`。
> **剩下的只有网页上发 Release** —— 即下面「发版步骤」的第 3、4 步。

| 附件 | 大小 | 取自 |
| --- | --- | --- |
| `fhlSearch_v3.1.0.exe` | 0.30 MB | `Windows/dist/fhlSearch_v3.1.0.exe` |
| `fhlSearch_v3.2.apk` | 44.32 MB | `Android/dist/fhlSearch_v3.2.apk` |
| `fhlSearch_v3.2.3.hap`（**未签名**，需侧载） | 1.52 MB | `Harmony/dist/fhlSearch_v3.2.3.hap` |

三端版本：**Windows 3.1.0 · Android 3.2 · HarmonyOS 3.2.3**
（Windows 本轮无代码改动，沿用 3.1.0 的包）。

**v3.2 更新说明（可直接粘到 Release 描述）**：

```
## 成语检索：三组条件同屏

声调 / 拼音 / 单字不再"三选一" —— 三组各 4 个格子同屏，想填哪组填哪组，三组内容同时参与检索
（同一位置填了多组时需同时满足，整组留空表示这一组不限；拼音仍为模糊匹配）。

结果卡改为"一字一列"：上排声调小标签、中排拼音、下排汉字，整排靠左紧凑，
命中的位次整列标绿。手机上出结果后，输入区自动折叠成一行条件摘要
（如「第 1 位 声 4 · 第 2 位 拼 du」），点一下展开继续改，三个动作键全部保留；
平板双栏不折叠。

## 诗词识图：先裁后识

选图 / 拍照后先出裁剪框，自动框住图中的 6×5 字格；可拖动移动、拖角自由改比例，
点「确认裁切」后才真正识别。混着积分榜、按钮、聊天文字的截图，先裁掉再认能明显减少错字。
识别完成后，6×5 表格下方回显送去识别的那张图，方便核对有没有裁歪。
裁切面板高度改为按图片宽高比计算，横向字格图不再上下留大片黑边，三个键底边对齐。

## 名士检索

滚轮选项重排：朝代按历史时间顺序（先秦 → 秦 → 西楚 → … → 清 → 梦），
爱好 / 社团 / 品阶按拼音首字母 A~Z。HarmonyOS 端另把 5 个输入型条件
（职业 / 生逢 / 出身·身世 / 技能 / 其他描述）改为行内输入框，不再弹面板。

## 修正

HarmonyOS：`@Component struct` 里用 getter（`private get query()`）在真机上读到的是 `undefined`，
点「检索」会直接 TypeError 崩溃退出 —— 已改为普通方法 `buildQuery()`；同样写法的
`SplitDivider.isActive` 一并改掉（它不崩溃，但条件恒为假、静默失效）。

## 兼容性

不新增任何依赖，识别链路一行没改，v3.1 的识别率完全保留
（6 张样例图仍 30/30 填满、6/6 直接出诗句）。三端依旧完全离线、不申请多余权限。
```

发版步骤：

1. 先按第四节把改动提交、推上去
2. `git tag -a v3.2.0 -m "Windows 3.1.0 / Android 3.2 / HarmonyOS 3.2.3"` → `git push origin v3.2.0`
3. 网页：仓库右侧 **Releases** → **Draft a new release** → 选刚推的 `v3.2.0` 标签 →
   标题 `v3.2.0`、描述粘上面那段 → 三个产物拖进 **Attach binaries** → **Publish release**
4. 发完把本文件第三节顶部的版本号改成新的（留作下次对照）

### 历史版本：v3.1.0 / v1.0.0（备查）

`v3.1.0` 标签已推送（<https://github.com/DanielWanhoo/fhlSearch/releases/tag/v3.1.0>）。
若当时没在网页上发过 Release，可照上面第 3 步补一个，附件取：

| 附件 | 大小 | 取自 |
| --- | --- | --- |
| `fhlSearch.exe` | 0.30 MB | v3.1.0 当时的 exe（现仓库里的 `Windows/dist/fhlSearch_v3.1.0.exe` 同内容） |
| `fhlSearch.apk` | 44.28 MB | `Android/dist/fhlSearch_v3.1.apk` |
| `fhlSearch.hap`（未签名） | 1.38 MB | `Harmony/dist/fhlSearch_v3.0.0.hap` |

`v1.0.0`：<https://github.com/DanielWanhoo/fhlSearch/releases/tag/v1.0.0>

> **附件上传的网络坑**：GitHub 的附件必须传到 `uploads.github.com`，而本机 SteamTools（Watt Toolkit）
> 只劫持了 `api.github.com`（解析到 `127.0.0.1`），`uploads.github.com` 走直连真实 IP，
> 在部分网络下会出现 `SSL: UNEXPECTED_EOF_WHILE_READING` 握手被断。属链路抖动，
> **原样重试几次即可**，不必改配置；网页拖拽上传同样可用。

> **关于体积**：`Android/dist/fhlSearch_v3.2.apk` 约 **44.32 MB**（v3 引入 ML Kit 文字识别后从 12 MB 涨上来，
> 其中约 30 MB 是内嵌的中文识别模型）。GitHub 单文件硬上限 100 MB，超过 **50 MB 会告警但不会拒收**。
> 目前放仓库里还能用；**如果继续涨过 50 MB，建议把 apk 从版本库里移除、只挂在 Release 附件里**
> （`git rm --cached` 并写进 `.gitignore`），否则每次 clone 都要拖 44 MB。

---

## 四、以后改了代码怎么更新

```bash
cd H:\projects\fhlSearch_github
git add -A
git commit -m "说明这次改了什么"
git push
```

各端重新出包：

```bat
:: Windows —— 改完 C# 源码后
cd H:\projects\fhlSearch_github\Windows
dotnet build src\FhlSearch\FhlSearch.csproj -c Release
python tools\make_dist.py                 :: 产物落到 dist\fhlSearch.exe
copy dist\fhlSearch.exe dist\fhlSearch_v<新版本>.exe

:: Android —— 改完 Kotlin 源码后
cd H:\projects\fhlSearch_github\Android
一键重新打包apk.bat                        :: 产物落到 dist\fhlSearch.apk
copy dist\fhlSearch.apk dist\fhlSearch_v<新版本>.apk

:: Windows —— 改了题库 Excel 后重新生成内嵌题库
cd H:\projects\fhlSearch_github\Windows
重新生成题库.bat
```

HarmonyOS 版用 DevEco Studio 打开 `Harmony/`，或按 `Harmony/README.md` 里的命令行方式出包；
出包后把 `entry/build/default/outputs/default/entry-default-unsigned.hap` 复制成
`Harmony/dist/fhlSearch_v<新版本>.hap`。

> **别忘了**：发新版时把各端 README 里的下载链接（`dist/fhlSearch_v3.x.…`）一起改成新文件名。

---

## 五、发布前检查清单

- [x] 三份 `NOTICE.md`（`Windows/`、`Android/`、`Harmony/`）里的联系邮箱已填为 `wtswgf@163.com`
      （若以后不想公开邮箱，把那一行删掉、只保留 Issue 渠道即可）
- [x] 仓库里**没有**签名文件。检查命令：

  ```bash
  git ls-files | findstr /i "keystore jks local.properties p12 cer"
  ```

  正常应该只看到 `Android/keystore.properties.example`（那只是示例，不含口令）
- [x] **内部开发资料没有入库**：`Harmony/dev-logs/`（逐日日志、旧源码备份、开发截图）
      与 `Harmony/CLAUDE.md`（AI 协作说明）已在 `Harmony/.gitignore` 里排除，确认没有手滑 `git add -f`
- [x] 打开仓库首页，确认**三端** README 的图片都能正常显示（含根目录 `demo/` 下 5 张效果截图）
- [ ] 如果要改协议，记得同步 `LICENSE`（根目录）与
      `Windows/LICENSE`、`Android/LICENSE`、`Harmony/LICENSE` ——
      四份的 MIT 正文必须一致，各端那份末尾的「覆盖哪些目录」说明要跟本端目录结构对得上
- [x] `Harmony/LICENSE` 末尾的说明指的是 `entry/`、`AppScope/`、`scripts/`、`docs/`，
      **不要**出现 Android 的 `app/`、`tools/`、`dist/fhlSearch.apk`（曾经抄错过一次）

### v3.2 专项检查

- [x] 三端版本号与 README 一致：Windows `3.1.0`（csproj `<Version>`）、
      Android `3.2`（`versionCode 5`）、HarmonyOS `3.2.3`（`versionCode 3200300`）
- [x] `dist/` 里只剩**带版本号**的归档文件入库，不带版本号的三个名字已写进各端 `.gitignore`
- [x] 各端 README / 使用说明里的 dist 文件名已同步为带版本号的形式
- [x] 根目录 `demo/` 下 5 张效果截图入库，文件名 `Demo_<机型>_<系统>`，
      根 README 的「效果截图」一节按机型 / 系统标注
- [x] 根 README 已按要求简化：标题 → 适用题目 → 当前版本 → 下载（指向 Releases）→
      主要功能 → 各平台特性（表格）→ 效果截图 → 安装须知（三端 + 鸿蒙侧载）→ 开发工具与模型 → 许可

### v3 专项检查（保留备查）

- [x] Windows 端 `dist/fhlSearch_v3.1.0.exe` 版本号 = **3.1.0.0**（右键 → 属性 → 详细信息可看）
- [x] Windows 端仓库副本能独立构建：拿 `Windows/` 单独拷到空目录跑
      `dotnet build src\FhlSearch\FhlSearch.csproj -c Release` → 0 错误，
      产物跑 `--selftest` 与参考实现对拍 **215/215 一致**（已验证）
- [x] v3 新文件都在库：`Windows/src/FhlSearch/Ocr/PoemOcr.cs`、
      `Windows/src/FhlSearch/Resources/ocr-sample.jpg`、
      `Windows/docs/screenshots/07-ocr-sample.jpg`
- [x] 三端 README 的「系统要求」已按 v3 更新：Windows 图片识别需 Win10 1809+ + 简体中文 OCR 组件；
      Android 需 Android 10+（ML Kit）；鸿蒙版用系统 Core Vision Kit（API 24 / 6.1.1，本地识别、不联网）

---

## 六、目录速查

```
fhlSearch_github/
├── README.md            仓库首页：适用题目 + 版本 + 下载（指向 Releases）+ 主要功能 +
│                        各平台特性表 + 效果截图 + 安装须知 + 开发工具与模型 + 许可
├── LICENSE              MIT（根目录这份便于 GitHub 自动识别协议）
├── .gitignore  .gitattributes
├── 发布到GitHub.md       本文件（维护者备忘）
│
├── demo/                根 README 用的效果截图（Demo_<机型>_<系统>）
│
├── Windows/             Windows 版（自带 README / LICENSE / NOTICE / CHANGELOG）
│   ├── dist/fhlSearch_v3.1.0.exe  0.30 MB（带版本号，入库）
│   ├── data/  docs/  src/  tools/
│   ├── src/FhlSearch/Ocr/                     图片识别引擎
│   ├── src/FhlSearch/Resources/ocr-sample.jpg 内嵌样例图（「查看截图样例」用）
│   ├── docs/screenshots/07-ocr-sample.jpg     文档用样例图
│   └── 重新生成题库.bat
│
├── Android/             Android 版（自带 README / LICENSE / NOTICE / CHANGELOG）
│   ├── dist/fhlSearch_v3.2.apk    44.32 MB（带版本号，入库）
│   ├── dist/fhlSearch_v3.1.apk    44.28 MB（旧版归档）
│   ├── app/              安卓源码（Gradle 工程）
│   │   └── src/main/java/.../ocr/  OcrEngine / PoemOcr / T2S
│   ├── data/  tools/
│   ├── docs/             公开文档
│   │   └── dev/          开发过程存档（构建环境验证、现状核查与交接）
│   └── 一键重新打包apk.bat
│
└── Harmony/             HarmonyOS 版（自带 README / LICENSE / NOTICE / CHANGELOG）
    ├── dist/fhlSearch_v3.2.3.hap  1.52 MB（未签名，需侧载）
    ├── dist/fhlSearch_v3.0.0.hap  1.38 MB（旧版归档）
    ├── AppScope/  entry/ 源码与资源
    ├── data/  docs/  scripts/
    ├── dev-logs/         开发日志（★已被 .gitignore 排除，不会上传）
    └── CLAUDE.md         AI 协作说明（★已被 .gitignore 排除，不会上传）
```
