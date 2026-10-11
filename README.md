[简体中文](README.md) · [繁體中文](docs/i18n/zh-Hant/README.md) · [日本語](docs/i18n/ja/README.md) · [한국어](docs/i18n/ko/README.md) · [English](docs/i18n/en/README.md) · [Español](docs/i18n/es/README.md) · [Русский](docs/i18n/ru/README.md) · [العربية](docs/i18n/ar/README.md)

<p align="center">
  <img src="docs/images/banner.svg" alt="HentaiPark" width="100%">
</p>

<div align="center">

[![Release](https://img.shields.io/github/v/release/drdon1234/Hentai-Park?label=下载)](https://github.com/drdon1234/Hentai-Park/releases/latest)
![Android](https://img.shields.io/badge/Android-7.0%2B-3DDC84?logo=android&logoColor=white)
![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)

</div>

> [!WARNING]
> 本应用涉及成人内容，仅限成年人在当地法律允许的范围内使用。所有内容均来自第三方站点，App 本身不存储也不提供任何内容。

## 截图

<p align="center">
  <img src="docs/screenshots/home.jpg" width="24%">
  <img src="docs/screenshots/multi_language_search.jpg" width="24%">
  <img src="docs/screenshots/continue_reading.jpg" width="24%">
  <img src="docs/screenshots/blocklist_presets.jpg" width="24%">
</p>

## 支持的源站

| 源站 | 类型 | 说明 |
|------|------|------|
| E-Hentai / ExHentai | 漫画 | 网页登录后可切换里站 |
| nhentai | 漫画 | |
| 禁漫天堂 | 漫画 | 支持车号直达，线路自动切换 |
| 哔咔漫画 | 漫画 | 自行配置账号，或确认后自动注册专用账号 |
| Hanime1 | 视频 | 首次使用可能需要通过 Cloudflare 验证 |

源站以插件形式加载，可在设置中添加第三方源。

## 功能

- **聚合搜索**：一次搜索所有源站；粘贴链接或输入车号（如 `JM350234`）直接打开作品
- **多语言搜索**：自动把关键词翻译成中 / 日 / 韩 / 英等多种语言一起搜索
- **书架与更新**：多分类收藏，自动检查连载更新并推送通知，可自动下载新章节
- **阅读器**：条漫 / 翻页 / 日漫模式，双页、裁白边、护眼滤镜，音量键翻页
- **视频播放**：清晰度切换、倍速、记忆播放进度；左右侧上下滑动调整亮度与音量，横向拖动调整进度；支持横屏及竖屏全屏、正反方向旋转
- **下载**：按章节下载漫画、按清晰度下载视频；支持导入导出 CBZ
- **换源迁移**：把收藏迁移到另一个源，保留阅读进度
- **屏蔽标签**：自定义屏蔽，并提供可按需启用的预设分组
- **隐私保护**：应用锁、无痕模式、封面模糊、防截屏
- **备份恢复**：一键备份书库、进度与设置，支持定时自动备份
- **八语言界面**：简体中文、繁体中文、日语、韩语、英语、西班牙语、俄语、阿拉伯语；支持跟随系统和即时切换，阿拉伯语采用从右到左布局

## 下载

前往 [Releases](https://github.com/drdon1234/Hentai-Park/releases/latest) 下载最新版本。不确定选哪个时，大多数手机请选择 `arm64-v8a` 版本。

## 开始使用

1. 在「发现」选择源站，或使用搜索栏搜索作品、粘贴作品链接、输入车号。多语言搜索保留原始关键词和检测到的源语言，同时显示翻译关键词。
2. 在「我的 → 语言 → 界面语言」选择语言。默认跟随系统；修改会立即生效并保存在本机，不影响作品原始标题、标签或已保存的用户数据。
3. 在「我的 → 源站管理」启用、排序及配置源站。哔咔未配置账号时，「发现」会显示提示，可进入自行配置或启用专用自动维护账号。
4. 开启哔咔「使用专用自动维护账号」时会弹出注册确认。确认后马上创建专用账号并登录，后续登录状态由应用维护。关闭开关会保留专用账号；重新开启可复用，已有手动账号不会被覆盖。注册失败可重试同一账号。
5. 漫画详情页可以收藏、选择分类及下载章节；「书架」整理收藏，「更新」检查新章节，「历史」和继续阅读恢复进度。「我的 → 备份与恢复」可以导出数据，恢复时与当前数据合并。

视频页左侧上下滑动调亮度、右侧上下滑动调音量，横向滑动预览进度，松手后跳转。播放控制提供横屏和竖屏展开，旋转屏幕时操作区随显示方向调整。阅读器支持上下滚动、从左到右或从右到左翻页，阅读方向由阅读器设置决定。

## 常见问题

**哔咔 / ExHentai 无法使用？**
哔咔需要自行配置账号或确认注册专用自动维护账号；ExHentai 需要网页登录，而且账号本身必须具备里站权限。

**图片加载慢或失败？**
可在设置中配置 HTTP 代理；禁漫 / 哔咔可尝试切换图片分流。

**Hanime1 一直转圈？**
按提示在内置浏览器中完成 Cloudflare 验证即可。

## 开发

```bash
flutter pub get
flutter build apk --release --split-per-abi
```

想为新站点编写源插件，请参考 [源插件开发指南](docs/SOURCE_API.md)。内置源插件版本从 `0.0.1` 开始；应用版本与插件版本分别管理。
