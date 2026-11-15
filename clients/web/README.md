# HentaiPark Web

Web 客户端正式位于 `clients/web`。从[项目首页](../../README.md)开始；Docker、首次解锁、更新和持久化见 [Web 部署](../../docs/WEB_DEPLOYMENT.md)。

在仓库根目录运行：

```sh
pnpm --dir clients/web install --frozen-lockfile
pnpm --dir clients/web build
pnpm --dir clients/web --filter @hentai-park/browser-worker exec playwright install chromium
pnpm --dir clients/web start
```

需要 Node.js 24.22.3+（24.x）与 pnpm 10.33.2。Windows 可运行 `clients/web/start-web.bat`，会保留可见服务终端并自动打开浏览器。开发、共享资产与发布流程见[Web 开发说明](../../docs/web/DEVELOPMENT.md)；设计遵循[公共准则](../../docs/DESIGN.md)和 [Web 准则](../../docs/design/WEB.md)。
