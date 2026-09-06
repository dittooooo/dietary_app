# MAF Conversation Workflow

This service is the conversation-only entry point for the dietary application. It uses Microsoft Agent Framework to route the existing Companion flows without changing DietaryAgent, NutritionistAgent, login, or manual diet-record behavior.

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
POST /companion/ask
```
