# Nutrition Agent 完整處理流程 v2

本文整理 `workspace/src/nutrition_agent` 調整後的 GraphRAG 流程。新版重點是提高檢索準確度，避免只根據自然語言問題產生 Cypher，並讓料理營養成分的產出具有可追蹤的運算依據。

新版核心流程：

`參數輸入 -> request 正規化 -> question type 判斷 -> 候選料理抽取 -> 料理名稱相似度 Match -> 食材 fallback 檢索 -> 全參數 text-to-cypher -> Neo4j 圖譜檢索 -> 營養成分彙總與熱量重算 -> debug trace -> OpenAI 產生回答 -> API response`

---

## 1. 模組與責任

| 檔案                      | 角色                                                                                                                  |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `app.py`                  | FastAPI 入口，提供 `GET /health` 與 `POST /ask`。                                                                     |
| `models.py`               | 定義 request、response、使用者資料、疾病、飲食紀錄、料理營養摘要、建議格式與 debug trace 格式。                       |
| `agent.py`                | 主流程 orchestration，串接題型判斷、候選抽取、名稱匹配、text-to-cypher、Neo4j retriever、營養彙總、answer generator。 |
| `text_to_cypher.py`       | 使用 LangChain 的 text-to-cypher，將完整 request、題型、慢性病、飲食紀錄摘要、候選料理與匹配結果一起轉成 Cypher。     |
| `dish_matcher.py`         | 新增模組。負責料理名稱相似度 Match，回傳每個候選料理在圖譜中的最佳匹配與分數。                                        |
| `ingredient_fallback.py`  | 新增模組。當料理名稱匹配分數低於門檻時，改從候選文字中找食材節點，並以食材推導料理營養成分。                          |
| `cypher_guard.py`         | Cypher 安全檢查，只允許 read-only query。                                                                             |
| `retriever.py`            | 執行 Cypher，將 Neo4j 型別轉成一般 Python dict，並整理 graph rows。                                                   |
| `nutrition_calculator.py` | 新增模組。彙總蛋白質、脂肪、碳水化合物，並用三大營養素重新計算熱量。                                                  |
| `answer_generator.py`     | 將問題、使用者資料、飲食紀錄、圖譜檢索結果、營養成分摘要與 debug trace 組成 prompt，呼叫 OpenAI 產生 JSON 回答。      |
| `config.py`               | 環境變數、Neo4j/OpenAI 設定、固定 graph schema、匹配門檻、debug 設定。                                                |

---

## 2. API 入口與輸入

入口在 `app.py`：

```python
@app.post("/ask", response_model=NutritionAgentResponse)
def ask(req: NutritionAgentRequest) -> NutritionAgentResponse:
    return agent.ask(req)
```

輸入模型是 `NutritionAgentRequest`，格式以 `request_comparison.json` 為準：

```json
{
  "question": "你覺得我今天要吃雞排便當還是排骨便當嗎",
  "question_type": "dish_comparison",
  "user_profile": {
    "height_cm": 170,
    "weight_kg": 70,
    "gender": "male",
    "age": 30
  },
  "health_condition": {
    "has_chronic_disease": true,
    "chronic_diseases": ["高血壓"]
  },
  "weekly_diet_records": [
    {
      "date": "2026-05-18",
      "meal": "breakfast",
      "dish_name": "鮪魚蛋吐司",
      "note": "無糖豆漿一杯"
    }
  ],
  "debug": false
}
```

欄位意義：

| 欄位                  | 型別                                          | 用途                                                                   |
| --------------------- | --------------------------------------------- | ---------------------------------------------------------------------- |
| `question`            | `str`                                         | 使用者原始問題，必填。                                                 |
| `cypher`              | `Optional[str]`                               | 若上游已產生 Cypher，可直接傳入；有值時仍需經過 read-only guard。      |
| `question_type`       | `single_dish` / `dish_comparison` / `unknown` | 可由前端或上游指定；系統仍會根據問題文字做二次判斷。                   |
| `user_profile`        | `UserProfile`                                 | 身高、體重、性別、年齡，用於 BMI 與個人化回答。                        |
| `health_condition`    | `HealthCondition`                             | 慢性病資訊，用於檢索疾病飲食規則與回答個人化建議。                     |
| `weekly_diet_records` | `List[DietRecord]`                            | 近期飲食紀錄，用於回答生成與飲食型態判斷；不直接當成圖譜中的料理真值。 |
| `debug`               | `bool`                                        | `true` 時 response 會包含 `cypher_used`、`graph_rows`、`debug_trace`。 |

如果 `user_profile`、`health_condition`、`weekly_diet_records` 沒有傳入，`agent.py` 會使用空模型或空 list：

```python
user_profile = request.user_profile or UserProfile()
health_condition = request.health_condition or HealthCondition()
weekly_records = request.weekly_diet_records or []
```

---

## 3. 主流程總覽

新版主流程在 `NutritionAgent.ask()`：

1. 讀取 request，補齊空的 user profile、health condition、weekly records。
2. 呼叫 `normalize_request(request)`，將 request 轉成可供 text-to-cypher 使用的完整 JSON payload。
3. 呼叫 `infer_question_type(question, request.question_type)` 決定 `effective_question_type`。
4. 呼叫 `extract_dish_candidates(full_payload)`，從 `question` 與結構化欄位抽出候選料理。
5. 呼叫 `DishMatcher.match_dishes(candidates)`，到 Neo4j 的 `(:Dish)` 做名稱匹配，並取得 `match_score`。
6. 對每一道候選料理做分流：
   - 若最佳料理匹配分數 `>= 60`，使用 `dish_match` 路徑。
   - 若最佳料理匹配分數 `< 60` 或沒有匹配結果，使用 `ingredient_fallback` 路徑。
7. 將完整 request、題型、候選料理、料理匹配結果、fallback 決策、慢性病資訊一起交給 `TextToCypherTranslator.translate(full_payload)`。
8. LangChain text-to-cypher 產出 read-only Cypher。
9. 呼叫 `validate_read_only_cypher(cypher)` 做安全檢查。
10. 呼叫 `GraphRetriever.retrieve(cypher)` 查 Neo4j。
11. 呼叫 `NutritionCalculator.summarize_and_recalculate(rows)` 彙總營養素，並用脂肪、碳水、蛋白質重新計算熱量。
12. 產生 `debug_trace`，記錄候選料理、匹配分數、fallback 決策、Cypher、查詢列數、營養彙總、熱量計算公式。
13. 呼叫 `AnswerGenerator.generate()`，把原始問題、個人資料、飲食紀錄、營養摘要、graph rows、debug trace 傳給 OpenAI。
14. 將 OpenAI 回傳的 `dish_advice`、`conclusion` 包成 `NutritionAgentResponse`。
15. 若 `debug=true`，額外回傳 `cypher_used`、完整 `graph_rows`、`debug_trace`。

---

## 4. Question Type 判斷

`infer_question_type()` 不再只看文字，也要參考 request 傳入的 `question_type`。

建議邏輯：

```python
def infer_question_type(question: str, request_question_type: str | None) -> str:
    comparison_markers = ["還是", "或", "vs", "VS", "比較", "哪個", "哪一個"]

    if any(marker in question for marker in comparison_markers):
        return "dish_comparison"

    if request_question_type in ["single_dish", "dish_comparison", "unknown"]:
        return request_question_type

    return "single_dish"
```

判斷原則：

- 問題文字明顯是比較題時，強制使用 `dish_comparison`。
- 問題文字不明顯時，使用 request 傳入的 `question_type`。
- 都沒有時，預設為 `single_dish`。

---

## 5. Request 正規化與全參數 text-to-cypher

### 5.1 為什麼要改

舊版 text-to-cypher 的主要輸入是：

```text
question + question_type + health_condition
```

新版要改成完整 request payload，原因是：

1. `question` 只代表使用者當下問法，資訊不足。
2. `health_condition.chronic_diseases` 會影響要不要查疾病飲食規則。
3. `weekly_diet_records` 會影響回答判斷，例如近期是否偏油、偏鹹、常吃高熱量料理。
4. `question_type` 會影響 Cypher 回傳結果是否要支援多料理比較。
5. 候選料理與匹配結果應該一起交給 text-to-cypher，避免 LLM 自己亂猜料理名稱。

### 5.2 新版 `translate()` 入口

舊版：

```python
TextToCypherTranslator.translate(question, health_condition, question_type)
```

新版：

```python
TextToCypherTranslator.translate(payload: TextToCypherPayload)
```

`TextToCypherPayload` 建議格式：

```json
{
  "question": "你覺得我今天要吃雞排便當還是排骨便當嗎",
  "question_type": "dish_comparison",
  "user_profile": {
    "height_cm": 170,
    "weight_kg": 70,
    "gender": "male",
    "age": 30
  },
  "health_condition": {
    "has_chronic_disease": true,
    "chronic_diseases": ["高血壓"]
  },
  "weekly_diet_records": [
    {
      "date": "2026-05-18",
      "meal": "breakfast",
      "dish_name": "鮪魚蛋吐司",
      "note": "無糖豆漿一杯"
    },
    {
      "date": "2026-05-18",
      "meal": "lunch",
      "dish_name": "雞腿便當",
      "note": "沒吃完，有點太多了"
    },
    {
      "date": "2026-05-19",
      "meal": "dinner",
      "dish_name": "牛肉麵",
      "note": "湯喝一半而已，他好鹹"
    },
    {
      "date": "2026-05-20",
      "meal": "lunch",
      "dish_name": "滷味",
      "note": "配菜有豆干、青菜和麵"
    },
    {
      "date": "2026-05-21",
      "meal": "dinner",
      "dish_name": "義式千層麵",
      "note": "有點油，但好吃"
    }
  ],
  "dish_candidates": ["雞排便當", "排骨便當"],
  "dish_match_results": [
    {
      "input_name": "雞排便當",
      "matched_dish_name": "雞排便當",
      "match_score": 100,
      "retrieval_strategy": "dish_match"
    },
    {
      "input_name": "排骨便當",
      "matched_dish_name": "排骨便當",
      "match_score": 100,
      "retrieval_strategy": "dish_match"
    }
  ]
}
```

注意：

- `weekly_diet_records` 不建議整包原文全部丟進 text-to-cypher，避免 prompt 太長。
- 可以先整理成 `weekly_diet_records_summary`，完整資料保留給 answer generator。
- text-to-cypher 的任務是產生圖譜查詢，不是直接做營養判斷。

---

## 6. 候選料理抽取

入口：

```python
candidates = extract_dish_candidates(full_payload)
```

抽取來源：

1. `question` 中的料理名稱。
2. 若未來 request 有結構化候選欄位，例如 `selected_dishes`，優先使用結構化欄位。
3. `weekly_diet_records` 只作為近期飲食背景，不應被抽成這次要比較的候選料理。

比較題範例：

```text
你覺得我今天要吃雞排便當還是排骨便當嗎
```

應抽出：

```json
["雞排便當", "排骨便當"]
```

抽取後要做清理：

- 移除語助詞：`你覺得`、`我今天要吃`、`嗎`。
- 移除比較詞：`還是`、`或`、`vs`。
- 去除空白與標點。
- 去除過短或過泛用詞，例如 `便當`、`餐`、`料理`，除非這是唯一候選。

---

## 7. 料理名稱 Match 與相似度分數

### 7.1 Match 目標

在真正查營養成分前，先確認使用者輸入的候選料理是否能對應到圖譜中的 `(:Dish)`。

入口：

```python
match_results = DishMatcher.match_dishes(candidates)
```

輸出：

```json
[
  {
    "input_name": "雞排便當",
    "matched_dish_name": "雞排便當",
    "match_score": 100,
    "match_reason": "exact match",
    "retrieval_strategy": "dish_match"
  }
]
```

### 7.2 分數門檻

```python
DISH_MATCH_THRESHOLD = 60
```

判斷：

| 分數    | 處理方式                                         |
| ------- | ------------------------------------------------ |
| `>= 60` | 視為料理名稱匹配成功，使用 `dish_match` 路徑。   |
| `< 60`  | 不直接相信料理名稱，改走 `ingredient_fallback`。 |
| 無匹配  | 改走 `ingredient_fallback`。                     |

### 7.3 建議 Cypher

```cypher
UNWIND $candidates AS candidate
MATCH (d:Dish)
WITH candidate, d,
     CASE
       WHEN d.name = candidate THEN 100
       WHEN d.name CONTAINS candidate THEN 85
       WHEN candidate CONTAINS d.name THEN 70
       ELSE 0
     END AS base_score
WITH candidate, d, base_score,
     CASE
       WHEN base_score > 0 THEN base_score
       ELSE 0
     END AS score
WHERE score > 0
ORDER BY candidate, score DESC, size(d.name) DESC
WITH candidate, collect({name: d.name, score: score})[0] AS best
RETURN
  candidate AS input_name,
  best.name AS matched_dish_name,
  best.score AS match_score
ORDER BY input_name
```

如果 Neo4j 有支援 fulltext index，可以另外建立：

```cypher
CREATE FULLTEXT INDEX dish_name_fulltext IF NOT EXISTS
FOR (d:Dish) ON EACH [d.name]
```

查詢時可使用：

```cypher
CALL db.index.fulltext.queryNodes("dish_name_fulltext", $candidate)
```

但因為 `cypher_guard.py` 目前禁止 `CALL`，若要使用 fulltext，就需要另外開一個受控的內部 matcher 方法，不讓 LLM 直接產生 `CALL`。

---

## 8. 低相似度時的食材 fallback 檢索

### 8.1 觸發條件

當某個候選料理：

```python
match_score < 60
```

或完全沒有 `matched_dish_name` 時，觸發食材 fallback。

範例：

```json
{
  "input_name": "豪華炸雞雙拼飯",
  "matched_dish_name": null,
  "match_score": 0,
  "retrieval_strategy": "ingredient_fallback"
}
```

### 8.2 fallback 概念

如果圖譜中沒有這道完整料理，就不要硬把它對應到錯誤料理。應改成：

1. 從候選料理名稱切出可能食材詞。
2. 到 `(:Ingredient)` 或 `(:FoodItem)` 查是否有相符節點。
3. 用找到的食材往後查 `(:Nutrition)`。
4. 將食材營養成分加總，推估成這道候選料理的營養成分。
5. 在 `debug_trace` 中標註這道料理是推估值，不是完整料理資料。

### 8.3 建議 Cypher

```cypher
UNWIND $fallback_targets AS target
MATCH (ing:Ingredient)
WHERE target.input_name CONTAINS ing.name
   OR ing.name CONTAINS target.input_name
MATCH (ing)-[hn:HAS_NUTRITION]->(n:Nutrition)
OPTIONAL MATCH (f:FoodItem {food_id: hn.source_food_id})
OPTIONAL MATCH (dis:Disease)-[rule:HAS_DIET_RULE]->(n)
WHERE dis.name IN $disease_names
RETURN
  target.input_name AS dish_name,
  null AS matched_dish_name,
  "ingredient_fallback" AS retrieval_strategy,
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
ORDER BY dish_name, ingredient_name, nutrition_name
LIMIT 1000
```

### 8.4 fallback 注意事項

食材 fallback 是推估，不是精準料理資料，因此回答時要降級描述：

- 可以說「依照名稱中可辨識的食材推估」。
- 不要說「系統精準查到這道料理」。
- 若完全找不到食材，應回傳「資料不足」，而不是請 LLM 編營養素。

---

## 9. 全參數 LangChain text-to-cypher

### 9.1 使用方式

新版不再只把 `question` 丟給 LangChain，而是把完整 payload 丟入 prompt。

```python
cypher_result = self.text_to_cypher.translate(
    TextToCypherPayload(
        question=request.question,
        question_type=effective_question_type,
        user_profile=user_profile,
        health_condition=health_condition,
        weekly_diet_records_summary=weekly_summary,
        dish_candidates=candidates,
        dish_match_results=match_results,
    )
)
```

### 9.2 Prompt 目標

LangChain 的 Cypher prompt 要明確要求：

- 根據 `dish_match_results` 決定查詢路徑。
- `retrieval_strategy = dish_match` 時，使用 `matched_dish_name` 查 `(:Dish)`。
- `retrieval_strategy = ingredient_fallback` 時，使用 `input_name` 查 `(:Ingredient)` 或 `(:FoodItem)`。
- 慢性病只可使用 `health_condition.chronic_diseases`。
- 不可以從問題文字自行推測慢性病。
- 不可以產生寫入型 Cypher。
- 不可以產生與營養圖譜無關的查詢。
- 必須回傳足夠欄位，讓後續可彙總營養成分與疾病規則。

### 9.3 LangChain prompt 草稿

```text
You are a Neo4j Text-to-Cypher generator for a Nutrition GraphRAG system.
Generate exactly one read-only Cypher query.
Do not answer the user. Do not output markdown. Output Cypher only.

Graph schema:
Dish {recipe_id, name, servings}
Ingredient {name, matched_food_id, matched_food_name, mapping_method}
FoodItem {food_id, name, category, aliases}
Nutrition {nutrition_id, name, name_zh, unit, category, source_column}
Disease {disease_id, name, name_en}
(:Dish)-[:CONTAINS]->(:Ingredient)
(:Ingredient)-[:HAS_NUTRITION]->(:Nutrition)
(:Disease)-[:HAS_DIET_RULE]->(:Nutrition)

Rules:
1. Use the full JSON payload, not only the question.
2. Use dish_match_results as the source of retrieval targets.
3. If retrieval_strategy is dish_match, query Dish by matched_dish_name.
4. If retrieval_strategy is ingredient_fallback, query Ingredient/FoodItem by input_name.
5. Use health_condition.chronic_diseases as disease_names. Do not infer diseases from question text.
6. Return nutrition rows with dish_name, matched_dish_name, retrieval_strategy, ingredient_name, nutrition_name, nutrition_name_zh, amount_per_serving, amount_per_100g, nutrition_unit, disease rule fields.
7. Only use MATCH, OPTIONAL MATCH, WHERE, WITH, UNWIND, RETURN, ORDER BY, LIMIT.
8. Do not use CREATE, MERGE, SET, DELETE, CALL, APOC, LOAD CSV, DROP, REMOVE.
9. Always LIMIT results.

Input JSON:
{payload_json}
```

---

## 10. Cypher 安全檢查

所有 Cypher 在執行前都要經過 `validate_read_only_cypher()`。

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
6. 必須包含 `LIMIT`，避免一次抓太多 graph rows。

使用位置：

- request 直接傳入 `cypher` 時。
- LangChain 產出 Cypher 後。
- `GraphRetriever.retrieve()` 真正執行前。

---

## 11. Neo4j 圖譜檢索

入口：

```python
rows = self.retriever.retrieve(cypher)
```

`GraphRetriever.retrieve()`：

```python
def retrieve(self, cypher: str) -> list[dict[str, Any]]:
    validate_read_only_cypher(cypher)

    with self.driver.session() as session:
        result = session.run(cypher)
        rows = [
            {key: self.to_plain_value(value) for key, value in record.data().items()}
            for record in result
        ]

    return rows
```

固定輸出欄位建議：

```json
{
  "dish_name": "雞排便當",
  "matched_dish_name": "雞排便當",
  "retrieval_strategy": "dish_match",
  "ingredient_name": "雞排",
  "food_item_name": "雞排",
  "nutrition_name": "fat",
  "nutrition_name_zh": "脂肪",
  "nutrition_category": "macro",
  "amount_per_serving": 25.3,
  "amount_per_100g": 18.2,
  "nutrition_unit": "g",
  "disease_name": "高血壓",
  "diet_rule_relation": "limit",
  "diet_rule_direction": "high",
  "diet_rule_note": "...",
  "diet_rule_reason": "...",
  "food_level_condition": "...",
  "sources_json": "..."
}
```

---

## 12. 圖譜結果濃縮與熱量重算

入口：

```python
dish_nutrition, nutrition_debug = self.nutrition_calculator.summarize_and_recalculate(rows)
```

### 12.1 彙總規則

新版仍會從 graph rows 彙總常見營養素，但熱量不再直接相信圖譜中的熱量列。

彙總步驟：

1. 逐列讀取：
   - `dish_name`
   - `retrieval_strategy`
   - `nutrition_name_zh`，若沒有則用 `nutrition_name`
   - `amount_per_serving`
   - `nutrition_unit`
2. 用 `COMMON_NUTRIENT_ALIASES` 做名稱標準化。
3. 只保留常見營養素，例如：
   - 熱量
   - 蛋白質
   - 脂肪
   - 碳水化合物
   - 糖
   - 鈉
   - 膳食纖維
4. 以 `dish_name + nutrient` 分組加總 `amount_per_serving`。
5. 對三大營養素做單位檢查，必須是 `g` 才能參與熱量重算。
6. 最終熱量使用公式重新計算。

### 12.2 熱量計算公式

最終料理的熱量必須由三大營養素計算：

```text
熱量 kcal = 蛋白質 g * 4 + 碳水化合物 g * 4 + 脂肪 g * 9
```

程式：

```python
def calculate_calories(protein_g: float, carb_g: float, fat_g: float) -> float:
    return round(protein_g * 4 + carb_g * 4 + fat_g * 9, 2)
```

### 12.3 熱量欄位處理規則

| 情況                              | 處理方式                                                     |
| --------------------------------- | ------------------------------------------------------------ |
| 蛋白質、脂肪、碳水都有值          | 用公式計算熱量，覆蓋原本 graph rows 中的熱量。               |
| 三大營養素缺一項                  | 不計算熱量，標記 `calorie_status = insufficient_macros`。    |
| 單位不是 `g`                      | 不納入熱量計算，標記 `unit_invalid`。                        |
| graph rows 有熱量但三大營養素不足 | 不可直接使用 graph 熱量當最終熱量，只能放在 debug 中作參考。 |

### 12.4 輸出格式

```json
[
  {
    "dish_name": "雞排便當",
    "retrieval_strategy": "dish_match",
    "nutrients": [
      {
        "name": "熱量",
        "amount_per_serving": 812.4,
        "unit": "kcal",
        "calculation_method": "macro_calculation",
        "formula": "protein_g*4 + carbohydrate_g*4 + fat_g*9"
      },
      {
        "name": "蛋白質",
        "amount_per_serving": 32.1,
        "unit": "g"
      },
      {
        "name": "脂肪",
        "amount_per_serving": 38.0,
        "unit": "g"
      },
      {
        "name": "碳水化合物",
        "amount_per_serving": 85.0,
        "unit": "g"
      }
    ]
  }
]
```

---

## 13. Debug trace 與執行過程 print

### 13.1 設計原則

使用者希望在生成回覆和料理營養成分時看到背後運算邏輯，所以新版要保留可追蹤資訊。

建議同時支援兩種方式：

1. 開發環境：使用 `print()` 或 `logger.info()` 印出過程。
2. API response：當 `debug=true` 時回傳 `debug_trace`。

正式環境不建議只依賴 `print()`，因為 API 使用者看不到後端 console。比較好的做法是：

```python
if request.debug:
    debug_trace.append({...})
logger.info("[NutritionAgent] ...")
```

### 13.2 Debug trace 格式

`NutritionAgentResponse` 新增：

```python
debug_trace: Optional[list[dict[str, Any]]] = None
```

範例：

```json
[
  {
    "step": "extract_dish_candidates",
    "message": "Extracted dish candidates from question.",
    "data": ["雞排便當", "排骨便當"]
  },
  {
    "step": "dish_match",
    "message": "Matched candidates against Dish nodes.",
    "data": [
      {
        "input_name": "雞排便當",
        "matched_dish_name": "雞排便當",
        "match_score": 100,
        "retrieval_strategy": "dish_match"
      }
    ]
  },
  {
    "step": "text_to_cypher",
    "message": "Generated Cypher from full request payload.",
    "data": {
      "cypher": "UNWIND ... RETURN ... LIMIT 1000"
    }
  },
  {
    "step": "nutrition_calculation",
    "message": "Calories recalculated from macros.",
    "data": {
      "dish_name": "雞排便當",
      "protein_g": 32.1,
      "carbohydrate_g": 85.0,
      "fat_g": 38.0,
      "calories_kcal": 812.4,
      "formula": "32.1*4 + 85.0*4 + 38.0*9"
    }
  }
]
```

### 13.3 print / logger 建議內容

```python
print("[NutritionAgent] question_type:", effective_question_type)
print("[NutritionAgent] dish_candidates:", candidates)
print("[NutritionAgent] dish_match_results:", match_results)
print("[NutritionAgent] generated_cypher:", cypher)
print("[NutritionAgent] graph_rows_count:", len(rows))
print("[NutritionAgent] dish_nutrition:", dish_nutrition)
print("[NutritionAgent] nutrition_debug:", nutrition_debug)
```

如果要比較正式，改用：

```python
logger.info("[NutritionAgent] dish_candidates=%s", candidates)
logger.info("[NutritionAgent] dish_match_results=%s", match_results)
logger.info("[NutritionAgent] graph_rows_count=%s", len(rows))
```

---

## 14. 傳給 OpenAI 的回答生成流程

入口：

```python
answer_payload = self.answer_generator.generate(
    question=request.question,
    question_type=effective_question_type,
    user_profile=user_profile,
    health_condition=health_condition,
    weekly_diet_records=weekly_records,
    dish_nutrition=dish_nutrition,
    graph_rows=rows[:DEFAULT_TOP_N_ROWS],
    debug_trace=debug_trace if request.debug else None,
)
```

### 14.1 組 context

`AnswerGenerator.generate()` 組出的 context：

```json
{
  "question": "你覺得我今天要吃雞排便當還是排骨便當嗎",
  "question_type": "dish_comparison",
  "user_profile": {
    "height_cm": 170,
    "weight_kg": 70,
    "gender": "male",
    "age": 30
  },
  "health_condition": {
    "has_chronic_disease": true,
    "chronic_diseases": ["高血壓"]
  },
  "weekly_diet_records": [...],
  "user_context_summary": {
    "bmi": 24.2,
    "bmi_category": "正常或過重邊界，依系統分類為準",
    "chronic_diseases": ["高血壓"],
    "recent_patterns": ["偏鹹", "偏油"],
    "weekly_record_count": 5
  },
  "dish_nutrition": [...],
  "graph_rows": [...],
  "retrieval_notes": {
    "calories_are_recalculated_from_macros": true,
    "ingredient_fallback_means_estimated_nutrition": true
  }
}
```

### 14.2 Answer prompt 重點

回答生成 prompt 需要新增規則：

- 回答必須根據 `dish_nutrition`，不能自己編營養數值。
- 熱量欄位只能使用 `calculation_method = macro_calculation` 的結果。
- 如果某料理是 `ingredient_fallback`，回答要說明是依可辨識食材推估。
- 如果某料理缺少三大營養素導致無法計算熱量，不可自行補值。
- 比較題必須選出一道相對推薦料理，但不要用禁止語氣。
- 若使用者有慢性病，必須優先考慮疾病規則，例如高血壓需注意鈉、油脂、加工食品。
- 近期飲食紀錄只作為輔助判斷，不可當成精準營養攝取資料。

要求 JSON 格式：

```json
{
  "dish_advice": [
    {
      "dish_name": "...",
      "suitability": "推薦 / 較不建議 / 可少量吃 / 資料不足",
      "key_reasons": ["...", "..."],
      "suggestions": ["...", "..."]
    }
  ],
  "conclusion": "..."
}
```

---

## 15. OpenAI 回答解析與比較題校正

OpenAI 回傳文字後：

```python
parsed = self._parse_json(self._complete(messages))
```

解析後使用 Pydantic 驗證：

```python
parsed["dish_advice"] = [
    DishAdvice(**item).model_dump()
    for item in parsed.get("dish_advice", [])
]
parsed["conclusion"] = str(parsed.get("conclusion", "")).strip()
```

### 15.1 比較題必須選出一道推薦料理

若 `question_type == "dish_comparison"`，系統檢查 LLM 是否有明確選出一道推薦料理。

判斷方式：

- `dish_advice` 中必須剛好有一道料理的 `suitability` 是 `推薦`。
- 如果沒有，再看 `conclusion` 是否只明確推薦一個 dish name。
- 若仍沒有，送 correction prompt 要求只修正 JSON，不重新編資料。

### 15.2 比較題結果正規化

通過檢查後，呼叫：

```python
normalize_comparison_advice(parsed, dish_nutrition)
```

正規化規則：

1. 以 `dish_nutrition` 中的料理列表為準。
2. 被選中的料理標成 `推薦`。
3. 其他料理標成 `較不建議` 或 `可少量吃`。
4. 如果某料理 `calorie_status = insufficient_macros`，不得把它標成絕對健康，只能標成 `資料不足` 或保守建議。

---

## 16. 最終輸出

`NutritionAgentResponse`：

```json
{
  "question": "你覺得我今天要吃雞排便當還是排骨便當嗎",
  "question_type": "dish_comparison",
  "dish_nutrition": [
    {
      "dish_name": "雞排便當",
      "retrieval_strategy": "dish_match",
      "nutrients": [
        {
          "name": "熱量",
          "amount_per_serving": 812.4,
          "unit": "kcal",
          "calculation_method": "macro_calculation"
        },
        {
          "name": "蛋白質",
          "amount_per_serving": 32.1,
          "unit": "g"
        }
      ]
    }
  ],
  "dish_advice": [
    {
      "dish_name": "排骨便當",
      "suitability": "推薦",
      "key_reasons": ["相較雞排便當可能油脂較低，但仍需注意鈉含量。"],
      "suggestions": ["醬汁減量，配菜選青菜，湯汁少喝。"]
    }
  ],
  "conclusion": "如果今天要在兩者中選一個，較建議排骨便當，但高血壓仍要注意醬汁與鈉含量。",
  "cypher_used": null,
  "graph_rows": null,
  "debug_trace": null
}
```

若 `debug=true`：

- `cypher_used` 放實際執行的 Cypher。
- `graph_rows` 放完整 Neo4j 查詢結果。
- `debug_trace` 放完整決策與運算過程。

若 `debug=false`：

- `cypher_used = null`
- `graph_rows = null`
- `debug_trace = null`

---

## 17. 資料流輸入輸出總表

| 階段                | 輸入                                        | 輸出                                                 |
| ------------------- | ------------------------------------------- | ---------------------------------------------------- |
| FastAPI `/ask`      | HTTP JSON body                              | `NutritionAgentRequest`                              |
| 預設值補齊          | request                                     | `user_profile`、`health_condition`、`weekly_records` |
| request 正規化      | request                                     | `full_payload`                                       |
| 題型判斷            | `question`、`request.question_type`         | `effective_question_type`                            |
| 候選料理抽取        | `full_payload`                              | `dish_candidates`                                    |
| 料理名稱 Match      | `dish_candidates`                           | `dish_match_results` with `match_score`              |
| fallback 決策       | `dish_match_results`                        | `retrieval_strategy`                                 |
| text-to-cypher      | `full_payload + match_results + strategy`   | `{cypher, question_type, rationale}`                 |
| Cypher guard        | `cypher`                                    | 通過或丟 `ValueError`                                |
| Neo4j retrieve      | `cypher`                                    | `rows: List[Dict[str, Any]]`                         |
| 營養摘要與熱量重算  | `rows`                                      | `dish_nutrition`, `nutrition_debug`                  |
| debug trace         | 各階段中間結果                              | `debug_trace`                                        |
| context 組裝        | request 資料、`dish_nutrition`、`rows[:80]` | OpenAI user JSON context                             |
| OpenAI answer       | system prompt + user context                | JSON 字串                                            |
| JSON parse/validate | OpenAI JSON 字串                            | `{dish_advice, conclusion}`                          |
| 比較題 normalize    | parsed answer、`dish_nutrition`             | 正規化後的 comparison advice                         |
| Response            | all outputs                                 | `NutritionAgentResponse`                             |

---

## 18. 新版邏輯的重要特性

1. text-to-cypher 不再只吃 `question`，而是吃完整 request payload。
2. 料理名稱會先做 Match，並回傳 `match_score`。
3. `match_score >= 60` 才使用完整料理資料。
4. `match_score < 60` 時改查食材節點，用食材推估料理營養成分。
5. 最終熱量必須由蛋白質、脂肪、碳水化合物計算，不能直接拿圖譜中的熱量列當最終值。
6. 若三大營養素不足，就標記資料不足，不讓 LLM 自行補熱量。
7. debug 模式會回傳完整運算過程，包含候選料理、匹配分數、fallback 決策、Cypher、graph rows 數量、營養彙總、熱量公式。
8. 比較題仍要選出一道相對推薦料理，但回答語氣維持溫和，不做強制禁止。
9. 慢性病只從 `health_condition.chronic_diseases` 進入檢索，不從 question 文字自行推測。
10. OpenAI 負責生成自然語言 JSON 回答，不負責編造營養數值。

---

## 19. 建議實作順序

1. 先新增 `debug_trace` 到 response model。
2. 新增 `DishMatcher.match_dishes()`，完成料理名稱分數機制。
3. 新增 `IngredientFallbackRetriever` 或將 fallback query 交給 text-to-cypher payload 控制。
4. 修改 `TextToCypherTranslator.translate()`，改收完整 payload。
5. 修改 LangChain prompt，強制使用 `dish_match_results` 與 `retrieval_strategy`。
6. 新增 `NutritionCalculator.summarize_and_recalculate()`。
7. 修改 `AnswerGenerator` prompt，禁止 LLM 自行編營養數值。
8. 用 `request_comparison.json` 測試：
   - 是否抽出 `雞排便當`、`排骨便當`。
   - 是否各自產生 match score。
   - 是否正確查到 graph rows。
   - 是否用三大營養素重算熱量。
   - 是否在高血壓情境下把鈉、油脂、醬汁列入理由。
   - `debug=true` 時是否能看到完整過程。
