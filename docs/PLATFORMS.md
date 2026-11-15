# 平台说明

本仓维护 Android 原生客户端与自托管 Web 客户端。

## Android

Android 7.0 及以上为当前支持平台。具体能力、安装限制和设备要求以实际版本和应用内提示为准。

## Web

Web 通过桌面或手机浏览器使用，支持本机 Node 运行和 Docker 部署。远程部署要求 HTTPS 反向代理与实例凭据；首次镜像发布前可从源码构建。详见 [Web 部署](WEB_DEPLOYMENT.md)。

Web 为单用户实例，使用独立数据目录与 JSON 备份，不支持 Android 数据库或 `.parkbak` 导入，也不提供跨端自动同步。浏览器、外站与设备差异以实际能力为准；不把 Chromium 验证等同于 Safari 或实体触屏验证。
