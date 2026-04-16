#!/bin/bash
set -e

# ============================================
#  ProxyHub 一键安装脚本
#  用法: bash <(curl -fsSL https://raw.githubusercontent.com/wh131462/ProxyHub/master/install.sh)
# ============================================

REPO_URL="https://github.com/wh131462/ProxyHub.git"
DEFAULT_INSTALL_DIR="/opt/proxy"
INSTALL_DIR="${PROXY_INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"

# 确保 CWD 有效（上次运行可能删除了当前目录）
cd "${HOME:-/tmp}" 2>/dev/null || cd /tmp

# 临时文件（trap 保证清理）
TMP_ENV=""
TMP_ACME=""
cleanup() { rm -f "$TMP_ENV" "$TMP_ACME"; }
trap cleanup EXIT

# 颜色（非 TTY 环境自动关闭）
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  CYAN='\033[0;36m'
  NC='\033[0m'
else
  RED='' GREEN='' YELLOW='' CYAN='' NC=''
fi

info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 端口占用检测（兼容 ss / lsof / netstat）
port_in_use() {
  local port=$1
  ss      -tlnp 2>/dev/null | grep -q ":${port} " && return 0
  lsof    -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null | grep -q .  && return 0
  netstat -tlnp 2>/dev/null | grep -q ":${port} " && return 0
  return 1
}

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
  if port_in_use "$port"; then
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

# ---- 下载项目 ----
info "下载项目文件..."

if command -v git &>/dev/null; then
  if [ -d "$INSTALL_DIR/.git" ]; then
    # 已是 git 仓库，直接 pull
    cd "$INSTALL_DIR" || error "无法进入安装目录: $INSTALL_DIR"
    git pull --quiet
    ok "已通过 git pull 更新"
  elif [ "$UPGRADE" = true ]; then
    # 旧版复制安装，迁移为 git 仓库：先备份，再 clone，恢复保留文件
    TMP_ENV=$(mktemp)
    TMP_ACME=$(mktemp)
    [ -f "$INSTALL_DIR/.env" ]      && cp "$INSTALL_DIR/.env"      "$TMP_ENV"
    [ -f "$INSTALL_DIR/acme.json" ] && cp "$INSTALL_DIR/acme.json" "$TMP_ACME"
    cd /tmp
    rm -rf "$INSTALL_DIR"
    if ! git clone --quiet --depth 1 "$REPO_URL" "$INSTALL_DIR"; then
      # clone 失败：还原保留文件
      mkdir -p "$INSTALL_DIR"
      [ -s "$TMP_ENV" ]  && cp "$TMP_ENV"  "$INSTALL_DIR/.env"
      [ -s "$TMP_ACME" ] && cp "$TMP_ACME" "$INSTALL_DIR/acme.json" && chmod 600 "$INSTALL_DIR/acme.json"
      error "git clone 失败，已还原原有配置，请检查网络后重试"
    fi
    [ -s "$TMP_ENV" ]  && cp "$TMP_ENV"  "$INSTALL_DIR/.env"
    [ -s "$TMP_ACME" ] && cp "$TMP_ACME" "$INSTALL_DIR/acme.json" && chmod 600 "$INSTALL_DIR/acme.json"
    ok "已迁移为 git 仓库（保留 .env 和 acme.json）"
  else
    # 全新安装，直接 clone 到安装目录
    if ! git clone --quiet --depth 1 "$REPO_URL" "$INSTALL_DIR"; then
      error "git clone 失败，请检查网络连接后重试"
    fi
    ok "已通过 git clone 下载"
  fi
else
  # 回退到 curl 下载（无 git 环境）
  RAW_BASE="https://raw.githubusercontent.com/wh131462/ProxyHub/master"
  mkdir -p "$INSTALL_DIR"
  curl -fsSL --max-time 30 "$RAW_BASE/docker-compose.yml" -o "$INSTALL_DIR/docker-compose.yml"
  curl -fsSL --max-time 30 "$RAW_BASE/.env.example"       -o "$INSTALL_DIR/.env.example"
  curl -fsSL --max-time 30 "$RAW_BASE/setup.sh"           -o "$INSTALL_DIR/setup.sh"
  curl -fsSL --max-time 30 "$RAW_BASE/.gitignore"         -o "$INSTALL_DIR/.gitignore"
  mkdir -p "$INSTALL_DIR/examples"
  curl -fsSL --max-time 30 "$RAW_BASE/examples/PROMPT.md" \
    -o "$INSTALL_DIR/examples/PROMPT.md" 2>/dev/null || true
  curl -fsSL --max-time 30 "$RAW_BASE/examples/tally-pro.docker-compose.yml" \
    -o "$INSTALL_DIR/examples/tally-pro.docker-compose.yml" 2>/dev/null || true
  ok "已通过 curl 下载"
fi

chmod +x "$INSTALL_DIR/setup.sh"
cd "$INSTALL_DIR" || error "无法进入安装目录: $INSTALL_DIR"

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
  read -rp "$(echo -e "${CYAN}Let's Encrypt 邮箱:${NC} ")" ACME_EMAIL < /dev/tty
  [ -z "$ACME_EMAIL" ] && error "邮箱不能为空"
  [[ "$ACME_EMAIL" != *@*.* ]] && error "邮箱格式不正确（示例: user@example.com）"

  # Dashboard 域名
  read -rp "$(echo -e "${CYAN}Dashboard 域名 (如 traefik.example.com):${NC} ")" DASHBOARD_DOMAIN < /dev/tty
  [ -z "$DASHBOARD_DOMAIN" ] && error "域名不能为空"
  [[ "$DASHBOARD_DOMAIN" != *.* || "$DASHBOARD_DOMAIN" == *" "* ]] && error "域名格式不正确（示例: traefik.example.com）"

  # Dashboard 用户名
  read -rp "$(echo -e "${CYAN}Dashboard 用户名 [admin]:${NC} ")" DASHBOARD_USER < /dev/tty
  DASHBOARD_USER="${DASHBOARD_USER:-admin}"

  # Dashboard 密码
  read -rsp "$(echo -e "${CYAN}Dashboard 密码:${NC} ")" DASHBOARD_PASS < /dev/tty
  echo ""
  [ -z "$DASHBOARD_PASS" ] && error "密码不能为空"

  # 生成密码哈希（依次尝试多种方式）
  DASHBOARD_AUTH=""
  if command -v htpasswd &>/dev/null; then
    DASHBOARD_AUTH=$(htpasswd -nBb "$DASHBOARD_USER" "$DASHBOARD_PASS" 2>/dev/null | sed 's/\$/\$\$/g')
  fi
  if [ -z "$DASHBOARD_AUTH" ] && command -v openssl &>/dev/null; then
    HASH=$(openssl passwd -apr1 "$DASHBOARD_PASS" 2>/dev/null)
    [ -n "$HASH" ] && DASHBOARD_AUTH=$(echo "${DASHBOARD_USER}:${HASH}" | sed 's/\$/\$\$/g')
  fi
  if [ -z "$DASHBOARD_AUTH" ]; then
    DASHBOARD_AUTH=$(docker run --rm httpd:2-alpine htpasswd -nBb "$DASHBOARD_USER" "$DASHBOARD_PASS" 2>/dev/null | sed 's/\$/\$\$/g')
  fi
  [ -z "$DASHBOARD_AUTH" ] && error "无法生成密码哈希，请确保系统已安装 htpasswd 或 openssl"

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

# 升级场景：从 .env 读取域名供结尾显示
if [ -z "$DASHBOARD_DOMAIN" ] && [ -f .env ]; then
  DASHBOARD_DOMAIN=$(grep "^DASHBOARD_DOMAIN=" .env | cut -d= -f2)
fi

echo ""

# ---- 启动服务 ----
info "启动 Traefik..."

# 检查端口是否仍被占用
BLOCKED_PORTS=()
for port in 80 443; do
  if port_in_use "$port"; then
    BLOCKED_PORTS+=("$port")
  fi
done
if [ ${#BLOCKED_PORTS[@]} -gt 0 ]; then
  warn "端口 ${BLOCKED_PORTS[*]} 仍被其他进程占用，Traefik 可能无法启动"
  warn "请先释放端口（如: sudo lsof -i :80 查找占用进程），再运行: cd ${INSTALL_DIR} && docker compose up -d"
fi

docker compose down 2>/dev/null || true

# 清理同名旧容器（可能由其他 compose 项目创建）
if docker ps -a --format '{{.Names}}' | grep -q '^traefik$'; then
  OLD_PROJECT=$(docker inspect traefik --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || true)
  if [ "$OLD_PROJECT" != "proxy" ]; then
    warn "发现非本项目的同名容器 traefik（所属项目: ${OLD_PROJECT:-未知}），正在移除..."
    docker stop traefik 2>/dev/null || true
    docker rm   traefik 2>/dev/null || true
    ok "旧容器已移除"
  fi
fi

if ! docker compose up -d; then
  error "Traefik 启动失败，请运行 'docker compose logs' 查看详情"
fi

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
