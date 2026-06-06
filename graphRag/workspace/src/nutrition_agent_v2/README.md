# Nutrition Agent

`nutrition_agent` 專注處理 GraphRAG 檢索與回答。知識圖譜建置仍由 `kg_builder` 負責。

## 模組分工

- `app.py`: FastAPI 入口，提供 `/ask` 與 `/health`。
- `agent.py`: Nutrition Agent 主流程。
- `retriever.py`: 執行傳入的 Cypher，整理料理營養成分。
- `answer_generator.py`: 根據圖譜結果與使用者資料產生精簡建議。
- `text_to_cypher.py`: 暫時的 LangChain `GraphCypherQAChain` 前置模組。未來可拆到其他模組。
- `sample_request_single_dish.json`: 單一道料理適合度判斷的假輸入資料。
- `sample_request_comparison.json`: 多道料理比較的假輸入資料。
- `models.py`: API 輸入與輸出格式。

## API 輸入

可直接傳入上游模組產生的 `cypher`：

```json
{
  "question": "我有糖尿病，我是適合吃義式千層麵嗎",
  "cypher": "MATCH ... RETURN ...",
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
  "weekly_diet_records": []
}
```

若 `cypher` 未提供，會暫時使用 `text_to_cypher.py` 產生查詢。
若未傳 `user_profile`、`health_condition` 或 `weekly_diet_records`，系統只會使用空資料，不會自動套用假資料。
慢性疾病只會讀取 `health_condition.chronic_diseases`，不會從 `question` 文字推測。
多道料理比較時，系統一定會選出其中一道相對較建議的料理；設計宗旨是協助使用者做出相對健康的選擇，而不是限制使用者不能吃。
回答會同時參考圖譜檢索結果、個人資料與當週飲食紀錄。
GraphRAG 檢索完成後，一律使用 LLM 產生 `dish_advice` 與 `conclusion`；若未設定有效的 `OPENAI_API_KEY`，`/ask` 會回傳 503，不會使用本地模板結論。

注意：LangChain Text-to-Cypher 仍需要 LLM provider。此專案目前使用 `langchain_openai.ChatOpenAI` 產生 Cypher，但不再直接用 OpenAI SDK 寫自訂轉換流程。

本模組刻意不依賴 Neo4j APOC。LangChain 原生 `Neo4jGraph` 會呼叫 `apoc.meta.data()` 自動讀 schema，但目前 Neo4j 容器未啟用 APOC；因此 `text_to_cypher.py` 使用 read-only GraphStore adapter 提供固定 schema 給 `GraphCypherQAChain`。

## 安裝 nutrition_agent 依賴

容器中若尚未安裝 LangChain，請只安裝 nutrition_agent 的 requirements：

```powershell
cd C:\_AlwaysUndone\dietary_app\graphRag\docker
docker compose exec graphrag-dev python -m pip install -r src/nutrition_agent/requirements.txt
```

## 啟動

```powershell
cd C:\_AlwaysUndone\dietary_app\graphRag\docker
docker compose exec graphrag-dev python -m uvicorn src.nutrition_agent.app:app --host 0.0.0.0 --port 8000
```

## 測試

```powershell
$body = Get-Content -Raw -Encoding UTF8 `
  C:\_AlwaysUndone\dietary_app\graphRag\workspace\src\nutrition_agent\sample_request_single_dish.json

$bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
Invoke-RestMethod -Uri "http://localhost:8000/ask" -Method POST -ContentType "application/json; charset=utf-8" -Body $bytes
```
