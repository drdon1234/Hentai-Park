> 路径约定：本文 `apps/`、`packages/`、`scripts/` 相对 `clients/web`；共享插件协议为 [SOURCE_API](../SOURCE_API.md)。历史测试路径属于原 Web 工作区，仅作证据引用，当前验证见 [ACCEPTANCE](ACCEPTANCE.md)。

# Web 架构详细设计

本文细化 [Web 设计准则](../design/WEB.md) 的进程、模块、数据流和生命周期，不改变单用户实例、多标签页和插件隔离边界。

## 进程边界

```text
Browser
  -> apps/web
  -> apps/api
       -> packages/domain-model
       -> packages/source-host -> apps/source-runner -> plugin
       -> apps/task-worker
       -> apps/browser-worker
```

- `apps/web` 只通过 HTTP/SSE API 访问数据。
- `apps/api` 负责会话、输入校验、事务、SourceCatalog、SourceOperations、媒体授权和错误映射。
- `apps/task-worker` 导出常驻 WorkerScheduler 和真实下载/订阅适配器，由同一实例的 runtime 装配，负责 outbox、文件恢复和 lease fencing；不依赖浏览器页面持续打开。
- `apps/source-runner` 是受 source-host 管理的独立 Node 子进程，通过逐行 JSON-RPC 接收调用；插件本身在受内存、CPU 和栈限制的 QuickJS 引擎中执行，不暴露 Node、进程环境和宿主文件系统。
- `apps/browser-worker` 导出按需的 Playwright 浏览器辅助服务，创建受控 Browser/Context/Page，负责验证、图片上传反搜和网页媒体辅助；不向插件或 Web 客户端暴露 CDP、Page 或任意脚本执行。
- `packages/domain-model` 不绑定数据库和运行时。
- `packages/source-contract` 是插件 manifest、能力和错误的唯一边界。

## 数据流

页面写操作先生成请求级 `requestKey`，API 在事务内校验、写入业务状态、追加 `domain_events`、追加 `event_outbox` 并保存幂等响应。worker 通过 lease generation 领取任务，执行结果再次校验 fencing 后更新任务和事件。浏览器通过 SSE 按全局 sequence 重放事件，BroadcastChannel 只负责低延迟 UI 通知。

读取内容的生产链是 `Web -> API -> SourceCatalog -> SourceHost -> source-runner -> plugin -> network broker`。发现和搜索调用真实插件，作品详情与章节保存稳定字段；音声目录通过真实分页产生稳定节点和可恢复进度。插件参数由运行时适配成冻结能力语义，Web 不按站点名写规则。搜索范围、游标、请求取消与来源失败状态必须贯通整条链，不能以缓存 SQL 查询或本地页面筛选替代真实来源查询。

封面、漫画、原生视频、音声与字幕由 SourceCatalog 生成会话绑定的 `authorizationId`。Web 只提交 `{source, resourceKey, authorizationId}` 申请短期 token；API 从服务器事实中刷新当前资源，并通过受 DNS 钉扎和权限约束的媒体代理返回数据。上游 URL、内联 HLS 密钥、上传图片及验证 HTML 不进入普通实体与日志。HLS 主清单、分段清单、分片和密钥继续使用同一授权链；子资源 URL 只包含不透明 ID。

站点安装/更新只接受受信索引中校验过 SHA-256 的包，权限变更和 minAppVersion 在宿主边界检查。安装日志的 prepared/committed/rolled_back 支持失败恢复；注册表中的插件路径相对当前插件目录重建。用户私有状态按源保存，账号状态须由插件真实确认，访问网页或取得 Cookie 不能直接作为登录成功证据。

原协议、未修改共享SDK和原宿主为本轮核对基线。Web已统一支持feed分类、videos与webVideo并存、独立album及当次session媒体权限；不再以冻结子集拒绝合法插件。播放优先videos，仅UNSUPPORTED且声明双能力时转入webVideo；下载保持videos链。网页描述的当次导航/框架权限由服务端建立临时无来源Cookie的context。文章正文与完整相册均走对应真实插件方法，不以textChapter或频道订阅替代。

状态同步使用服务器实体版本判断是否重读，SSE sequence 仅用于全局重放，eventVersion 仅用于聚合事件流。每个浏览器标签页有独立 tabId 和连接生命周期，关闭标签页只终止页面资源。收藏、任务、订阅、账号、设置及主题以服务端提交结果为准，未提交表单和搜索草稿保留在当前标签页。

## 生命周期

唯一生产装配入口是 `scripts/start-web.mjs -> scripts/runtime.mjs`，由 `pnpm start` 和 Windows 启动脚本调用。`apps/api/src/index.ts` 只构造 API，不单独创建另一套生产进程。构建通过 `pnpm build` 按依赖顺序生成运行包、QuickJS 使用的浏览器 polyfill 和前端静态产物；Vite dev 入口同样装配真实 runtime，并代理 `/api` 与 `/health`。

runtime 依次验证模式与监听地址，建立 DATA_DIR/DOWNLOAD_DIR 和实例密钥，加载插件注册表及安装日志并恢复未提交安装，初始化数据库迁移和当前注册状态，再装配 catalog、浏览器辅助、后台调度器及静态页面。worker 完成启动扫描后才监听 HTTP。Local 默认回环与端口 8787；Server 强制显式 Host、实例凭据和 HTTPS 允许来源。`/health` 实际查询数据库并检查 worker，未运行不能返回 ready；浏览器环境另在诊断中区分可用与不可用。

关闭时停止新扫描，向活动下载与订阅发送取消信号，等待有界回调，释放租约、浏览器和 source-runner，最后关闭 SQLite。崩溃恢复依赖未完成任务、删除意图、文件 hash/checkpoint、未发布 outbox 和租约 generation。下载物理路径按当前 DOWNLOAD_DIR 与稳定任务身份计算，Windows 绝对引用不会在 Linux 中照搬执行；完整目录迁移与只含元数据的 JSON 备份分别处理。

## 发布依赖和证据

Fastify、QuickJS、tough-cookie、source-host、source-runtime 以及 Playwright 属于生产运行依赖。Playwright npm 包与浏览器可执行文件是两项独立条件：安装包不代表 Chromium 已安装，生产镜像必须带所需浏览器和系统库，或显式配置可执行路径。React 与 hls.js 被前端构建；TypeScript、Vite、esbuild 及构建 polyfill 所用的 core-js-pure、fast-text-encoding、linkedom 属于构建工具。当前 Dockerfile 复制构建结果和依赖树，不能据此宣称镜像已经移除全部开发依赖。

构建和类型检查验证产物可生成，不能证明浏览器、插件、媒体与持久化功能。真实页面测试、API 注入、独立进程、文件字节、数据库重启与数据目录迁移分别验证各自路径；凭据、站点挑战或平台条件未覆盖时保留明确的未验证项。全部测试文件和产物位于根目录 `test/`，始终不进入 Git 跟踪。发布结论以[验收边界](ACCEPTANCE.md) 的完整验收为准。
