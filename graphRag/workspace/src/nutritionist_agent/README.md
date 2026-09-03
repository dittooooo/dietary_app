# Nutrition Agent v2

FastAPI GraphRAG service for nutrition advice.

Runtime path:

```text
POST /nutritionist-agent/ask -> proactive disease rules + deterministic nutrition retrieval -> evidence -> validated OpenAI advice
POST /nutritionist-agent/dish-nutrition -> NutritionAgent -> Neo4j retrieval -> nutrition summary
GET /nutritionist-agent/dishes/search -> Neo4j Dish and FoodItem name keyword search
```

## Request

`cypher` and `debug` are not public request fields. The service always builds read-only Cypher internally.

```json
{
  "question": "今天午餐怎麼選比較好？",
  "dish_info_list": [
    {"dish_name": "雞腿便當", "amount": 1},
    {"dish_name": "滷肉飯", "amount": 1}
  ],
  "question_type": "dish_comparison",
  "user_profile": {
    "height_cm": 170,
    "weight_kg": 70,
    "gender": "male",
    "age": 30,
    "diet_goal": "增肌"
  },
  "health_condition": {
    "has_chronic_disease": true,
    "chronic_diseases": ["糖尿病"]
  },
  "weekly_diet_records": [
    {
      "date": "2026-08-30",
      "record": [
        {
          "meal_type": "lunch",
          "dish_name": "雞腿便當",
          "note": "外食"
        }
      ]
    }
  ]
}
```

## Fields

- `question`: Required user question.
- `dish_info_list`: Required structured dish names and serving amounts from the caller. Nutritionist Agent does not extract dish names from `question`.
- `question_type`: Required. One of `single_dish`, `dish_comparison`, or `unknown`.
- `user_profile`: Optional user profile.
- `health_condition`: If `has_chronic_disease=true`, proactively retrieve all named diseases' rules even when the question never mentions disease. Disease names mentioned in the question are also matched against Neo4j `Disease.name` and retrieved, without changing the user's diagnosis. The question's actual topic leads the answer; profile restrictions are secondary context when relevant. Matching is case-insensitive literal-name matching, not alias or typo resolution. Missing evidence is explained by the model when relevant; no fixed conclusion suffix is appended.
- `weekly_diet_records`: Uses only valid records from today and the preceding six days. Update static example dates before testing.

See [flow and evidence rules](NUTRITION_AGENT_FLOW.md) and [test instructions](test_area/README.md). New ready-to-paste cases are in `test_data/advice_cases/`; `test_data/v1/` is historical.

## Dish Nutrition Lookup

Use `POST /nutritionist-agent/dish-nutrition` when another service only needs nutrition data for a single dish, such as writing a diet record. This endpoint does not call OpenAI and does not generate advice.

Request:

```json
{
  "dish_name": "雞腿便當"
}
```

Response:

```json
{
  "dish_nutrition": {
    "dish_name": "雞腿便當",
    "matched_name": "雞腿便當",
    "matched_type": "dish",
    "match_score": 114,
    "match_reason": "exact dish match",
    "retrieval_strategy": "dish_match",
    "nutrients": []
  }
}
```

## Environment

Required for a real `/ask` request:

Only `dietary_app/.env` is loaded; process environment variables take precedence. Nested `.env` files are ignored.

```env
OPENAI_API_KEY=sk-...
NEO4J_URI=bolt://localhost:7687
NEO4J_USER=neo4j
NEO4J_PASSWORD=...
```

`/dish-nutrition` itself only uses Neo4j and does not call OpenAI.

## Dish Name Search

Use `GET /nutritionist-agent/dishes/search?q=便` to find stored recipe and food-item names containing a keyword. The endpoint searches both `Dish.name` and `FoodItem.name`; it does not call OpenAI or calculate nutrition. Results are ordered as exact match, name-prefix match, then other containing matches.

```json
{
  "query": "便",
  "results": [
    {
      "id": "recipe-1",
      "name": "雞腿便當",
      "type": "dish",
      "calories": {"value": 620.0, "unit": "kcal", "basis": "per_serving"},
      "macronutrients": {
        "protein_g": 35.2,
        "carbohydrates_g": 72.4,
        "fat_g": 18.0,
        "basis": "per_serving"
      }
    },
    {
      "id": "food-1",
      "name": "香蕉",
      "type": "food_item",
      "calories": {"value": 85.0, "unit": "kcal", "basis": "per_100g"},
      "macronutrients": {
        "protein_g": 1.1,
        "carbohydrates_g": 22.0,
        "fat_g": 0.3,
        "basis": "per_100g"
      }
    }
  ],
  "total": 1,
  "limit": 30
}
```

`q` is required and accepts 1–100 characters. `limit` is optional (default `30`, maximum `50`).
`calories` is `null` when the graph lacks enough nutrition data. Calories are calculated from protein, carbohydrate, and fat when all three are available; otherwise the graph's calorie value is used.
`macronutrients` always includes protein, carbohydrates, and fat in grams; unavailable values are `null`.

Optional:

```env
APP_ENV=local
OPENAI_API_BASE=https://api.openai.com/v1
OPENAI_MODEL=gpt-5.6-luna
NUTRITION_AGENT_TOP_N_ROWS=80
NUTRITION_AGENT_DISH_MATCH_THRESHOLD=60
NUTRITION_AGENT_GRAPH_QUERY_LIMIT=1000
```

## Development Setup

This service runs with Python 3.12 and a project-local virtual environment. The `.venv` folder is created separately on each developer's machine and must not be committed.

### First-time setup

Install Python 3.12, then run these commands in PowerShell from the `graphRag\workspace` directory:

```powershell
cd C:\path\to\dietary_app\graphRag\workspace
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r src\nutritionist_agent\requirements.txt
```

If `py -3.12` reports that no suitable runtime was found, use the installed Python 3.12 executable directly:

```powershell
& "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe" -m venv .venv
```

Create or copy the project's root `.env` file and configure the developer's own Neo4j and OpenAI credentials. Do not commit `.env`.

### Start the service

Open a new PowerShell window, or continue in the existing one, then run:

```powershell
cd C:\path\to\dietary_app\graphRag\workspace
.\.venv\Scripts\Activate.ps1
python -m uvicorn src.nutritionist_agent.app:app --host 0.0.0.0 --port 8000
```

The `(.venv)` prefix should appear in the PowerShell prompt. If the environment has not been created yet, complete the first-time setup first.

Health check:

```powershell
curl http://127.0.0.1:8000/health
```

Swagger:

```text
http://127.0.0.1:8000/docs
```
