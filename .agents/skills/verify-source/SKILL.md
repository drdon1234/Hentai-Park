---
name: verify-source
description: 用真实请求验证一个或多个 HentaiPark 站点插件是否可用（首页、分页、搜索、详情、封面解码、章节/视频/正文/游戏资源）。修改插件后、发布前，或用户报告某站点失效时使用。
---

# 验证站点插件

AGENTS.md 要求：每个改动过的插件都要用真实请求验证首页、分页、搜索、详情、封面（必须能解码），以及漫画章节或视频分集/媒体。离线校验和“HTTP 200”都不算验证。

## 准备

```powershell
npm ci --prefix 'tools/source-runner'
```

验证脚本放在被忽略的 `test/` 下（例如 `test/verify_source.mjs`），不提交。脚本基于共享运行时：

```js
import { loadSource } from '../tools/source-runner/host.mjs';
const { manifest, call } = await loadSource('<key>.js');
const page1 = await call('feed', manifest.defaultFeed, { page: 1, options: {} });
```

每个站点依次检查：

1. **首页**：`feed(defaultFeed, { page: 1 })` 有结果。
2. **第二页**：`hasNext` 为真时用 `page: 2`（游标站点传回 `cursor`），结果不能和第一页完全相同。
3. **搜索**：用首页某个作品标题里的词搜索，有结果。没有搜索接口的站点不声明 `search`。
4. **详情**：`detail(id, preview)` 返回标题、章节或单章 ID。
5. **封面**：按 `manifest.imageHeaders` 下载并检查文件头（JPEG / PNG / WebP / GIF / AVIF）和尺寸；声明了 `imageDecrypt` 的域名要先按 AES-CBC 解密再检查。
6. **内容**：
   - 漫画/图集：`chapter()` 有页面，第一页图片能解码（`token` 页先调 `resolveImage`；`transform` 表示需要还原的切条图）。
   - 视频：`videos(id, episodeId)` 有地址；MP4 用 `Range: bytes=0-65535` 请求，确认是 `ftyp`；HLS 确认以 `#EXTM3U` 开头。`capabilities.videos === false` 的站点只在原站播放，跳过。
   - 小说：`textChapter()` 的 `paragraphs` 非空。
   - 游戏：`gameResources()` 返回资源和渠道；不要调用 `resolveGameResource` 之外的写操作，也不要触发回复解锁。

## 解读结果

- `CLOUDFLARE`、`CONFIRM_REQUIRED` 或 HTTP 200 验证页：优先使用项目已有的无感交互框架处理，按 `docs/SOURCE_API.md` 的网络章节检查插件的 `network.mode`、`network.origin` 与 `network.confirmation`。Node 运行时无法完成浏览器验证，应转到具备框架能力的设备环境验证，不能直接判定插件失效。
- 无感交互处理失败时，优先定位并修复对应站点的接入、验证识别、自动操作或完成判定，再继续原业务验证；站点规则修在插件，通用缺陷修在框架。不得仅记录“需要手动验证”就结束，也不得通过预置验证 Cookie、关闭 TLS 校验、放宽域名限制或共享会话掩盖失败。
- 无感交互使用无预置验证 Cookie 的隔离设备会话，检查验证自动完成且原业务请求得到真实内容，再继续上述检查。保持框架的只读重试和写操作不重放限制；年龄确认遵守应用已确认成年的前提，不自动执行登录、付费或回复。
- 缺少设备或环境能力时，继续可完成的规则检查与根因定位，并明确报告阻塞和未验证范围，不宣称自动交互通过。调用项目框架不等于获准使用 computer use，工具权限仍遵守 `AGENTS.md`。
- `LOGIN_REQUIRED`：需要账号的功能，记录为未验证；不要使用或索要用户的真实账号。
- `NETWORK` / 超时：先确认是不是需要代理（`network.vpnHint`），换网络重试一次再下结论。
- 插件真的坏了（解析失败、第二页重复、封面不是图片）：定位根因并修复插件，提高插件版本，再重新验证。

## 汇报

用表格列出每个站点每一步的结果和关键数据（条数、图片格式与尺寸、媒体类型），并单独列出没有验证到的步骤和原因。

遇到站点验证时，补充无感交互所用平台、验证类型、自动处理结果及原业务请求结果；失败时说明根因、修复与复验结果，未解决时说明具体阻塞。
