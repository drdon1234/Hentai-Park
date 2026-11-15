# HentaiPark Web

独立单用户 Web 实例：发现/搜索、漫画与小说、文章/频道/独立相册、视频与音声、游戏与酒馆、收藏与进度、离线下载/订阅、站点插件和 Web 数据备份。支持多标签页，不提供多用户或移动端迁移。

## 启动

需要 Node.js 24.22.3+（24.x LTS）与 pnpm 10.33.2：

```powershell
pnpm install --frozen-lockfile
pnpm build
pnpm --filter @hentai-park/browser-worker exec playwright install chromium
pnpm start
```

默认访问 http://127.0.0.1:8787。Windows 可运行 start-web.bat；开发运行 dev-web.bat。复制 .env.example 到 .env 配置数据目录。启用应用锁后，Local 用 DATA_DIR/instance.key 解锁。远程部署须显式配置 Server、强凭据与 HTTPS 反向代理，详见 docs/WEB_DEPLOYMENT.md。

Windows 双击 `start-web.bat` 会打开独立服务终端，启动成功后显示实际访问地址、端口并打开默认浏览器。再次启动会先关闭同一项目目录下由此入口启动的旧服务；关闭服务终端会结束服务及其子进程，关闭浏览器不会停止服务。其他项目和 Node 程序不受影响。首次从旧版启动入口切换时，请先关闭旧服务终端；端口被其他程序占用时显示错误，不自动杀占用进程。

官方插件随应用内置，启动时自动通过可信 SHA-256 索引和隔离声明检查安装缺失插件，首次启动可能稍慢；不访问外站业务页面。后续启动保留已安装版本、禁用状态与账号设置，更新仍通过站点页执行，不会自动覆盖用户版本。不会执行浏览器提供的脚本路径。账号/Cookie、SQLite 和下载保存在独立 DATA_DIR。媒体、反搜和字幕授权仅保存在会话内存；浏览器关闭不停止后台任务。

## 真实验收状态

发布与可交付结论以 [任务板](docs/WEB_TASK_BOARD.md) 的 FIX-066 / FULL-001 状态为准，不能从构建成功或 manifest 可加载推断全部站点可用。当前101项通过声明检查，不代表全部外站已完成验收。Docker/Compose已实际验证；外部账号、挑战、设备条件和未解释失败分别记录，不写成通过。

本轮候选证据与剩余条件见 [最终候选验收报告](docs/WEB_ACCEPTANCE.md) 和 [逐项验收清单](docs/WEB_ACCEPTANCE_ITEMS.md)。Node 基线为 24.22.3，来源与范围见 [基线核验](docs/WEB_NODE_BASELINE.md)。FULL-001 保持未通过，独立最终审查通过前不宣告正式完成。

测试和本地验收证据只放在被忽略的 test/，不进入 Git 或生产镜像。生产使用 pnpm build / pnpm start；类型检查为 pnpm typecheck，结构及忽略规则检查为 pnpm verify:structure。

42项原始缺口及后续FIX-051至081的修复映射见 [WEB_BASELINE_REPAIR.md](docs/WEB_BASELINE_REPAIR.md)。当前候选为rc-538101d3c730ac14，旧候选仅代表各自历史快照；一次未定因PARSE仍作为OBS-001交独立审查，复验成功不等于原失败已修复。
