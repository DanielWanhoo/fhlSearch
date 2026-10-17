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

## 三、发一个 Release，把安装包挂上去（✅ v1.0.0 已发布）

Release 页面：<https://github.com/DanielWanhoo/fhlSearch/releases/tag/v1.0.0>

三个附件均已上传（非草稿），直链可直接分发：

| 附件 | 大小 | 下载地址 |
| --- | --- | --- |
| `fhlSearch.exe` | 0.18 MB | <https://github.com/DanielWanhoo/fhlSearch/releases/download/v1.0.0/fhlSearch.exe> |
| `fhlSearch.apk` | 12.03 MB | <https://github.com/DanielWanhoo/fhlSearch/releases/download/v1.0.0/fhlSearch.apk> |
| `fhlSearch.hap`（**未签名**，需侧载） | 1.02 MB | <https://github.com/DanielWanhoo/fhlSearch/releases/download/v1.0.0/fhlSearch.hap> |

仓库里同样保留了这三份产物（`Windows/dist/`、`Android/dist/`、`Harmony/dist/`），两处一致。

### 以后发新版本

1. 先改 `Android/CHANGELOG.md`，加上新版本一节
2. 提交并打标签：`git tag -a v1.0.1 -m "..."` → `git push origin v1.0.1`
3. 网页：仓库右侧 **Releases** → **Draft a new release** → 选刚推的标签 → 标题与说明 → 三个产物拖进 **Attach binaries** → **Publish release**

> **附件上传的网络坑**：GitHub 的附件必须传到 `uploads.github.com`，而本机 SteamTools（Watt Toolkit）
> 只劫持了 `api.github.com`（解析到 `127.0.0.1`），`uploads.github.com` 走直连真实 IP，
> 在部分网络下会出现 `SSL: UNEXPECTED_EOF_WHILE_READING` 握手被断。属链路抖动，
> **原样重试几次即可**，不必改配置；网页拖拽上传同样可用。

> **关于体积**：`Android/dist/fhlSearch.apk` 约 12 MB。GitHub 单文件硬上限 100 MB
> （超过 50 MB 会告警），所以放仓库里没问题；但如果以后 apk 涨到几十 MB，
> 建议从版本库移除、只挂在 Release 附件里。

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

---

## 六、目录速查

```
fhlSearch_github/
├── README.md            仓库首页：平台表 + 下载表 + 三端截图
├── LICENSE              MIT（根目录这份便于 GitHub 自动识别协议）
├── .gitignore  .gitattributes
├── 发布到GitHub.md       本文件（维护者备忘）
│
├── Windows/             Windows 版（自带 README / LICENSE / NOTICE / CHANGELOG）
│   ├── dist/fhlSearch.exe
│   ├── data/  docs/  src/  tools/
│   └── 重新生成题库.bat
│
├── Android/             Android 版（自带 README / LICENSE / NOTICE / CHANGELOG）
│   ├── dist/fhlSearch.apk
│   ├── app/              安卓源码（Gradle 工程）
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
