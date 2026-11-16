> 路径约定：本文 `apps/`、`packages/`、`scripts/` 相对 `clients/web`；共享插件协议为 [SOURCE_API](../SOURCE_API.md)。历史测试路径属于原 Web 工作区，仅作证据引用，当前验证见 [ACCEPTANCE](ACCEPTANCE.md)。

# Web 领域数据模型（CORE-003）

## SQLite 实现（DATA-001）

Web API 使用 Node.js `node:sqlite` 的 `DatabaseSync`。生产入口 `scripts/runtime.mjs` 以 `DATA_DIR/web.sqlite` 为默认数据库，`DATA_DIR` 默认指向仓库的 `data/`，`WEB_DB_PATH` 可显式覆盖。连接初始化固定执行 WAL、5 秒 busy timeout、foreign keys 和 synchronous=NORMAL；当前 `PRAGMA user_version` 为 14。启动时所有待执行迁移在同一个 `BEGIN IMMEDIATE` 事务中完成，失败回滚整批并关闭连接；未知高版本拒绝启动。

| Schema 版本 | 变更 |
| --- | --- |
| 1 | Web 独立基础表 |
| 2 | history 显式 scope_key、operation/requestKey 复合幂等记录和请求指纹 |
| 3 | 下载稳定资源键及唯一约束 |
| 4 | 移除持久化媒体 token 表，授权仅存在内存 |
| 5 | works.metadata_json 保存稳定公开元数据 |
| 6 | 收藏、订阅、下载统一领域 JSON tuple 资源键；同步文件键、checkpoint、删除意图和 history scope_key |
| 7 | subscriptions.deleted_at 支持保留事件历史的软删除 |
| 8 | chapters.node_type 保存音声资源节点类型 |
| 9 | chapters.node_metadata_json 保存目录身份、字幕关联及语言等稳定节点信息 |

媒体 token 和 `authorizationId` 由 API 进程内存管理，绑定来源、资源身份、当前会话和短期过期时间。客户端只提交服务器签发的授权身份，不能用自填上游 URL 或域名扩大访问范围。临时媒体 URL、HLS 密钥、反搜上传和验证 HTML 不进入作品、事件或普通缓存。站点 Cookie 与插件私有状态属于单独的按源持久化资产，保存在 `DATA_DIR/private/`；只有用户显式选择账号或 Cookie 分区时才允许进入备份。

DATA-002 的 worker 以 `domain_events` 为不可变事件源，通过 `event_outbox` 可靠发布；发布状态和尝试次数可恢复。SSE 使用全局 sequence 与 `Last-Event-ID` 重放，Web 消费端按 eventId 去重；`event_deliveries` 为需要持久投递账本的消费者提供唯一约束，不等同于每次 SSE 读取已经登记到该表。订阅检查在事务内写入 `subscription_seen`、`subscription_checks` 并更新成功时间；任务 worker 重启时重新扫描未完成任务和未发布 outbox。

复合主键和唯一键覆盖作品、章节、下载变体、资源键、业务幂等键、全局 sequence、聚合事件版本以及租约身份。`history.scope_key` 统一为 `JSON.stringify([source, workId, chapterId ?? null])`，既避免 NULL 唯一性漏洞，也避免冒号和特殊章节名碰撞。迁移资源键时保留已有 taskId，不以重建任务代替现有数据迁移。删除意图保留在 `deletion_intents`，直到实际文件与数据库清理完成。

常驻 worker 通过 `WorkerScheduler.start()`/`stop()` 管理生命周期。每轮检查控制意图、发布 outbox、对账删除与文件、领取下载，再检查到期订阅；单进程 active Map 和数据库租约共同阻止重叠执行。启动自动恢复 queued/running/cancelling，paused 保持暂停，failed 必须经允许的显式 retry 后重新排队，永久失败不会不断重跑。默认订阅检查周期为 5 分钟，与任务轮询间隔独立；失败按有上限的退避安排 next_due。暂停、取消、删除及停止会触发 AbortSignal；运行中的任务定期续租，提交时同时校验 running 状态、generation、租约有效期和删除意图。停止不无限等待失去响应的适配器。

生产接入通过 `DownloadTaskAdapter.execute(task, context)` 和 `SubscriptionAdapter.fetch(subscription)` 注入。下载适配器只能返回 completed、retryable_failure 或 permanent_failure，worker 在同一事务中再次校验 lease、更新任务计数/错误分类并追加 domain event/outbox；订阅适配器只返回可持久化的内容身份和版本，seen 去重仍由数据库主键保证。

第一条 SourceHost 适配链由 `SourceHostDownloadAdapter`/`SourceHostSubscriptionAdapter` 提供：按持久化的 source、work/chapter/variant 或 dimension/target 组装 invoke 参数，宿主不可用和网络异常标记为可重试，响应结构或资源身份非法标记为永久协议错误；没有宿主时不会伪造成功。

作品详情通过 SourceCatalog 调用当前插件并更新 `works` 与 `chapters` 的稳定字段；标签、作者、番号、音声目录根和字幕关联等公开元数据进入 `metadata_json`，媒体地址和密钥保留在独立授权内存中。章节与音声资源节点的进度分别按各自稳定章节身份保存。

章节 reader 返回持久化阅读/播放进度、资源描述及服务器签发的 `authorizationId`，不返回原始签名地址。进度冲突以章节版本校验，旧标签页不能静默覆盖更新后的事实。

这是 Web 独立平台的领域层，不复用移动端数据库表、迁移或同步协议，也不包含用户、租户或跨用户权限字段。实现位于 `packages/domain-model/src`，只导出不可变 TypeScript 类型和纯函数，不绑定 SQL/ORM。

## 身份、资源键与写请求幂等

作品身份是 `source + id`，章节身份是 `source + workId + chapterId`。下载任务身份键在章节身份上加入稳定的 `variant`，因此同一章节的不同画质/格式是不同任务。`DownloadVariant` 保留 `original`、`compressed`、`stream`，同时允许站点扩展字符串；扩展值必须是稳定业务标识，不能是临时媒体 URL。

资源键和写请求幂等键严格分离：`workCollectionResourceKey` 只定位一个作品收藏资源，`subscriptionResourceKey` 只定位 `source + dimension + target`；`collectionWriteIdempotencyKey`、`subscriptionWriteIdempotencyKey` 还需要调用方提供本次请求的 requestKey。同一作品先收藏再取消收藏必须使用不同 requestKey，不能因资源键相同而错误去重。下载任务的 `downloadTaskId` 是稳定任务身份，写请求仍应由 API 另行记录请求幂等结果。

资源键使用领域纯函数的 JSON tuple 编码：`collection:[source,workId]`、`subscription:[source,dimension,target]`、`download:[source,workId,chapterId,variant]`，其中方括号部分是实际 JSON 字符串而非冒号拼接。媒体章节资源键是 `chapter:` 加章节 tuple，单页再加入页身份；媒体身份与下载任务身份互不代替。

## 作品、分类、能力与历史

跨站迁移在一个 SQLite 写事务中合并目标收藏、分类、章节进度、历史和小说笔记。章节只按标题或章节编号在两侧都唯一时匹配；目标已有进度取较新值。任一带进度的旧章节无法无歧义匹配时保留原收藏，避免迁移造成数据丢失。

`mediaKind` 只描述阅读、播放、音声、游戏或内容渲染方式，固定值包括 `comic`、`article`、`novel`、`video`、`voice`、`game`、`tavern`、`mixed`、`unknown`；它不能把 `comic` 改名为 `manga`。`category`/`sourceCategory` 描述来源分类，支持 feed、article、doujin、gallery、illustration、anime、aiDrama、jav、adult、shortvideo、recording、live、asmr、novel、tavern、game、onlineGame、other，二者不能混为一谈。`metadataOnly`、`reverseSearchOnly`、`rankingOnly` 是 `CapabilitySnapshot` 能力限制，不是普通作品分类。

能力快照保存的是作品当时可用能力，并不等同于 source manifest 当前能力；缓存可能过期，API 必须在执行操作前重新校验当前 manifest。metadataOnly 内容不能被当成普通可播放作品。快照额外覆盖 ranking、metadata、comments、album、subscriptionUpdates 和 postShortVideos。

`capability_json` 保存完整 `CapabilitySnapshot`，包含必需布尔字段、`capturedAt` 和 `sourceVersion`，并可带插件协议声明的附加布尔标记。它不是 `Record<string, boolean>`；禁止把时间和版本强制转换成能力开关。`metadataOnly`、`reverseSearchOnly`、`rankingOnly` 不改变作品的 mediaKind/category。

历史继承 `WorkIdentity`，`chapterId`、`chapterTitle`、`page`、`pageCount`、`position` 都可选，因此可以表达作品级历史、章节级历史、单集视频和无章节作品。`Chapter` 仍独立保存阅读状态、页进度以及视频位置/时长，阅读和视频语义互不覆盖。

## 下载状态机与租约 fencing

允许迁移如下：

```text
queued   --start-->   running --complete--> completed
                         |  \--fail-------> failed --retry--> queued
                         |  \--pause------> paused --resume--> running
queued/running/paused/failed --cancel--> cancelling --cancelled--> cancelled
```

`nextDownloadStatus`、`canTransitionDownloadStatus` 和 `assertDownloadTransition` 是纯函数，非法迁移没有目标状态。`checkpoint`、`recoverable`、`retryCount`、更新时间和状态用于重启恢复。

`TaskLease.leaseGeneration` 是 fencing token。任务写入前 DATA-002 必须调用 `canWriteWithLease(lease, { taskId, leaseOwner, leaseGeneration, now })`，同时校验 taskId、leaseOwner、generation、有效时间和未取消；任一身份不匹配、时间无效或租约过期都失败。重新获取租约会递增 generation，旧 Worker 即使仍在运行也必须被拒绝。

实际文件使用 `DOWNLOAD_DIR/sha256(taskId)/000000.bin`；HLS 本地清单使用相应序号的 `.m3u8`，清单只引用同目录相对分片，AES 密钥不落盘。`download_files.resource_key` 精确绑定 `task.resource_key + ':file:N'`，checkpoint 保存已提交文件的 SHA-256。写入先用受控 `.part`，完整校验、同步和原子重命名后才提交文件记录与进度。漫画图片复用宿主解密与格式校验，文件 hash 对应实际解密后的离线字节；原生媒体保持流式写入。

数据目录从 Windows 迁移到 Docker 或更换下载根时，启动按稳定 taskId、文件序号与严格后缀计算当前根中的唯一位置，并更新数据库 path；原绝对根不会被读取、复制或删除。完整文件核对大小和启动 SHA-256，未完成文件按 checkpoint 续传。缺失文件标记 `FILE_MISSING`；身份或物理位置无法唯一确认标记 `DOWNLOAD_PATH_INVALID`，保留失败与删除意图，不能伪装完成。删除也使用同一规范路径计算，只处理当前下载根中的文件。

## 事件、全局 SSE 游标与重复消费

`DomainEvent` 不包含 delivered/read 等可变状态，事件本身保持不可变。字段含义严格区分：`sequence` 是跨作品、下载、订阅、插件和账号事件的全局单调序号；`aggregateVersion` 是实体版本；`eventVersion` 是单个聚合事件流版本，三者不能混用。

`GlobalEventCursor.afterSequence` 用于 SSE 全局重放，`eventCursorAfter` 返回该游标；DATA-002 应按 `sequence > afterSequence` 查询所有聚合事件，按 sequence 顺序重放，再把最后一条 sequence 返回给客户端。需要只重放单个聚合时使用 `AggregateEventCursor`、`aggregateEventCursorAfter` 和 `isEventAfterAggregateCursor`。

`SubscriptionEvent` 是不可变的订阅内容事件，只记录 eventId、订阅、内容、观察时间、内容版本和可选 payload，不包含 delivered/read。`EventDelivery` 按 consumerId 记录某次投递/处理，`EventReadState` 仅按 eventId 保存单用户实例的持久已读，不绑定页面身份。多个标签页可以分别收到同一个 eventId；消费端以 eventId 去重，UI 已读状态独立存储，二者不能混为一谈。

领域 EventType 固定为 `work.updated`、`chapter.progressed`、`collection.changed`、`download.statusChanged`、`subscription.updated`、`subscription.contentSeen`、`plugin.installed`、`account.updated`。下载进度继续使用 `download.statusChanged`，订阅检查使用 `subscription.updated` 加 `kind:'check'`，不新增临时事件枚举。成功检查即使为空也建立 baseline；只有后续首次出现的真实内容才进入 `subscription_events`，并与领域事件共用 eventId。检查状态事件不能增加内容未读数。SSE 的 `sync.required` 仅是失效游标的传输控制信号。

`isStableDownloadVariant`/`assertStableDownloadVariant` 拒绝空字符串、超过 128 字符、控制字符、`http://`/`https://`/协议相对 URL 及所有匹配 `/^[A-Za-z][A-Za-z0-9+.-]*:/` 的 URI scheme（包括 data、mailto、javascript 和其他 scheme）。variant 只能是 `original`、`compressed`、`stream` 或站点定义的稳定画质/音质/格式/字幕标识；临时签名 URL、HLS 清单、Token 和请求参数不得进入 variant。临时签名 URL、HLS 密钥、验证 HTML、反搜上传内容均不进入领域实体或事件 payload。

## 错误结构和未来数据库映射

`DomainError` 固定 `code`、`messageKey`、`retryable`、`requestId`、`operation`、`causeCategory`，可选 `source` 与结构化 `details`。API 可将其序列化为 JSON；领域层不决定 HTTP 状态码或本地化文本。

当前 SQLite 表与领域实体保持以下名称一致：`works`、`chapters`、`history`、`categories`、`work_collections`、`source_registry`、`source_settings`、`source_accounts`、`app_settings`、`download_tasks`、`download_files`、`deletion_intents`、`task_leases`、`restore_checkpoints`、`subscriptions`、`subscription_checks`、`subscription_seen`、`subscription_events`、`domain_events`、`event_outbox`、`event_deliveries`、`event_read_states` 和 `idempotency_records`。不使用独立的 `work_categories` 或 `source_installations` 表：作品分类关系保存在 `work_collections.category_ids_json`，插件安装状态保存在 `source_registry.manifest_json` 与其启用状态中。必须为复合身份、资源键、写请求幂等键、全局 sequence、聚合版本/事件版本和 leaseGeneration 建立唯一或并发约束。

## 可重复验证

历史领域测试编译领域包并运行行为测试，临时目录由根目录 `/test/` 忽略规则保护。包的 scripts 目前只提供 typecheck，不提供不存在的 package test 入口。正式构建使用 `pnpm build`，类型检查使用 `pnpm typecheck`；两者都不能替代领域行为与集成功能验证。

## DATA-004/005 服务约束

下载控制只允许冻结状态机定义的迁移，暂停、恢复、重试、取消和删除意图均使用 `operation + requestKey` 幂等记录；worker 扫描不会执行 `paused` 任务，`cancelling` 任务在安全点收敛为 `cancelled`。删除意图在文件删除与任务清理完成后才标记完成，重启时可继续处理。

订阅检查依据明确的 baseline 标记决定首次检查，不能用 seen 条目是否非空推断。后续新内容才写入 `subscription_events`，检查本身另发已有类型的状态事件。事件已读使用实例共享的 `event_read_states(eventId)` 唯一键，多标签通过 SSE 同步；重复标记不产生第二条状态或重复事件。软删除订阅保留历史事件，禁用状态不参与调度；重新创建相同目标时重新建立基线。

Server 会话使用 `HttpOnly; Secure; SameSite=Strict` 会话 Cookie 与独立 CSRF Cookie；写请求检查 Origin、CSRF 和进程级速率窗口。设置保存使用单调版本号，年龄确认、应用锁和锁定超时在 API 边界校验。备份导入在事务 savepoint 中合并，任意记录失败会回滚整个导入。诊断不包含 Cookie、Token、签名 URL 和私有内容；默认备份同样排除凭据，显式 accounts/cookies 分区才包含用户选择的持久敏感数据。

## DATA-006/007 适配与恢复

SourceHost 适配器只发送稳定的 `source + workId + chapterId + variant + resourceKey` 或 `source + dimension + target` 身份；响应会再次校验身份。网络、超时和宿主不可用错误可重试，认证/验证/协议/身份错误为永久失败。没有 SourceHost 时 API 返回稳定的不可用错误，不伪造成功结果。

worker 停止时先停止新扫描并取消活动调用，等待有超时与信号约束的处理回调、释放本进程租约，再结束调度；租约重新获取递增 generation，旧 generation 写入被 fencing 拒绝。没有发布器时不会把 outbox 伪标已发布，进程重启后继续发布未提交项。

## JSON 备份与物理迁移

格式固定为 `hentai-park-web-backup`、manifest version 1，分区枚举见 `WEB_API.md`。默认完整稳定分区不包含账号、Cookie 或下载元数据，用户可分别显式加入。恢复 works 的公开元数据、章节类型与字幕关联、作品级 null 历史、分类收藏、订阅基线、内容事件与已读状态；SQL 布尔 0 必须保持禁用，不以 `=== false` 误判。

导入先严格校验全部结构，再在同一 savepoint 中按稳定身份合并。缺失外键、未知字段、临时授权、签名 URL 或任意本地 path 都不能静默跳过。已有较新的阅读进度和未选中的本地数据保留；恢复的源注册保持禁用，只有可信安装的插件可运行。JSON 下载分区不含真实文件、租约和活跃检查点，恢复后明确标记 `BACKUP_FILES_NOT_INCLUDED`，不能宣称离线文件已经恢复。包含文件与插件私有状态的实例搬迁须迁移完整持久化目录，并停止写入后复制 SQLite 及其必要状态；不导入移动端资产。

## 集成验证证据边界

`test/int-worker.mjs`、`test/int-worker-process.mjs`、`test/int-worker-encrypted-image.mjs`、`test/int-worker-data-root.mjs` 覆盖真实 HTTP 文件字节、持久化重开、进程强杀恢复、租约、图片解密与物理根迁移；`test/int-backup.mjs` 覆盖数据库往返和导入失败回滚。这些受忽略目录保护的专项证据不能替代外部站点账号、Docker 平台及全部产品功能的最终验收，最终结论以[验收边界](ACCEPTANCE.md) 为准。


## 迁移10至14

迁移10新增小说UTF-16位置、小说笔记、分类排序、作品真实内容更新时间、订阅跨批扫描/内容关联及词包/酒馆持久化；将旧viewer/tab任一已读合并为eventId单事实。迁移11新增有限直播录制参数和反搜结果历史；迁移12新增用户显式保存的私有查询图，迁移13保存酒馆会话的非秘密设置；迁移14新增独立模型连接及世界书术语包。旧迁移历史保持，未知高版本仍拒绝。

漫画同章节版本下合并最大页码，非法页码拒绝；视频允许有效回看；小说以服务器实际正文长度约束UTF-16偏移。作品抓取时间和contentUpdatedAt分开，首次完整目录建立基线不当作新章节更新。

下载metadata保留kind/format/transform，本地hash校验、完整资源计划指纹、插件内容身份和账号上下文共同决定续取。实际计划变化或本地损坏时重取未完成资产；不能据同URL推断远站内容永远不变。已完成任务不因远站重解析而删除。离线访问不依赖远站或临时授权，仍受本机实例会话与真实路径/大小校验约束。

私有Host文件是当前账号、Cookie和源设置事实；SQL中的source_accounts/source_settings是一次性待导入队列。导出不写镜像，持久失败保留队列，恢复普通源设置保留未导出的密码、账号和Cookie。普通备份不含下载文件，恢复下载元数据明确不可恢复，不假装文件存在。标签词包独立导入导出，临时媒体/附件缓存不混入业务备份；世界书术语包按原schema2完整放入默认备份。模型连接的非秘密设置默认导出，API密钥只有显式选择敏感分区才导出；目标实例以自己的AES-GCM密钥重新加密，绑定endpoint，普通恢复不覆盖未导出的私密列。备份专用导入/预览接口上限128MiB，导出使用紧凑JSON并预留封装空间；超过上限明确要求按分区分别导出，不产生无法重新导入的成功假象。
