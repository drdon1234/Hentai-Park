> 路径约定：本文 `apps/`、`packages/`、`scripts/` 相对 `clients/web`；共享插件协议为 [SOURCE_API](../SOURCE_API.md)。历史测试路径属于原 Web 工作区，仅作证据引用，当前验证见 [ACCEPTANCE](ACCEPTANCE.md)。

# 浏览器原生行为与共享状态

页面导航、已提交搜索条件、source、scope、筛选和分页游标写入 URL。作品、章节和导航使用真实链接，保留前进/后退、刷新、新标签、中键和复制链接；滚动位置按完整 URL 保存。草稿、弹窗、视图偏好和未提交设置属于当前标签页。

收藏、进度、下载、订阅、主题和站点状态以服务端为事实来源。localStorage/BroadcastChannel 只传播失效通知，不保存或广播业务快照、签名地址和凭据。每个文档生成唯一 tabId，复制标签不会复用常量身份。没有 BroadcastChannel 时使用 storage 事件。

SSE 读取 event 行到 eventType，使用全局 sequence 作为 Last-Event-ID，按 eventId 去重。流持续推送并有心跳；断线退避重连，隐藏时释放非必要流，重新前台/online/pageshow 后重新校验服务端快照。过期/越界游标触发 sync.required 全量同步。快照刷新有合并、单飞和代次保护，避免事件重放放大请求或迟到快照覆盖新事实。

搜索由提交触发，草稿和输入法组词不请求；取消会中止实际 API/插件请求，迟到结果按代次丢弃。搜索游标绑定条件与来源版本，过期后显示可重试错误，不冒充空结果。

媒体只使用服务端登记的 source/resourceKey/authorizationId。请求 token 后经同源代理播放，网页不能自行指定上游 URL/域名；漫画可只重取失败页。进度按漫画页或播放时间串行、节流保存，在暂停/隐藏时补写，恢复后读取服务端事实。无痕时不写历史。页面关闭不会取消服务端下载或订阅检查。

Server 会话失效保留当前 URL，通过实例凭据重新认证；站点 LOGIN_REQUIRED 不会误清实例会话。Cookie 轮换、退出和应用锁超时撤销媒体授权与活动 SSE；应用锁活动信号与后台快照/媒体进度分开。

实际证据和剩余浏览器/站点限制见[验收边界](ACCEPTANCE.md)；CSS zoom 检查不等于操作系统原生缩放或实体读屏器验收。
