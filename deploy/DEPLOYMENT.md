# 天宫医疗智能体 —— 部署文档

> 适用场景：**全新机器**（从零安装操作系统后）快速部署并完整跑通。
> 覆盖平台：**Windows** 与 **Linux**（Ubuntu/Debian 为主，附 CentOS/RHEL 备选命令）。
> 版本要求：**Python 3.13**（必须，3.12/3.14 会导致依赖安装失败或运行异常）。
> 阅读方式：本文档是**手把手流程**——每条命令都附「✔ 预期输出」和「✘ 失败排查」，照着做即可。

---

## 目录

1. [架构总览](#1-架构总览)
2. [部署前置条件清单](#2-部署前置条件清单)
3. [部署流程总览](#3-部署流程总览)
4. [Windows 全新部署](#4-windows-全新部署)
5. [Linux 全新部署](#5-linux-全新部署)
6. [部署后验证](#6-部署后验证)
7. [日常运维](#7-日常运维)
8. [常见问题排查](#8-常见问题排查)

---

## 1. 架构总览

```
浏览器 / HTTP 客户端
        │  :8080
        ▼
  FastAPI 应用 (uvicorn)  ──┬── PostgreSQL   :5432   结构化数据（药品/疾病/患者）
   src/main.py              ├── Redis        :6379   会话短期记忆（LangGraph checkpoint）
        │                   ├── Milvus       :19530  长期记忆向量库（Agent 记忆）
        │                   ├── MinIO       :9000   文件存储（知识文档）
        │                   ├── Neo4j       :7687   医学知识图谱
        │                   └── attu        :3000   Milvus 可视化客户端（可选）
        │
        ├── Ollama :11434  ── nomic-embed-text   本地向量化（长期记忆）
        └── DeepSeek API（外部）── deepseek-v4-flash  聊天/推理模型
```

**各组件作用与缺失影响：**

| 组件 | 必需性 | 缺失时影响 |
|---|---|---|
| PostgreSQL + Redis + MinIO + Milvus + Neo4j（Docker 一组起） | 必需 | `/health/deps` 降级，相关功能不可用 |
| Ollama + nomic-embed-text | 必需 | 长期记忆（保存/检索病史、过敏史）不可用 |
| DeepSeek API Key | 必需 | Agent 无法对话 |
| attu | 可选 | 仅 Milvus 可视化，不影响功能 |

**端口占用表：**

| 端口 | 服务 | 说明 |
|---|---|---|
| 8080 | FastAPI 应用 | 主入口 |
| 5432 | PostgreSQL | |
| 6379 / 8001 | Redis / RedisInsight | |
| 19530 / 9091 | Milvus gRPC / HTTP | |
| 9000 / 9001 | MinIO / 控制台 | |
| 7474 / 7687 | Neo4j WebUI / Bolt | |
| 3000 | attu | Milvus 可视化 |
| 11434 | Ollama | 本地 embedding |

---

## 2. 部署前置条件清单

部署前确认以下软件可用（**全新机器需逐一安装，见第 4/5 章**）：

| 软件 | 最低版本 | Windows 检测 | Linux 检测 |
|---|---|---|---|
| Python | **3.13.x** | `python --version` | `python3 --version` |
| Docker | 20+（含 compose 插件） | `docker version` | `docker --version` |
| Docker Compose | 2.x | `docker compose version` | `docker compose version` |
| Ollama | 0.5+ | `ollama --version` | `ollama --version` |
| Git（可选） | - | `git --version` | `git --version` |

> ⚠️ **系统中若已存在 `DEEPSEEK_API_KEY` 环境变量，会覆盖 `.env` 中的配置**（旧 key 会报 401）。
> 部署前建议检查并清空：Linux `unset DEEPSEEK_API_KEY`；Windows `set DEEPSEEK_API_KEY=`。

**快速自检**：Linux 上可直接运行 `bash deploy/check_env.sh`，脚本会逐项检测上述软件并在缺失时给出安装命令。

---

## 3. 部署流程总览

```
全新机器
  │
  ▼
① 安装系统软件  Python 3.13 / Docker / Ollama    ← 第 4.1 章（Win）/ 5.1 章（Linux）
  │                                               每步都带检测命令，缺哪个装哪个
  ▼
② 获取项目代码（git clone 或拷贝）                ← 第 4.2 / 5.2 章
  │
  ▼
③ 部署（三选一）
   ├─ 方式一：deploy\start_dev.bat（推荐）        ← 第 4.3 / 5.3 章，自动完成 ④⑤⑥⑦⑧
   ├─ 方式二：deploy\install.bat  +  deploy\start.bat（部署/启动分开）
   └─ 方式三：全手动                               ← 第 4.4 / 5.4 章
  │
  ▼
④ 创建虚拟环境 + 安装依赖
⑤ 配置 .env（填 DeepSeek key）
⑥ 启动 Docker 容器（Postgres/Redis/Milvus/MinIO/Neo4j）
⑦ 初始化数据库（建表 + 导入医学数据 + 构建知识图谱，仅首次）
⑧ 启动应用（uvicorn :8080）
  │
  ▼
⑨ 验证  /health、/health/deps、浏览器 /chat 对话  ← 第 6 章
```

**三种部署方式对比：**

| 方式 | 命令 | 适用场景 | 特点 |
|---|---|---|---|
| 一键 | `start_dev.bat` / `start_dev.sh` | 全新机器首选 | 自动完成全部部署+启动，之后每次直接跑 |
| 分开 | `install`（首次）+ `start`（日常） | 已部署的机器日常维护 | 首次跑 install 初始化，之后每天跑 start 秒启动 |
| 手动 | 见第 4.4 / 5.4 章 | 排查问题、学习流程 | 每步可控，方便定位问题 |

> `install` 只做一次（用 `.deployed` 标记控制，见 4.3 节）；日常用 `start` 即可。

---

## 4. Windows 全新部署

### 4.1 安装系统软件

#### ① Python 3.13

**步骤：**
1. 打开 https://www.python.org/downloads/ 下载 **Python 3.13** 安装包（x86-64）。
2. 安装时**务必勾选 "Add Python to PATH"**（否则后续找不到 `python` 命令），其余默认即可。
3. 安装完成后，**重新打开**一个命令行窗口再验证。

**✔ 预期输出：**
```bat
C:\> python --version
Python 3.13.4
```

**✘ 失败排查：**
- `'python' 不是内部或外部命令` → 安装时没勾 "Add Python to PATH"，重新安装或手动把 `C:\Python313\` 加进系统 PATH。
- 版本不是 3.13（比如 3.12/3.14）→ 依赖安装会失败，**必须卸载重装 3.13**。

#### ② Docker Desktop

**步骤：**
1. 下载安装 https://www.docker.com/products/docker-desktop/ 。
2. 首次启动会要求启用 WSL2（按提示重启）。若系统无 WSL，先执行 `wsl --install` 并重启。
3. 启动 Docker Desktop，等待右下角图标变为运行状态（约 30 秒~1 分钟）。
4. 验证。

**✔ 预期输出：**
```bat
C:\> docker version
Client: Docker Engine ...
Server: Docker Engine ...     ← 必须出现 Server 部分，代表引擎在运行
C:\> docker compose version
Docker Compose version v2.xx.x
```

**✘ 失败排查：**
- `docker version` 只显示 Client、没有 Server → 引擎没启动，等 Docker Desktop 图标变绿或重启 Docker Desktop。
- WSL2 报错 → 在"设置-应用-可选功能"里安装"适用于 Linux 的 Windows 子系统"，然后重启。
- 权限问题（Linux 容器需要管理员）→ 以管理员身份运行 Docker Desktop。

#### ③ Ollama

**步骤：**
1. 下载安装 https://ollama.com/download/windows 。
2. 安装后 Ollama 常驻后台（托盘可见，开机自启），无需手动启动。
3. 拉取 embedding 模型（约 274MB）。

**✔ 预期输出：**
```bat
C:\> ollama pull nomic-embed-text
pulling ...  100%
verifying sha256 digest
writing manifest
success

C:\> ollama ps
NAME                   ID     SIZE    PROCESSOR    UNTIL
nomic-embed-text:...   ...    849 MB  100% GPU     ...
```

**✘ 失败排查：**
- `ollama` 命令找不到 → 重装 Ollama，或手动把 `%LOCALAPPDATA%\Programs\Ollama` 加进 PATH。
- 拉取失败/超时 → 网络问题，重试；`ollama ps` 无输出 → 模型没加载，重跑 `ollama pull`。

> **快捷方式**：4.1 装好软件后，直接运行 `deploy\start_dev.bat` 即可自动完成 4.2~4.5 全部步骤。以下第 4.2~4.4 节供了解内部逻辑和排查用。

### 4.2 获取项目代码

**✔ 预期输出：**
```bat
C:\> git clone <你的仓库地址> tiangong-agent
Cloning into 'tiangong-agent'...
remote: Enumerating objects: ...
Receiving objects: ... done.
C:\> cd tiangong-agent
```
（没有 Git 可直接拷贝整个项目文件夹）

### 4.3 方式一：脚本一键部署（推荐）

#### 脚本调用关系

```
start_dev.bat（根目录，双击入口）
   └─→ deploy\start_dev.bat         组合：先部署后启动
          ├─→ deploy\install.bat    ① 部署（7 步，仅首次）
          └─→ deploy\start.bat      ② 启动（3 步，日常）
```

#### ① install.bat —— 部署的 7 步详解

首次运行会执行全部 7 步；**再次运行会自动跳过已完成步骤**（.venv/.env 已存在则跳过，`.deployed` 标记存在则跳过初始化）。每天看这里的第 7 步完成后，脚本就绪。

| 步骤 | 做什么 | ✔ 预期输出 | ✘ 失败表现 / 处理 |
|---|---|---|---|
| [1/7] | 检查 Python → 无 `.venv` 则创建并 `pip install -r requirements.txt`（约 3-5 分钟） | `Creating venv...` → pip 进度条 → `venv already exists`（已存在时） | `[ERROR] Python not found...` → 没装 Python 3.13；`[ERROR] Failed to install dependencies` → 网络问题，换 pip 镜像（见 8.2） |
| [2/7] | 无 `.env` 则复制 `.env.example` 并**用记事本打开**，让你填 `DEEPSEEK_API_KEY` | `notepad` 弹出 `.env`；保存后按任意键 | 直接关掉没保存 → 脚本会继续，但后面对话报 401 |
| [3/7] | 检查 Docker，未运行则自动启动 Docker Desktop 并等待（最多 5 分钟） | `Docker ready.` | `[ERROR] Docker start timed out` → 手动打开 Docker Desktop |
| [4/7] | `docker compose up -d` 启动 7 个容器，等待全部 healthy（最多 5 分钟） | 7 行 `Container tiangong-xxx Running` → `Containers ready.` | `[ERROR] Failed to start infra containers` → 见 8.1 端口冲突 / 8.3 镜像拉取 |
| [5/7] | 无 `.deployed` 则初始化数据库：建表 → 导数据 → 建图谱（共 10-15 分钟） | `Creating tables` → `Importing PostgreSQL data` → `Building Neo4j...` → `Database initialized.` / 已存在则 `Already initialized, skip.` | 中途失败会提示具体步骤（alembic/postgres/neo4j），见 8.4 |
| [6/7] | 检查 Ollama，缺 `nomic-embed-text` 则自动拉取 | `Ollama running` → `embedding model ready` | `[WARN] Ollama not running` → 对话正常但长期记忆不可用，手动启动 Ollama 后重跑 |
| [7/7] | 完成 | `Deployment finished` | - |

> **`.deployed` 标记**：首次初始化成功后，项目根目录会生成一个名为 `.deployed` 的空文件。它就是个"已经部署过"的记号——之后每次运行，第 5 步看到它就直接跳过，不用再等 10 分钟。

#### ② start.bat —— 启动的 3 步详解（日常）

| 步骤 | 做什么 | ✔ 预期输出 |
|---|---|---|
| [1/3] | 检查 Docker，未运行则启动 | `Docker ready.` |
| [2/3] | 确保 7 个容器在运行 | `Containers started.` |
| [3/3] | 启动应用（前台，窗口保持打开） | 见下方"应用启动日志" |

> 首次运行 start.bat 时，若发现 `.deployed` 不存在，会自动先调用 install.bat 补做部署，防止直接白屏。

#### ③ 应用启动日志（成功的样子）

```bat
[3/3] Starting app at http://localhost:8080 ...
INFO:     Started server process [12345]
INFO:     Waiting for application startup.
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:8080 (Press CTRL+C to quit)
```

看到 `Application startup complete` 即成功，浏览器打开 **http://localhost:8080/chat**。

> 注意：**命令行窗口要一直开着**，它是应用本体，关掉 = 停服；按 Ctrl+C 正常退出。

### 4.4 方式二：手动部署（详解）

> 与方式一等效，只是每一步手动执行，方便理解与排查。

#### ① 创建虚拟环境并安装依赖

```bat
python -m venv .venv
.venv\Scripts\activate
python -m pip install --upgrade pip
pip install -r requirements.txt
```

**✔ 预期输出：** 最后看到 `Successfully installed ...`（237 个包）
**✘ 失败排查：** 见 8.2（网络/镜像/版本）。

#### ② 配置环境变量

```bat
copy .env.example .env
```
然后用记事本打开 `.env`（`notepad .env`）。**全部字段说明：**

| 字段 | 含义 | 默认值 | 是否需改 |
|---|---|---|---|
| `APP_NAME` / `APP_ENV` / `APP_DEBUG` | 应用名/环境/调试 | tiangong-agent / dev / true | 否 |
| `DB_HOST` `DB_PORT` `DB_USER` `DB_PASSWORD` `DB_NAME` | PostgreSQL 连接 | localhost / 5432 / medical / medical123 / medical_db | 否（与 docker-compose 一致） |
| `REDIS_HOST` `REDIS_PORT` `REDIS_PASSWORD` `REDIS_DB` | Redis 连接 | localhost / 6379 / 空 / 0 | 否 |
| `MINIO_ENDPOINT` `MINIO_ACCESS_KEY` `MINIO_SECRET_KEY` `MINIO_BUCKET` `MINIO_SECURE` | MinIO 对象存储 | localhost:9000 / minioadmin / minioadmin / knowledge-docs / false | 否 |
| `MILVUS_HOST` `MILVUS_PORT` | Milvus 向量库 | localhost / 19530 | 否 |
| `NEO4J_URI` `NEO4J_USER` `NEO4J_PASSWORD` | Neo4j 图谱 | bolt://localhost:7687 / neo4j / medical123 | ⚠️ 宿主机 7687 被占用时需改（见 8.1） |
| `DASHSCOPE_API_KEY` `BASE_URL_CHAT` `CHAT_MODEL` | 阿里 DashScope（已不用） | - | 留空即可 |
| **`DEEPSEEK_API_KEY`** | **DeepSeek 对话密钥** | xxx | ✅ **必须填**，填 `sk-` 开头的一串 |
| `DEEPSEEK_MODEL` | DeepSeek 模型名 | deepseek-v4-flash | 否（写死勿改） |
| `LOG_LEVEL` `LOG_DIR` | 日志 | DEBUG / logs | 否 |

**✔ 预期输出：** 保存后，确保 `DEEPSEEK_API_KEY=sk-你的key` 那一行非空。

#### ③ 启动基础设施（Docker）

```bat
docker compose up -d
```

**✔ 预期输出：** 每个服务一行 `Container tiangong-xxx Started`。然后查看状态：
```bat
docker compose ps
```
期望 7 个容器全部 `Up` 且 `(healthy)`：

```
NAMES                   STATUS
tiangong-postgres       Up 1 minute (healthy)
tiangong-redis          Up 1 minute (healthy)
tiangong-milvus         Up 1 minute (healthy)
tiangong-minio          Up 1 minute (healthy)
tiangong-neo4j          Up 1 minute (healthy)
tiangong-milvus-etcd    Up 1 minute
tiangong-attu           Up 1 minute
```

**7 个服务分别是什么：**

| 服务 | 作用 | 健康状态判断 |
|---|---|---|
| postgres | 结构化数据（药品/疾病/患者/问诊） | `(healthy)` |
| redis | 会话短期记忆（Redis Stack，含 RedisJSON） | `(healthy)` |
| etcd | Milvus 的元数据存储 | 无健康检查，`Up` 即可 |
| minio | 对象存储（知识文档文件） | `(healthy)` |
| milvus | 向量数据库（长期记忆） | `(healthy)`（最慢，启动 1-2 分钟） |
| attu | Milvus 可视化界面（可选） | `Up` 即可 |
| neo4j | 医学知识图谱 | `(healthy)` |

**✘ 失败排查：**
- 某个容器反复 `(health: starting)` 或 `unhealthy` → 见 8.1（端口冲突）、8.3（镜像）。
- `docker compose ps` 报端口占用 → 宿主机已有同名服务（见 8.1）。

#### ④ 初始化数据库（仅首次，约 10-15 分钟）

```bat
:: 1) 建表（Alembic 迁移）
alembic upgrade head

:: 2) 导入医学数据到 PostgreSQL（约 2-3 分钟）
python scripts/init_postgres.py

:: 3) 构建 Neo4j 知识图谱（约 5-10 分钟）
python scripts/init_neo4j.py
```

**✔ 预期输出：**

`alembic upgrade head`：
```
INFO  [alembic.runtime.migration] Running upgrade  -> b3469536e763, init schema
INFO  [alembic.runtime.migration] Running upgrade b3469536e763 -> 147c08d69b76, init medical schema
```

`init_postgres.py` 结尾统计（tqdm 进度条后）：
```
PostgreSQL 数据导入完成
  科室:         54 个
  症状:       5998 种
  药品:       3828 种
  疾病:       8807 条
  疾病-症状关联: 54707 条
  疾病-药品关联: 74119 条
```

`init_neo4j.py` 结尾统计（若你看到各实体/关系条数接近下表即成功）：
```
Neo4j 知识图谱构建完成
  节点: Disease 8807 / Symptom 5998 / Drug 3828 / Food 4746 / Check 3353 / Department 54
  关系: RECOMMEND_DRUG 59465 / HAS_SYMPTOM 54710 / DO_EAT 40221 / NEED_CHECK 39418 /
        NO_EAT 22239 / BELONGS_TO 16781 / COMMON_DRUG 14647 / ACOMPANY_WITH 12024
```

**✘ 失败排查：** 见 8.4。若想验证 Neo4j：浏览器打开 http://localhost:7474 （neo4j/medical123）运行 `MATCH (n) RETURN count(n)`。

### 4.5 启动应用（方式三：手动）

```bat
.venv\Scripts\python.exe -m uvicorn src.main:app --host 0.0.0.0 --port 8080
```

**✔ 预期输出：** 见 4.3 的"应用启动日志"。浏览器打开 **http://localhost:8080/chat**。

---

## 5. Linux 全新部署

> 以 **Ubuntu 22.04/24.04（Debian 系）** 为主命令，**CentOS/RHEL（RPM 系）** 的差异用「RHEL：」标注。

### 5.1 安装系统软件

#### ① 基础工具

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y curl git ca-certificates
# RHEL/CentOS 9
sudo dnf install -y curl git ca-certificates
```

**✔ 预期输出：** 无报错、最后出现 `Setting up ...` 完成提示。

#### ② Python 3.13

先检测：
```bash
python3 --version
```
- 输出 `Python 3.13.x` → 直接跳到 ③。
- 否则按下面二选一安装。

**方式 A：Ubuntu 用 deadsnakes PPA（推荐）**
```bash
sudo add-apt-repository ppa:deadsnakes/ppa -y
sudo apt update
sudo apt install -y python3.13 python3.13-venv python3.13-dev
python3.13 --version
```
**✔ 预期输出：** `Python 3.13.x`。

**方式 B：pyenv（通用，任意发行版）**
```bash
curl -fsSL https://pyenv.run | bash
# 把以下三行追加到 ~/.bashrc（重启 shell 生效）
echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.bashrc
echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(pyenv init -)"' >> ~/.bashrc
exec "$SHELL"
# 先装编译依赖（Ubuntu）：
sudo apt install -y build-essential libssl-dev zlib1g-dev libbz2-dev \
  libreadline-dev libsqlite3-dev libffi-dev libncurses-dev
# 然后
pyenv install 3.13
pyenv global 3.13
python3 --version
```
**✔ 预期输出：** `Python 3.13.x`。

> 后续命令统一用 `python3`。

#### ③ Docker Engine + Compose 插件

```bash
# 官方一键脚本（自动适配发行版），需要 sudo
curl -fsSL https://get.docker.com | sudo sh

# 让当前用户免 sudo 使用 docker（重要，否则每次都要 sudo）
sudo usermod -aG docker $USER
newgrp docker

# 启动并设置开机自启
sudo systemctl enable --now docker

# 验证
docker --version
docker compose version
docker run --rm hello-world
```

**✔ 预期输出：** `Hello from Docker!`（最后一行）+ `Docker Compose version v2.xx.x`。
**✘ 失败排查：** `docker compose` 不存在 → `sudo apt install -y docker-compose-plugin`（或重装 docker-ce 后重试）；`permission denied` → 没执行 `usermod -aG docker` 或没重新登录。

#### ④ Ollama

```bash
# 官方安装脚本（自动装成 systemd 服务）
curl -fsSL https://ollama.com/install.sh | sh

# 确认服务运行
ollama --version
sudo systemctl status ollama --no-pager | head -5

# 拉取 embedding 模型
ollama pull nomic-embed-text
```

**✔ 预期输出：** `ollama --version` 显示版本；`systemctl status` 显示 `Active: active (running)`；pull 结束显示 `success`。

> 无独立显卡也没关系，nomic-embed-text 很小，CPU 即可流畅运行。

> **快捷方式**：5.1 装好软件后，先 `chmod +x deploy/*.sh`，再运行 `deploy/start_dev.sh` 即可自动完成 5.2~5.5 全部步骤。以下为手动流程，供了解与排查。

### 5.2 获取项目代码

```bash
git clone <你的仓库地址> tiangong-agent
cd tiangong-agent
```

### 5.3 方式一：脚本一键部署

与 Windows 版逻辑完全一致，只是换成了 bash 脚本：

```
start_dev.sh
   ├─→ install.sh   部署（7 步，仅首次，用 .deployed 标记控制）
   └─→ start.sh     启动（3 步，日常）
```

首次运行前给脚本加执行权限：
```bash
chmod +x deploy/install.sh deploy/start.sh deploy/start_dev.sh
```

**install.sh 的 7 步（与 install.bat 对应）：**

| 步骤 | 做什么 | ✔ 预期输出 | ✘ 失败排查 |
|---|---|---|---|
| [1/7] | 建 `.venv` + 装 `requirements-linux.txt` | `Creating virtual env...` → pip 进度 | `[ERROR] python3 版本低于 3.13` → 见 5.1② |
| [2/7] | 生成 `.env` 并提示编辑填 key | `vi .env` 提示 | 没填 key → 对话 401 |
| [3/7] | 启动 Docker 服务并等待 | `Docker ready.` | `[ERROR] Docker 不可用` → 见 5.1③ |
| [4/7] | `docker compose up -d` + 等 healthy | 7 容器 `Running` → `容器已就绪` | 端口冲突见 8.1 |
| [5/7] | 首次初始化数据库（alembic + postgres + neo4j） | `Database initialized.` / `Already initialized, skip.` | 见 8.4 |
| [6/7] | 检查 Ollama + 拉模型 | `embedding 模型已就绪` | `[WARN] Ollama 未运行` → `sudo systemctl start ollama` |
| [7/7] | 完成 | `部署完成！` | - |

**start.sh 的 3 步：** 检查 Docker → `docker compose up -d` → 启动 uvicorn（`exec .venv/bin/python -m uvicorn ...`）。

### 5.4 方式二：手动部署（详解）

#### ① 创建虚拟环境并安装依赖

> ⚠️ **Linux 用 `requirements-linux.txt`**（已剔除 `pywin32` 等 Windows 专属包；用 `requirements.txt` 会安装失败）。

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -r requirements-linux.txt
```

**✔ 预期输出：** `Successfully installed ...`
**✘ 失败排查：** 见 8.2。

#### ② 配置环境变量

```bash
cp .env.example .env
vi .env   # 填 DEEPSEEK_API_KEY
```
字段说明与 Windows 完全一致（见 4.4 ② 的字段表）。**至少填 `DEEPSEEK_API_KEY`。**

#### ③ 启动基础设施

```bash
docker compose up -d
docker compose ps
```
期望 7 个容器 `Up (healthy)`（见 4.4 ③ 的容器表）。

#### ④ 初始化数据库

```bash
alembic upgrade head
python scripts/init_postgres.py    # 约 2-3 分钟
python scripts/init_neo4j.py       # 约 5-10 分钟
```
预期输出与 Windows 相同（见 4.4 ④ 的统计数字）。

### 5.5 启动应用（方式三：手动）

```bash
.venv/bin/python -m uvicorn src.main:app --host 0.0.0.0 --port 8080
```
看到 `Application startup complete` 即成功，浏览器打开 `http://<服务器IP>:8080/chat`。

> 部署前可用 `bash deploy/check_env.sh` 一键自检环境是否齐全。

---

## 6. 部署后验证

| 检查项 | 命令 / 地址 | ✔ 期望输出 |
|---|---|---|
| 应用健康 | `curl http://localhost:8080/health` | `{"status":"ok"}` |
| 依赖健康 | `curl http://localhost:8080/health/deps` | 5 个依赖全部 `"ok":true`（见下方样例） |
| 聊天页面 | 浏览器 `http://localhost:8080/chat` | 页面可打开、能对话 |
| 长期记忆 | 对话中发「记住，我血压偏高、对花生过敏」，换会话问「我有什么病史」 | 能回忆起写入的内容 |
| 自动测试（可选） | `pytest test -v` | `3 passed`（需 API Key，约 1 分钟） |

**`/health/deps` 成功时的完整返回：**
```json
{"status":"ok","dependencies":{
  "postgres":{"ok":true,"error":""},
  "redis":{"ok":true,"error":""},
  "minio":{"ok":true,"error":""},
  "milvus":{"ok":true,"error":""},
  "neo4j":{"ok":true,"error":""}}}
```
- `status:"ok"` 且 5 个依赖全 `ok:true` → 基础设施全部就绪。
- 某个依赖 `ok:false` 带 error → 该服务没起或连不上，对照 8.1/8.3 排查。

**`pytest test -v` 成功时的结尾：**
```
test/test_supervisor_agent.py::test_supervisor_agent PASSED
test/test_supervisor_agent.py::test_agent_memory PASSED
test/test_supervisor_agent.py::test_agent_store PASSED
======================== 3 passed in 49.33s ========================
```

---

## 7. 日常运维

### 启动 / 停止

| 操作 | Windows | Linux |
|---|---|---|
| 一键部署+启动（全新机器） | 双击 `start_dev.bat` | `deploy/start_dev.sh` |
| 仅部署（首次一次性） | `deploy\install.bat` | `deploy/install.sh` |
| 仅启动（日常） | `deploy\start.bat` | `deploy/start.sh` |
| 停止应用 | 窗口 Ctrl+C | `Ctrl+C` 或 `kill` 进程 |
| 停止基础设施 | `docker compose down` | `docker compose down` |
| 清空基础设施数据 | `docker compose down -v` | `docker compose down -v` |

> `deploy/*.sh` 需先 `chmod +x`。
> `install` 只执行一次（初始化用 `.deployed` 标记控制）；日常用 `start` 即可。

### 日志

- 应用日志：`logs/YYYY-MM-DD.log`（项目根目录，按天滚动，保留 30 天）
- 基础设施日志：`docker compose logs -f <服务名>`（如 `docker compose logs -f milvus`）
- Ollama 日志：Windows `%LOCALAPPDATA%\Ollama`；Linux `journalctl -u ollama`

### 升级

```bash
git pull                                            # 拉取新代码
pip install -r requirements-linux.txt               # 安装新依赖（Windows 用 requirements.txt）
alembic upgrade head                                # 有数据库变更时执行
docker compose pull && docker compose up -d         # 更新镜像并重启容器
```

---

## 8. 常见问题排查

### 8.1 端口被占用（部署后某依赖连不上）
- 常见：宿主机已有 **Neo4j / Redis / PostgreSQL** 占用了 7687 / 6379 / 5432。
- 排查：`netstat -ano | findstr <端口>`（Windows）或 `ss -ltn | grep <端口>`（Linux）。
- 解决：停掉占用进程；或改 `docker-compose.yml` 里该服务的宿主机端口映射（如 `"7688:7687"`），并同步改 `.env` 对应连接地址。
- 典型：宿主机装了 Neo4j 服务占 7687 → 先 `net stop neo4j`（Windows）或 `sudo systemctl stop neo4j`（Linux）。

### 8.2 依赖装不上
- Linux 报错含 `pywin32`、`win32_setctime` → 用错了文件，**改用 `requirements-linux.txt`**。
- 下载慢/超时 → 换国内镜像：
  ```bash
  pip install -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple
  ```
- Windows 报错缺少编译工具 → 确认用的是 Python 3.13（3.12/3.14 常缺 wheel）。

### 8.3 Docker 镜像拉取慢 / 失败
- 首次 `docker compose up -d` 需拉约 2-5 GB 镜像，慢属正常。
- 失败重试：`docker compose pull && docker compose up -d`。
- Docker Hub 慢 → 配置加速镜像（编辑 Docker Desktop 的 daemon.json，或 Linux `/etc/docker/daemon.json` 加 `registry-mirrors`）。

### 8.4 初始化数据库失败
- 确保先 `docker compose ps` 全 healthy 再初始化。
- `alembic` 报连不上 → PostgreSQL 没就绪，等 healthy 再跑。
- 数据导入中断 → 脚本幂等可重跑；Neo4j 图谱中断可重跑（会清空重建）。

### 8.5 对话报 401 / "Your api key is invalid"
- 应用读到的 Key 不是 `.env` 里的：系统环境变量 `DEEPSEEK_API_KEY`（旧值）覆盖了 `.env`。
- 解决：`unset DEEPSEEK_API_KEY`（Linux）/ `set DEEPSEEK_API_KEY=`（Windows）后重启应用；或把系统环境变量更新为正确 Key。

### 8.6 长期记忆报「记忆保存/检索失败」
- 多为 Ollama 未启动或模型未加载。
- 排查：`ollama ps` 应显示 `nomic-embed-text`；没有就 `ollama pull nomic-embed-text`。
- 本项目已内置：模型常驻（keep_alive=-1）、首次自动预热重试，通常无需人工干预。
- 若 Milvus 集合维度报错（1024 vs 768）：说明集合是旧版本建的，删除后重建：
  ```bash
  python -c "from pymilvus import utility, connections; connections.connect('t', host='localhost', port=19530); utility.drop_collection('agent_long_term_memory', using='t')"
  ```

### 8.7 对话报 400 "assistant message with tool_calls ..."
- 原因：Redis 中某会话的短期记忆状态损坏（历史上某次工具调用中断所致）。
- 已内建自愈：再遇到时服务端会自动重置该会话并重试，无需人工处理。
- 手动清空所有会话状态（会丢短期对话上下文，长期记忆在 Milvus 不受影响）：
  ```bash
  docker exec tiangong-redis redis-cli --scan --pattern 'checkpoint*' | xargs -r docker exec -i tiangong-redis redis-cli del
  ```

### 8.8 模型 / 对话很慢
- 首次对话会经历 Ollama 模型预热（几秒~几十秒），属正常。
- DeepSeek 为外部 API，网络差时单轮可能 10-30 秒；已设 180 秒超时保护。

### 8.9 修改了代码没生效
- 应用以非 `--reload` 方式启动时，改代码后需重启应用进程。
