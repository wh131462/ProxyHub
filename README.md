# Traefik Proxy

共享反向代理服务，用于在单台服务器上管理多个 Docker 项目的路由和 HTTPS。

## 项目结构

```
proxy/
├── docker-compose.yml   # Traefik 服务配置
├── .env.example         # 环境变量��板
├── .gitignore
├── setup.sh             # 一键初始化脚本
└── README.md
```

## 快速开始

```bash
# 1. 运行初始化（首次会生成 .env，需编辑后再次运行）
./setup.sh

# 2. 编辑 .env 填入你的配置
vim .env

# 3. 再次运行启动
./setup.sh
```

## 其他项目接入

在其他项目的 `docker-compose.yml` 中添加以下配置即可接入：

```yaml
services:
  your-app:
    # ... 你的服务配置
    labels:
      - traefik.enable=true
      - traefik.http.routers.your-app.rule=Host(`app.yourdomain.com`)
      - traefik.http.routers.your-app.entrypoints=websecure
      - traefik.http.routers.your-app.tls.certresolver=letsencrypt
      - traefik.http.services.your-app.loadbalancer.server.port=3000
    networks:
      - proxy
      - default  # 内部服务通信保留默认网络

networks:
  proxy:
    external: true
```

## 常用命令

```bash
# 查看状态
docker compose ps

# 查看日志
docker compose logs -f traefik

# 重启
docker compose restart

# 停止
docker compose down
```
