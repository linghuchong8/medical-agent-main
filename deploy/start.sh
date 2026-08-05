#!/usr/bin/env bash
# ============================================
# 天宫医疗智能体 - 启动 (日常)
# ============================================
set -e
cd "$(dirname "$0")/.."

echo "============================================"
echo " 天宫医疗智能体 - 启动 (日常)"
echo "============================================"

# ---------- 0. 尚未部署则自动部署 ----------
if [ ! -f .deployed ]; then
    echo "检测到尚未部署，自动执行部署..."
    bash "$(dirname "$0")/install.sh"
fi

# ---------- 1. Docker ----------
echo ""
echo "[1/3] 检查 Docker..."
if ! docker version >/dev/null 2>&1; then
    sudo systemctl start docker 2>/dev/null || true
    for i in $(seq 1 60); do
        docker version >/dev/null 2>&1 && break
        echo "  等待 Docker 就绪... ($i)"
        sleep 5
    done
fi

# ---------- 2. 容器 ----------
echo ""
echo "[2/3] 确保容器运行..."
docker compose up -d
echo "  容器已启动。"

# ---------- 3. 应用 ----------
echo ""
echo "[3/3] 启动应用 (http://localhost:8080)..."
echo "  按 Ctrl+C 停止"
echo ""
# 清除残留的旧环境变量，确保 .env 里的新 key 生效
unset DEEPSEEK_API_KEY DASHSCOPE_API_KEY HTTP_PROXY HTTPS_PROXY ALL_PROXY 2>/dev/null || true
exec .venv/bin/python -m uvicorn src.main:app --host 0.0.0.0 --port 8080
