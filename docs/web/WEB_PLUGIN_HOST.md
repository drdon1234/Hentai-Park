> 路径约定：本文 `apps/`、`packages/`、`scripts/` 相对 `clients/web`；共享插件协议为 [SOURCE_API](../SOURCE_API.md)。历史测试路径属于原 Web 工作区，仅作证据引用，当前验证见 [ACCEPTANCE](ACCEPTANCE.md)。

# Web 插件宿主

协议依据为本仓库SOURCE_API.md、未修改的共享Park SDK及原宿主行为。2026-11-14经用户授权修正Web新增约束：feed为合法分类；videos与webVideo可并存；album与频道订阅、更新订阅独立；media.scope支持session。类型、JSON Schema、手写校验与单一运行时转换同步维护，不修改插件或SDK迁就宿主。真实inspect生成的可信索引为101项、拒绝0项；索引通过不代表101个外站全部可用。

API经SourceCatalog/SourceOperations调用SourceHost；source-runner为独立受限Node进程，插件和共享SDK在QuickJS WASM执行。JSON-RPC不注入Node、宿主函数、文件系统、进程或原生网络对象；保留内存、栈、超时、Node permission、请求取消、池上限、空闲回收、崩溃与进程退出释放。可信安装校验SHA、版本、实际inspect manifest，使用不可变包和事务日志恢复/回滚。

执行截止由宿主为每个RPC签入deadlineAt，并与宿主取消定时器使用同一预算（上限300秒）；runner校验该字段，执行与pending jobs使用最早在途请求截止，不按任意1秒片段截断合法解析。启动独立5秒、无在途请求后台任务1秒仍有界；QuickJS堆64MiB和栈512KiB限制保留。引擎实际中断事实一旦触发即锁存并回收进程，返回可重试TIMEOUT，不能被SDK捕获后变为PARSE；普通异常即使含interrupted字样也不伪装截止。stdout用增量UTF8解码，已signal终止的runner晚到close直接完成，dispose终止态不会复活。

网络权限分开处理：

- homepage是展示/发布入口，不要求属于来源Cookie域。原生公开请求可访问插件解析出的其他公网HTTPS目的地，支持发布页、候选过滤及公开上游解析；插件自己的业务身份检查仍执行。Cookie自动读写及导入仅限manifest.domains；外部请求不获得来源Cookie罐。插件为公开上游显式生成的请求头独立于Cookie自动导入，重定向统一执行方法/正文转换与非敏感头白名单，不依赖秘密头名称黑名单。
- 原生每次及每跳检查HTTPS、无用户凭据/非标准端口、全部DNS结果的公网属性，TLS连接钉扎已检查IP；保留时间、响应/解压大小及取消限制。公开跨域不授予浏览器导航、文件系统或进程权限。
- 登录、验证及站点浏览器会话继续按来源和登录导航声明约束。网页播放使用服务端实际webVideo返回的目标、navigationDomains/frameDomains建立独立临时context；不要求将当次目标复制到静态Cookie域。主框架与子框架分别检查；当次session媒体只对该播放器的媒体/图片/XHR子请求开放公网资源，其他子资源仍按临时声明边界检查。不导入或导出来源账号/Cookie；弹窗、下载、WebSocket、service worker继续阻断。
- 图片按服务端实际插件输出建立不透明授权，可来自公开HTTPS CDN。media.scope=session按实际videos节点、清单及逐跳重定向派生临时资源链，不使用固定CDN域代替本次授权。静态media.domains仍约束非session媒体。前端只提交authorizationId/稳定资源身份，不能自行声明URL、scope或域名。

媒体token绑定会话、source、稳定资源tuple及最长5分钟TTL；HLS主/子清单、MAP、分片、密钥重写为不透明子资源。插件format=hls支持text/plain/octet-stream和无扩展名的合法清单，必须校验EXTM3U及大小；声明格式不能让任意文本变成媒体。播放与下载均按已验证的最终清单地址解析相对URI；逐跳校验及跨源头部剥离不关闭；GET/HEAD/Range、图片解密/格式检查和20MiB限制保持。`playback-origin`专用x-*头经实际返回节点的WeakMap context绑定，只发给初始媒体origin；复制对象不能新造context。上下文、临时URL、密钥不进入实体、检查点、默认备份或日志。断开请求、锁定/注销/关闭服务会中止活动传输，来源停用/宿主释放/TTL撤销context。

播放优先videos。仅双能力且videos返回UNSUPPORTED时进入webVideo；HTTP、NETWORK、PARSE、AUTH/LOGIN、VERIFICATION/CLOUDFLARE、TIMEOUT、CANCELLED均显示原错误。原生解析未成功时不签发原生播放授权；前端切换/卸载先停止原播放器和请求。下载独立调用videos，不回退网页。远端网页返回同源画面、实际Opus音轨、状态与有限控制；不能捕获的音轨明确失败。网页关闭、断流、锁定、注销、版本变化和服务退出释放context，未领取5秒、领取后空闲90秒释放。

文章按type=article分发，browseLayout仍只有list/grid。真实detail的有序blocks/tagLinks严格校验并仅在有界内存缓存，不存正文或短期媒体地址；作品/收藏/历史持久化摘要和稳定进度。图片通过opaque授权；视频块只保留稳定ID，播放时重新调用videos(articleId,mediaId)，切换和离页释放。

相册只调用subscription.media(scope,{page,cursor})，scope为target、feed/options/common或search/keyword/filters/common，绝不回退subscription.posts或chapter。完整媒体保留稳定ID、presentation、日期、原站预览/锁定语义和跨页合并/order；游标绑定来源不可变包、范围与实例会话，重复上游游标明确失败。附件经subscription.mediaChunk按128KiB对齐读取，逐块校验，单项512MiB/缩略图2MiB，宿主控制缓存路径及原子完成，取消清理part；资源描述及秘密引用不持久化。

network.confirmation仅执行声明的gate/ready、checkbox、成年日期与确认动作；成功后检查requiredCookies，失败/取消释放浏览器。真实外站、私人账号、挑战与实体设备条件分别记录，受控HTTP和后台自动化不能替代这些条件。

## 重定向与媒体凭据边界（AUDIT-001、AUDIT-018）

原生请求、浏览器代理与资源传输共用transport-policy。301/302仅POST转GET，303除HEAD外转GET；转换时移除正文及内容头。307/308与保留方法的301/302不会跨origin重放正文或非GET/HEAD。同源有副作用重放必须显式followRedirects。跨origin仅保留User-Agent、Accept、Accept-Language、Accept-Encoding、Range、Cache-Control、Pragma，所有其他头移除；原生链一旦跨origin，后续跳转不再从来源Cookie罐重新注入凭据，即使目标也在domains中。直接请求授权账号域、同origin合法跳转仍保留Cookie。目标每跳重新检查HTTPS、公网DNS/IP钉扎及权限，最多5跳，取消关闭响应。

浏览器使用Chromium CDP Fetch逐请求拦截，覆盖重定向、子框架及worker；普通Playwright route只拦首跳，不能充当这一安全边界。未安装拦截不能创建可用页面；浏览器原生DNS禁止绕过代理，service worker/WebSocket继续阻断。页面重导航时已关闭子target不再执行关闭操作，避免清理竞态中断新导航。

原生媒体和图片均不自动读取或写入来源Cookie，不附加账号Authorization，也不自动制造Origin/Referer。显式Origin必须精确为来源声明域的HTTPS origin；仅Referer可使用media.referrerDomains的例外。图片Origin/Referer使用来源域和imageNetwork.domains，不继承原生media例外。原生专用x-*头须声明playback-origin并来自实际插件返回节点，仅初始媒体origin可接收。跨origin、授权刷新、HLS密钥/分片、Range和下载不扩大权限。来源账号网络与登录浏览器保留各自合法Cookie行为。证据及未验证项以ACCEPTANCE.md 中记录的历史边界为准。


本轮补齐AES-GCM、API版本、真实browser/auto通道、动态候选空值及多参数方法，源设置/账号/网页导入和在线包预览安装均走共享Host。图片保持原生优先、受限浏览器回退；原生媒体保持无站点Cookie。新代码证据见历史修复记录，历史快照不能证明这些新增链路已验。

声明式确认由共享confirmPage执行：先校验并填写声明控件，再定位确切按钮，通过浏览器真实点击等待导航稳定。只有文档变化后才允许下一阶段确认，同一文档不重复副作用；未声明字段、非安全同源动作及私网目标仍拒绝。页面导航导致上下文销毁属于网络执行失败，不冒报插件解析错误；主动取消和截止超时保留原分类。受控确认场景与真实公开来源的验证分别记录，不把人工挑战推断为已解决。

浏览器网络请求区分origin会话预热与目标内容：符合条件的同源HTML GET在目标文档完成确认并消费已加载页面，目标异步gate/ready仍有界等待。首页不必具有目标的业务就绪标记；确认已导航到目标时直接复用，并在首次目标传输保留允许的请求头。POST、HEAD、API敏感头、base64和资源请求保持fetch语义，不为通过门控重放副作用；资源凭据隔离不随文档导航分支扩大。

原生请求统一补缺省User-Agent，按大小写无关检查保留插件显式值。整合浏览器工作器从已锁定Playwright的Chromium元数据生成桌面UA，原生、普通与持久化受控浏览器使用同一身份，不硬编码浏览器版本或额外启动探测浏览器。独立SourceHost未整合浏览器时使用公开软件标识。媒体、图片、直播与模型流共用缺省头规则，但不因此导入来源账号、Cookie或跨源授权；公开UA与敏感凭据的重定向策略仍分开处理。
