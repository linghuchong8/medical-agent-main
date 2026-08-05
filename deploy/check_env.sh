#!/usr/bin/env bash
# ============================================
# 天宫医疗智能体 - 部署环境自检脚本 (Linux)
# 检测必备软件是否齐全，缺失时给出安装命令
# 使用: bash check_env.sh
# ============================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[!!]${NC} $1"; }
fail() { echo -e "${RED}[X]${NC} $1"; }
fail_count=0

echo "============================================"
echo " 部署环境自检 (需要 root 权限时会提示 sudo)"
echo "============================================"
echo ""

# ---------- 检测 OS ----------
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "系统: $PRETTY_NAME"
else
    echo "系统: 未知"
fi

# ---------- Python ----------
echo ""
echo "--- Python (需 >= 3.13) ---"
if command -v python3 >/dev/null 2>&1; then
    PYVER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null)
    MAJOR=$(echo "$PYVER" | cut -d. -f1); MINOR=$(echo "$PYVER" | cut -d. -f2)
    if [ "$MAJOR" -eq 3 ] && [ "$MINOR" -ge 13 ]; then
        ok "python3 = $PYVER"
    else
        warn "python3 = $PYVER (低于 3.13)"
        fail_count=$((fail_count+1))
    fi
else
    fail "未找到 python3"
    echo "  安装: sudo apt install -y python3.13 python3.13-venv (Debian/Ubuntu, 需 deadsnakes PPA)"
    fail_count=$((fail_count+1))
fi

if ! python3 -m venv --help >/dev/null 2>&1; then
    warn "缺少 python venv 模块"
    echo "  安装: sudo apt install -y python3.13-venv"
    fail_count=$((fail_count+1))
fi

# ---------- Docker ----------
echo ""
echo "--- Docker ---"
if command -v docker >/dev/null 2>&1; then
    ok "docker $(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)"
else
    fail "未找到 docker"
    echo "  安装: curl -fsSL https://get.docker.com | sudo sh"
    fail_count=$((fail_count+1))
fi

if docker compose version >/dev/null 2>&1; then
    ok "docker compose 可用"
else
    fail "缺少 docker compose 插件"
    echo "  安装: sudo apt install -y docker-compose-plugin  (或重装 docker-ce 后重试)"
    fail_count=$((fail_count+1))
fi

if docker info >/dev/null 2>&1; then
    ok "Docker 引擎运行中"
else
    warn "Docker 引擎未运行或当前用户无权限"
    echo "  启动: sudo systemctl start docker"
    echo "  免 sudo 使用: sudo usermod -aG docker \$USER && newgrp docker"
    fail_count=$((fail_count+1))
fi

# ---------- Ollama ----------
echo ""
echo "--- Ollama ---"
if command -v ollama >/dev/null 2>&1; then
    ok "ollama $(ollama --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
else
    fail "未找到 ollama"
    echo "  安装: curl -fsSL https://ollama.com/install.sh | sh"
    fail_count=$((fail_count+1))
fi

if curl -s -m 3 http://127.0.0.1:11434/api/version >/dev/null 2>&1; then
    ok "Ollama 服务运行中 (:11434)"
    if ollama list 2>/dev/null | grep -q nomic-embed-text; then
        ok "embedding 模型 nomic-embed-text 已就绪"
    else
        warn "缺少 embedding 模型"
        echo "  安装: ollama pull nomic-embed-text"
        fail_count=$((fail_count+1))
    fi
else
    warn "Ollama 服务未运行"
    echo "  启动: sudo systemctl start ollama"
    fail_count=$((fail_count+1))
fi

# ---------- 关键端口 ----------
echo ""
echo "--- 关键端口占用检查 ---"
for port in 8080 5432 6379 19530 7687 11434; do
    if ss -ltn 2>/dev/null | grep -q ":$port " || netstat -ltn 2>/dev/null | grep -q ":$port "; then
        warn "端口 $port 已被占用（若为项目自身的服务则正常）"
    else
        ok "端口 $port 空闲"
    fi
done

echo ""
echo "============================================"
if [ "$fail_count" -eq 0 ]; then
    echo -e "${GREEN}环境检查通过！可以直接进入部署步骤。${NC}"
    echo "下一步: 参考 deploy/DEPLOYMENT.md 第 4 章"
else
    echo -e "${RED}共发现 $fail_count 项问题，请按上面的提示安装后重试。${NC}"
fi
echo "============================================"
exit $fail_count
