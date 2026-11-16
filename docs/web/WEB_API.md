> 路径约定：本文 `apps/`、`packages/`、`scripts/` 相对 `clients/web`；共享插件协议为 [SOURCE_API](../SOURCE_API.md)。历史测试路径属于原 Web 工作区，仅作证据引用，当前验证见 [ACCEPTANCE](ACCEPTANCE.md)。

# Web API

> 状态：目标契约已冻结。本文列出的接口包含设计契约；当前实现以 `clients/web/apps/api/src` 路由为准，验证范围见[验收边界](ACCEPTANCE.md)。未实现接口不得由前端自行伪造或绕过 API。

所有响应包含 `x-request-id` 响应头。错误统一为 `{ error: { code, messageKey, retryable, requestId, operation, causeCategory, details? } }`。业务路由统一使用 `/api/v1`，只有健康检查保留顶层 `/health`。

## 1. 会话和实例

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/health` | API、数据库和 worker 健康状态 |
| GET | `/api/v1/session` | 当前实例会话和认证状态 |
| POST | `/api/v1/session/login` | Server 模式建立会话；Local 模式返回已初始化状态 |
| POST | `/api/v1/session/logout` | 撤销当前会话 |
| POST | `/api/v1/session/activity` | 记录当前标签页的实际用户活动，用于应用锁闲置计时 |

单用户实例不携带用户、租户或角色字段。认证使用 HttpOnly、Secure、SameSite Cookie；URL 不包含 Token、Cookie 或私有验证参数。

`GET /session` 返回 `{sessionId, mode, authenticated, csrfToken?, requestId}`，其中 `sessionId` 是不可用于认证的公开会话标识，实际会话凭据只在 HttpOnly Cookie 中。Server 登录提交 `{token}` 并使用实例的 `AUTH_TOKEN` 验证，成功后轮换会话和 CSRF；业务写请求携带 `Origin`、会话 Cookie 和 `x-csrf-token`。Local 模式限回环 Host，可自动建立会话；启用应用锁后须用实例凭据解锁。退出、会话过期或应用锁闲置超时会撤销该会话的媒体授权并关闭其事件流。Local 默认 HTTP 仅用于可信回环环境；Server 必须使用配置的 HTTPS 来源。

## 2. 发现、搜索和作品

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/api/v1/discovery` | 全局、域或站点的真实推荐货架；支持 `source`、`category`、`categories`、`limit` |
| GET | `/api/v1/sources` | 站点列表和健康状态 |
| GET | `/api/v1/sources/:key` | 站点 manifest 摘要、能力和目录状态 |
| POST | `/api/v1/sources/:key/enable` | 启用或停用站点，body `{enabled}` |
| POST | `/api/v1/sources/:key/update` | 安装、更新或回滚站点；操作由服务端任务化 |
| POST | `/api/v1/sources/:key/login` | 启动站点登录流程，不返回 Cookie |
| POST | `/api/v1/sources/:key/verify` | 启动或完成站点验证流程 |
| POST | `/api/v1/sources/:key/filter-options` | 查询 manifest 声明的动态目录/搜索筛选候选，不修改业务状态 |
| GET | `/api/v1/sources/:key/rankings/:board/options` | 获取榜单的实际静态/动态选项 |
| GET | `/api/v1/rankings` | 真实榜单分页，区分作品、人物和卖家；genre 为作品筛选 |
| POST | `/api/v1/search` | 作品、标签、番号、链接和资料搜索 |
| POST | `/api/v1/reverse-search` | 图片反搜；上传内容只存在当前请求/会话 |
| GET | `/api/v1/works` | 作品列表、筛选、排序和游标分页 |
| GET | `/api/v1/works/:source/:workId` | 作品详情和能力快照 |
| GET | `/api/v1/works/:source/:workId/chapters` | 章节列表和阅读状态 |
| POST | `/api/v1/works/:source/:workId/chapters/read-state` | 事务标记真实章节已读/未读；版本校验和幂等 |
| GET | `/api/v1/reader/:source/:workId/:chapterId` | 阅读器内容和页/媒体授权元数据 |

搜索响应必须返回分页游标、来源状态、稳定错误码和请求代次；迟到结果由客户端丢弃。作品和章节响应返回稳定身份、版本字段和 `requestId`，临时签名地址不写入响应持久化字段。

发现货架保留来源顺序，包含 `sourceName`、`category`、`layout`、`feedKey`，真实分区另有 `sectionIndex`。`hasNext` 是上游 feed 的分页事实，不代表分区可独立分页。全局/域使用 `limit` 预览，并返回 `itemCount`、`previewTruncated`；指定 `source` 时真实分区完整返回，普通 feed 仍通过 `/works?source=...&feed=...` 进入分页列表。无上游分区链接时不制造 link。`category` 在调用插件前过滤，`source` 与 `category` 同时提供时取交集。

站点列表/详情的 `candidate` 为可信索引候选 `{manifest,version,sha256,permissions:{added,removed}}`，当前 `manifest`/`version` 仍表示已安装版本。页面在安装/更新前展示当前到目标版本、SHA、权限变化与风险，确认后提交。更新 body 可携带 `expectedSha256`、`expectedVersion`、`expectedCurrentVersion`（未安装为 null）作为并发前置条件；候选或当前版本变化返回 `CONFLICT`，不执行安装。包 SHA、真实 manifest 与原子事务校验继续由宿主执行。

`filter-options` body 为 `{scope:'feed'|'search',feed?,filter,keyword?,values?}`；`values` 只含该动态项声明的直接父条件。缺失父条件、未声明项、越界字段或非法输入不能调用任意插件方法。返回 `{items:[{value:string|number,label,color?}],requestId}`，最多 500 个不重名候选；失败保留稳定错误，不静默截断。缓存按源版本、scope、feed/关键词、筛选项及父条件区分，最多保留两分钟；只读查询不发送业务变更事件。控件取消过时请求，上级变化清除下级，支持加载失败重试，数字值保持数字。

`GET /works` 在提供 source 时通过真实 feed 分页，接受 `feed` 与 JSON 编码的 `filters={...options,common?}`；搜索同样在 filters 中承载 common。宿主调用前将 common 提升到插件请求的 `common`，其维度、范围与排序必须由当前 feed 或 `searchCommonFilters` 声明，不能向未声明来源传递。游标绑定源版本、目录、完整条件及分页大小，条件变化须重新开始。

榜单查询参数为 `{source,board,options?,cursor?,limit?}`，options 是 JSON 编码选择。返回条目包含 `{source,rank,title,kind,workId?,url?,keyword?}`；只有作品持久化为 works，人物、卖家、分类不能伪造作品身份。页面保留原名次和指标；作品打开详情，人物/分类按真实 keyword 或名称搜索并保留原站入口，卖家仅保留原站。动态选项经真实 runner 的 `rankingOptions` 加载，分页与选项/版本绑定，非法值或源失败不能伪装为空榜单。

搜索 body 为 `{query, scope?, source?, filters?, cursor?, limit?, requestGeneration?}`；`scope` 为 `all | title | summary | id | link | metadata`。生产路径把范围与筛选传入插件查询；`metadata` 仅选取声明 `metadataSearch` 的源，普通聚合不混入资料专用源。标题、摘要、ID、链接范围还核对实际返回字段。游标与关键词、范围、来源、筛选、条数及插件版本绑定，条件改变不能复用旧游标。多源请求有限并发，来源失败以 `sources[].code` 单独返回；全部失败不能伪装为空成功。

作品使用 `{source, workId}`，章节使用 `{source, workId, chapterId}`，不再混用 `id` 作为 Web 响应身份。`capabilities` 包含领域能力快照、`capturedAt` 和 `sourceVersion`；不能把整个对象视作纯布尔表。执行阅读、播放、下载等操作时还须检查当前安装插件。音声目录沿用章节接口的 `directoryId` 与游标，目录节点返回 `nodeType`；图片、台本、字幕节点读取和媒体曲目分别走能力允许的阅读或播放路径。

## 3. 媒体

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| POST | `/api/v1/media/tokens` | 创建最多 5 分钟的不透明媒体授权 |
| GET/HEAD | `/api/v1/media/:token` | 代理媒体、Range、206、HEAD 和 HLS 资源 |

签发时校验 HTTPS、无凭据/端口、声明域名和 DNS 公网地址。授权只保存在 API 进程内存，过期或撤销返回 404。HLS 清单、分片和密钥沿用同一授权链，不向客户端暴露原始签名 URL。

阅读器、封面及反搜相关图片返回 `{source, resourceKey, authorizationId}`。前端把这三个字段提交给 `/media/tokens`，得到 `{token, expiresAt, requestId}`；客户端填写的上游 `url`、`domains` 不是授权依据。服务端根据 `authorizationId` 重新取得当前资源，并校验来源、稳定资源身份、会话和当前插件权限。媒体 URL 仅使用不透明 token；HLS 子资源的 `resource` 参数也是授权链内的不透明 ID，不是上游地址。代理使用 DNS 钉扎、声明域校验、拒绝重定向及短期私有缓存策略。

插件当次 `videos().headers` 中经 manifest `media.requestHeaders` 声明的 `playback-origin` 专用头，绑定该次返回节点的独立内存 `mediaContext`。该内部上下文不下发网页、不写数据库、checkpoint、备份或普通日志，也不以来源加 URL 的全局槽位共享凭据。API 的授权闭包和 worker 持有各自上下文，HLS 主/子清单、分片、MAP 与密钥仅在与初始媒体相同 origin 时继承专用头，跨 origin 不传；新播放或刷新返回新上下文，不能覆盖并发播放的凭据。未声明头被过滤，未声明域仍然拒绝，即使 URL 出现在插件结果中也不扩大域权限；停用来源、释放宿主或上下文过期后撤销该授权。无专用头的字符串图片页不需要额外上下文授权，仍受相同域名和公网边界约束。

图片统一在宿主校验格式与 20 MiB 上限；声明 `imageDecrypt` 时先识别明文，否则按 UTF-8 密钥执行 AES-CBC 和严格 PKCS7 解密。解密失败不能作为有效图片返回。原生视频、音声和 HLS 使用媒体代理；只声明 `webVideo` 的站点使用独立受限网页播放器，不伪装原生媒体或下载能力。`reader` 在该分支返回 `webPlayer:{playerId,frameUrl,audioUrl,controlUrl,statusUrl,expiresAt}`，地址全部是当前实例下不透明播放器资源，不下发原站脚本或远程控制对象。

受限播放器使用 `/api/v1/web-player/:id/status`、`/frames`、`/audio` 和 POST `/control`。控制 action 仅为 `play | pause | seek | rate | click | key | close`，请求携带 requestKey 并检查会话身份。导航与 frame 域须是 manifest 已声明集合的子集；空闲过期、源停用/版本变化、会话撤销、关闭或连接中断释放浏览器资源。普通 worker 导航测试仍不能单独作为这条实际播放、音轨、交互与释放路径的验收证据；真实站点挑战与凭据条件须另行说明。

图片 HEAD 的类型和长度对应解密后的实际表示；字节范围也在校验/解密后应用，不把客户端 Range 转发为加密文件的片段。无效范围返回 416，单范围和后缀范围返回实际解密字节的 206。

## 4. 书架、历史和进度

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/api/v1/library` | 收藏、分类和书架分区 |
| POST | `/api/v1/library` | 收藏写入；body `{source, workId, favorite?, categoryIds?, requestKey}` |
| POST | `/api/v1/library/migrate` | 跨站迁移收藏、分类、章节进度、历史和小说笔记；未匹配进度时保留原收藏 |
| GET | `/api/v1/maintenance/storage` | 服务端数据库、已完成下载和自动备份占用统计 |
| POST | `/api/v1/maintenance/delete-read-downloads` | 将已读章节的服务端下载加入删除队列 |
| GET | `/api/v1/history` | 历史和继续阅读列表 |
| PATCH | `/api/v1/history/:source/:workId/:chapterId` | 写入漫画页码、视频/音声时间点和有效进度 |
| POST | `/api/v1/history` | 写入作品级历史；`chapterId` 可为空，仍须提供 `requestKey` |

收藏使用作品资源身份 `source + workId`；作品分类存储在 `work_collections.category_ids_json`。阅读/播放进度按内容类型和服务端更新时间处理。

收藏写入的 `favorite` 与 `categoryIds` 独立：更新已有记录时，省略的字段保留服务端当前值；显式空分类数组才清空分类。分类 ID 去重。可携带 `version` 校验，过时返回 `CONFLICT`；幂等指纹按提交意图计算，不因后续其他写入改变。

新记录仅填写分类时不自动收藏；收藏必须显式提交 `favorite:true`。分类与收藏的事实都由服务端返回，界面不能把分类成功伪装成收藏成功。

页码以零为起点。进度写入携带章节 `version`；过时版本返回 `CONFLICT`，客户端重读服务端版本后再提交。`history.scope_key` 是 `JSON.stringify([source, workId, chapterId ?? null])`，作品级历史与名为 `__work__` 的真实章节互不冲突。无痕模式不写入历史和进度。

## 5. 下载任务

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/api/v1/downloads` | 任务列表、进度、错误和分页 |
| POST | `/api/v1/downloads` | 创建任务；body `{source, workId, chapterId, variant?, requestKey}` |
| POST | `/api/v1/downloads/:id/pause` | 暂停可暂停任务 |
| POST | `/api/v1/downloads/:id/resume` | 恢复暂停任务 |
| POST | `/api/v1/downloads/:id/retry` | 对可重试失败创建新的请求尝试 |
| POST | `/api/v1/downloads/:id/cancel` | 进入 `cancelling` 并最终变为 `cancelled` |
| DELETE | `/api/v1/downloads/:id` | 创建删除意图并删除任务/文件 |

下载资源身份是 `source + workId + chapterId + variant`，请求级 `requestKey` 只用于 `operation + requestKey` 幂等，不作为资源或 taskId。variant 必须是稳定业务标识，禁止 URL、控制字符和 URI scheme。

规范资源键由领域函数生成：收藏为 `collection:` 加作品 JSON tuple，订阅为 `subscription:` 加来源、维度、目标 JSON tuple，下载为 `download:` 加来源、作品、章节、变体 JSON tuple。新建下载的 taskId 使用规范下载键；已有持久化 taskId 保持稳定，按资源 tuple 去重。下载控制请求在 path 中编码整个 taskId，不能按冒号拆分身份。

状态机：`queued -> running -> paused/completed/failed`；`queued/running/paused/failed -> cancelling -> cancelled`。删除和恢复由服务端任务状态机决定，页面关闭不影响后台任务。

## 6. 订阅和事件

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/api/v1/subscriptions` | 订阅列表、检查状态和未读数量 |
| POST | `/api/v1/subscriptions` | 创建订阅；body `{source, dimension, target, enabled?, requestKey}` |
| PATCH | `/api/v1/subscriptions/:id` | 更新目标、启用和通知设置 |
| DELETE | `/api/v1/subscriptions/:id` | 删除订阅，可选择保留事件历史 |
| POST | `/api/v1/subscriptions/:id/check` | 立即触发一次检查 |
| GET | `/api/v1/events` | SSE 全局事件流 |
| POST | `/api/v1/events/read` | 按 `eventIds` 写入实例共享的持久已读状态 |

首次订阅检查建立 baseline，不把历史内容误报为新更新。事件流支持 `Last-Event-ID`，按全局 `sequence` 重放；消费端以 `eventId` 去重，界面已读状态由 `event_read_states` 独立保存。

首次成功的空结果同样建立 baseline。检查成功或失败使用冻结的 `subscription.updated`，payload 为 `{subscriptionId, kind:'check', success, checkedAt, errorCode?}`；它只刷新检查状态，不创建内容未读事件。真实新内容才写入 `subscription_events`，其 eventId 与对应 `domain_events` 相同。删除订阅默认保留事件历史并软删除，`keepEvents:false` 才删除订阅及内容事件；停用订阅的立即检查返回 `CONFLICT`。

SSE 帧的 `id` 是全局 `sequence`，`event` 是事件类型，`data` 包含完整领域事件，客户端必须解析 `event` 字段。事件类型固定为 `work.updated`、`chapter.progressed`、`collection.changed`、`download.statusChanged`、`subscription.updated`、`subscription.contentSeen`、`plugin.installed`、`account.updated`。`aggregateVersion` 是实体版本，`eventVersion` 是该聚合事件流版本，均不替代全局 sequence。游标越界或失效时使用传输控制事件 `sync.required` 触发全量同步，它不属于领域枚举。每个标签页有自己的 SSE 消费游标，业务已读仅按 eventId 持久化，刷新和换标签不会重置；BroadcastChannel 仅通知重新读取服务端事实。

## 7. 设置、备份和诊断

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/api/v1/settings` | 外观、语言、网络、过滤、下载、通知和隐私设置 |
| PATCH | `/api/v1/settings` | 版本校验的设置写入；冲突返回 `CONFLICT` |
| POST | `/api/v1/backup/export` | 按用户选择导出数据库、站点设置和下载元数据 |
| POST | `/api/v1/backup/import/preview` | 只读预览真实合并结果及分区冲突计数 |
| POST | `/api/v1/backup/import` | 校验 manifest 后事务合并，失败保留当前数据 |
| GET | `/api/v1/diagnostics` | API、数据库、worker、插件宿主和站点诊断 |

备份不包含临时签名 URL、运行中租约、缓存、反搜上传内容和短期验证 HTML。诊断输出必须脱敏 Cookie、Token、签名 URL、AI 密钥和私有内容。

导出 body 为 `{include?}`，导入为 `{backup, requestKey}`。默认包含 `sourceRegistry`、`sourceSettings`、`works`、`chapters`、`categories`、`history`、`library`、`subscriptions`、`subscriptionSeen`、`subscriptionEvents`、`eventReadStates`、`novelNotes`、`tavernAssets`、`tavernConversations`、`subscriptionEventTargets`、`settings`；只有显式选择才加入 `accounts`、`cookies`、`downloads`。账号和 Cookie 是用户选择的敏感持久数据，不能进入默认备份或诊断。导出响应顶层 `requestId` 不是备份业务字段，保存或导入时剔除该响应元数据。格式固定为 `manifest.format='hentai-park-web-backup'`、`manifest.version=1`，`manifest.includes` 与实际数据分区一致。

导入预览 body 仅为 `{backup}`，沿用实例会话及 Server CSRF 校验，无业务 `requestKey`。成功返回 `{preview:true,canImport:true,partitions,totals,restoredSourcesDisabled,requestId}`；`partitions` 以备份分区名为键，每项为 `{incoming,added,replaced,retained,conflicts}`，`totals` 为对应计数之和。`added/replaced/retained` 互斥且合计为 `incoming`；`conflicts` 为已有同身份数据的业务值不同或订阅自然身份重映射的行数，属于重叠提示计数，合并规则可自动处理，不表示额外行或阻止导入。纯时间戳与版本差异不单独计为业务冲突。

预览在只读复制的纯内存 SQLite 中运行与实际导入相同的严格校验及合并引擎：较新记录优先、章节较新进度保护、站点设置/账号字段合并、订阅身份及事件引用重映射、已存在下载按资源 tuple 保留。真实数据库、WAL、设置版本、事件/outbox、幂等记录和来源私有状态不改变；响应仅包含分区名、计数与布尔标记，不回显行身份、标题、账号、Cookie 或其他值。非法结构/引用仍以稳定错误响应拒绝。预览只代表当时快照，实际导入重新校验当前数据；确认前若数据变化，结果以提交时的合并事实为准。

导入校验全部记录并在事务/savepoint 内合并，外键缺失、未知字段或非法授权数据会回滚整个导入；幂等指纹覆盖完整 backup。恢复的站点注册表保持停用，不能从备份执行插件脚本。下载仅导出元数据，导入不接受本地 path 或活动 lease；没有文件的恢复任务返回明确失败状态，允许按真实资源重试。物理数据目录迁移与 JSON 备份是不同操作，详见数据及部署文档。

## 8. 通用约束

- 持久化业务写入必须提供 `requestKey`，幂等身份为 `operation + requestKey`，同时保存完整请求指纹；会话、活动心跳、搜索、反搜、媒体授权和备份导出不作为业务幂等写入。
- 相同幂等键复用不同 body 返回 `CONFLICT`。
- 收藏、下载、订阅和设置写入在同一事务中完成业务写入、幂等记录和 domain event/outbox 追加。
- 分页统一使用 `{items, page:{limit,nextCursor}}`。
- 所有输入运行时校验；长度、控制字符、URL、variant、来源 key 和游标非法时返回稳定 4xx。
- 来源 key 复用 source-contract 的冻结校验：1–100 个 ASCII 字母、数字、下划线或连字符，保留 `_app` 不允许作为来源；API、反搜与备份一致。长作品/章节/下载身份的编码路径由有界路由长度支持，不使用框架默认 100 字符截断。
- 宿主的 `INVALID_MANIFEST`、`INCOMPATIBLE`、`BLOCKED`、`TIMEOUT` 等错误保留来源分类与稳定 code，不伪装成未知内部错误；响应不回传插件私有错误文本。
- 领域错误保留 `causeCategory`，HTTP 状态码由 API 层映射。
- Node.js 运行时限定为 24.22.3+ 的 24.x LTS；SQLite 使用 Node 24 的 `node:sqlite` 内置 API。


### 受控网页播放器资源

webVideo-only Reader 或原生明确返回 UNSUPPORTED 的双能力 Reader 可返回 `webPlayer:{playerId,frameUrl,audioUrl,statusUrl,controlUrl,expiresAt}`，所有 URL 均为 `/api/v1/web-player/:playerId/` 下的同源窄资源；原生媒体优先级、稳定资源 tuple 和 domain event 语义保持。该描述不含上游网页、媒体 URL 或 Cookie。

- `GET status` 返回真实远端 `state/paused/position/duration/rate/muted/hasAudio/viewport/expiresAt`；`state` 为 ready/loading/verification_required/failed/closed，失败包含稳定错误码。
- `GET frames` 是 no-store MJPEG 网页画面流，同一资源仅允许一个连接；断开该画面流关闭播放器。
- `GET audio` 是 no-store 实时 Opus/WebM 音轨；每次新连接生成完整初始化头，旧连接停止捕获。仅声音连接断开不关闭页面。
- `POST control` 接受 `action` 为 play/pause/seek/rate/click/key/close 及对应位置、速度、坐标或固定按键，必须携带 requestKey 与现有会话 CSRF；相同键不同动作返回 CONFLICT，重复同动作不重放点击。按键为 Space、Enter、Escape 和四个 Arrow 键。

资源绑定实例会话、source/version 与真实作品/章节，跨会话不可读取。创建后未领取的资源 5 秒释放，领取后 90 秒无访问自动释放；关闭、取消、断流、锁定/注销、来源关闭/更新和服务器 preClose 同样释放。网页 Cookie 独立临时，禁止导入/导出来源凭据。历史只记真实访问，未可靠获得精确续播时省略 position/page，不把网页截图时间写为原生进度。不可捕获的音轨返回可见失败，不以静音代替成功。

### 来源目录与榜单查询

`GET /api/v1/works?source=...&feed=...&filters=...` 按真实插件 feed 分页，filters 为 JSON 对象，普通键传给 feed 的 options，通用范围/排序放在 common；游标绑定来源、插件版本、feed、条件和页大小。不能混用 SQL 全站缓存、其他 feed 或搜索结果。缺省 feed 使用 manifest.defaultFeed；全局无 source 的作品列表保留 category/order 缓存查询。有 feed/filters 时必须指定 source。

`POST /api/v1/sources/:key/filter-options` 是同会话/CSRF 的只读声明查询，body 为 `{scope:'feed'|'search',feed?,filter,keyword?,values?}`；只允许 manifest 声明 dynamic 的选项，通过独立受限 runner RPC 调用同一 Park 运行时。返回 `{items:[{value,label,color?}],requestId}`。取消向下传播；有界短期缓存按完整语义区分，未声明/超量/坏响应明确失败，不写业务事件。

`GET /api/v1/rankings?source=...&board=...&options=...&cursor=...&limit=...` 按冻结 rankings 能力调用真实 ranking，options 为 JSON 对象；目录与榜单共用绑定语义的 opaque 游标实现。返回标准 items/page/requestId，每项有 source/rank/title/kind，作品额外 workId，人物/卖家保持其身份和合法原站 URL；genre是分类条件下的作品榜，仍返回work。`GET /api/v1/sources/:key/rankings/:board/options` 返回真实运行时解析的选择项 `{items:[{key,label,default?,values:[{value,label}]}],requestId}`，包括动态选项。无声明、非法参数或解析失败明确报错。

历史查询响应中的 duration/readState 来自相同章节的服务端事实，继续阅读视图可据此排除已完成媒体。分类关联只要求合法 categoryIds，categories 是可选名称元数据；备份导出、预览和导入保持同一语义，无名称记录的合法分类ID也必须可原样回导，不能伪造名称或丢弃关联。

API在读取或创建会话前拒绝 Sec-Fetch-Site: cross-site 的浏览器请求（包括GET/HEAD），响应CORP为same-origin；不依赖单一浏览器的SameSite实现。原Strict/Secure/HttpOnly、Origin及CSRF校验保持同一路径。无浏览器Fetch Metadata的受权API客户端仍按Cookie/写入Origin-CSRF规则校验。

榜单读取不向works或普通首页磁盘缓存写入任何榜单结果。genre声明表示分类筛选下的作品榜（如现有catalog-fanza的legacySearchPPV.contents），不是分类实体列表；共享Park运行时仍按原协议规范为work。人物/卖家保持其非作品身份。只有用户显式打开作品后，正常详情/资料详情链才摄入稳定作品，榜单原始rank/keyword/url留在榜单响应与独立游标中。

legacy参数仅在source-runtime单一适配器转换：metadataDetail接收(id,请求context)，metadataMagnets只接收id；普通detail未提供preview时不构造第二个数组项，防止JSON把undefined变成null破坏插件缺省参数。动态候选缓存与搜索/feed/榜单/目录/反搜游标同时绑定已安装的不可变插件产物；同版本内容替换也拒绝旧游标，不复用旧候选。页面pagehide后拒绝新普通客户端请求，最后进度/关闭的keepalive保留，pageshow恢复重新读事实；网络取消的活动心跳不会派生额外认证查询，401仍由统一适配器通知。

作品详情保留实际authors；资料详情的code在Web规范化为workCode，actors保留为独立出演信息而非作者。界面显示服务端来源/编号与sourceUrl原站入口，仅存在真实workCode时给出该编号的搜索链接，不从标题或ID猜测。


## 文章、相册与双视频协议接线

- `GET /api/v1/reader/:source/:workId/:chapterId` 对article返回有序`blocks`及`tagLinks`。块为`{type:'text',text}`、`{type:'image',mediaAuthorization}`、`{type:'video',id,previewAuthorization?}`；不调用textChapter、不返回原始媒体URL。现有章节进度字段保存文章块位置。
- `GET /api/v1/articles/:source/:workId/media/:mediaId` 校验当前真实正文包含该稳定视频ID后调用videos，返回video reader载荷及opaque授权；不能提交任意URL或虚构媒体ID。
- `GET /api/v1/works?source=...&link=...` 使用声明的searchLink进行文章标签分页，link须来源域内HTTPS，仍由插件检查路径/标签身份。与普通feed各自绑定游标条件。
- `GET /api/v1/albums/:source?scope=<JSON>&cursor=...` 的scope严格为`{target:string}`、`{feed,options?,common?}`或`{search:{keyword,filters?,common?}}`。返回`{items,page:{limit,nextCursor},requestId}`；items包含`id,source,title,text,date,presentation,locked,coverBlurred,media`。媒体包含稳定`id/type/order?/previewOnly/blurred`及`mediaAuthorization/previewAuthorization?`，隐藏短期URL和resource。跨页重复作品按media.id合并、按完整order恢复顺序；空页仍可继续，重复上游游标报PARSE。游标绑定scope、会话与不可变插件包，改条件/换包后拒绝旧游标。
- 独立album不依赖频道subscription；相册页不向作品/书架表持久化正文或短期媒体地址。resource只从实际插件返回建立授权，分块经内部albumChunk→subscription.mediaChunk映射，不开放客户端调用路径或本机缓存位置。
- 双视频reader先调用videos，只有该解析返回UNSUPPORTED且确有webVideo才创建临时网页播放器。字幕等后续错误不触发网页回退，下载仍仅videos。
- 图片及media.scope=session在服务端实际输出上建立公网授权，旧静态media.domains继续限制非session媒体。所有会话/CSRF、DNS/IP钉扎、逐跳、大小、TTL、取消/撤销保持；前端不能传递scope、URL或域名来扩大权限。HLS格式按真实插件format与已授权清单继承，兼容合法text/plain及无后缀子清单，非EXTM3U文本拒绝。


## 本轮基线修复接口

- 搜索增加 keywords（最多8项）、sources、mediaKind、category；多关键词共享去重并分别保存每来源游标。GET /sources/:source/suggestions、POST /search/resolve、POST /sources/:source/random 分别用于建议、明确解析和随机作品。
- GET/PATCH /sources/:key/settings 为实际Host设置，PATCH带settings、version、requestKey。GET /sources/:key/account、POST logout/managed；managed必须confirmed。网页登录使用login-browser及source-logins下的frame/control/complete/DELETE，只导入声明的Cookie和localStorage键。
- GET /works/:source/:workId/content、comments、related、thumbnails、magnets、interaction、media-choices/:chapterId、navigation/:chapterId 消费公开详情。原站互动POST必须confirmed，应用收藏保持独立。
- channels下的normalize、targets、saved、posts与独立albums分别提供；posts/:source/:workId不假定普通detail存在。游戏、酒馆与live-chat使用各自受控服务，不把秘密描述符交给浏览器。
- POST /media/:token/renew按服务器资源身份重新解析并续期，返回token/expiresAt/changed。源写入、锁定和注销撤销旧授权与在途请求；HLS只能读取注册子资源。
- GET /offline/:taskId及其files/:id仅从已完成本地任务读取，支持HEAD/Range，源停用或断网不重新解析来源。data-transfer支持CBZ导入、CBZ/PDF导出，恢复图像transform后才生成PDF。
- POST /recordings需source/workId/chapterId、confirmed、durationSeconds(1..3600)、maxBytes(1MiB..2GiB)、requestKey。POST /recordings/:id/stop保留已提交分片并结束；普通直播下载仍拒绝。
- categories提供名称CRUD/排序/版本；DELETE history按scopeKeys/before/all清理。library/works只读缓存，POST library/check-updates执行真实收藏目录差异检查；recent使用contentUpdatedAt。
- subscription-events提供带稳定内容身份、关联目标及跳转信息的更新；events/read只接eventIds。目标先normalize，再query/check；基线扫描游标可恢复，账号/设置/插件语义变化重建基线。
- translate与search/translate仅在启用内容翻译且本次confirmed时向固定翻译服务发送选定文字。tag-packs导入/导出/删除按来源和语言分区，原文与搜索身份不变。

备份导出响应是纯备份文件，请求跟踪号仅在响应头。源设置从Host读取只读快照；source_settings/source_accounts只保存待导入队列，成功持久恢复后消费。普通源设置不包含密码声明或内部账号标志；账户/Cookie须显式选择。预览与提交均做私有结构校验，提交按当时数据库状态重新计算合并。


## 酒馆与词包收口接口

`GET/POST /api/v1/tavern/connections`和按ID的DELETE管理独立模型连接；只返回hasKey，不返回明文密钥。HTTPS提供方可使用显式端口；仅Local或部署明确开启时允许精确HTTP回环地址，HTTP连接禁止密钥、认证头和重定向。`worldbook-term-packs`保留原schema2，条目翻译prepare只生成可验证占位文本，由用户显式确认翻译。

`GET /api/v1/tag-packs/available`读取固定官方索引；`POST /api/v1/tag-packs/download`只接受来源、语言、确认版本/SHA256及confirmed，不接受下载URL。资源限固定提交官方路径，拒重定向、坏SHA、超限和版本降级，失败保留旧包。

备份默认包含tavernConnections/worldbookTerms，tavernConnectionSecrets必须明确选择；preview执行纯校验和目标加密准备，SQL不变，确认import才在同一事务写入。备份预览/导入专用上限128MiB，普通API上限保持16MiB。

## 本轮 UX 数据投影与状态补充

`GET /works?source=...` 保持 `items/page`，按真实上游分区新增 `sections?: {key,title,items}[]`。key 由上游页码与分区原索引组成，仅是分页投影身份，不是原站永久分区 ID；同名分区不合并。真实空分区保留，非空分区全部被跨页去重后不伪造空分区。上游同时返回 sections/items 时分区顺序优先，独立条目去重追加；榜单和普通无分区 feed 不伪造分组。分区与作品均应用原可见性和媒体授权规则。

发现及历史的 `categories` 为合法17域的CSV；缺省表示不过滤，显式空字符串表示空集合，与 `category` 取交集。发现先按范围过滤再调用插件；历史先按真实作品域过滤再排序分页。`uniqueWorks=true` 在范围内每作品取最近一次访问，再分页，用于继续看；默认历史仍保留作品级及章节级记录。

`GET /history?resume=true&source=...&workId=...&limit=1` 只读查询该作品最近有效可消费章节，返回真实 `nodeType`，排除目录/其他文件及已删除节点；不受全局前若干条截断。它与域筛选/uniqueWorks互斥；不提前调用 reader，不写历史。前端按节点类型进入消费，既有 reader 返回已存进度。

章节 `read-state` 请求包含 `{chapters:[{chapterId,version}],readState:'read'|'unread',requestKey}`，最多200项，事务校验真实章节和版本，仅变更read_state及版本，不伪造进度、不删除历史；事件保持多标签同步。冲突整批拒绝，重复requestKey按原幂等机制处理。
