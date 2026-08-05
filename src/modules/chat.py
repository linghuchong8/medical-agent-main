import asyncio

from fastapi import APIRouter, HTTPException
from fastapi.responses import HTMLResponse
from loguru import logger
from pydantic import BaseModel

from src.agents.supervisor_agent import chat_endpoint

router = APIRouter(prefix="/api/v1", tags=["chat"])
page_router = APIRouter()

# 模型响应最长等待时间（秒），超时返回友好错误，避免请求无限挂起
CHAT_TIMEOUT_SECONDS = 180


class ChatRequest(BaseModel):
    user_id: str
    session_id: str
    message: str


class ChatResponse(BaseModel):
    user_id: str
    session_id: str
    reply: str


@router.post("/chat", response_model=ChatResponse)
async def chat(req: ChatRequest) -> ChatResponse:
    """调用天宫医疗 Agent 进行对话。"""
    try:
        reply = await asyncio.wait_for(
            chat_endpoint(req.user_id, req.session_id, req.message),
            timeout=CHAT_TIMEOUT_SECONDS,
        )
    except asyncio.TimeoutError:
        logger.error(f"对话超时（>{CHAT_TIMEOUT_SECONDS}s）: user={req.user_id} session={req.session_id}")
        raise HTTPException(status_code=504, detail="模型响应超时，请稍后重试")
    except Exception as e:
        # 会话状态损坏（Redis checkpoint 里 assistant tool_calls 缺少工具结果）时，
        # 自动重置该会话并重试一次，避免用户手动清 Redis
        if "tool_calls" in str(e) and "tool messages" in str(e):
            thread_id = f"{req.user_id}:{req.session_id}"
            logger.warning(f"检测到损坏的会话状态，重置 thread 并重试: {thread_id} | {e}")
            await _reset_thread_checkpoints(thread_id)
            try:
                reply = await asyncio.wait_for(
                    chat_endpoint(req.user_id, req.session_id, req.message),
                    timeout=CHAT_TIMEOUT_SECONDS,
                )
            except Exception as e2:
                logger.exception(f"重置后对话仍失败: user={req.user_id} session={req.session_id} error={e2}")
                raise HTTPException(status_code=500, detail=f"对话失败：{e2}")
        else:
            logger.exception(f"对话失败: user={req.user_id} session={req.session_id} error={e}")
            raise HTTPException(status_code=500, detail=f"对话失败：{e}")
    return ChatResponse(user_id=req.user_id, session_id=req.session_id, reply=reply)


async def _reset_thread_checkpoints(thread_id: str) -> None:
    """删除某个 thread 在 Redis 中的短期记忆 checkpoint（用于自愈损坏的会话状态）。"""
    from src.infra.redis_cache import _checkpointer_client

    client = _checkpointer_client
    try:
        async for key in client.scan_iter(match=f"checkpoint*{thread_id}*"):
            await client.delete(key)
        logger.info(f"已重置会话 checkpoint: {thread_id}")
    except Exception as e:
        logger.warning(f"清理会话 checkpoint 失败: {thread_id} error={e}")


_CHAT_HTML = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>天宫医疗 - 智能体</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: "Microsoft YaHei", sans-serif; background: #f5f7fa; height: 100vh; display: flex; flex-direction: column; }
  header { background: #2b6cb0; color: #fff; padding: 14px 20px; font-size: 18px; font-weight: bold; }
  header small { font-weight: normal; font-size: 12px; opacity: .85; margin-left: 10px; }
  #chat { flex: 1; overflow-y: auto; padding: 20px; }
  .msg { max-width: 75%; margin: 10px 0; padding: 10px 14px; border-radius: 10px; line-height: 1.6; white-space: pre-wrap; word-break: break-word; }
  .user { background: #2b6cb0; color: #fff; margin-left: auto; }
  .agent { background: #fff; color: #333; border: 1px solid #e2e8f0; }
  .meta { font-size: 11px; color: #999; margin-bottom: 4px; }
  #inputbar { display: flex; gap: 10px; padding: 14px 20px; background: #fff; border-top: 1px solid #e2e8f0; }
  #input { flex: 1; padding: 10px 14px; border: 1px solid #cbd5e0; border-radius: 8px; font-size: 14px; outline: none; }
  #send { padding: 10px 22px; background: #2b6cb0; color: #fff; border: none; border-radius: 8px; font-size: 14px; cursor: pointer; }
  #send:disabled { opacity: .5; cursor: not-allowed; }
  .hint { font-size: 12px; color: #999; padding: 2px 20px 12px; }
</style>
</head>
<body>
<header>天宫医疗 - 智能体<small>智慧问诊 · 报告解读 · 药物查询 · 长期记忆</small></header>
<div id="chat"></div>
<div class="hint">对话会自动保存到长期记忆，换新会话仍可回忆起病史、过敏史等信息。</div>
<div id="inputbar">
  <input id="input" placeholder="输入你的问题，回车发送" autocomplete="off">
  <button id="send">发送</button>
</div>
<script>
  const uid = localStorage.getItem("tg_uid") || ("u" + Math.random().toString(36).slice(2, 10));
  let sid = localStorage.getItem("tg_sid") || ("s" + Math.random().toString(36).slice(2, 10));
  localStorage.setItem("tg_uid", uid);
  localStorage.setItem("tg_sid", sid);

  const chat = document.getElementById("chat");
  const input = document.getElementById("input");
  const sendBtn = document.getElementById("send");

  function addMsg(role, text) {
    const div = document.createElement("div");
    div.className = "msg " + role;
    const meta = document.createElement("div");
    meta.className = "meta";
    meta.textContent = role === "user" ? "我" : "天宫医疗";
    div.appendChild(meta);
    div.appendChild(document.createTextNode(text));
    chat.appendChild(div);
    chat.scrollTop = chat.scrollHeight;
    return div;
  }

  let busy = false;

  async function send() {
    if (busy) return;
    const text = input.value.trim();
    if (!text) return;
    input.value = "";
    sendBtn.disabled = true;
    busy = true;
    addMsg("user", text);
    const placeholder = addMsg("agent", "思考中...");
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 200000);
    try {
      const res = await fetch("/api/v1/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ user_id: uid, session_id: sid, message: text }),
        signal: controller.signal
      });
      clearTimeout(timer);
      let data = {};
      try { data = await res.json(); } catch (err) {}
      if (!res.ok) {
        placeholder.textContent = "请求失败（HTTP " + res.status + "）：" + (data.detail || "未知错误");
      } else {
        placeholder.textContent = data.reply || "（空回复）";
      }
    } catch (e) {
      clearTimeout(timer);
      placeholder.textContent = (e && e.name === "AbortError")
        ? "请求超时，请稍后重试"
        : "请求失败：" + e;
    } finally {
      sendBtn.disabled = false;
      busy = false;
      input.focus();
    }
  }

  sendBtn.addEventListener("click", send);
  input.addEventListener("keydown", e => { if (e.key === "Enter") send(); });
  input.focus();
</script>
</body>
</html>
"""


@page_router.get("/chat", response_class=HTMLResponse, include_in_schema=False)
async def chat_page() -> HTMLResponse:
    """浏览器聊天页面。"""
    return HTMLResponse(content=_CHAT_HTML)
