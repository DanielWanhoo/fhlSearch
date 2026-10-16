# 维护者备忘：把这个仓库发布到 GitHub

本仓库 = `H:\projects\fhlSearch_github`，里面按平台分了两个目录：

| 目录 | 内容 |
| --- | --- |
| `Windows/` | C# / WinForms 桌面版，单个 exe |
| `Android/` | Kotlin 安卓版，单个 apk |

两个目录**各自是一个完整工程**：`Windows/` 用 `dotnet build` 编译，`Android/` 用 `gradlew` 编译，
互不依赖。仓库已经 `git init` 过并完成了首次提交，只差接上 GitHub 远端。

---

## 一、在 GitHub 上建一个空仓库

1. 浏览器打开 <https://github.com/new>
2. **Repository name** 填一个名字，例如 `fhlSearch`
3. 选 **Public**（公开）或 **Private**（私有）都行
4. ⚠️ 下面的 `Add a README file`、`Add .gitignore`、`Choose a license`
   **一个都不要勾** —— 本地这些文件都已经有了，勾了推送时会冲突
5. 点 **Create repository**

---

## 二、把本地代码推上去

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

---

## 三、（可选）发一个 Release，把安装包挂上去

仓库里已经带了编译好的 `Android/dist/忘川检索.apk` 和 `Windows/dist/忘川检索.exe`，
直接下载就能用。如果想在右侧的 **Releases** 里也放一份：

1. 仓库页面右侧 → **Releases** → **Create a new release**
2. **Choose a tag** 填 `v1.0.0` → 点 *Create new tag*
3. 标题填 `v1.0.0`，说明可以复制 `Android/CHANGELOG.md` 里的内容
4. 把两个产物拖进 **Attach binaries** 框里
5. 点 **Publish release**

---

## 四、以后改了代码怎么更新

```bash
cd H:\projects\fhlSearch_github
git add -A
git commit -m "说明这次改了什么"
git push
```

安卓版改完代码后，重新出包：

```bat
cd H:\projects\fhlSearch_github\Android
一键重新打包apk.bat
```

---

## 五、发布前检查清单

- [ ] `Android/NOTICE.md` 和 `Windows/NOTICE.md` 里的邮箱占位符
      （`[[请填写你的邮箱]]`）换成你自己的，或者删掉那一行、只保留 Issue 渠道
- [ ] 仓库里**没有**签名文件。检查一下：

  ```bash
  git ls-files | findstr /i "keystore jks local.properties"
  ```

  正常应该只看到 `Android/keystore.properties.example`（那只是示例，不含口令）
- [ ] 打开仓库首页，确认两个平台的 README 图片都能正常显示
- [ ] 如果以后要改协议，记得同步 `Windows/LICENSE` 与 `Android/LICENSE`

---

## 六、目录速查

```
fhlSearch_github/
├── README.md            仓库首页：平台表 + 下载表
├── .gitignore
├── Windows/             Windows 版（自带 README / LICENSE / NOTICE / CHANGELOG）
│   ├── dist/忘川检索.exe
│   ├── data/  docs/  src/  tools/
│   └── 重新生成题库.bat
└── Android/             Android 版（自带 README / LICENSE / NOTICE / CHANGELOG）
    ├── dist/忘川检索.apk
    ├── app/              安卓源码（Gradle 工程）
    ├── data/  docs/  tools/
    └── 一键重新打包apk.bat
```
