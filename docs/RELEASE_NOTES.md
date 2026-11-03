## 中文

### 新功能
- 运行日志新增 debug 模式，可仅本次开启或预约仅下次开启；预约生效时会在启动后提示。
- 新增长效日志开关，跨启动追加保存，达到 100 MiB 后淘汰最早记录；关闭后立即覆盖历史运行日志。

### 改进
- 短暂网络错误与服务器错误自动有限重试；播放在重新聚焦后恢复重试，下载和录制可继续在后台恢复。
- 动态筛选候选跨面板缓存，统一浏览与搜索筛选的普通标题、选项和大字体布局。
- 普通日志记录日常故障与恢复过程，debug 日志补充启动、请求耗时、缓存及播放状态，导出包含全部保留的运行日志。

### 修复
- 主页默认站点随站点顺序同步，恢复默认排序后立即更新。
- 修复黄豆短剧等视频复用过期播放地址导致首次加载失败的问题。
- 修复吃瓜筛选标题裁剪，补齐 EH 最新入口及 Danbooru 浏览入口实际支持的筛选条件。
- 媒体启动页接入现有无感验证交互，减少只等待验证而无法继续加载的情况。

### 插件更新
- E-Hentai 0.0.17。
- Danbooru 0.0.9。

## English

### New
- Added debug logging for the current session or the next launch only, with a startup notice when the scheduled mode activates.
- Added persistent runtime logs across launches, dropping the oldest records at 100 MiB; disabling this option immediately replaces runtime history.

### Improvements
- Transient network and server errors receive limited automatic retries; playback retries resume after focus returns, while downloads and recordings can recover in the background.
- Dynamic filter choices are cached across panels, with consistent section headings, choices and large-text layouts in browsing and search.
- Normal logs capture everyday failures and recovery; debug logs add startup, request timing, cache and playback state details, with all retained runtime logs included in exports.

### Fixes
- The default home site now follows site order and updates immediately when the default order is restored.
- Fixed initial playback failures caused by expired cached video addresses, including Huangdou dramas.
- Fixed clipped gossip filter headings and added supported filters to EH's latest feed and Danbooru's browsing feeds.
- Connected media startup pages to the existing automatic verification interaction so verification can continue beyond passive waiting.

### Plugin updates
- E-Hentai 0.0.17.
- Danbooru 0.0.9.
