#!/usr/bin/env bash
# ============================================
# 天宫医疗智能体 - 部署 (首次一次性)
# ============================================
set -e
cd "$(dirname "$0")/.."

echo "============================================"
echo " 天宫医疗智能体 - 部署 (首次一次性)"
echo "============================================"

# ---------- 1. Python ----------
echo ""
echo "[1/7] 检查 Python (需 >= 3.13)..."
if ! command -v python3 >/dev/null 2>&1; then
    echo "  [错误] 未找到 python3，请先安装 Python 3.13"
    echo "  参考: deploy/DEPLOYMENT.md 第 4.1 节"
    exit 1
fi
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3,13) else 1)' || {
    echo "  [错误] python3 版本低于 3.13: $(python3 --version)"
    exit 1
}

# ---------- 2. 虚拟环境 + 依赖 ----------
echo ""
echo "[2/7] 检查虚拟环境..."
if [ ! -x .venv/bin/python ]; then
    echo "  创建虚拟环境..."
    python3 -m venv .venv
    .venv/bin/python -m pip install --upgrade pip
    echo "  安装依赖 (约几分钟, Linux 用 requirements-linux.txt)..."
    .venv/bin/python -m pip install -r requirements-linux.txt
else
    echo "  虚拟环境已存在"
fi

# ---------- 3. .env ----------
echo ""
echo "[3/7] 检查 .env 配置..."
if [ ! -f .env ]; then
    cp .env.example .env
    echo "  已生成 .env，请编辑填写 DEEPSEEK_API_KEY:"
    echo "    vi .env"
    echo "  填写完保存后，按回车继续..."
    read -r _
else
    echo "  .env 已存在"
fi

# ---------- 4. Docker ----------
echo ""
echo "[4/7] 检查 Docker..."
if ! docker version >/dev/null 2>&1; then
    echo "  启动 Docker 服务..."
    sudo systemctl start docker 2>/dev/null || true
    for i in $(seq 1 60); do
        docker version >/dev/null 2>&1 && break
        echo "  等待 Docker 就绪... ($i)"
        sleep 5
    done
fi
if ! docker version >/dev/null 2>&1; then
    echo "  [错误] Docker 不可用，请参考 deploy/DEPLOYMENT.md 第 4.1 节安装"
    exit 1
fi
echo "  Docker 已就绪。"

# ---------- 5. 容器 ----------
echo ""
echo "[5/7] 启动基础设施容器..."
docker compose up -d
echo "  等待容器就绪 (最多 5 分钟)..."
for i in $(seq 1 60); do
    if ! docker compose ps | grep -qE "starting|unhealthy"; then
        break
    fi
    sleep 5
done
echo "  容器已就绪。"

# ---------- 6. 初始化数据库 (首次) ----------
echo ""
echo "[6/7] 初始化数据库..."
if [ ! -f .deployed ]; then
    echo "  正在建表 (alembic)..."
    .venv/bin/python -m alembic upgrade head
    echo "  正在导入 PostgreSQL 医学数据 (约 2-3 分钟)..."
    .venv/bin/python scripts/init_postgres.py
    echo "  正在构建 Neo4j 知识图谱 (约 5-10 分钟)..."
    .venv/bin/python scripts/init_neo4j.py
    touch .deployed
    echo "  数据库初始化完成。"
else
    echo "  已初始化过，跳过。"
fi

# ---------- 7. Ollama ----------
echo ""
echo "[7/7] 检查 Ollama..."
if ! curl -s -m 5 http://127.0.0.1:11434/api/version >/dev/null 2>&1; then
    echo "  [警告] Ollama 未运行，长期记忆功能不可用 (对话不受影响)"
    echo "  启动: sudo systemctl start ollama"
else
    echo "  Ollama 运行中"
    if ! ollama list 2>/dev/null | grep -q nomic-embed-text; then
        echo "  拉取 embedding 模型 nomic-embed-text (约 274MB)..."
        ollama pull nomic-embed-text
    else
        echo "  embedding 模型已就绪"
    fi
fi

echo ""
echo "============================================"
echo " 部署完成！日常启动请运行: deploy/start.sh"
echo "============================================"
