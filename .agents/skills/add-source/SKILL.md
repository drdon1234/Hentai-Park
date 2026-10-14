---
name: add-source
description: 新增或大改一个 HentaiPark 站点插件（assets/sources/*.js）。在用户要求接入新站点、为站点补充浏览/搜索/播放能力，或重写某个插件时使用。
---

# 新增站点插件

协议细节以 `docs/SOURCE_API.md` 为准，本技能只给出顺序和容易遗漏的点。全程用中文与用户沟通。

## 1. 先调查，再声明

- 用真实请求摸清站点：首页有哪些入口（推荐 / 排行 / 热门 / 最新）、分页方式（页号还是游标）、搜索接口、详情结构、图片或视频地址、是否需要登录、Cloudflare 或年龄确认。
- 确定 `type`（comic / video / novel / game）和 `category`（doujin / gallery / anime / aiDrama / jav / adult / shortvideo / novel / game / other），只能二选一地准确声明。
- `defaultFeed` 按 **推荐 > 排行榜 > 热门** 选择，真的没有才用最新或其他有效入口。不得写没有验证过的接口。
- 中国大陆可能需要代理的站点声明 `network.vpnHint: true`。
- `domains` 只写站点自己的可注册域名；图片 CDN、媒体域名分别放进 `imageNetwork` / `media`，不要为了省事扩大 `domains`。

## 2. 编写插件

- 新建 `assets/sources/<key>.js`，`key` 只用 `[A-Za-z0-9_-]`，文件名必须是 `<key>.js`；从同类型的现有插件复制结构最快。
- 站点规则全部写在插件里，不要去 Dart 里按站点名加特例。
- 所有界面文案（名称、说明、标签名、选项、提示、错误）用简体中文原文。只属于本插件的词写进 manifest 的 `i18n` 块（`zh-Hant`、`ja`、`ko`、`en`、`es`、`ru`、`ar` 七种），通用词（排序、最新、热门…）直接复用应用的翻译。占位符写法必须一致。
- 错误用 `Park.error(code, '中文模板 {name}', { params: { name } })`，不要把变量拼进消息字符串。
- 混合类型的站点给每个作品填写 `mediaKind`；小说和游戏作品总是填写。
- 不在 ID、封面地址或游标里放凭据；日志只用 `this.log({ code, host, transport, reason })`。

## 3. 登记

- 在 `assets/sources/index.json` 中加入条目（`key`、`name`、`version: "0.0.1"`、`type`、`category`、`file`、`description`），顺序即默认排序。
- 修改已有插件时，同时提高脚本里的 `version` 和 `index.json` 中的版本（补丁位 +1）。插件版本与应用版本分开，不要动 `pubspec.yaml`。
- 用户可见的说明同步到 `README.md` 的“支持的站点”表（只列站点名）；协议有变化时更新 `docs/SOURCE_API.md`。

## 4. 验证

- 用 `verify-source` 技能对新插件做真实请求验证（首页、第二页、搜索、详情、封面解码、章节或媒体）。封面 HTTP 200 不等于可用，必须能解码。
- 运行离线校验：`node tools/publish_sources.mjs --commit <HEAD 提交号> --output test/checks/official-source-index.json`。
- 有条件时在模拟器上实际打开一次站点页、详情和阅读/播放。
- 完成说明里列出验证证据，以及没有验证到的部分（例如需要登录的功能）。

## 不要做

- 不要关闭 TLS 校验、放宽跨域重定向限制或共享 Cookie 来“修好”请求。
- 不要伪造推荐/排行接口或用空结果掩盖解析失败。
- 测试脚本只放在根目录 `test/`，不提交；未经用户要求不提交、不推送。
