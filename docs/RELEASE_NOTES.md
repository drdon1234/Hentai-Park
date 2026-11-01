## 中文

### 新功能
- 站点浏览新增卡片与详细单行列表切换，默认使用卡片。

### 改进
- 统一筛选、相册、短视频和其他工具按钮样式，搜索筛选与多语言搜索不再单独占行。
- 标签更紧凑，分组标题与首行标签对齐；显示与过滤开关增加底部即时提示。
- 播放器统一使用右上角选集按钮，移除旧的同系列切换和独立选集栏，减少重复菜单；保留亮度和音量调节条样式并显示当前数值。
- 短剧在滑动落定后切换选集，并短暂保留上一集，减少误滑返回时的等待。
- 短视频的仅视频与带信息切换移至右下角，简介与进度条排列更紧凑。

### 修复
- 修复连续进入关联作品后旧播放页累积媒体资源的问题，返回时重新加载并恢复进度。
- 长标题支持完整翻译，翻译失败时显示提示并保留原文。
- 修复切换短剧选集后立即退出全屏时显示旧集标题或黑屏占位的问题，等待期间显示加载状态。
- 修复短视频模式未正确显示 Android 系统导航栏的问题。
- 相册和视频帖模式入口仅在支持对应功能的创作社区显示。

### 插件更新
- Pixiv 0.0.15：推荐结果去重，补充稀疏漫画结果，并在推荐批次重复时停止继续加载。
- Baidu 0.0.6：正确提示图片上传被拒绝，避免误报结果解析失败。

## English

### New
- Site browsing now supports cards and detailed single-row lists, with cards as the default.

### Improvements
- Unified filter, album, short-video, and other toolbar buttons. Search filters and multilingual search no longer occupy separate rows.
- Made tags more compact and aligned group headings with the first row. Display and filter toggles now show immediate feedback near the bottom.
- Unified episode selection in the upper-right button, removed the old series switch and separate episode bar, and reduced duplicate player menus. Brightness and volume bars retain their appearance and now show current values.
- Drama episodes switch after a swipe settles and briefly retain the previous episode to reduce waiting when reversing an accidental swipe.
- Moved the video-only and information toggle to the lower right and brought descriptions closer to the progress bar.

### Fixes
- Fixed media resource accumulation when opening related works repeatedly. Returning reloads playback and restores progress.
- Long titles can be translated in full. Translation failures show feedback and preserve the original text.
- Fixed stale episode titles or black placeholders when leaving fullscreen immediately after changing drama episodes. A loading indicator is shown while waiting.
- Fixed Android system navigation bar visibility in short-video mode.
- Album and video-post mode entries now appear only in creator communities that support them.

### Plugin updates
- Pixiv 0.0.15: deduplicate recommendations, fill sparse manga results, and stop loading repeated recommendation batches.
- Baidu 0.0.6: correctly report rejected image uploads instead of a result parsing failure.
