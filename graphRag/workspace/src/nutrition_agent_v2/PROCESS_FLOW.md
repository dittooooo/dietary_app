# Nutrition Agent 完整處理流程

本文整理 `workspace/src/nutrition_agent` 目前實作的 GraphRAG 流程：

`參數輸入 -> question type 判斷 -> text to cypher -> Neo4j 圖譜檢索 -> 圖譜結果整理 -> OpenAI 產生回答 -> API response`

## 1. 模組與責任

| 檔案 | 角色 |
| --- | --- |
| `app.py` | FastAPI 入口，提供 `GET /health` 與 `POST /ask`。 |
| `models.py` | 定義 request、response、使用者資料、疾病、飲食紀錄、料理營養摘要與建議格式。 |
| `agent.py` | 主流程 orchestration，串接 text-to-cypher、Neo4j retriever、answer generator。 |
| `text_to_cypher.py` | 將自然語言問題轉成 Cypher。若能直接解析菜名，會用固定 Cypher template；否則使用 LangChain + OpenAI 產生 Cypher。 |
| `cypher_guard.py` | Cypher 安全檢查，只允許 read-only query。 |
| `retriever.py` | 執行 Cypher，將 Neo4j 型別轉成一般 Python dict，並彙總常見營養素。 |
| `answer_generator.py` | 將問題、使用者資料、圖譜檢索結果組成 prompt，呼叫 OpenAI 產生 JSON 回答。 |
| `config.py` | 環境變數、Neo4j/OpenAI 設定、固定 graph schema。 |

## 2. API 入口與輸入

入口在 `app.py`：

```python
@app.post("/ask", response_model=NutritionAgentResponse)
def ask(req: NutritionAgentRequest) -> NutritionAgentResponse:
    return agent.ask(req)
```

輸入模型是 `NutritionAgentRequest`：

```json
{
  "question": "我有糖尿病，適合吃義式千層麵嗎？",
  "cypher": null,
  "question_type": "single_dish",
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
  "weekly_diet_records": [],
  "debug": false
}
```

欄位意義：

| 欄位 | 型別 | 用途 |
| --- | --- | --- |
| `question` | `str` | 使用者原始問題，必填。 |
| `cypher` | `Optional[str]` | 若上游已產生 Cypher，可直接傳入；有值時會跳過 text-to-cypher。 |
| `question_type` | `single_dish` / `dish_comparison` / `unknown` | 可由前端或上游指定；若問題被判定為比較題，系統會強制使用 `dish_comparison`。 |
| `user_profile` | `UserProfile` | 身高、體重、性別、年齡，用於 BMI 與個人化回答。 |
| `health_condition` | `HealthCondition` | 慢性病資訊；目前只信任這裡的 `chronic_diseases`，不從 question 自行推測疾病。 |
| `weekly_diet_records` | `List[DietRecord]` | 近期飲食紀錄，用於回答時補充飲食型態。 |
| `debug` | `bool` | `true` 時 response 會包含 `cypher_used` 與完整 `graph_rows`。 |

如果 `user_profile`、`health_condition`、`weekly_diet_records` 沒有傳入，`agent.py` 會使用空模型或空 list：

```python
user_profile = request.user_profile or UserProfile()
health_condition = request.health_condition or HealthCondition()
weekly_records = request.weekly_diet_records or []
```

## 3. 主流程總覽

主流程在 `NutritionAgent.ask()`：

1. 讀取 request，補齊空的 user profile、health condition、weekly records。
2. 呼叫 `infer_question_type(question)` 初步判斷題型。
3. 決定 `effective_question_type`。
4. 如果 request 已帶 `cypher`：
   - 用 `validate_read_only_cypher()` 檢查安全性。
   - 直接進入 Neo4j 檢索。
5. 如果 request 沒帶 `cypher`：
   - 呼叫 `TextToCypherTranslator.translate()`。
   - 產出 `cypher` 與實際使用的 `question_type`。
6. 呼叫 `GraphRetriever.retrieve(cypher)` 查 Neo4j。
7. 呼叫 `GraphRetriever.summarize_dish_nutrition(rows)` 將 graph rows 濃縮成料理營養摘要。
8. 呼叫 `AnswerGenerator.generate()`，把原始問題、個人資料、飲食紀錄、營養摘要、graph rows 傳給 OpenAI。
9. 將 OpenAI 回傳的 `dish_advice`、`conclusion` 包成 `NutritionAgentResponse`。
10. 如果 `debug=true`，額外回傳 `cypher_used` 與完整 `graph_rows`。

## 4. Question Type 判斷

`infer_question_type(question)` 在 `text_to_cypher.py`。

邏輯很單純：只要 question 內含比較語意 marker，例如 `vs`、`VS` 或中文比較詞，就回傳：

```python
"dish_comparison"
```

否則回傳：

```python
"single_dish"
```

`agent.py` 的合併邏輯：

```python
inferred_type = infer_question_type(request.question)
effective_question_type = (
    inferred_type
    if inferred_type == "dish_comparison"
    else request.question_type or inferred_type
)
```

意思是：

- 只要系統從文字判斷是比較題，就強制採用 `dish_comparison`。
- 若不是比較題，優先使用 request 傳入的 `question_type`。
- 若 request 沒傳，使用推論結果。

## 5. Text-to-Cypher 流程

入口：

```python
TextToCypherTranslator.translate(question, health_condition, question_type)
```

這裡有兩條路徑。

### 5.1 路徑 A：偵測到菜名，使用固定 Cypher template

`translate()` 會先做：

```python
dish_targets = self.resolve_dish_targets(question, effective_question_type)
disease_names = self.resolve_diseases(health_condition)
```

#### 5.1.1 菜名解析

`resolve_dish_targets()` 的邏輯：

1. 如果是 `dish_comparison`，先用 `extract_dish_candidates(question)` 從比較題文字切出候選菜名。
2. 用 `find_dish_targets_by_candidates(candidates)` 到 Neo4j 查 `(:Dish)`：

```cypher
UNWIND $candidates AS candidate
MATCH (d:Dish)
WHERE d.name = candidate
   OR d.name CONTAINS candidate
   OR candidate CONTAINS d.name
WITH d.name AS name, candidate,
     CASE
       WHEN d.name = candidate THEN 100
       WHEN d.name CONTAINS candidate THEN 80 + size(candidate)
       WHEN candidate CONTAINS d.name THEN 20 + size(d.name)
       ELSE 0
     END AS score
ORDER BY candidate, score DESC, size(name) DESC
WITH candidate, collect(name)[0] AS best_name, collect(score)[0] AS best_score
WHERE best_name IS NOT NULL AND best_score >= 20
RETURN candidate, best_name AS name
ORDER BY size(name) DESC
LIMIT $limit
```

輸出格式：

```json
[
  {
    "display_name": "使用者文字中的菜名",
    "match_name": "Neo4j 中實際匹配到的 Dish.name"
  }
]
```

3. 若候選菜名不足，改用直接包含查詢：

```cypher
MATCH (d:Dish)
WHERE $question CONTAINS d.name
RETURN d.name AS name
ORDER BY size(d.name) DESC
LIMIT $limit
```

4. 最後用 `prune_generic_dish_names()` 移除比較泛用、被其他長菜名包含的名稱。

#### 5.1.2 疾病解析

`resolve_diseases()` 只讀 `health_condition`：

```python
if health_condition.has_chronic_disease and health_condition.chronic_diseases:
    return health_condition.chronic_diseases
return []
```

也就是：

- 使用者問題文字寫「我有糖尿病」不會被這裡直接拿來當疾病。
- 必須由 request 的 `health_condition.chronic_diseases` 傳入。

#### 5.1.3 固定 Cypher 產生

只要 `dish_targets` 有值，就呼叫：

```python
build_dish_rule_cypher(dish_targets, disease_names)
```

若有疾病，會加上：

```cypher
OPTIONAL MATCH (dis:Disease)-[rule:HAS_DIET_RULE]->(n)
WHERE dis.name IN [...]
```

若沒有疾病，會用 `null AS dis, null AS rule` 讓後續 RETURN 欄位仍保持一致。

產出的主要查詢形狀：

```cypher
UNWIND [{display_name: "...", match_name: "..."}] AS dish_target
MATCH (d:Dish)-[c:CONTAINS]->(ing:Ingredient)
WHERE d.name = dish_target.match_name
MATCH (ing)-[hn:HAS_NUTRITION]->(n:Nutrition)
OPTIONAL MATCH (dis:Disease)-[rule:HAS_DIET_RULE]->(n)
WHERE dis.name IN [...]
OPTIONAL MATCH (f:FoodItem {food_id: hn.source_food_id})
WHERE c.matched_food_id IS NULL OR hn.source_food_id = c.matched_food_id
RETURN
  dish_target.display_name AS dish_name,
  d.name AS matched_dish_name,
  ing.name AS ingredient_name,
  coalesce(f.name, hn.source_food_name) AS food_item_name,
  n.name AS nutrition_name,
  n.name_zh AS nutrition_name_zh,
  n.category AS nutrition_category,
  hn.amount_per_serving AS amount_per_serving,
  hn.amount_per_100g AS amount_per_100g,
  hn.unit AS nutrition_unit,
  dis.name AS disease_name,
  rule.relation AS diet_rule_relation,
  rule.direction AS diet_rule_direction,
  rule.note AS diet_rule_note,
  rule.reason AS diet_rule_reason,
  rule.food_level_condition AS food_level_condition,
  rule.sources_json AS sources_json
ORDER BY diet_rule_relation, ingredient_name, nutrition_name, dish_name
LIMIT 1000
```

固定 Cypher 的輸出欄位就是後面回答生成最重要的 graph context。

### 5.2 路徑 B：沒有偵測到菜名，使用 LangChain + OpenAI 產生 Cypher

若 `dish_targets` 是空的，會走：

```python
translate_with_langchain(question, health_condition, effective_question_type)
```

前置條件：

- `OPENAI_API_KEY` 必須存在且不能是 `dummy-key`。
- 必須安裝 `langchain`、`langchain-community`、`langchain-openai`。

使用的 LLM：

```python
ChatOpenAI(
    model=OPENAI_MODEL,
    temperature=0.0,
    api_key=OPENAI_API_KEY,
    base_url=OPENAI_API_BASE,
)
```

使用的 chain：

```python
GraphCypherQAChain.from_llm(
    llm=llm,
    graph=graph,
    cypher_prompt=cypher_prompt,
    validate_cypher=True,
    allow_dangerous_requests=True,
)
```

雖然 `allow_dangerous_requests=True`，但實際 graph adapter 的 `query()` 和產出後的 `validate_read_only_cypher()` 都會再擋 read/write 風險。

#### 5.2.1 LangChain 使用的 schema

因為專案不依賴 Neo4j APOC，所以 `text_to_cypher.py` 自建 read-only `NutritionGraphStore`，提供固定 schema。主要 schema 來自 `config.py` 的 `GRAPH_SCHEMA`：

```text
Dish -> CONTAINS -> Ingredient -> HAS_NUTRITION -> Nutrition <- HAS_DIET_RULE <- Disease
```

節點：

- `Dish {recipe_id, name, servings}`
- `Ingredient {name, matched_food_id, matched_food_name, mapping_method}`
- `FoodItem {food_id, name, category, aliases}`
- `Nutrition {nutrition_id, name, name_zh, unit, category, source_column}`
- `Disease {disease_id, name, name_en}`

關係：

- `(:Dish)-[:CONTAINS]->(:Ingredient)`
- `(:Ingredient)-[:HAS_NUTRITION]->(:Nutrition)`
- `(:Disease)-[:HAS_DIET_RULE]->(:Nutrition)`

#### 5.2.2 Text-to-Cypher prompt

LangChain Cypher prompt 常數在：

```python
text_to_cypher.py::LANGCHAIN_TEXT_TO_CYPHER_TEMPLATE
```

原始 prompt 內容在目前檔案中有部分 mojibake，但從可讀片段與程式邏輯可確認它要求：

- 你是 Text-to-Cypher 產生器。
- 根據 Neo4j schema 與使用者問題產生 Cypher。
- 只輸出 Cypher，不要 Markdown 或 JSON。
- 只允許 read-only 查詢，使用 `MATCH` / `OPTIONAL MATCH` / `WHERE` / `RETURN` / `ORDER BY` / `LIMIT`。
- 禁止 `CREATE`、`MERGE`、`SET`、`DELETE`、`CALL`、`APOC` 等寫入或程序呼叫。
- `HAS_DIET_RULE` 是 Disease 到 Nutrition 的關係。
- 慢性病只來自 `health_condition` JSON，不要從問題文字自行推測。
- 如果沒有慢性病，不要任意加疾病條件。

實際送給 LangChain 的 user question 不是原始 question，而是 `_build_langchain_question()` 組出的 enriched question，包含：

```text
question: 使用者原始問題
question_type: single_dish / dish_comparison / unknown
health_condition: health_condition.model_dump() 的 JSON
```

LangChain 產生內容後，程式會：

1. 用 `extract_cypher(content)` 抽出 Cypher。
2. `strip()`。
3. 呼叫 `validate_read_only_cypher(cypher)`。
4. 回傳：

```json
{
  "cypher": "...",
  "question_type": "...",
  "rationale": "Generated by LangChain GraphCypherQAChain cypher_generation_chain."
}
```

## 6. Cypher 安全檢查

所有 Cypher 在執行前都會經過 `validate_read_only_cypher()`。

檢查規則：

1. 不可是空字串。
2. 不可包含多 statement；中間不能有 `;`。
3. 禁止寫入或危險關鍵字：

```text
CREATE, MERGE, SET, DELETE, DETACH, REMOVE, DROP,
LOAD CSV, CALL, APOC, CREATE INDEX, CREATE CONSTRAINT,
ALTER, GRANT, DENY, REVOKE, START, INSERT, FINISH
```

4. 必須以 `MATCH`、`OPTIONAL MATCH` 或 `UNWIND` 開頭。
5. 必須包含 `RETURN`。

這個 guard 會出現在三個地方：

- request 直接傳入 `cypher` 時。
- LangChain 產出 Cypher 後。
- `GraphRetriever.retrieve()` 真正執行前。

## 7. Neo4j 圖譜檢索

入口：

```python
rows = self.retriever.retrieve(cypher)
```

`GraphRetriever.retrieve()`：

```python
validate_read_only_cypher(cypher)
with self.driver.session() as session:
    result = session.run(cypher)
    return [
        {key: self.to_plain_value(value) for key, value in record.data().items()}
        for record in result
    ]
```

輸入：

- 一段已通過安全檢查的 read-only Cypher。

輸出：

- `List[Dict[str, Any]]`，每個 dict 是 Neo4j 的一列結果。
- 若結果含 Neo4j `Node`、`Relationship`、`Path`，會轉成一般 JSON-like dict。

例如固定 Cypher 的一列結果會長得像：

```json
{
  "dish_name": "義式千層麵",
  "matched_dish_name": "義式千層麵",
  "ingredient_name": "起司",
  "food_item_name": "起司",
  "nutrition_name": "fat",
  "nutrition_name_zh": "脂肪",
  "nutrition_category": "macro",
  "amount_per_serving": 12.3,
  "amount_per_100g": 20.5,
  "nutrition_unit": "g",
  "disease_name": "糖尿病",
  "diet_rule_relation": "limit",
  "diet_rule_direction": "high",
  "diet_rule_note": "...",
  "diet_rule_reason": "...",
  "food_level_condition": "...",
  "sources_json": "..."
}
```

## 8. 圖譜結果濃縮：dish_nutrition

Neo4j 查回的 `rows` 會先被濃縮：

```python
dish_nutrition = self.retriever.summarize_dish_nutrition(rows)
```

這一步只整理常見營養素，邏輯在 `retriever.py`：

1. 逐列讀取：
   - `dish_name`
   - `nutrition_name_zh`，若沒有則用 `nutrition_name`
   - `amount_per_serving`
   - `nutrition_unit`
2. 用 `COMMON_NUTRIENT_ALIASES` 做名稱標準化。
3. 只保留 `COMMON_NUTRIENT_ORDER` 中的營養素。
4. 以 `dish_name + nutrient` 分組加總 `amount_per_serving`。
5. 四捨五入到小數點後兩位。

輸出格式：

```json
[
  {
    "dish_name": "義式千層麵",
    "nutrients": [
      {
        "name": "熱量",
        "amount_per_serving": 520.0,
        "unit": "kcal"
      },
      {
        "name": "脂肪",
        "amount_per_serving": 20.5,
        "unit": "g"
      }
    ]
  }
]
```

注意：

- `dish_nutrition` 是摘要，只包含程式定義的常見營養素。
- 完整圖譜內容仍會以 `graph_rows` 傳給 OpenAI，但最多只傳前 80 筆。

## 9. 傳給 OpenAI 的回答生成流程

入口：

```python
answer_payload = self.answer_generator.generate(...)
```

輸入參數：

| 參數 | 來源 |
| --- | --- |
| `question` | request 原始問題 |
| `question_type` | text-to-cypher 後確認的題型 |
| `user_profile` | request 或空模型 |
| `health_condition` | request 或空模型 |
| `weekly_diet_records` | request 或空 list |
| `dish_nutrition` | `summarize_dish_nutrition(rows)` |
| `graph_rows` | `rows[:DEFAULT_TOP_N_ROWS]`，預設 80 筆 |

### 9.1 組 context

`AnswerGenerator.generate()` 會組出 context：

```json
{
  "question": "...",
  "question_type": "single_dish",
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
  "weekly_diet_records": [],
  "user_context_summary": {
    "bmi": 24.2,
    "bmi_category": "...",
    "chronic_diseases": ["糖尿病"],
    "recent_patterns": {},
    "weekly_record_count": 0
  },
  "dish_nutrition": [...],
  "graph_rows": [...]
}
```

`user_context_summary` 由 `summarize_user_context()` 產生：

- 若有身高體重，計算 BMI。
- 根據 BMI 分類。
- 若 `has_chronic_disease=true`，帶入 chronic diseases。
- 掃描 `weekly_diet_records` 的 dish name 與 note，統計近期型態，例如油、鹹、甜、均衡等 pattern。
- 計算 `weekly_record_count`。

### 9.2 OpenAI messages

`generate_with_llm()` 實際送出的 messages：

```python
messages = [
    {"role": "system", "content": ANSWER_PROMPT},
    {"role": "user", "content": json.dumps(context, ensure_ascii=False, indent=2)},
]
```

也就是：

- system prompt：`answer_generator.py::ANSWER_PROMPT`
- user prompt：完整 JSON context

呼叫方式：

```python
response = self.client.chat.completions.create(
    model=OPENAI_MODEL,
    messages=messages,
    temperature=0.0,
)
```

OpenAI client 設定：

```python
OpenAI(api_key=OPENAI_API_KEY, base_url=OPENAI_API_BASE)
```

預設模型來自 `config.py`：

```python
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4.1-mini")
```

若 `OPENAI_API_KEY` 沒有設定，或是 `dummy-key`，會直接丟錯：

```text
LLM answer generation requires OPENAI_API_KEY.
```

FastAPI 會轉成 HTTP 503。

### 9.3 Answer prompt 重點

回答生成 prompt 常數在：

```python
answer_generator.py::ANSWER_PROMPT
```

原始 prompt 目前也有部分 mojibake，但從可讀結構與後續驗證邏輯可確認它要求 OpenAI：

- 扮演 Nutrition Agent。
- 根據 GraphRAG 檢索結果、料理營養、使用者個人資料、健康狀態與當週飲食紀錄回答。
- 不要輸出 Markdown。
- 不要輸出 graph rows 原文。
- 回答必須是 JSON object。
- `dish_advice` 每個項目需包含：
  - `dish_name`
  - `suitability`
  - `key_reasons`
  - `suggestions`
- `conclusion` 是總結。
- 單一道料理時，判斷適合度並給出 3 點以內的建議。
- 多道料理比較時，需要比較各料理，並選出一道相對較建議的料理。
- 比較題不是要禁止使用者吃，而是在候選料理中協助做相對健康的選擇。
- 回答要參考 `health_condition`，也要把 `user_profile` 與 `weekly_diet_records` 納入判斷。

要求的 JSON 格式：

```json
{
  "dish_advice": [
    {
      "dish_name": "...",
      "suitability": "...",
      "key_reasons": ["...", "..."],
      "suggestions": ["...", "..."]
    }
  ],
  "conclusion": "..."
}
```

## 10. OpenAI 回答解析與比較題校正

OpenAI 回傳文字後會進入：

```python
parsed = self._parse_json(self._complete(messages))
```

`_parse_json()` 支援兩種格式：

1. 純 JSON object。
2. 包在 ```json code fence 裡的 JSON。

解析後會用 Pydantic 驗證：

```python
parsed["dish_advice"] = [
    DishAdvice(**item).model_dump()
    for item in parsed.get("dish_advice", [])
]
parsed["conclusion"] = str(parsed.get("conclusion", "")).strip()
```

### 10.1 比較題必須選出一道推薦料理

若 `question_type == "dish_comparison"`，系統會檢查 LLM 是否有明確選出一道推薦料理：

```python
has_llm_comparison_choice(parsed, dish_nutrition)
```

判斷方式：

- 先看 `dish_advice` 中是否剛好有一道料理的 `suitability` 等於 prompt 指定的「推薦」字串。
- 如果沒有，再看 `conclusion` 是否只提到一個 dish name，且附近有推薦語意 marker。

若第一次沒有選出明確推薦，會再送一次 correction prompt，要求模型只修正 JSON，並明確在比較題中選一道推薦。

若 retry 後仍沒有明確選擇，會丟：

```text
LLM answer did not mark exactly one recommended dish for comparison after retry.
```

### 10.2 比較題結果正規化

比較題通過檢查後，會呼叫：

```python
normalize_comparison_advice(parsed, dish_nutrition)
```

這一步會：

1. 找出 LLM 選中的 dish。
2. 以 `dish_nutrition` 中的料理為準，重新整理 `dish_advice`。
3. 被選中的料理標成「推薦」。
4. 其他料理標成「較不建議」。
5. 若某料理缺少 `key_reasons` 或 `suggestions`，補上預設文字。

因此比較題最後的 `dish_advice` 順序與 dish list 會以 `dish_nutrition` 為準，而不是完全照 LLM 原始輸出。

## 11. 最終輸出

`NutritionAgentResponse`：

```json
{
  "question": "我有糖尿病，適合吃義式千層麵嗎？",
  "question_type": "single_dish",
  "dish_nutrition": [
    {
      "dish_name": "義式千層麵",
      "nutrients": [
        {
          "name": "熱量",
          "amount_per_serving": 520.0,
          "unit": "kcal"
        }
      ]
    }
  ],
  "dish_advice": [
    {
      "dish_name": "義式千層麵",
      "suitability": "...",
      "key_reasons": ["..."],
      "suggestions": ["..."]
    }
  ],
  "conclusion": "...",
  "cypher_used": null,
  "graph_rows": null
}
```

若 `debug=true`：

- `cypher_used` 會放實際執行的 Cypher。
- `graph_rows` 會放完整 Neo4j 查詢結果。

若 `debug=false`：

- `cypher_used = null`
- `graph_rows = null`

## 12. 資料流輸入輸出總表

| 階段 | 輸入 | 輸出 |
| --- | --- | --- |
| FastAPI `/ask` | HTTP JSON body | `NutritionAgentRequest` |
| 預設值補齊 | request | `user_profile`、`health_condition`、`weekly_records` |
| 題型判斷 | `question`、`request.question_type` | `effective_question_type` |
| text-to-cypher | `question`、`health_condition`、`question_type` | `{cypher, question_type, rationale}` |
| Cypher guard | `cypher` | 通過或丟 `ValueError` |
| Neo4j retrieve | `cypher` | `rows: List[Dict[str, Any]]` |
| 營養摘要 | `rows` | `dish_nutrition: List[DishNutrition]` |
| context 組裝 | request 資料、`dish_nutrition`、`rows[:80]` | OpenAI user JSON context |
| OpenAI answer | system prompt + user context | JSON 字串 |
| JSON parse/validate | OpenAI JSON 字串 | `{dish_advice, conclusion}` |
| 比較題 normalize | parsed answer、`dish_nutrition` | 正規化後的 comparison advice |
| Response | all outputs | `NutritionAgentResponse` |

## 13. 目前邏輯的幾個重要特性

1. 使用者直接傳 `cypher` 時，系統不會再做 text-to-cypher。
2. 慢性疾病只由 `health_condition.chronic_diseases` 進入檢索邏輯。
3. 有偵測到菜名時，通常不需要 OpenAI 產生 Cypher，會直接使用固定查詢模板。
4. OpenAI 一定會被用於最終回答生成；沒有有效 `OPENAI_API_KEY` 時不會產生 fallback 結論。
5. 傳給回答模型的 graph rows 預設最多 80 筆，但 Neo4j 實際查詢可能最多 1000 筆。
6. `dish_nutrition` 是從 graph rows 聚合出來的摘要；回答模型同時拿到摘要與原始 graph rows。
7. 比較題有二次校正與正規化，目標是強制選出一道相對推薦料理。
8. Cypher safety guard 會重複檢查，避免 OpenAI 或外部輸入帶入寫入型 Cypher。

