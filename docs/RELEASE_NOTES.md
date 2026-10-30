## 中文

### 新功能
- 图片反搜新增历史，可载入最近搜索图片、逐条删除或清空，无痕模式不记录。
- 搜索结果新增临时显示已屏蔽内容的图标开关，聚合搜索与站点搜索均可使用。
- 站点列表、搜索与订阅页面支持隐藏原站明确标记为仅预览的内容。
- 新增 AI 生成预设屏蔽组，播放器新增同系列快捷入口。

### 改进
- 增加播放期间的本地暂存容量，HLS 长视频持续保留近期分段，减少回拖等待。
- 读取页面遇到短暂连接故障或网关错误时自动有限重试。

### 修复
- 改善 Android 选图返回后偶发的图片处理失败。
- 修复播放器更多菜单在部分布局下为空的问题。
- 从聚合搜索进入站点结果时保留已有搜索结果，避免重复初始化搜索。
- 修复部分列表标签不完整导致屏蔽规则漏匹配的问题。

### 插件更新
- E-Hentai 0.0.14、哔咔 0.0.11：保留完整列表标签用于内容过滤。
- iXXX 0.0.17：识别列表中明确标注的预览结果。

### 注意事项
- 反搜历史图片保存在本机，未加密且不包含在应用备份中，可在反搜历史中删除。
- 预览过滤只依据站点提供的明确标记，不会自动判断未标明的内容。

## English

### New
- Image search history can reload recent search images, delete individual entries, or clear all entries. Incognito mode does not record images.
- Aggregate and individual site search results include an icon to temporarily show blocked content.
- Site listings, searches, and subscription pages can hide content explicitly marked as preview-only by the site.
- Added an AI-generated blocking preset and a series shortcut in the video player.

### Improvements
- Increased temporary playback cache capacity and continuously retain recent HLS segments during long videos to reduce backward-seek delays.
- Page reads automatically retry temporary connection failures and gateway errors a limited number of times.

### Fixes
- Improved occasional image processing failures after returning from the Android image picker.
- Fixed empty player menus in some layouts.
- Preserve existing results when opening individual site results from aggregate search, avoiding a duplicate initial search.
- Fixed missed blocking matches caused by incomplete tags in some listings.

### Plugin updates
- E-Hentai 0.0.14 and Pica 0.0.11: preserve complete listing tags for content filtering.
- iXXX 0.0.17: recognize explicitly labeled preview results in listings.

### Notes
- Image search history is stored locally without encryption and is excluded from app backups. Images can be deleted from history.
- Preview filtering relies on explicit site labels and does not infer availability for unlabeled content.
