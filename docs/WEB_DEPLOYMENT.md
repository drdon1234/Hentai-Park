# Web 部署

[返回 README](../README.md) · [工程与发布](web/DEVELOPMENT.md)

Web 是单用户自托管服务，可通过桌面或手机浏览器使用。Docker 镜像名为 `drdon1234/hentai-park`，当前构建目标为 **linux/amd64（x86_64）**。不要假设 ARM NAS 可原生运行。

**首次发布前提：** 首次使用远端镜像前，须将代码推送并等待 Release platforms 工作流成功。Android 与 Docker 只由版本发布流水线统一构建，正式稳定版本发布后提供 `latest`。普通提交不触发这两端构建。发布前使用下面的本地构建方式。

## Docker Compose

需要 Docker Engine / Docker Desktop 和 Compose v2。Windows 可在已配置 Docker 的 WSL 环境中运行。以下命令在仓库根目录执行：

```sh
git clone https://github.com/drdon1234/Hentai-Park.git
cd Hentai-Park
cp clients/web/.env.example clients/web/.env
```

编辑 `clients/web/.env`：

```dotenv
WEB_IMAGE=drdon1234/hentai-park:latest
AUTH_TOKEN=replace-with-a-long-random-instance-credential
WEB_ALLOWED_ORIGIN=https://park.example.org
WEB_PORT=8787
```

必须更换示例凭据和域名。`AUTH_TOKEN` 是 Web 实例解锁凭据，不是 Docker Hub Token；至少 16 字符，建议随机 32 字符以上。`WEB_ALLOWED_ORIGIN` 是浏览器实际访问的 HTTPS origin（协议、域名、可选端口，不带路径或末尾斜杠）。例如用 `openssl rand -hex 32` 生成实例凭据，妥善保管 `.env`。

远端镜像发布后：

```sh
docker compose -f clients/web/compose.yaml pull
docker compose -f clients/web/compose.yaml up -d --no-build
docker compose -f clients/web/compose.yaml ps
```

默认映射 `127.0.0.1:8787 → 容器 8787`，仅供同宿主 HTTPS 反向代理访问。`WEB_PORT` 可改宿主端口。不要直接暴露容器 HTTP 服务；远程 Server 模式要求 HTTPS，首次在配置的 HTTPS 地址访问，用 `AUTH_TOKEN` 解锁并完成成年确认，没有默认用户名或密码。健康端点为 `/health`。

## 发布前的本地构建

在同一 `.env` 中将 `WEB_IMAGE` 改为 `hentai-park-web:local`，保留上面的实例凭据和 HTTPS 配置：

```sh
docker compose -f clients/web/compose.yaml build
docker compose -f clients/web/compose.yaml up -d --no-build --pull never
```

等价的单独构建命令：

```sh
docker build --platform linux/amd64 -f clients/web/Dockerfile -t hentai-park-web:local .
```

构建上下文必须是原仓库根目录，不能只复制 `clients/web` 构建。Dockerfile 专用忽略清单仅允许 Web 源码、根插件/运行时、pubspec 与许可证进入上下文；Android、个人配置和数据不进入镜像。

## 数据与浏览器依赖

Compose 的 `park-data` 命名卷挂载 `/data`（实际卷名带 Compose 项目前缀）；数据库、配置、插件状态和密钥持久化于此，下载位于 `/data/downloads`。保持同一个 Compose 项目名和数据卷；`down` 不删除卷，**不要使用 `down -v`** 来做普通停止或更新。

服务以 `node` 用户 **UID/GID 1000:1000** 运行，命名卷首次初始化可直接使用。若自行改成宿主目录挂载，如 `./park-data:/data`，必须预先创建专用目录并确保 UID/GID 1000:1000 可读写；不要把宿主整个媒体库递归改属主。此镜像不提供 PUID/PGID 自动改属主功能。

镜像安装锁文件对应的 Playwright Chromium 和 Debian 系统库，Compose 提供 1 GiB 共享内存和 init 进程。宿主无须另装 Chromium、Node 或 FFmpeg，也无须桌面/Xvfb；不要照搬其他项目的浏览器参数。浏览器环境可用不代表所有外站验证都能自动通过。

Web 使用独立 JSON 备份，不支持 Android 数据库或 `.parkbak` 导入。导出备份不带实际下载文件；包含账号/Cookie 的备份未加密，应妥善保管。数据迁移应停止服务后完整迁移数据卷；对不可恢复的重要资产按迁移风险做必要备份。

## HTTPS 反向代理

代理在宿主运行时转发到 `http://127.0.0.1:8787`（或配置的 `WEB_PORT`）。例如 Caddy：

```caddyfile
park.example.org {
    reverse_proxy 127.0.0.1:8787
}
```

域名 DNS 和受信证书需正确配置。保留 `Origin`、Cookie 和 `Sec-Fetch-*` 请求头，支持长连接/SSE，不缓存认证 API；不要移除 Secure Cookie 属性或放宽来源校验。代理自身在容器内时，它的 `127.0.0.1` 不指向 Web 容器，应接入同一受控 Docker 网络并使用 `web:8787`，不要为此公开后端端口。

## 更新与停止

远端镜像部署：

```sh
docker compose -f clients/web/compose.yaml pull
docker compose -f clients/web/compose.yaml up -d --no-build
```

源码部署更新代码后重新执行 `build`，再执行 `up -d --no-build --pull never`。普通停止和恢复：

```sh
docker compose -f clients/web/compose.yaml stop
docker compose -f clients/web/compose.yaml start
```

移除容器和项目网络、保留数据卷：`docker compose -f clients/web/compose.yaml down`。

| 镜像标签 | 含义 |
| --- | --- |
| `X.Y.Z` | 对应 `vX.Y.Z` 正式版本标签 |
| `X.Y.Z-rc.1` 等 | 对应预发布标签，不更新 latest |
| `latest` | 最近发布的正式稳定版本 |
| `sha-<完整提交SHA>` | 追溯源码提交；需要固定构建时使用镜像 digest |

## 本机直接运行

需要 Node.js 24.22.3+（24.x）及 pnpm 10.33.2，见 [Web 工程入口](../clients/web/README.md)。Windows 双击 `clients/web/start-web.bat`，保持服务终端打开；浏览器会自动打开。若默认端口被 `dev-web` 占用，启动器会询问是否终止开发服务；若被其他程序占用，会询问是否使用随机可用端口。开发使用 `dev-web.bat` 或 `pnpm --dir clients/web dev`。

默认仅监听 `http://127.0.0.1:8787`。本机模式默认不要求实例解锁，启用应用锁后使用 `clients/web/data/instance.key` 中的凭据；若设置了 `AUTH_TOKEN` 则使用该值。相对数据路径相对 `clients/web` 解释。回环 HTTP 的 Secure Cookie 依赖浏览器本机例外；WebKit/Safari 建议经受信 HTTPS 使用，不宣称已完成全部浏览器验收。

## 排障与可选配置

```sh
docker compose -f clients/web/compose.yaml logs --tail 100 web
docker compose -f clients/web/compose.yaml ps
```

- 缺少凭据/HTTPS origin 时 Compose 或服务会拒绝启动；解锁失败先检查 `AUTH_TOKEN` 和实际访问 origin，不要填写 Docker Hub Token。
- `/data` 权限错误：核对专用挂载目录与 UID/GID；Chromium 不可用：使用完整镜像和 Compose 配置，核对共享内存、宿主资源与容器日志。
- 代理可通过 `WEB_HTTP_PROXY` 指定；只有确实需要访问本地代理时设置 `WEB_HTTP_PROXY_ALLOW_LOCAL=true`。本地 AI 服务访问需显式设置 `WEB_ALLOW_LOCAL_AI=true`，不会关闭目标网络或 TLS 校验。
- Docker 地址池耗尽时先检查现有网络、宿主/VPN/WSL 路由；可设置 `WEB_DOCKER_SUBNET` 为经过核对的无冲突私有网段。默认由 Docker 分配，不提供本机专用网段作为通用配置，不要清理其他应用网络。
