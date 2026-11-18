# HentaiPark Web

独立单用户 Web 实例：发现/搜索、漫画与小说、文章/频道/独立相册、视频与音声、游戏与酒馆、收藏与进度、离线下载/订阅、站点插件以及 `.parkbak` / JSON 数据备份。支持多标签页与桌面/移动 PWA 安装，不提供多用户账号。

## 启动

需要 Node.js 24.22.3+（24.x LTS）与 pnpm 10.33.2：

```powershell
pnpm install --frozen-lockfile
pnpm build
pnpm --filter @hentai-park/browser-worker exec playwright install chromium
pnpm start
```

默认访问 http://127.0.0.1:8787。Windows 可运行 start-web.bat；开发运行 dev-web.bat。复制 .env.example 到 .env 配置数据目录。启用应用锁后，可在设置中配置独立的应用锁 PIN（或使用 `DATA_DIR/instance.key` 凭据）解锁。远程部署须显式配置 Server、强凭据与 HTTPS 反向代理，详见 [DEPLOYMENT.md](DEPLOYMENT.md)。

Windows 双击 `start-web.bat` 会打开独立服务终端，启动成功后显示实际访问地址、端口并打开默认浏览器。再次启动会先关闭同一项目目录下由此入口启动的旧服务；如果 8787 被 `dev-web` 占用，会询问是否先终止开发服务；如果被其他程序占用，会询问是否改用随机可用端口。关闭服务终端会结束服务及其子进程，关闭浏览器不会停止服务。其他项目和 Node 程序不受影响。首次从旧版启动入口切换时，请先关闭旧服务终端。

官方插件随应用内置，启动时自动通过可信 SHA-256 索引和隔离声明检查安装缺失插件，首次启动可能稍慢；不访问外站业务页面。后续启动保留已安装版本、禁用状态与账号设置，更新仍通过站点页执行，不会自动覆盖用户版本。不会执行浏览器提供的脚本路径。账号/Cookie、SQLite 和下载保存在独立 DATA_DIR。媒体、反搜和字幕授权仅保存在会话内存；浏览器关闭不停止后台任务。

路径约定：本文 `apps/`、`packages/`、`scripts/` 相对 `clients/web`；共享插件协议为 [SOURCE_API](../../docs/SOURCE_API.md)。
