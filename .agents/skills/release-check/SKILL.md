---
name: release-check
description: HentaiPark 发布前的检查清单（应用 APK 或官方插件）。在用户准备发版、打 tag、生成发布说明，或问“可以发布了吗”时使用。只检查和报告，不提交、不推送、不发布。
---

# 发布前检查

这个技能只做检查和整理，**不提交、不推送、不打 tag、不上传**。这些动作必须由用户明确要求后单独执行。

## 1. 工作区

- `git status`：列出将要发布的改动；确认 `/test/` 仍在 `.gitignore` 中，`test/` 下没有被跟踪的文件（`git ls-files test` 应为空）。
- 不要提交与本次发布无关的本地修改（例如 `windows/flutter/generated_plugin_registrant.h` 这类机器相关文件）。
- 本地提交不得把 Codex 作为联合提交人。

## 2. 自动检查

```powershell
.\tools\check.ps1
```

必须全部通过：八语言文案、样式令牌、`flutter analyze`、`dart format`、官方插件离线校验。

## 3. 插件

- 每个改动过的插件：脚本 `version` 与 `assets/sources/index.json` 一致，且比上次发布更高（补丁位 +1 即可）。用 `git diff <上次发布> -- assets/sources` 找出改动过的插件。
- 每个改动过的插件都用 `verify-source` 技能做过真实请求验证，结果写进给用户的检查报告，不写进发布正文。
- 协议有变化时 `docs/SOURCE_API.md` 已更新；新增站点已加入 `README.md` 的站点表。

## 4. 应用

- 版本号只在用户要求时修改；核对 `pubspec.yaml` 的 versionName / versionCode 递增、包名不变。
- 正式构建需要 `android/key.properties` 与正式证书：`flutter build apk --release --split-per-abi`。
- 在真机或模拟器上覆盖安装旧版本，确认书库、进度、Cookie 登录、下载、备份恢复都还在（旧数据完整可读）。
- 截图有变化时更新 `docs/screenshots/` 并同步八种语言的 README。

## 5. 发布说明

正文就是应用内更新对话框显示的内容，严格按 `docs/DEVELOPMENT.md` 的“发布说明”格式起草：

- 只有 `## 中文` 与 `## English` 两节，内容一一对应；小节按“新功能、改进、修复、插件更新、注意事项”（英文 New、Improvements、Fixes、Plugin updates、Notes）的顺序，空小节省略；条目为单行 `- ` 列表，不用表格、链接、行内代码、粗体和分隔线。
- 标题为 `HentaiPark vX.Y.Z`。
- 只写用户能感知的变化与必须由用户执行的操作；“插件更新”列出站点名与新版本。不写实现细节、测试或验证数量、构建号、签名、APK 架构选择和泛泛提示。
- 检查结果和未验证的部分写进给用户的检查报告，不写进发布正文。
