# 医疗智能体（Medical Agent）

解决医疗领域的 Agent 业务构建。包括：
1. 智慧问诊 Agent
2. 报告解读 Agent
3. 药物 Agent
4. 知识文档 Agent
5. 运营数据 Agent

## 部署教程

> 从 GitHub 克隆到部署成功跑通的完整教程（Windows / Linux，含一键脚本与手动两种方式）：
>
> 👉 [docs/克隆部署教程.md](docs/克隆部署教程.md)

### 快速开始

```sh
git clone https://github.com/linghuchong8/medical-agent-main.git
cd medical-agent-main

# 配置 .env（至少填 DEEPSEEK_API_KEY）
copy .env.example .env   # Windows
cp .env.example .env     # Linux
```

- **Windows**：装好 [Python 3.13](https://www.python.org/downloads/)、[Docker Desktop](https://www.docker.com/products/docker-desktop/)、[Ollama](https://ollama.com/download/windows) 后，双击 `start_dev.bat`。
- **Linux**：装好 Python 3.13、Docker、Ollama 后，`chmod +x deploy/*.sh && ./deploy/start_dev.sh`。

启动后访问 **http://localhost:8080/chat**。

