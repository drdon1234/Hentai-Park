# Windows 工程与开发说明

[开发说明入口](../DEVELOPMENT.md) · [Windows 设计准则](../design/WINDOWS.md) · [公共设计准则](../DESIGN.md) · [插件协议](../SOURCE_API.md)

## 环境与目录

Windows 原生客户端位于 `clients/windows`，采用 **.NET 10（C#）+ Windows App SDK（WinUI 3）** 单解决方案模块化架构，不修改根仓库 Flutter/Android 构建链。

- 工具链：.NET SDK 10.0+、Windows 10 SDK（10.0.19041.0+）、Node.js 22+（用于契约生成与资产同步）、Microsoft Edge WebView2 Evergreen Runtime。
- 唯一共享事实源：`assets/public-contract.json`、`assets/runtime/park_runtime.js`、`assets/sources/*.js`、`assets/i18n/*.json`、`assets/tag_translations/`、`assets/worldbook_terms/` 与根 `pubspec.yaml` 版本号。`clients/windows/assets/` 为构建期同步副本，已在 `.gitignore` 中忽略，不纳入版本控制。

| 目录 | 职责 |
| --- | --- |
| `clients/windows/scripts/` | 契约代码生成、共享资产同步（`sync-assets.mjs`）与八语言文案静态校验（`check-localizations.mjs`） |
| `clients/windows/locales/` | Windows 桌面补充界面文案（八语言同步，与根 `assets/i18n/` 叠加生效） |
| `clients/windows/src/Park.Core/` | 公共契约、领域模型、八语言国际化、12 领域 `AppSettings`、内容屏蔽匹配器、白名单 `Diagnostics` 与 `DesktopShutdown` |
| `clients/windows/src/Park.Library/` | 对齐 Android Schema v7 的 SQLite WAL 书库、串行写入队列、进度合并、换源迁移、三级并发下载协调器与 `.parkbak` 流式备份互通 |
| `clients/windows/src/Park.Engine/` | 公网 IP/TLS SNI 校验网络栈、按源分区 Cookie、密码学与图片 AES-CBC 解密、WebView2 多 Profile 隔离宿主、无感验证交互与 `127.0.0.1` 流式媒体代理 |
| `clients/windows/src/Park.App/` | WinUI 3 现代桌面界面（Mica Alt / Acrylic 暖调主题、沉浸标题栏、多标签与画中画、全品类浏览/阅读/播放/酒馆视图、Windows Hello 与防截屏桥接） |

## 构建与检查

在仓库根目录执行以下命令（PowerShell）：

```powershell
node 'clients/windows/scripts/sync-assets.mjs'
node 'clients/windows/scripts/check-localizations.mjs'
dotnet build 'clients/windows/src/Park.App/Park.App.csproj' -c Release
```

生成便携目录（Unpackaged 自包含部署，`WindowsPackageType=None`）：

```powershell
dotnet publish 'clients/windows/src/Park.App/Park.App.csproj' -c Release -r win-x64 -o 'clients/windows/publish/win-x64'
```

使用统一打包脚本输出便携包与用户态安装包至被忽略的 `test/distribution/`（连带 `.sha256` 校验摘要）：

```powershell
node 'clients/windows/scripts/package-release.mjs' package x64
```

本机未安装 Inno Setup 6 时，可附加 `--skip-installer` 仅验证便携 ZIP 打包。

## 发布流水线

- `.github/workflows/windows-ci.yml`：仅供 `workflow_call` 调用，在 `windows-latest` 执行共享资产同步、八语言文案扫描与 WinUI 3 Release 编译检查。
- `.github/workflows/windows-release.yml`：仅支持在默认分支通过 `workflow_dispatch` 手动触发，普通提交与 PR 不触发构建或发包。`publish` 默认 `false`（仅上传 Actions 构建产物）；显式勾选 `publish` 后才进入 `release` 环境，将 `HentaiPark-<版本>-<构建号>-windows-<x64|arm64>-setup[-unsigned].exe`、`...-portable[-unsigned].zip` 及 `.sha256` 发布至 `vX.Y.Z` GitHub Release。
- 代码签名：`release` 环境同时配置 `WINDOWS_PFX_BASE64` 与 `WINDOWS_PFX_PASSWORD` 时自动对主程序与安装包执行 SHA-256 Authenticode 签名及校验，结束后在 `always()` 步骤销毁 `test/signing/` 临时证书材料；部分缺失直接失败，完全未配置时输出带 `-unsigned` 标识的分发包。

## 运行机制与安全边界

- **插件沙箱与多 Profile 隔离：** 每个插件运行于独立的离屏 InPrivate WebView2 实例与虚拟来源 `https://<source>.source.park.invalid/`，启用 `default-src 'none'` CSP 并拦截全部浏览器网络请求，仅通过受控 `postMessage` 访问归属锁定的 `Park.__native` 桥。站点验证/网页登录使用 `park_site_<key>`，网页视频使用一次性无痕 Profile，在线游戏使用加载前强校验名称的 `park_game_<sha256>` 持久 Profile。
- **无感验证：** 共享 `AccessChallengeEngine` 在成年确认前提下处理声明式年龄门（含固定日期 `1999-12-31` 与精确问答），并通过离屏 `CoreWebView2CompositionController` 分发视图内指针点击处理可信验证框，不抢占系统鼠标焦点，不开放远程调试端口。
- **网络、媒体代理与隐私：** 原生请求与 `127.0.0.1` 随机令牌媒体代理均强制校验公网 DNS 地址（含代理 fake-ip 段 `198.18.0.0/15`、`2001:2::/48`）与原域名 TLS 证书，跨源重定向自动剥离认证头且停止注入源 Cookie。酒馆 API 密钥经 Windows DPAPI 加密保存；防截屏使用 `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)`；自动诊断严格执行字段与文案键白名单。
- **数据与备份互通：** 默认数据位于 `%LOCALAPPDATA%\HentaiPark`（可执行文件同级存在 `portable.flag` 时使用 `./data`）。`park.db` 与 `.parkbak`（`version: 1`）保持与 Android 双向兼容合并；跨平台未知设置键原样保留，本机导出目录登记 `export_directories.json` 不进入备份。

## 测试与验证约束

- 所有单元测试、集成测试工程、冒烟脚本、截图及测试产物统一置于根目录 `test/windows/` 下，受根 `.gitignore` 的 `/test/` 规则保护，严禁跟踪或提交。
- 静态编译与单元测试通过不代替真实站点请求验证及 [Windows 设计准则](../design/WINDOWS.md#windows-界面验收边界) 规定的双组合场景（`1440×900` 标准桌面与 `800×720` 大字号分屏）真机运行验收。
