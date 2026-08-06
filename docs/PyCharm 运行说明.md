# PyCharm 运行说明

> 本机用 PyCharm 直接运行本项目的步骤。
> 前置：项目已按《克隆部署教程》部署过一次（依赖已装入 `.venv`、`.env` 已配置）。

---

## 1. 前置准备（PyCharm 外完成）

> 这两步不在代码里，需要先手动就绪，否则运行配置连不上数据库。

### ① 启动 Docker 基础设施

```sh
# 启动 Docker Desktop（Windows），等图标变绿
docker compose up -d
docker compose ps        # 7 个容器都应 Up / (healthy)
```

### ② 启动 Ollama（长期记忆需要）

```sh
ollama ps                # 应显示 nomic-embed-text；没有则 ollama pull nomic-embed-text
```

### ③ 确认 .env

项目根目录存在 `.env` 且 `DEEPSEEK_API_KEY` 已填（`copy .env.example .env` 后填写）。

---

## 2. 用 PyCharm 打开项目

1. 打开 PyCharm → **Open** → 选择项目根目录（`D:\develop\medical-agent-main\medical-agent-main`）
2. 弹出的信任窗口点 **Trust Project**

## 3. 配置 Python 解释器

1. **File → Settings → Project → Python Interpreter → Add Interpreter → Existing**
2. 选择虚拟环境解释器：
   - Windows：`.venv\Scripts\python.exe`
   - Linux/macOS：`.venv/bin/python`
3. 确认版本为 **Python 3.13**（3.12/3.14 会依赖安装失败）

## 4. 创建运行配置

右上角运行配置下拉 → **Edit Configurations…** → **＋** → **FastAPI**

| 项 | 填法 |
|---|---|
| Module name | `uvicorn` |
| Script path / Target | `src.main:app` |
| Host | `127.0.0.1` |
| Port | `8080` |
| Working directory | **项目根目录**（必须，否则 `.env` 读不到、连不上库） |

> 若 PyCharm 没有 FastAPI 类型，用 **Python** 类型：Module name = `uvicorn`，Parameters = `src.main:app --host 0.0.0.0 --port 8080`，其余同上。

点 **Apply → OK** 保存。

## 5. 运行与验证

1. 点绿色 **Run** 按钮
2. 控制台出现即成功：
   ```
   Application startup complete.
   Uvicorn running on http://127.0.0.1:8080
   ```
3. 浏览器打开 **http://localhost:8080/chat** 开始对话
4. 可选：`curl http://localhost:8080/health/deps` 应返回 5 个依赖全部 `"ok":true`

---

## 6. 常见问题

| 现象 | 原因 / 处理 |
|---|---|
| 启动报连不上 PostgreSQL/Redis 等 | Docker 没起或容器没起：`docker compose up -d` |
| 启动日志 `no file named .env` / 连库失败 | Working directory 不是项目根目录，改运行配置 |
| 对话正常但保存/检索记忆报错 | Ollama 未运行或模型未拉：`ollama pull nomic-embed-text` |
| 对话报 401 invalid api key | 系统环境变量 `DEEPSEEK_API_KEY` 覆盖了 `.env`，清空后重启 |
| 8080 端口被占用 | 改运行配置 Port，或先关掉占用 8080 的进程 |
