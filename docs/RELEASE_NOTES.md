## 中文

### 改进
- 音声播放页在小高度窗口和大字体下支持滚动，字幕与播放控制更易访问。
- 推荐作品按需加载，搜索、更新与存储页面加载失败后可重试。

### 修复
- 修复部分列表遇到空页或重复游标时提前结束、遗漏后续结果的问题。
- 修复视频切集、返回播放页和倍速设置失败后的状态恢复与资源释放问题。
- 修复下载、录制与 CBZ 导入中的并发操作和异常恢复问题，避免覆盖未完成的数据。
- 修复损坏配置文件恢复时覆盖此前保留原件的问题，并改进反搜历史加载失败后的重试。
- 在线游戏存档导入校验游戏与网站来源，避免向错误游戏或已跳转的网站写入存档。
- 修复登录、资源获取、备份与插件管理中的重复操作及页面退出后的状态更新问题。

### 插件更新
- 无码厂商 0.0.12、哔咔漫画 0.0.13、Eporner 0.0.12、电报 0.0.13：修复目录与分页完整性。
- MissAV 0.0.14、PornPics 0.0.12、Literotica 0.0.10：推荐内容独立加载，失败时可重试。
- 禁漫天堂 0.0.11：旧线路不可用时重新获取站点线路。
- SWAG 短视频 0.0.7：请求失败时正常提示错误，避免显示为空列表。
- XVideos 0.0.13：修复推荐内容接口识别错误。

## English

### Improvements
- Voice playback pages scroll in short windows and with large text, keeping subtitles and playback controls accessible.
- Related works load on demand, and failed searches, update checks, and storage measurements can be retried.

### Fixes
- Fixed lists ending early or missing later results after empty pages or repeated cursors.
- Fixed state recovery and resource cleanup when switching episodes, returning to playback, or changing playback speed fails.
- Fixed concurrent operations and failure recovery in downloads, recordings, and CBZ imports to avoid overwriting incomplete data.
- Fixed recovery of damaged configuration files overwriting previously preserved originals, and improved retrying failed reverse-search history loads.
- Game save imports validate the game and website origin to prevent writing saves to the wrong game or a redirected website.
- Fixed repeated operations and state updates after leaving login, resource retrieval, backup, and plugin management pages.

### Plugin updates
- Uncensored Studios 0.0.12, PicACG 0.0.13, Eporner 0.0.12, Telegram 0.0.13: fixed catalog and pagination completeness.
- MissAV 0.0.14, PornPics 0.0.12, Literotica 0.0.10: related content loads independently and supports retrying failures.
- JMComic 0.0.11: refreshes site routes when old routes become unavailable.
- SWAG Short Videos 0.0.7: failed requests report errors instead of appearing as empty lists.
- XVideos 0.0.13: fixed incorrect detection of the related-content interface.
