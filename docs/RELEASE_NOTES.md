## 中文

### 改进
- 重做纯音频播放界面，缩小控制区、扩大字幕区域，独立展示选集，将后台播放和拼接放入播放设置。
- 拼接播放按曲目加载音频和字幕，减少开启等待；各曲时长完整后显示总进度。
- 音声目录恢复卡片展示，无封面时显示耳机图标，目录内保留分层浏览。
- 视频信息区增加常驻选集入口，缩短标题与简介之间的留白；普通点播画面支持左右双击快退和快进。
- 短剧播放适应播放接口返回的 CDN 地址变化。

### 修复
- 修复 ASMRHoney 普通作品误入目录导致无法播放的问题。
- 修复 Hentai ASMR 默认只展示中文字幕分类的问题，默认浏览全部作品。
- 改善 ASMR Gay、ASMR Moon 搜索，默认查找目录并提供文件筛选。
- 修复 Honey 筛选候选不随地区和内容类型联动的问题，合并 EroASMR 重复浏览入口。

### 插件更新
- ASMRHoney 0.0.4、ASMR Gay 0.0.4、ASMR Moon 0.0.4、Hentai ASMR 0.0.3、EroASMR 0.0.3。
- 黄豆短剧 0.0.11、黄果短剧 0.0.14、91短剧 0.0.11。

### 注意事项
- 未读取所有曲目时显示当前曲目进度，可通过选集或字幕中的曲目标题跳转；切换曲目可能短暂缓冲。

## English

### Improvements
- Redesigned audio-only playback with compact controls, more subtitle space, a separate track selector, and background and joined playback in settings.
- Joined playback loads audio and subtitles per track to reduce startup waits; the combined timeline appears once all track durations are known.
- Restored cards for audio directories, with headphone icons for missing covers and hierarchical browsing inside folders.
- Added a persistent episode selector below videos, reduced the title-to-description gap, and enabled double-tap seeking at the sides of regular on-demand videos.
- Short-drama playback adapts to CDN addresses returned by playback services.

### Fixes
- Fixed ordinary ASMRHoney works incorrectly opening as directories and failing to play.
- Fixed Hentai ASMR defaulting to the Chinese-subtitled category; browsing now defaults to all works.
- Improved ASMR Gay and ASMR Moon search with directories selected by default and an optional file filter.
- Fixed Honey filter choices not following region and content type, and merged duplicate EroASMR browsing entries.

### Plugin updates
- ASMRHoney 0.0.4, ASMR Gay 0.0.4, ASMR Moon 0.0.4, Hentai ASMR 0.0.3, EroASMR 0.0.3.
- Huangdou 0.0.11, Huangguo 0.0.14, 91 short dramas 0.0.11.

### Notes
- Until all tracks have been opened, the progress bar shows the current track. Use the track selector or track headings in subtitles to jump; switching tracks may briefly buffer.
