#!/bin/bash
set -e

# ============================================
#  ProxyHub 一键安装脚本
#  用法: curl -fsSL https://raw.githubusercontent.com/wh131462/ProxyHub/master/install.sh | bash
# ============================================

REPO_URL="https://github.com/wh131462/ProxyHub.git"
DEFAULT_INSTALL_DIR="/opt/proxy"
INSTALL_DIR="${PROXY_INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"

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
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}     ProxyHub 一键安装${NC}"
echo -e "${CYAN}  Traefik 共享反向代理服务${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# ---- 环境检查 ----
info "检查运行环境..."

# 检查是否为 root 或有 sudo 权限
if [ "$EUID" -ne 0 ] && ! sudo -n true 2>/dev/null; then
  warn "建议使用 root 用户运行，或确保当前用户有 sudo 权限"
fi

# 检查 Docker
if ! command -v docker &>/dev/null; then
  error "未检测到 Docker，请先安装: https://docs.docker.com/engine/install/"
fi
ok "Docker $(docker --version | awk '{print $3}' | tr -d ',')"

# 检查 Docker Compose
if docker compose version &>/dev/null; then
  ok "Docker Compose $(docker compose version --short)"
elif command -v docker-compose &>/dev/null; then
  ok "docker-compose $(docker-compose --version | awk '{print $3}' | tr -d ',')"
  warn "建议升级到 Docker Compose V2 (docker compose)"
else
  error "未检测到 Docker Compose，请先安装: https://docs.docker.com/compose/install/"
fi

# 检查 Docker 是否运行
if ! docker info &>/dev/null; then
  error "Docker 未运行，请先启动 Docker 服务"
fi

# 检查端口占用
for port in 80 443; do
  if ss -tlnp 2>/dev/null | grep -q ":${port} " || \
     lsof -iTCP:${port} -sTCP:LISTEN 2>/dev/null | grep -q .; then
    warn "端口 ${port} 已被占用，Traefik 启动后可能会冲突"
  fi
done

echo ""

# ---- 安装目录 ----
info "安装目录: ${INSTALL_DIR}"

if [ -d "$INSTALL_DIR" ] && [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
  warn "检测到已有安装，将更新文件（保留 .env 和 acme.json）"
  UPGRADE=true
else
  UPGRADE=false
fi

mkdir -p "$INSTALL_DIR"

# ---- 下载项目 ----
info "下载项目文件..."

if command -v git &>/dev/null; then
  # 使用 git clone
  if [ "$UPGRADE" = true ] && [ -d "$INSTALL_DIR/.git" ]; then
    cd "$INSTALL_DIR"
    git pull --quiet
    ok "已通过 git pull 更新"
  else
    TMP_DIR=$(mktemp -d)
    git clone --quiet --depth 1 "$REPO_URL" "$TMP_DIR"
    # 复制文件，保留已有的 .env 和 acme.json
    cp "$TMP_DIR/docker-compose.yml" "$INSTALL_DIR/"
    cp "$TMP_DIR/.env.example" "$INSTALL_DIR/"
    cp "$TMP_DIR/setup.sh" "$INSTALL_DIR/"
    cp "$TMP_DIR/.gitignore" "$INSTALL_DIR/"
    [ -d "$TMP_DIR/examples" ] && cp -r "$TMP_DIR/examples" "$INSTALL_DIR/"
    rm -rf "$TMP_DIR"
    ok "已通过 git 下载"
  fi
else
  # 回退到 curl 下载
  RAW_BASE="https://raw.githubusercontent.com/wh131462/ProxyHub/master"
  curl -fsSL "$RAW_BASE/docker-compose.yml" -o "$INSTALL_DIR/docker-compose.yml"
  curl -fsSL "$RAW_BASE/.env.example" -o "$INSTALL_DIR/.env.example"
  curl -fsSL "$RAW_BASE/setup.sh" -o "$INSTALL_DIR/setup.sh"
  curl -fsSL "$RAW_BASE/.gitignore" -o "$INSTALL_DIR/.gitignore"
  mkdir -p "$INSTALL_DIR/examples"
  curl -fsSL "$RAW_BASE/examples/PROMPT.md" -o "$INSTALL_DIR/examples/PROMPT.md" 2>/dev/null || true
  curl -fsSL "$RAW_BASE/examples/tally-pro.docker-compose.yml" -o "$INSTALL_DIR/examples/tally-pro.docker-compose.yml" 2>/dev/null || true
  ok "已通过 curl 下载"
fi

chmod +x "$INSTALL_DIR/setup.sh"
cd "$INSTALL_DIR"

# ---- 初始化 acme.json ----
if [ ! -f acme.json ]; then
  touch acme.json
  chmod 600 acme.json
  ok "创建 acme.json（权限 600）"
fi

# ---- 交互式配置 ----
if [ -f .env ] && [ "$UPGRADE" = true ]; then
  ok "保留已有 .env 配置"
else
  info "开始配置..."
  echo ""

  # 邮箱
  read -rp "$(echo -e "${CYAN}Let's Encrypt 邮箱:${NC} ")" ACME_EMAIL
  [ -z "$ACME_EMAIL" ] && error "邮箱不能为空"

  # Dashboard 域名
  read -rp "$(echo -e "${CYAN}Dashboard 域名 (如 traefik.example.com):${NC} ")" DASHBOARD_DOMAIN
  [ -z "$DASHBOARD_DOMAIN" ] && error "域名不能为空"

  # Dashboard 密码
  read -rp "$(echo -e "${CYAN}Dashboard 用户名 [admin]:${NC} ")" DASHBOARD_USER
  DASHBOARD_USER="${DASHBOARD_USER:-admin}"

  # 生成密码哈希
  if command -v htpasswd &>/dev/null; then
    read -rsp "$(echo -e "${CYAN}Dashboard 密码:${NC} ")" DASHBOARD_PASS
    echo ""
    [ -z "$DASHBOARD_PASS" ] && error "密码不能为空"
    DASHBOARD_AUTH=$(htpasswd -nB "$DASHBOARD_USER" <<< "$DASHBOARD_PASS" | sed 's/\$/\$\$/g')
  else
    # 使用 Docker 中的 htpasswd
    read -rsp "$(echo -e "${CYAN}Dashboard 密码:${NC} ")" DASHBOARD_PASS
    echo ""
    [ -z "$DASHBOARD_PASS" ] && error "密码不能为空"
    DASHBOARD_AUTH=$(docker run --rm httpd:2-alpine htpasswd -nB "$DASHBOARD_USER" "$DASHBOARD_PASS" 2>/dev/null | sed 's/\$/\$\$/g')
    if [ -z "$DASHBOARD_AUTH" ]; then
      warn "自动生成密码失败，请稍后手动编辑 .env"
      DASHBOARD_AUTH="${DASHBOARD_USER}:\$\$2y\$\$05\$\$placeholder"
    fi
  fi

  # 写入 .env
  cat > .env << EOF
# Let's Encrypt 证书邮箱
ACME_EMAIL=${ACME_EMAIL}

# Traefik Dashboard 域名
DASHBOARD_DOMAIN=${DASHBOARD_DOMAIN}

# Dashboard 登录凭证
DASHBOARD_AUTH=${DASHBOARD_AUTH}
EOF

  ok "配置已写入 .env"
fi

echo ""

# ---- 启动服务 ----
info "启动 Traefik..."
docker compose down 2>/dev/null || true
docker compose up -d

echo ""
ok "安装完成！"
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "  安装目录: ${CYAN}${INSTALL_DIR}${NC}"
echo -e "  Dashboard: ${CYAN}https://${DASHBOARD_DOMAIN:-<见 .env>}${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "常用命令:"
echo -e "  ${CYAN}cd ${INSTALL_DIR}${NC}"
echo -e "  ${CYAN}docker compose ps${NC}        # 查看状态"
echo -e "  ${CYAN}docker compose logs -f${NC}   # 查看日志"
echo -e "  ${CYAN}docker compose restart${NC}   # 重启服务"
echo -e "  ${CYAN}docker compose down${NC}      # 停止服务"
echo ""
echo -e "其他项目接入方法请参考: ${CYAN}${INSTALL_DIR}/examples/${NC}"
echo ""
