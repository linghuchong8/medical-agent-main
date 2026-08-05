import asyncio

import pytest


@pytest.fixture(scope="session", autouse=True)
async def _close_shared_redis_clients():
    """在共享事件循环关闭前，主动关闭模块级 Redis 客户端，避免 'Event loop is closed'。"""
    yield
    from src.infra.redis_cache import _checkpointer_client, _redis_client

    for client in (_redis_client, _checkpointer_client):
        try:
            await asyncio.wait_for(client.aclose(), timeout=5)
        except Exception:
            pass
