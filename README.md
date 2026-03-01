# ProxyHub

共享反向代理服务，用于在单台服务器上管理多个 Docker 项目的路由和 HTTPS。

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/wh131462/ProxyHub/master/install.sh | bash
```

默认安装到 `/opt/proxy`，可通过环境变量自定义：

```bash
PROXY_INSTALL_DIR=/home/user/proxy curl -fsSL https://raw.githubusercontent.com/wh131462/ProxyHub/master/install.sh | bash
```

安装过程会交互式引导你完成配置（邮箱、域名、Dashboard 密码）。

## 手动安装

```bash
git clone https://github.com/wh131462/ProxyHub.git proxy
cd proxy
./setup.sh
```

## 项目结构

```
proxy/
├── install.sh           # 远程一键安装脚本
├── setup.sh             # 本地初始化脚本
├── docker-compose.yml   # Traefik 服务配置
├── .env.example         # 环境变量模板
└── examples/            # 接入示例
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
cd /opt/proxy  # 或你的安装目录

docker compose ps          # 查看状态
docker compose logs -f     # 查看日志
docker compose restart     # 重启服务
docker compose down        # 停止服务
```
