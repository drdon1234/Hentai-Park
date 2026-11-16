# Web 工程与发布

[开发说明入口](../DEVELOPMENT.md) · [部署](../WEB_DEPLOYMENT.md) · [Web 设计](../design/WEB.md) · [插件协议](../SOURCE_API.md)

## 构建与目录

Web 位于 `clients/web`，独立 pnpm workspace，不改变 Android 的 Node 或构建流程。以下命令从仓库根目录执行，需要 Node.js 24.22.3+（24.x）及 pnpm 10.33.2：

```sh
pnpm --dir clients/web install --frozen-lockfile
pnpm --dir clients/web verify:structure
pnpm --dir clients/web typecheck
pnpm --dir clients/web build
pnpm --dir clients/web --filter @hentai-park/browser-worker exec playwright install chromium
pnpm --dir clients/web start
pnpm --dir clients/web dev
```

Linux 原生运行还需 Playwright 系统库，可使用 `playwright install --with-deps chromium`。Dockerfile 已安装匹配锁文件的 Chromium 和系统库，不需要宿主机安装浏览器。镜像目前包含构建工具与完整依赖树，不宣称仅含生产依赖。

`assets/sources/*.js`、`assets/runtime/park_runtime.js` 是唯一人工维护来源。`build` 生成被忽略的 `clients/web/assets` 副本、polyfill、应用版本和兼容索引，使用真实 SourceHost/QuickJS inspect 计算 manifest 与 SHA-256。插件声明和共享 SDK 原样使用；版本读取根 `pubspec.yaml`。`sources:index` 也重新复制共享资产。启动、开发与 Windows 启动器在产物缺失或共享资产变化时重建，普通 Web 源码修改后执行 `build`。

运行路径从脚本位置确定，`.env` 固定读取 `clients/web/.env`，相对 `DATA_DIR` 和 `DOWNLOAD_DIR` 相对 `clients/web` 解释。默认数据位于 `clients/web/data`。启动器保留项目路径隔离的互斥、Windows Job Object 子进程回收、关闭通知及浏览器自动打开；迁移不会接管来源项目的运行实例。

所有测试、夹具、截图和验收产物仅放根 `test/`，不纳入 Git。根 `/test/` 规则与 Web 依赖、产物、数据忽略规则必须保留。

## 发布流水线

Android 与 Web 使用独立发布入口：`release.yml` 负责 Android，推送与应用版本匹配的 `v*.*.*` 标签或在 main 手动运行 Android Release；`web-release.yml` 负责 Web Docker，需在 main 手动运行并使用 `clients/web/package.json` 的独立 Web 版本。普通 main 提交与 PR 不触发平台检查、Android 构建或 Docker 构建。`check.yml`、`build.yml`、`web-ci.yml`、`web-docker.yml` 仅接受 workflow_call。插件与词包的独立发布流程保持不变。

Android 发布流程先校验应用版本与发布说明，执行原生检查、Android 构建并创建 GitHub Release。Web 发布流程先执行 Web 检查，再构建并按 `clients/web/package.json` 版本推送 linux/amd64 Docker 镜像，同时更新稳定版本标签和 `latest`。跨 GitHub/Docker Hub 的发布不是原子事务：一端失败时另一端可能已经发布。

构建 job 只有 contents:read，不进入 release 环境；镜像发布 job 单独进入 release 环境获取 Docker Hub 凭据，PR 不可调用发布入口。Web 的第三方 Actions 固定到已核实的提交 SHA，Android 与 Web 仍使用各自 Node 基线。

`release` 环境 Secrets：`DOCKERHUB_USERNAME`、`DOCKERHUB_TOKEN`（Docker Hub Access Token，具有目标仓库推送权限）；仓库 Variable：`DOCKERHUB_IMAGE`（不含 tag 的 `namespace/repository`）。已有 `release/DOCKERHUB_TOKEN` 由用户配置，本次保留；用户名通过 stdin 配置。若以后通过本机终端输入 Token，必须隐藏输入并通过 stdin 上传，不进入文件或命令参数。替换现有同名值须显式授权。Secret 无法读回，现有 Token 的认证及推送权限要等线上登录步骤验证。

正式版本发布 `X.Y.Z` 和 `latest`，每次附加提交 SHA 标签，不再维护 edge。手动发布使用 pubspec.yaml 版本，与 Android Release 一致；标签版本必须匹配 pubspec。Web 标签生成器拒绝普通 push/PR，预发布镜像不会更新 latest；整体发布入口仍遵循原项目的版本规则（目前原生发布工具仅接受稳定 vX.Y.Z）。版本提交须属于 main 历史，其他分支不允许手动发布。

每次发布附加完整 `sha-<40位提交SHA>` tag 及 OCI source/version/revision/license 标签。SHA 标签表示源码提交，镜像 digest 才精确标识构建结果。线上是否可拉取以实际 workflow 运行结果为准；本地静态检查与构建不代表发布成功。

## 工程文档与证据

[架构](WEB_ARCHITECTURE.md)、[API](WEB_API.md)、[数据](WEB_DATA.md)、[插件宿主](WEB_PLUGIN_HOST.md)、[浏览器行为](WEB_NATIVE_BEHAVIOR.md)、[功能边界](WEB_FEATURES.md)、[全端 UX 优化方案](WEB_UX_IMPROVEMENT_PLAN.md)。


参考阅读：已实际阅读 [JAV-Pilot README](https://github.com/drdon1234/JAV-Pilot) 和[安装说明](https://github.com/drdon1234/JAV-Pilot/blob/main/docs/guide/getting-started.md)，仅借鉴 Compose 优先、发布前本地构建、持久化与升级的文档组织。Web 的 HTTPS、实例凭据、固定非 root 用户、端口及浏览器依赖均依据本项目实现。
