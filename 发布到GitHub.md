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

> ⚠️ **HarmonyOS 版发的是未签名 hap**：在 `Harmony/dist/fhlSearch.hap`。
> 华为装包必须签名，所以它不是"点开即装"，用户得用**小白调试助手 / DevEco Studio** 之类的工具侧载，
> 并自备华为开发者账号（官网自行认证）+ 设备开开发者模式 —— 具体说明写在各 README 里，别再改回"不放安装包"。
> 另外：这个 hap 是用 `H:\projects\CulturalSearch` 的构建产物复制的（同 bundleName / 同版本），
> 以后重新出包记得同步替换。

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
git config http.sslCAInfo "C:/Users/wtswg/.workbuddy/system-ca-bundle.pem"
```

注意：`http.schannelCheckRevoke=false` 对本机代理**无效**，别在这上面浪费时间。
若换网络后仍报证书错误，把上面 `sslCAInfo` 指向包含系统根与 Mozilla 根证书的合并 pem 即可。

---

## 三、发一个 Release，把安装包挂上去

### ✅ 当前要发的版本：v3.1.0

| 附件 | 大小 | 取自 |
| --- | --- | --- |
| `fhlSearch.exe` | 0.30 MB | `Windows/dist/fhlSearch.exe` |
| `fhlSearch.apk` | 44.3 MB | `Android/dist/fhlSearch.apk` |
| `fhlSearch.hap`（**未签名**，需侧载） | 1.02 MB | `Harmony/dist/fhlSearch.hap`（鸿蒙版仍是 2.0.0，暂无图片识别） |

三端版本：**Windows 3.1.0 · Android 3.1 · HarmonyOS 2.0.0**。

**v3.1 更新说明（可直接粘到 Release 描述）**：

```
## 诗词检索新增「从图片识别」

把题目截图丢进去，自动找出 6×5 字格、认出 30 个汉字并直接检索 —— 不用一个个敲字。

- Windows：使用系统自带 OCR，需要 Windows 10 (1809) 及以上 + 简体中文 OCR 组件
- Android：使用 ML Kit 文字识别
- 低版本系统上该按钮提示不可用，其余功能不受影响

## 识别率优化（v3.1）

参考一批真实截图做回归，能直接命中诗句的图片从 3/6 提升到 5/6，平均识别字数 21.2→28.2（满分 30）。

## 其他

- 使用说明补充「识别不准时怎么办」「截图建议」两节，并内置标准样例截图
  （Windows 版「使用说明」里点「查看截图样例」即可看到）
- 文档补充 Windows on Arm（ARM64）可行性说明：Win11 Arm 可运行，Win10 Arm 不保证
- Windows 端 215 条检索用例与独立 Python 参考实现交叉对拍，结果完全一致
```

发版步骤：

1. 先按第四节把改动提交、推上去
2. `git tag -a v3.1.0 -m "Windows 3.1.0 / Android 3.1 / HarmonyOS 2.0.0"` → `git push origin v3.1.0`
3. 网页：仓库右侧 **Releases** → **Draft a new release** → 选刚推的 `v3.1.0` 标签 →
   标题 `v3.1.0`、描述粘上面那段 → 三个产物拖进 **Attach binaries** → **Publish release**
4. 发完把本文件第三节顶部的版本号改成新的（留作下次对照）

### 历史版本：v1.0.0（已发布，备查）

Release 页面：<https://github.com/DanielWanhoo/fhlSearch/releases/tag/v1.0.0>

| 附件 | 大小 | 下载地址 |
| --- | --- | --- |
| `fhlSearch.exe` | 0.18 MB | <https://github.com/DanielWanhoo/fhlSearch/releases/download/v1.0.0/fhlSearch.exe> |
| `fhlSearch.apk` | 12.03 MB | <https://github.com/DanielWanhoo/fhlSearch/releases/download/v1.0.0/fhlSearch.apk> |
| `fhlSearch.hap`（**未签名**，需侧载） | 1.02 MB | <https://github.com/DanielWanhoo/fhlSearch/releases/download/v1.0.0/fhlSearch.hap> |

仓库里同样保留了三份产物（`Windows/dist/`、`Android/dist/`、`Harmony/dist/`），两处一致。

> **附件上传的网络坑**：GitHub 的附件必须传到 `uploads.github.com`，而本机 SteamTools（Watt Toolkit）
> 只劫持了 `api.github.com`（解析到 `127.0.0.1`），`uploads.github.com` 走直连真实 IP，
> 在部分网络下会出现 `SSL: UNEXPECTED_EOF_WHILE_READING` 握手被断。属链路抖动，
> **原样重试几次即可**，不必改配置；网页拖拽上传同样可用。

> **关于体积**：`Android/dist/fhlSearch.apk` 现在约 **44 MB**（v3 引入 ML Kit 文字识别后从 12 MB 涨上来）。
> GitHub 单文件硬上限 100 MB，超过 **50 MB 会告警但不会拒收**。
> 所以目前放仓库里还能用；**如果继续涨过 50 MB，建议把 apk 从版本库里移除、只挂在 Release 附件里**
> （`git rm --cached Android/dist/fhlSearch.apk` 并写进 `.gitignore`），否则每次 clone 都要拖 44 MB。
>
> 顺便：Windows 端 exe 也从 0.18 MB 涨到 **0.30 MB**（内嵌了 97 KB 的截图样例 + OCR 代码），体积无压力。

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
dotnet build -c Release

:: Android —— 改完 Kotlin 源码后
cd H:\projects\fhlSearch_github\Android
一键重新打包apk.bat

:: Windows —— 改了题库 Excel 后重新生成内嵌题库
cd H:\projects\fhlSearch_github\Windows
重新生成题库.bat
```

HarmonyOS 版用 DevEco Studio 打开 `Harmony/`，或按 `Harmony/README.md` 里的命令行方式出包。

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
- [x] 打开仓库首页，确认**三端** README 的图片都能正常显示（本地 20 处图片引用全部可解析）
- [ ] 如果要改协议，记得同步 `LICENSE`（根目录）与
      `Windows/LICENSE`、`Android/LICENSE`、`Harmony/LICENSE` ——
      四份的 MIT 正文必须一致，各端那份末尾的「覆盖哪些目录」说明要跟本端目录结构对得上
- [x] `Harmony/LICENSE` 末尾的说明指的是 `entry/`、`AppScope/`、`scripts/`、`docs/`，
      **不要**出现 Android 的 `app/`、`tools/`、`dist/fhlSearch.apk`（曾经抄错过一次）

### v3 专项检查（本次新增）

- [x] Windows 端 `dist/fhlSearch.exe` 版本号 = **3.1.0.0**（右键 → 属性 → 详细信息可看）
- [x] Windows 端仓库副本能独立构建：拿 `Windows/` 单独拷到空目录跑
      `dotnet build src\FhlSearch\FhlSearch.csproj -c Release` → 0 错误，
      产物跑 `--selftest` 与参考实现对拍 **215/215 一致**（已验证）
- [x] v3 新文件都在库：`Windows/src/FhlSearch/Ocr/PoemOcr.cs`、
      `Windows/src/FhlSearch/Resources/ocr-sample.jpg`、
      `Windows/docs/screenshots/07-ocr-sample.jpg`
- [x] `Windows/docs/screenshots/07-ocr-sample.jpg` 与 `Windows/README.md`、`Windows/docs/使用说明.md`
      里的图片引用路径对得上（README 用 `docs/screenshots/`，使用说明用 `screenshots/`）
- [x] 三端 README 的「系统要求」已按 v3 更新：Windows 图片识别需 Win10 1809+，
      鸿蒙版暂无图片识别
- [ ] **提交历史待整理（可选）**：`6bda678` 这个提交标题写的是「Android v3.0」，
      但里面同时包含**全部 Windows v3.0/v3.1 改动**（`Windows/` 下 16 个文件 + exe）。
      内容没错，只是提交信息读起来像"只动了安卓"。若在意历史整洁，可在推送前重排：

      ```bash
      cd H:\projects\fhlSearch_github
      git reset --soft 74d02d8            # 工作区不动，HEAD 回到上次已推送的提交
      git add Windows                      # 先提交 Windows v3
      git commit -m "Windows v3.0/v3.1：诗词图片识别 + 识别率优化 + Arm 说明"
      git add Android                      # 再提交 Android v3
      git commit -m "Android v3.0/v3.1：ML Kit 图片识别 + 识别率优化"
      git add -A                           # 剩下的（根 README / 本文件）
      git commit -m "文档：补充 v3.1 发布说明"
      ```

      > 这 2 个提交**还没推送**，所以重排是安全的；万一操作失误可以用 `git reflog` 找回。

---

## 六、目录速查

```
fhlSearch_github/
├── README.md            仓库首页：平台表 + 下载表 + 三端截图 + v3 图片识别说明
├── LICENSE              MIT（根目录这份便于 GitHub 自动识别协议）
├── .gitignore  .gitattributes
├── 发布到GitHub.md       本文件（维护者备忘）
│
├── Windows/             Windows 版（自带 README / LICENSE / NOTICE / CHANGELOG）
│   ├── dist/fhlSearch.exe          0.30 MB
│   ├── data/  docs/  src/  tools/
│   ├── src/FhlSearch/Ocr/          ★ v3 新增：图片识别引擎
│   ├── src/FhlSearch/Resources/ocr-sample.jpg  ★ v3 新增：内嵌样例图（「查看截图样例」用）
│   ├── docs/screenshots/07-ocr-sample.jpg      ★ v3 新增：文档用样例图
│   └── 重新生成题库.bat
│
├── Android/             Android 版（自带 README / LICENSE / NOTICE / CHANGELOG）
│   ├── dist/fhlSearch.apk          44 MB
│   ├── app/              安卓源码（Gradle 工程）
│   │   └── src/main/java/.../ocr/  ★ v3 新增：OcrEngine / PoemOcr / T2S
│   ├── data/  tools/
│   ├── docs/             公开文档
│   │   └── dev/          开发过程存档（构建环境验证、现状核查与交接）
│   └── 一键重新打包apk.bat
│
└── Harmony/             HarmonyOS 版（自带 README / LICENSE / NOTICE / CHANGELOG）
    ├── dist/fhlSearch.hap  未签名安装包（需侧载）
    ├── AppScope/  entry/ 源码与资源
    ├── data/  docs/  scripts/
    ├── dev-logs/         开发日志（★已被 .gitignore 排除，不会上传）
    └── CLAUDE.md         AI 协作说明（★已被 .gitignore 排除，不会上传）
```
