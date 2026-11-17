# Web 部署

[返回 README](../README.md)

Web 目前处于 **Beta 阶段**，使用体验仍在持续优化。将 HentaiPark 部署到自己的电脑或服务器后，即可通过桌面或手机浏览器使用。每个实例供一人使用，不提供独立的多用户账号；部分功能和站点支持可能继续调整。

## 使用 Docker 部署

准备好以下环境：

- 支持运行 Linux x86_64（amd64）容器的设备；当前镜像不提供 ARM 原生版本。
- Docker 和 Compose v2。
- 一个指向部署设备的域名，以及提供有效 HTTPS 证书的反向代理。

以下命令使用 Linux / macOS / WSL 终端，在仓库根目录执行。

### 1. 获取配置

```sh
git clone https://github.com/drdon1234/Hentai-Park.git
cd Hentai-Park
cp clients/web/.env.example clients/web/.env
```

编辑 `clients/web/.env`，设置以下内容：

```dotenv
WEB_IMAGE=drdon1234/hentai-park:latest
AUTH_TOKEN=replace-with-your-own-long-random-credential
WEB_ALLOWED_ORIGIN=https://park.example.org
WEB_PORT=8787
```

| 配置 | 如何填写 |
| --- | --- |
| `WEB_IMAGE` | 使用上面的镜像地址；`latest` 表示最新稳定版，也可换成已发布的版本标签以固定版本。 |
| `AUTH_TOKEN` | 自己生成的随机访问凭据，至少 16 字符，建议 32 字符以上。打开 Web 时用它解锁，请勿分享。 |
| `WEB_ALLOWED_ORIGIN` | 实际访问地址，包含 `https://`、域名及非默认端口（如有），不带路径或末尾斜杠。 |
| `WEB_PORT` | 供反向代理连接的本机端口，默认 `8787`；被占用时可修改。 |

必须替换示例凭据和域名，并妥善保管 `.env`。可用 `openssl rand -hex 32` 生成随机凭据。

### 2. 启动服务

```sh
docker compose -f clients/web/compose.yaml pull
docker compose -f clients/web/compose.yaml up -d --no-build
```

### 3. 配置 HTTPS 并访问

将域名指向部署设备，在同一宿主机的反向代理中转发到 `http://127.0.0.1:8787`。修改过 `WEB_PORT` 时，使用对应端口。例如 Caddy 配置：

```caddyfile
park.example.org {
    reverse_proxy 127.0.0.1:8787
}
```

将示例域名替换为自己的域名，并确保与 `WEB_ALLOWED_ORIGIN` 一致。若代理也运行在 Docker 中，需将代理接入 Web 服务的 Docker 网络，并将上游设为 `web:8787`。

浏览器打开配置的 HTTPS 地址，输入 `AUTH_TOKEN` 解锁，按提示确认成年后即可使用，无需用户名。远程访问必须使用 HTTPS；默认的 `127.0.0.1:8787` 仅供反向代理连接，不是手机或其他电脑的访问地址。

## 更新与停止

在原仓库目录执行以下命令更新镜像并重建服务，已有数据会保留：

```sh
docker compose -f clients/web/compose.yaml pull
docker compose -f clients/web/compose.yaml up -d --no-build
```

固定版本部署时，先将 `.env` 中的 `WEB_IMAGE` 改为目标版本标签。

停止服务：

```sh
docker compose -f clients/web/compose.yaml stop
```

再次启动：

```sh
docker compose -f clients/web/compose.yaml start
```

## 保留数据与备份

默认配置将收藏、进度、设置、站点登录状态和下载文件保存在 Docker 数据卷 `park-data` 中。更新或重建容器会保留这些数据。请继续使用原仓库目录和同一个 Compose 项目；更换项目名会使用另一份数据卷，看起来像全新安装。

**不要删除数据卷，也不要用 `docker compose down -v` 停止或更新服务，这会删除保存的数据及下载文件。**

Web 使用独立的 JSON 备份，不支持导入 Android 数据库或 `.parkbak`，也不提供 Android 与 Web 之间的自动同步。导出备份不包含下载文件；包含账号和 Cookie 的备份未加密，请勿公开或分享。

迁移到其他设备时，先停止服务，再完整迁移原数据卷，并保留 `.env` 配置。仅复制项目文件不能迁移个人数据。

## 仅在本机使用

不需要远程访问时，也可直接在电脑上运行，无需配置域名。先按 [本机运行说明](../clients/web/README.md)安装依赖并启动；Windows 可在准备完成后双击 `clients/web/start-web.bat`。

浏览器访问 `http://127.0.0.1:8787`，保持服务终端打开，关闭终端会停止服务。本机模式默认无需解锁；启用应用锁后，使用 `clients/web/data/instance.key` 中的凭据（若自行设置了 `AUTH_TOKEN`，则使用该值）。默认数据保存在 `clients/web/data`，请勿删除。

Safari 使用本机 HTTP 时可能无法保持登录，建议改用有受信证书的 HTTPS 地址。

## 常见问题

**镜像无法拉取？**

检查镜像地址、版本标签及设备到 Docker Hub 的网络连接。若所选版本尚未提供镜像，可在仓库根目录执行以下命令从源码构建；同时将 `.env` 中的 `WEB_IMAGE` 改为 `hentai-park-web:local`，其余配置不变：

```sh
docker compose -f clients/web/compose.yaml build
docker compose -f clients/web/compose.yaml up -d --no-build --pull never
```

源码部署更新时，先更新源码，再重复上述命令。

**无法启动、访问或解锁？**

查看服务状态与近期日志：

```sh
docker compose -f clients/web/compose.yaml ps
docker compose -f clients/web/compose.yaml logs --tail 100 web
```

确认 `AUTH_TOKEN` 已填写且不少于 16 字符，浏览器地址与 `WEB_ALLOWED_ORIGIN` 一致，HTTPS 证书有效，反向代理端口正确。更改 `.env` 后需执行 `up -d --no-build` 才会应用。分享排障信息时，请隐藏凭据、Cookie 和私人内容。

**需要使用网络代理或本地 AI 服务？**

可在 `.env` 中设置 `WEB_HTTP_PROXY`。代理位于内网时还需设置 `WEB_HTTP_PROXY_ALLOW_LOCAL=true`；连接本地 AI 服务需设置 `WEB_ALLOW_LOCAL_AI=true`。地址必须能从容器内访问，容器中的 `127.0.0.1` 不指向宿主机。

**自定义数据目录后提示没有写入权限？**

默认数据卷无需额外设置。改用宿主目录挂载时，需允许容器用户 `1000:1000` 读写该专用目录。
