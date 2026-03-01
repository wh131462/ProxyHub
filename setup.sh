#!/bin/bash
set -e

echo "=== Traefik Proxy 初始化 ==="

# 1. 创建 acme.json（Let's Encrypt 证书存储）
if [ ! -f acme.json ]; then
  touch acme.json
  chmod 600 acme.json
  echo "✓ 创建 acme.json（权限 600）"
else
  echo "✓ acme.json 已存在"
fi

# 2. 检查 .env 文件
if [ ! -f .env ]; then
  cp .env.example .env
  echo ""
  echo "⚠ 已从 .env.example 复制 .env，请编辑以下配置："
  echo "  - ACME_EMAIL: 你的邮箱（用于 Let's Encrypt）"
  echo "  - DASHBOARD_DOMAIN: Dashboard 访问域名"
  echo "  - DASHBOARD_AUTH: 登录密码（运行以下命令生成）："
  echo ""
  echo "    echo \$(htpasswd -nB admin) | sed -e 's/\$/\$\$/g'"
  echo ""
  echo "  编辑完成后重新运行此脚本。"
  exit 0
fi

# 3. 启动
echo ""
echo "启动 Traefik..."
docker compose up -d

echo ""
echo "✓ Traefik 已启动"
echo ""
docker compose ps
