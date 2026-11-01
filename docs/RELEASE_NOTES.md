## 中文

### 修复
- 修复隐藏页面和列表预缓存区域仍可能自动加载下一页的问题。
- 修复多语言搜索无法继续翻页、空页后提前结束及重复分页链接的问题。
- 修复刷新失败后已有浏览和搜索结果被清空的问题，失败时保留内容供继续阅读和重试。
- 修复播放器失去焦点、被弹层遮挡、切到后台或锁定后临时倍速未恢复，以及取消按键时误跳进度的问题。
- 修复取消图片反搜裁剪或图片处理失败后已有识别结果被清空的问题。
- 修复打开已完成漫画时可能联网补充缺失内容的问题，已完成下载保持离线读取，未完成漫画仍可边下边读。

## English

### Fixes
- Fixed hidden pages and prefetched list items triggering automatic pagination.
- Fixed multilingual search failing to load subsequent pages, stopping after empty pages, and accepting repeated pagination links.
- Fixed failed refreshes clearing existing browsing and search results. Content now remains available for reading and retrying.
- Fixed temporary playback speed persisting after focus loss, an overlay, backgrounding, or app locking, and unintended seeking when a key press is cancelled.
- Fixed existing image search results being cleared when cropping is cancelled or image processing fails.
- Fixed completed comic downloads fetching missing content online. Completed downloads remain offline, while unfinished comics still support reading during downloads.
