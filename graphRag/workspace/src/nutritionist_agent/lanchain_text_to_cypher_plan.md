# LangChain Text-to-Cypher 導入計畫

## Summary

將目前寫死的 `TextToCypherTranslator` 改成「可切換的 Cypher 產生層」：

- 預設保留現有 template 查詢，確保 `/ask`、`/dish-nutrition` 不被破壞。
- 新增 LangChain Text-to-Cypher translator，只負責產生 Cypher，不負責執行查詢或產生回答。
- 呼叫端負責 `should_handle`、`dish_names`、`question_type`；nutritionist agent 信任這些結構化欄位，但仍保留舊抽取邏輯作為相容 fallback。
- 後端保留 `DishMatcher`、`cypher_guard`、row schema validation，避免 LangChain 自由產生不可用或不安全的查詢。

## Responsibility Split

呼叫端負責：

- 判斷 `should_handle`：不該處理的問題不要呼叫 nutritionist API。
- 抽取 `dish_names`：作為 authoritative dish candidates；nutritionist agent 不再讓 LangChain 自行猜料理名稱。
- 判斷 `question_type`：
  - 1 道料理：`single_dish`
  - 2 道以上料理：`dish_comparison`
  - 無法判斷才傳 `unknown`
- 傳入既有健康 context：`user_profile`、`health_condition`、`weekly_diet_records`。
- 不傳 Cypher、不傳 Neo4j schema、不直接控制查詢。

nutritionist agent 負責：

- 接收 `/ask` payload，若有 `dish_names/question_type` 就優先採用。
- 用 `DishMatcher` 將 `dish_names` 對齊 Neo4j 中的 `Dish` 或 `FoodItem`。
- 將 `question`、`question_type`、`dish_match_results`、`health_condition`、`GRAPH_SCHEMA` 組成 LangChain prompt context。
- 由 LangChain 產生 read-only Cypher。
- 驗證 Cypher 安全性、必備 RETURN aliases、查詢結果 row schema。
- 執行 Neo4j 查詢後交給既有 `NutritionCalculator`、`AnswerGenerator`。

## Key Implementation Changes

- 在 `config.py` 新增設定：
  - `NUTRITION_AGENT_CYPHER_MODE=template|langchain`，預設 `template`。
  - `NUTRITION_AGENT_CYPHER_FALLBACK=template|error`，預設 `template`。
  - `NUTRITION_AGENT_CYPHER_MODEL`，預設沿用 `OPENAI_MODEL`。
- 將現有 `TextToCypherTranslator` 明確改名或包裝為 `TemplateTextToCypherTranslator`。
- 新增 `LangChainTextToCypherTranslator`：
  - 使用 LangChain + `ChatOpenAI` 產生 Cypher。
  - Prompt 強制使用 `dish_match_results`，禁止從 question 額外推論料理。
  - Prompt 強制輸出單一 Cypher statement，不輸出解釋文字。
  - Prompt 強制 RETURN 既有 calculator 需要的 aliases：`dish_name`、`matched_name`、`matched_type`、`matched_dish_name`、`match_score`、`match_reason`、`retrieval_strategy`、`ingredient_name`、`food_item_name`、`nutrition_name`、`nutrition_name_zh`、`nutrition_category`、`amount_per_serving`、`amount_per_100g`、`nutrition_unit`、`disease_name`、`diet_rule_relation`、`diet_rule_direction`、`diet_rule_note`、`diet_rule_reason`、`food_level_condition`、`sources_json`。
- 新增 translator factory：
  - `template` 模式：完全走現有邏輯。
  - `langchain` 模式：先走 LangChain；若產生失敗、驗證失敗或 row schema 不合格，依設定 fallback 到 template。
- 擴充 validation：
  - 沿用 `validate_read_only_cypher()`。
  - 新增 RETURN alias validator，檢查必要欄位是否以正確 alias 回傳。
  - 新增 row validator，查詢後確認 rows 至少符合 `NutritionCalculator` 的必要欄位契約。
- `/ask` 流程維持相容：
  - 有 `dish_names`：直接使用呼叫端提供的料理名稱。
  - 沒有 `dish_names`：保留現有 `extract_dish_candidates()` fallback。
  - 有 `question_type`：採用呼叫端判斷。
  - 沒有 `question_type`：保留現有 `infer_question_type()` fallback。
- `/dish-nutrition` 同樣透過 translator factory，避免單一料理營養 API 與 `/ask` 查詢邏輯分裂。

## LangChain Prompt Policy

- `dish_match_results` 是查詢目標的唯一來源。
- `matched_dish_name` 存在時，用它查 `(:Dish {name})`。
- `retrieval_strategy=fooditem_fallback` 時，用 `matched_food_id` 查 `(:FoodItem {food_id})`。
- `retrieval_strategy=ingredient_fallback` 時，只允許用 `input_name` 與 `Ingredient.name` 做受限模糊查詢。
- 慢性病只從 `health_condition.chronic_diseases` 取得，查 `Disease -> HAS_DIET_RULE -> Nutrition`。
- 所有查詢必須 read-only、必須有 `LIMIT`、不得使用 `CALL/APOC/CREATE/MERGE/SET/DELETE/LOAD CSV`。
- LangChain 不負責營養加總、不負責熱量公式、不負責回答建議，這些仍由既有後處理負責。

## Test Plan

- Unit tests：
  - `template` mode 產出的 Cypher 與現有行為相容。
  - `langchain` mode mock LLM 輸出合法 Cypher 時可通過 guard 與 RETURN alias validation。
  - LangChain 輸出多語句、寫入語句、缺 `LIMIT`、缺必要 RETURN alias 時會被拒絕。
  - LangChain 失敗時依 `NUTRITION_AGENT_CYPHER_FALLBACK=template` 回到 template。
- Integration tests：
  - `/ask` single dish：有 `dish_names/question_type`，回傳 `dish_nutrition` 與 `dish_advice`。
  - `/ask` dish comparison：兩道料理皆保留在 response 中，即使其中一道查不到資料。
  - `/dish-nutrition`：單一道料理仍能不呼叫 AnswerGenerator，只回營養摘要。
  - 無 `dish_names` 舊 payload：仍可走相容 fallback，不破壞既有呼叫端。
- Manual validation：
  - 比較同一組 request 在 `template` 與 `langchain` mode 的 generated Cypher、row count、final response。
  - 測試問題類型：低鈉、低糖、高蛋白、糖尿病適合度、兩道料理比較。

## Assumptions

- 先不把 `dish_names`、`question_type` 改成 API 必填，避免破壞既有呼叫端。
- `should_handle` 不加入 nutritionist API；呼叫端判斷不處理時直接不要呼叫。
- LangChain 只做 Cypher generation，不使用 `GraphCypherQAChain` 直接查詢或回答，因為現有系統需要固定 row schema 給 `NutritionCalculator`。
- 第一版預設 `NUTRITION_AGENT_CYPHER_MODE=template`；開發與展示時再切到 `langchain` 驗證效果。
