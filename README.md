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
| 哔咔漫画 | 漫画 | 需要账号登录 |
| Hanime1 | 视频 | 首次使用可能需要通过 Cloudflare 验证 |

源站以插件形式加载，可在设置中添加第三方源。

## 功能

- **聚合搜索**：一次搜索所有源站；粘贴链接或输入车号（如 `JM350234`）直接打开作品
- **多语言搜索**：自动把关键词翻译成中 / 日 / 韩 / 英等多种语言一起搜索
- **书架与更新**：多分类收藏，自动检查连载更新并推送通知，可自动下载新章节
- **阅读器**：条漫 / 翻页 / 日漫模式，双页、裁白边、护眼滤镜，音量键翻页
- **视频播放**：清晰度切换、倍速、记忆播放进度
- **下载**：按章节下载漫画、按清晰度下载视频；支持导入导出 CBZ
- **换源迁移**：把收藏迁移到另一个源，保留阅读进度
- **屏蔽标签**：自定义屏蔽，并提供可按需启用的预设分组
- **隐私保护**：应用锁、无痕模式、封面模糊、防截屏
- **备份恢复**：一键备份书库、进度与设置，支持定时自动备份

## 下载

前往 [Releases](https://github.com/drdon1234/Hentai-Park/releases/latest) 下载最新版本。不确定选哪个时，大多数手机请选择 `arm64-v8a` 版本。

## 常见问题

**哔咔 / ExHentai 无法使用？**
需要先登录对应源站的账号；ExHentai 还要求账号本身具备里站权限。

**图片加载慢或失败？**
可在设置中配置 HTTP 代理；禁漫 / 哔咔可尝试切换图片分流。

**Hanime1 一直转圈？**
按提示在内置浏览器中完成 Cloudflare 验证即可。

## 开发

```bash
flutter pub get
flutter build apk --release --split-per-abi
```

想为新站点编写源插件，请参考 [源插件开发指南](docs/SOURCE_API.md)。
