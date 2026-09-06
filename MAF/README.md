# MAF Conversation Workflow

This service is the conversation entry point for the dietary application. It uses Microsoft Agent Framework to route the existing conversation flows while keeping DietaryAgent and NutritionistAgent behind their existing APIs.

## Live workflow trace

Start the stack in the foreground, or follow all workflow services after a detached start:

```powershell
docker compose logs -f maf companion backend nutritionist
```

Each workflow request uses one short trace ID across services. Log lines follow this format:

```text
[demo-chat-01] [MAF] [ROUTED] 分流完成 intent=general_chat dishes=無
[demo-chat-01] [CompanionAgent] [STARTED] 產生最終回覆 ...
```

The trace reports workflow state, selected agent, a shortened problem summary, downstream calls, completion, and failures. Authorization headers, API keys, and profile details are not logged.

## Run locally

From the repository root:

```powershell
.\.venv\Scripts\python.exe -m uvicorn MAF.app:app --host 0.0.0.0 --port 3001
```

Required environment variables:

```text
OPENAI_API_KEY
OPENAI_MODEL                  (default: gpt-4o-mini)
COMPANION_AGENT_API_URL       (default: http://localhost:3000)
DIETARY_AGENT_API_URL         (default: http://localhost:8080)
COMPANION_PROMPT_DIR          (optional local override)
```

Endpoints:

```text
GET  /health
POST /maf/ask
POST /maf/confirm
```
