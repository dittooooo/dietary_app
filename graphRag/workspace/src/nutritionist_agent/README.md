# Nutrition Agent v2

FastAPI GraphRAG service for nutrition advice.

Runtime path:

```text
POST /ask -> NutritionAgent -> Neo4j retrieval -> nutrition summary -> OpenAI answer
```

## Request

`cypher` and `debug` are not public request fields. The service always builds read-only Cypher internally.

```json
{
  "question": "我有糖尿病，這些料理適合我嗎？",
  "dish_names": ["雞腿便當", "滷肉飯"],
  "question_type": "dish_comparison",
  "user_profile": {
    "height_cm": 170,
    "weight_kg": 70,
    "gender": "male",
    "age": 30
  },
  "health_condition": {
    "has_chronic_disease": true,
    "chronic_diseases": ["糖尿病"]
  },
  "weekly_diet_records": [
    {
      "date": "2026-07-13",
      "meal": "lunch",
      "dish_name": "雞腿便當",
      "note": "外食"
    }
  ]
}
```

## Fields

- `question`: Required user question.
- `dish_names`: Structured dish names from the caller. If present, these are used before parsing dish names from `question`.
- `question_type`: Optional. One of `single_dish`, `dish_comparison`, or `unknown`.
- `user_profile`: Optional user profile.
- `health_condition`: Optional chronic disease context.
- `weekly_diet_records`: Optional recent diet records for answer context.

## Environment

Required for a real `/ask` request:

```env
OPENAI_API_KEY=sk-...
NEO4J_URI=bolt://host.docker.internal:7687
NEO4J_USER=neo4j
NEO4J_PASSWORD=...
```

Optional:

```env
APP_ENV=local
OPENAI_API_BASE=https://api.openai.com/v1
OPENAI_MODEL=gpt-4.1-nano
NUTRITION_AGENT_TOP_N_ROWS=80
NUTRITION_AGENT_DISH_MATCH_THRESHOLD=60
NUTRITION_AGENT_GRAPH_QUERY_LIMIT=1000
```

## Local Run

```powershell
cd C:\_AlwaysUndone\dietary_app\graphRag\docker
docker compose up -d --build
```

Health check:

```powershell
curl http://127.0.0.1:8000/health
```

Swagger:

```text
http://127.0.0.1:8000/docs
```
