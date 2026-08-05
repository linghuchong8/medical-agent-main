import asyncio

from langchain.agents.middleware import SummarizationMiddleware
from langgraph.checkpoint.redis import AsyncRedisSaver
from langchain.agents import create_agent
from langchain_deepseek.chat_models import ChatDeepSeek

from src.agents.store_tools import save_memory, search_memory
from src.infra.milvus_client import get_milvus_client_alias
from src.infra.milvus_store import MilvusStore
from src.infra.redis_cache import get_checkpointer_redis
from dotenv import load_dotenv
from loguru import logger
load_dotenv()


def _get_embedding_model():
    """返回向量化模型。使用本地 Ollama 的 nomic-embed-text（免费离线）。"""
    from langchain_ollama import OllamaEmbeddings
    return OllamaEmbeddings(
        model="nomic-embed-text",
        base_url="http://127.0.0.1:11434",
        keep_alive=-1,
    )


async def _warmup_embedding(embedding_model) -> None:
    """预热 Ollama 模型：模型首次加载期间 embed 请求会 503，需重试等待加载完成。"""
    import asyncio as _asyncio
    last_exc: Exception | None = None
    for attempt in range(6):
        try:
            await embedding_model.aembed_query("预热")
            return
        except Exception as e:
            last_exc = e
            await _asyncio.sleep(min(2 ** attempt, 20))
    if last_exc:
        logger.warning(f"Ollama 模型预热失败，将在首次使用时重试: {last_exc}")

# 创建出 监督 Agent
async def create_supervisor_agent():
    # 1. 复用项目已有的 checkpointer 专用 Redis 客户端（bytes 模式）
    redis_client = get_checkpointer_redis()

    # 2. 创建 AsyncRedisSaver，并调用 asetup() 初始化 RediSearch 索引
    # asetup() 会在 Redis Stack 中创建 checkpoint / checkpoint_write 两个索引
    # 必须在首次使用前调用一次，索引已存在时自动跳过，可以重复调用
    checkpointer = AsyncRedisSaver(redis_client=redis_client)
    await checkpointer.asetup()


    # 3. 长期记忆
    # ── 长期记忆：Milvus Store ─────────────────────────────────────────
    milvus_alias = get_milvus_client_alias()
    embedding_model = _get_embedding_model()
    await _warmup_embedding(embedding_model)
    store = MilvusStore(
        alias=milvus_alias,
        embeddings=embedding_model,
        dims=768,   # nomic-embed-text 输出 768 维
    )

    # 4. 长期记忆工具
    tools = [save_memory, search_memory]

    # 4. 创建 Agent
    agent = create_agent(
        model="deepseek-v4-flash",
        tools=tools,
        system_prompt=(
            "你是天宫医疗的智能助手。"
            "当用户提到重要的个人信息或病史时，使用 save_memory 工具记住它。"
            "当需要回忆用户历史信息时，使用 search_memory 工具检索。"
        ),
        checkpointer=checkpointer, # 短期记忆. agent chat ui（禁用你配置 checkpointer）
        store=store # 长期记忆. 把同一个用户，任意会话的有价值信息进行存储。
    )
    return agent


# 模块级单例：避免每次请求都重新创建 agent 和 checkpointer
_supervisor_agent = None
_supervisor_agent_lock: asyncio.Lock | None = None

# 返回 agent
async def get_supervisor_agent():
    """返回全局单例 Agent，首次调用时初始化（加锁防止并发重复创建）。"""
    global _supervisor_agent, _supervisor_agent_lock
    if _supervisor_agent is None:
        if _supervisor_agent_lock is None:
            _supervisor_agent_lock = asyncio.Lock()
        async with _supervisor_agent_lock:
            if _supervisor_agent is None:
                _supervisor_agent = await create_supervisor_agent()
    return _supervisor_agent


# FastAPI 路由中使用
async def chat_endpoint(user_id: str, session_id: str, message: str):
    # 使用单例，不重复初始化。获取 agent
    agent = await get_supervisor_agent()

    # thread_id 用来区分不同会话。  用户id:会话id:日期（前端传来一个会话id）
    config = {"configurable": {"thread_id": f"{user_id}:{session_id}"}}

    result = await agent.ainvoke(
        {"messages": [{"role": "user", "content": message}]},
        config=config,
    )
    return result["messages"][-1].content