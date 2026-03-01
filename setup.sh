#!/bin/bash
set -e

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo ""
echo -e "${CYAN}=== ProxyHub 初始化 ===${NC}"
echo ""

# 切换到脚本所在目录
cd "$(dirname "$0")"

# 1. 创建 acme.json（Let's Encrypt 证书存储）
if [ ! -f acme.json ]; then
  touch acme.json
  chmod 600 acme.json
  ok "创建 acme.json（权限 600）"
else
  ok "acme.json 已存在"
fi

# 2. 检查 .env 文件
if [ ! -f .env ]; then
  info "首次运行，开始配置..."
  echo ""

  # 邮箱
  read -rp "$(echo -e "${CYAN}Let's Encrypt 邮箱:${NC} ")" ACME_EMAIL
  [ -z "$ACME_EMAIL" ] && error "邮箱不能为空"

  # Dashboard 域名
  read -rp "$(echo -e "${CYAN}Dashboard 域名 (如 traefik.example.com):${NC} ")" DASHBOARD_DOMAIN
  [ -z "$DASHBOARD_DOMAIN" ] && error "域名不能为空"

  # Dashboard 用户名 & 密码
  read -rp "$(echo -e "${CYAN}Dashboard 用户名 [admin]:${NC} ")" DASHBOARD_USER
  DASHBOARD_USER="${DASHBOARD_USER:-admin}"

  if command -v htpasswd &>/dev/null; then
    read -rsp "$(echo -e "${CYAN}Dashboard 密码:${NC} ")" DASHBOARD_PASS
    echo ""
    [ -z "$DASHBOARD_PASS" ] && error "密码不能为空"
    DASHBOARD_AUTH=$(htpasswd -nB "$DASHBOARD_USER" <<< "$DASHBOARD_PASS" | sed 's/\$/\$\$/g')
  else
    read -rsp "$(echo -e "${CYAN}Dashboard 密码:${NC} ")" DASHBOARD_PASS
    echo ""
    [ -z "$DASHBOARD_PASS" ] && error "密码不能为空"
    DASHBOARD_AUTH=$(docker run --rm httpd:2-alpine htpasswd -nB "$DASHBOARD_USER" "$DASHBOARD_PASS" 2>/dev/null | sed 's/\$/\$\$/g')
    if [ -z "$DASHBOARD_AUTH" ]; then
      warn "自动生成密码失败，使用占位符，请稍后手动编辑 .env"
      DASHBOARD_AUTH="${DASHBOARD_USER}:\$\$2y\$\$05\$\$placeholder"
    fi
  fi

  cat > .env << EOF
# Let's Encrypt 证书邮箱
ACME_EMAIL=${ACME_EMAIL}

# Traefik Dashboard 域名
DASHBOARD_DOMAIN=${DASHBOARD_DOMAIN}

# Dashboard 登录凭证
DASHBOARD_AUTH=${DASHBOARD_AUTH}
EOF

  ok "配置已写入 .env"
  echo ""
fi

# 3. 启动
info "启动 Traefik..."
docker compose down 2>/dev/null || true
docker compose up -d

echo ""
ok "Traefik 已启动"
echo ""
docker compose ps
