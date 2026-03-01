# Traefik 反向代理接入 - AI 提示词

> 将下方提示词添加到项目的 AI 上下文中（如 CLAUDE.md、Cursor Rules 等），AI 会自动读取并改造项目的 Docker 配置。

---

## 提示词

本项目需要接入服务器上已有的 Traefik v3 共享反向代理，通过 Docker 网络 `proxy`（bridge）统一管理路由和 HTTPS（Let's Encrypt 自动签发）。

改造 docker-compose.yml 时遵循以下规则：

1. 顶层 networks 声明 `proxy: external: true`，同时创建一个项目内部网络用于服务间通信
2. 需要对外暴露的服务同时加入 proxy 和内部网络，并添加 traefik labels：
   - traefik.enable=true
   - traefik.http.routers.{路由名}.rule=Host(`域名`)
   - traefik.http.routers.{路由名}.entrypoints=websecure
   - traefik.http.routers.{路由名}.tls.certresolver=letsencrypt
   - traefik.http.services.{路由名}.loadbalancer.server.port=容器内部端口
3. 数据库、缓存等内部服务只加入内部网络，不暴露端口
4. 移除所有 ports 映射，流量统一走 Traefik 转发
5. 路由名在 Traefik 中全局唯一，使用 `项目名-服务类型` 格式
