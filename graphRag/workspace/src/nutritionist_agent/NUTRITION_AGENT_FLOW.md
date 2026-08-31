# Nutrition Agent v2 架構與生命週期說明

這個資料夾實作的是一個飲食建議 GraphRAG agent。外部呼叫者透過 FastAPI 的 `/ask` 路徑送入使用者問題、已整理好的料理清單、個人資料、慢性病資訊與近一周飲食紀錄；Nutrition Agent 不負責從問題抽取料理或判斷問題類型。系統會對齊 Neo4j 圖譜中的料理或食物節點，查出營養素與疾病飲食規則，重新彙總主要營養資訊，最後呼叫 OpenAI 產生繁體中文飲食建議並回傳。若只需要替飲食紀錄取得單一道料理營養成分，則可呼叫 `/dish-nutrition`，它會共用圖譜檢索與營養彙總流程，但不呼叫 OpenAI。

目前主流程不是讓 LLM 即時自由生成 Cypher，而是由 `text_to_cypher.py` 依照料理配對結果用程式化模板產生 read-only Cypher。這樣可以讓圖譜查詢欄位、慢性病條件與安全限制都維持穩定。

## 主要檔案職責

- `app.py`：FastAPI HTTP 入口，定義 `/health`、`/ready`、`/ask`、`/dish-nutrition`。
- `models.py`：Pydantic request/response 與內部資料模型，包含問答與單一料理營養查詢格式。
- `agent.py`：整個 Nutrition Agent 的流程協調器，另外提供不產生建議的單一料理營養查詢。
- `text_to_cypher.py`：問題型態判斷、料理候選抽取、payload 標準化、Cypher 組裝。
- `dish_matcher.py`：將使用者輸入料理名稱配對到 Neo4j 的 `Dish` 或 `FoodItem`。
- `retriever.py`：執行 Neo4j Cypher，並將 Neo4j 型別轉成一般 Python 資料。
- `nutrition_calculator.py`：彙總圖譜營養列，並用三大營養素重新計算熱量。
- `answer_generator.py`：組合 LLM context、呼叫 OpenAI、驗證與清理回答。
- `cypher_guard.py`：檢查 Cypher 是否只讀、安全、單一語句且有 `LIMIT`。
- `config.py`：讀取 `.env` 與環境變數，提供 Neo4j/OpenAI/查詢限制設定。

`test_area` 是 Neo4j 資料檢查與修補用途，本文件依照需求不納入主流程說明。

## 輸入格式

外部呼叫 `POST /ask` 時，請求模型定義在 `models.py` 的 `NutritionAgentRequest`：

- `question`：使用者原始問題，必填。
- `dish_info_list`：呼叫端明確提供的料理名稱與份數，Nutrition Agent 不再從自然語言問題抽料理。
- `question_type`：呼叫端提供的 `single_dish`、`dish_comparison` 或 `unknown`。
- `user_profile`：使用者身高、體重、性別、年齡。
- `health_condition`：是否有慢性病與慢性病清單。
- `weekly_diet_records`：近一周飲食紀錄，提供個人化建議背景。

FastAPI 入口在 `app.py` 的 `ask(req: NutritionAgentRequest)`。這個 function 只負責 HTTP 層錯誤轉換，真正流程會呼叫 `agent.ask(req)`。

若只是飲食紀錄要查單一道料理營養成分，可呼叫 `POST /dish-nutrition`，請求模型是 `DishNutritionRequest`：

```json
{
  "dish_name": "雞腿便當"
}
```

回應模型是 `DishNutritionResponse`，只包含一筆 `dish_nutrition`，不包含 `dish_advice` 或 `conclusion`。

## 完整生命週期

### 1. 服務啟動與設定載入

`config.py` 在匯入時會呼叫 `load_env_files()`，依序讀取：

- 根目錄 `dietary_app/.env`

接著建立以下設定：

- `NEO4J_URI`、`NEO4J_USER`、`NEO4J_PASSWORD`
- `OPENAI_API_KEY`、`OPENAI_API_BASE`、`OPENAI_MODEL`
- `DEFAULT_TOP_N_ROWS`
- `DISH_MATCH_THRESHOLD`
- `GRAPH_QUERY_LIMIT`

`app.py` 建立 FastAPI app 後會呼叫 `validate_required_config()`。在 production 環境中，如果缺少 OpenAI key 或 Neo4j 連線設定，會直接阻止服務啟動。

### 2. 建立 NutritionAgent

`app.py` 會在模組層建立：

```python
agent = NutritionAgent()
```

`agent.py` 的 `NutritionAgent.__init__()` 會建立五個核心子模組：

- `GraphRetriever`：管理 Neo4j driver。
- `TextToCypherTranslator`：將標準 payload 轉成查詢 Cypher。
- `DishMatcher`：處理料理名稱配對。
- `NutritionCalculator`：計算營養摘要。
- `AnswerGenerator`：呼叫 OpenAI 產生回答。

### 3. 接收 `/ask` 請求

`app.py` 的 `ask()` 收到 request 後，呼叫 `agent.py` 的 `NutritionAgent.ask()`。若流程中丟出：

- `ValueError`：轉成 HTTP 400。
- `RuntimeError`：轉成 HTTP 503。
- `Neo4jError`：轉成 HTTP 503。

因此外部 API 呼叫者不會直接看到 Python exception，而是得到合理的 HTTP 錯誤。

### 4. 補齊預設資料與判斷問題型態

在 `agent.py` 的 `NutritionAgent.ask()` 開頭：

- 若 `user_profile` 沒提供，使用空的 `UserProfile()`。
- 若 `health_condition` 沒提供，使用空的 `HealthCondition()`。
- 若 `weekly_diet_records` 沒提供，使用空清單。

`question_type` 與 `dish_info_list` 均由呼叫端提供，Agent 直接採用，不再分析 question 文字。

### 5. 標準化第一次 payload

`agent.py` 呼叫 `text_to_cypher.py` 的 `normalize_request_payload()`，組出第一次 `full_payload`。這份 payload 會包含：

- 原始問題。
- 問題型態。
- 結構化料理名稱。
- 使用者資料。
- 慢性病資料。
- 近一周飲食紀錄摘要。
- 尚未填入的料理候選與配對結果。

近一周飲食紀錄摘要由 `summarize_weekly_records_for_retrieval()` 產生，包含：

- 紀錄筆數。
- 最近最多 10 個料理名稱。
- 從 note 擷取出的關鍵字，例如「炸」「油」「鹹」「甜」「蔬菜」。

### 6. 抽出料理候選名稱

料理名稱抽取與問題類型判斷已移至呼叫端；Agent 僅驗證並使用 `dish_info_list`。

### 7. 料理名稱配對 Neo4j 節點

`agent.py` 呼叫 `dish_matcher.py` 的 `DishMatcher.match_dishes(dish_candidates)`。

這一步會在 `DishMatcher` 初始化時從 Neo4j 讀取所有 `Dish` 與 `FoodItem` 名稱，建立可重複使用的 Python `BM25Okapi` index。KG 更新後可以呼叫 `refresh_bm25_index()` 重建 index。

每次請求會依序執行：

1. 對標準化後的名稱做 exact lookup。
2. Exact 找不到時，用 BM25 取得 Top-K 候選。
3. 用 token overlap 計算 0 到 99 的非 exact `match_score`，並保留 100 給 exact match。
4. 依 threshold 與候選分數差距判斷 `match` 或 `no_match`。

BM25 index 同時包含：

- `(:Dish)`：料理節點。
- `(:FoodItem)`：食物項目節點。

配對後會決定 `retrieval_strategy`：

- `dish_match`：配到 `Dish` 且分數達門檻，後續從完整食譜路徑查營養。
- `fooditem_fallback`：配到 `FoodItem` 且分數達門檻，後續直接從食物營養查。
- `ingredient_fallback`：未達門檻或找不到節點，後續用輸入名稱比對 `Ingredient`。

這個結果會寫入 `dish_match_results`。

### 8. 標準化第二次 payload

`agent.py` 再次呼叫 `normalize_request_payload()`，這次會把：

- `dish_candidates`
- `dish_match_results`

一起放進 payload。這份第二次 payload 才是後續產生 Cypher 的主要依據。

### 9. 產生安全 Cypher

`agent.py` 呼叫 `text_to_cypher.py` 的 `TextToCypherTranslator.translate(full_payload)`。

`translate()` 目前會呼叫 `build_graph_retrieval_cypher()`，而不是呼叫 LLM。它會從 payload 取出：

- `dish_match_results`
- `health_condition.chronic_diseases`

慢性病名稱由 `resolve_diseases_from_payload()` 取得，而且只相信 `health_condition`，不從問題文字推測疾病。

`build_graph_retrieval_cypher()` 會把所有 retrieval target 轉成 Cypher literal，查詢路徑如下：

```text
Dish -> CONTAINS -> Ingredient -> MAPS_TO -> FoodItem -> HAS_NUTRITION -> Nutrition
Disease -> HAS_DIET_RULE -> Nutrition
```

不同策略的查詢方式：

- `dish_match`：用 `matched_dish_name` 找 `(:Dish)`，再沿著食譜成分查營養。
- `ingredient_fallback`：用使用者輸入名稱模糊比對 `(:Ingredient)`。
- `fooditem_fallback`：用 `matched_food_id` 直接找 `(:FoodItem)`。

回傳欄位包含：

- 使用者料理名稱與配對名稱。
- 配對類型、分數、原因、策略。
- ingredient 與 food item 名稱。
- 營養素名稱、中文名、分類、單位。
- 每份量估計值與每 100g 數值。
- 疾病飲食規則欄位。

產生後會經過 `cypher_guard.py` 的 `validate_read_only_cypher()`，檢查：

- 不可空白。
- 不可包含多語句。
- 不可包含 `CREATE`、`MERGE`、`SET`、`DELETE`、`CALL`、`APOC`、`LOAD CSV` 等寫入或高風險關鍵字。
- 必須以 `MATCH`、`OPTIONAL MATCH` 或 `UNWIND` 開頭。
- 必須有 `RETURN`。
- 必須有 `LIMIT`。

### 10. 查詢 Neo4j

`agent.py` 呼叫 `retriever.py` 的 `GraphRetriever.retrieve(cypher)`。

`retrieve()` 會再次呼叫 `validate_read_only_cypher()`，然後用 Neo4j session 執行查詢。回傳 record 會經過 `to_plain_value()` 遞迴轉換，讓 Neo4j 的 `Node`、`Relationship`、`Path` 變成可 JSON 序列化的 dict/list。

### 11. 缺資料 fallback retry

第一次查詢後，`agent.py` 呼叫 `_missing_candidates_from_rows()` 檢查哪些候選料理沒有出現在查詢結果中。

如果有缺資料候選，`NutritionAgent.ask()` 會建立新的 fallback match result：

```text
retrieval_strategy = ingredient_fallback
match_reason = no nutrition rows from dish match
```

然後再次：

1. 建立 fallback payload。
2. 呼叫 `TextToCypherTranslator.translate()`。
3. 呼叫 `GraphRetriever.retrieve()`。
4. 把 fallback rows 合併回原本 rows。

這段設計的目的，是避免料理名稱雖然配到 `Dish`，但食譜路徑缺營養資料時，整道料理直接消失。

### 12. 彙總營養與重算熱量

`agent.py` 呼叫 `nutrition_calculator.py` 的 `NutritionCalculator.summarize_and_recalculate(rows)`。

這個 function 會做：

1. 讀取每列 row 的 `dish_name`。
2. 使用 `nutrition_name_zh` 或 `nutrition_name` 找營養素名稱。
3. 透過 `COMMON_NUTRIENT_ALIASES` 將不同名稱合併，例如：
   - `粗蛋白`、`protein` -> `蛋白質`
   - `粗脂肪`、`脂質`、`fat` -> `脂肪`
   - `總碳水化合物`、`carbs` -> `碳水化合物`
4. 只保留 `COMMON_NUTRIENT_ORDER` 中的重要營養素。
5. 依料理與營養素累加 `amount_per_serving`。
6. 保留配對 metadata，例如 `matched_name`、`matched_type`、`match_score`、`match_reason`。

每道料理會呼叫 `_recalculate_calories()`。熱量計算邏輯是：

- 先把圖譜原本的「熱量」取出當參考。
- 若蛋白質、碳水化合物、脂肪都有資料，且單位都是 `g`，用公式重新計算：

```text
protein_g*4 + carbohydrate_g*4 + fat_g*9
```

- 若單位不正確，標記 `calorie_status = unit_invalid`。
- 若缺少三大營養素，標記 `calorie_status = insufficient_macros`。

最後回傳：

- `dish_nutrition`：每道料理的摘要。
- `nutrition_debug`：熱量重算的除錯資訊，只寫 log，不直接回傳給 API。

### 13. 比較題補齊候選

如果問題型態是 `dish_comparison`，`agent.py` 會呼叫 `_ensure_candidate_nutrition()`。

這個 function 的目的，是確保比較題中每個候選料理都出現在 `dish_nutrition`。如果某道料理完全沒有查到營養列，仍會補一筆 `DishNutrition`，其中主要營養素的 `amount_per_serving` 會是 `None`，熱量狀態為 `insufficient_macros`。

這樣做可以讓 LLM 知道「這道料理是候選之一，但資料不足」，而不是在比較題中忽略它。

### 14. 組合 LLM context

`agent.py` 呼叫 `answer_generator.py` 的 `AnswerGenerator.generate()`。

`generate()` 會組合一份 context 給 OpenAI，內容包含：

- 原始問題。
- 問題型態。
- 使用者基本資料。
- 慢性病資料。
- 近一周飲食紀錄完整內容。
- `summarize_user_context()` 產出的使用者摘要。
- `dish_nutrition`。
- 最多 `DEFAULT_TOP_N_ROWS` 筆 graph rows。
- retrieval notes，例如熱量已重算、fallback 是估算、建議文字不可輸出營養數字。

如果 `OPENAI_API_KEY` 沒有設定或是 `dummy-key`，會直接丟出 `RuntimeError`。目前系統不再產生 fallback conclusion，必須有可用的 OpenAI key 才能完成 `/ask`。

### 15. OpenAI 產生回答

`answer_generator.py` 的 `generate_with_llm()` 會建立兩則 message：

- system：`ANSWER_PROMPT`，規定回答角色、格式、限制與安全規則。
- user：完整 JSON context。

`_complete()` 會用 OpenAI Chat Completions API 呼叫指定模型。`_parse_json()` 會解析模型回傳 JSON，也支援模型包在 ```json code fence 的情況。

`ANSWER_PROMPT` 的重要規則包括：

- 使用繁體中文。
- 只能根據 GraphRAG 與使用者資料回答。
- 不可杜撰數值。
- 建議文字不可輸出 kcal、mg、g、克、百分比等具體數字或單位。
- 慢性疾病只根據 `health_condition`，不能從 question 文字推測。
- 若是比較題，必須剛好推薦一個候選料理。
- 若有慢性病，結尾會依 `health_condition.chronic_diseases` 動態加入對應健康指標與用藥提醒；沒有慢性病資料時不強行加入疾病提醒。

### 16. 比較題回答校正

若 `question_type == dish_comparison`，`generate_with_llm()` 會用 `has_llm_comparison_choice()` 檢查 LLM 是否有明確推薦一個料理。

判斷方式：

- 優先看 `dish_advice` 是否剛好一個項目的 `suitability` 是「推薦」。
- 若沒有，再看 `conclusion` 是否提到某一道候選料理，且附近有「建議」「選擇」「推薦」等字。

如果第一次沒有明確選擇，會加上一段 correction prompt 要求模型重試一次。如果重試後仍沒有明確選擇，就丟出 `RuntimeError`。

### 17. 回答後處理

`AnswerGenerator.generate()` 會做三段後處理：

1. `normalize_comparison_advice()`  
   比較題中，確保每道候選料理都有一筆 advice，且只有被選中的料理是「推薦」。

2. `attach_match_metadata_to_advice()`  
   將 `dish_nutrition` 裡的 `matched_name`、`matched_type`、`match_score`、`match_reason` 補回 LLM advice，方便前端顯示與除錯。

3. `sanitize_nutrition_numbers()`  
   將模型可能輸出的具體數字與單位替換成「相對偏高」等定性文字，符合產品規則。

### 18. 組成 API 回應

最後 `agent.py` 的 `NutritionAgent.ask()` 建立 `NutritionAgentResponse`，其格式定義在 `models.py`：

- `question`：原始問題。
- `question_type`：實際判斷或採用的問題型態。
- `dish_nutrition`：每道料理的營養摘要與配對 metadata。
- `dish_advice`：LLM 產生並後處理過的逐料理建議。
- `conclusion`：總結回答。

這份 response 會回到 `app.py` 的 `/ask`，由 FastAPI 序列化成 UTF-8 JSON 回傳給呼叫者。

## 資料流總覽

```text
POST /ask
  -> app.py: ask()
  -> agent.py: NutritionAgent.ask()
  -> text_to_cypher.py: normalize_request_payload()
  -> dish_matcher.py: DishMatcher.match_dishes()
  -> text_to_cypher.py: normalize_request_payload()
  -> text_to_cypher.py: TextToCypherTranslator.translate()
  -> text_to_cypher.py: build_graph_retrieval_cypher()
  -> cypher_guard.py: validate_read_only_cypher()
  -> retriever.py: GraphRetriever.retrieve()
  -> agent.py: _missing_candidates_from_rows()
  -> optional fallback retry
  -> nutrition_calculator.py: summarize_and_recalculate()
  -> nutrition_calculator.py: _recalculate_calories()
  -> agent.py: _ensure_candidate_nutrition()
  -> answer_generator.py: AnswerGenerator.generate()
  -> answer_generator.py: generate_with_llm()
  -> answer_generator.py: normalize_comparison_advice()
  -> answer_generator.py: attach_match_metadata_to_advice()
  -> answer_generator.py: sanitize_nutrition_numbers()
  -> models.py: NutritionAgentResponse
  -> UTF-8 JSON response
```

```text
POST /dish-nutrition
  -> app.py: dish_nutrition()
  -> agent.py: NutritionAgent.get_dish_nutrition()
  -> text_to_cypher.py: normalize_request_payload()
  -> dish_matcher.py: DishMatcher.match_dishes()
  -> text_to_cypher.py: TextToCypherTranslator.translate()
  -> retriever.py: GraphRetriever.retrieve()
  -> optional ingredient fallback retry
  -> nutrition_calculator.py: summarize_and_recalculate()
  -> models.py: DishNutritionResponse
  -> UTF-8 JSON response
```

## 如何閱讀這份程式碼

建議閱讀順序：

1. 先看 `models.py`，了解 API 輸入輸出資料長什麼樣。
2. 再看 `app.py`，確認 `/ask` 如何進入 agent。
3. 接著看 `agent.py`，掌握主流程順序。
4. 看 `text_to_cypher.py`，理解料理抽取與 Cypher 產生。
5. 看 `dish_matcher.py`，理解名稱配對與 fallback 策略。
6. 看 `nutrition_calculator.py`，理解營養彙總與熱量重算。
7. 看 `answer_generator.py`，理解 OpenAI prompt、比較題校正與輸出清理。
8. 最後看 `retriever.py`、`cypher_guard.py`、`config.py`，理解基礎設施與安全邊界。

## 目前架構重點

- `/ask` 對外只接受自然語言問題與結構化使用者資料，不接受外部傳入 Cypher。
- Cypher 一律由內部產生，且經過 `validate_read_only_cypher()` 檢查。
- 慢性病條件只來自 `health_condition`，避免模型或文字解析自行猜測疾病。
- 料理名稱會先配對圖譜節點，再決定要走完整食譜查詢或 fallback 查詢。
- 熱量優先由蛋白質、碳水化合物、脂肪重新計算，不直接信任圖譜熱量。
- LLM 的任務是根據整理後的圖譜與使用者資料產生建議，不負責創造營養數字。
- 比較題必須推薦一個候選料理，避免回答無法落地。
