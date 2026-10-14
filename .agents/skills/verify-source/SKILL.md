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

- `CLOUDFLARE`、`CONFIRM_REQUIRED`：Node 里无法完成浏览器验证，记录为“需要在设备上验证”，不要判定插件失效，也不要尝试绕过。
- `LOGIN_REQUIRED`：需要账号的功能，记录为未验证；不要使用或索要用户的真实账号。
- `NETWORK` / 超时：先确认是不是需要代理（`network.vpnHint`），换网络重试一次再下结论。
- 插件真的坏了（解析失败、第二页重复、封面不是图片）：定位根因并修复插件，提高插件版本，再重新验证。

## 汇报

用表格列出每个站点每一步的结果和关键数据（条数、图片格式与尺寸、媒体类型），并单独列出没有验证到的步骤和原因。
