```
cd C:\_AlwaysUndone\dietary_app\graphRag\workspace
python -m pip install -r src\kg_builder\requirements.txt
python -m uvicorn src.kg_builder.app:app --host 0.0.0.0 --port 8000
```

如果成功，終端會停在 Uvicorn 執行畫面。另開一個 PowerShell 測試：

```
Invoke-RestMethod -Uri "http://localhost:8000/docs"
```

## append_recipe_mapping.py

之後你要再匯入同一份或新版 mapping，可以跑：

```
$env:NEO4J_URI='bolt://localhost:7687'
py .\graphRag\workspace\src\kg_builder\append_recipe_mapping.py
```

# kg_builder README

這個資料夾是飲食知識圖譜和 GraphRAG 問答的核心程式區。它主要做兩件事：

1. 把食譜、食材、食品營養資料、疾病飲食規則整理成 Neo4j 知識圖譜。
2. 讓使用者用自然語言提問，由系統轉成 Cypher 查圖譜，再根據查到的結果回答。

白話來說，這裡是在把「一道菜有哪些食材」、「食材對應到哪個食品資料庫項目」、「食品含有哪些營養素」、「疾病對哪些營養素有建議或限制」串成一張圖。之後問答系統就能沿著這張圖查證據，而不是只靠模型自由回答。

## 目前主要流程

整體流程可以想成五段：

```text
食譜資料
  -> Dish 菜色
  -> Ingredient 食材
  -> FoodItem 食品資料庫項目
  -> Nutrition 營養成分
  -> Disease 疾病飲食規則
  -> GraphRAG 問答
```

實際查詢時，最常走的路徑是：

```cypher
(Dish)-[:CONTAINS]->(Ingredient)
(Ingredient)-[:MAPS_TO]->(FoodItem)
(FoodItem)-[:HAS_NUTRITION]->(Nutrition)
(Disease)-[:HAS_DIET_RULE]->(Nutrition)
```

也就是說，`Ingredient` 本身不直接連到 `Nutrition`。食材營養必須先透過 `MAPS_TO` 找到食品資料庫項目，再從 `FoodItem` 的每 100g 營養資料推算。


## 檔案總覽

### app.py

FastAPI 入口。

它把 `QueryEngine` 包成 HTTP API，目前有三個端點：

- `GET /health`
  - 檢查服務是否正常。
- `POST /ask`
  - 輸入自然語言問題。
  - 回傳產生的 Cypher、查詢結果和文字回答。
- `POST /recommend`
  - 輸入 `dish_name` 和 `disease_name`。
  - 內部組成問題後丟給 `QueryEngine`，回傳飲食建議。

環境變數預設值：

```text
NEO4J_URI=bolt://localhost:7687
NEO4J_USER=neo4j
NEO4J_PASSWORD=password
```

### query_engine.py

GraphRAG 問答核心。

它負責：

- 讀取 `.env` 裡的 Neo4j / OpenAI 設定。
- 把使用者問題轉成 Cypher。
- 檢查 Cypher 是否安全。
- 執行 Neo4j 查詢。
- 把查詢結果交給模型整理成回答。

重要類別是 `QueryEngine`。

主要方法：

- `ask(question)`
  - GraphRAG 問答主流程。
  - 先判斷問題裡是否同時提到某道菜和某個疾病。
  - 如果有，就使用穩定的內建查詢模板。
  - 如果沒有，就呼叫模型產生 Cypher。
  - 執行查詢後，再用查詢結果生成回答。
- `generate_dish_disease_cypher(question)`
  - 專門處理「某道菜對某疾病適不適合」這類問題。
  - 這種問題不讓模型自由發揮，直接用固定查詢邏輯。
- `generate_cypher(question)`
  - 讓模型依照 `GRAPH_SCHEMA` 和規則產生 Cypher。
- `validate_read_only_cypher(cypher)`
  - 防止模型產生寫入或破壞資料庫的 Cypher。
- `repair_cypher(question, cypher, error)`
  - 如果 Neo4j 回報語法錯誤，會要求模型修正一次。
- `generate_answer(question, cypher, rows)`
  - 根據查到的 graph rows 產生最後回答。

### knowledge_agent_importer.py

建立知識圖譜的主程式。

它會把資料匯入 Neo4j，建立節點與關係。這份檔案是目前最重要的 KG builder。

它使用的資料來源不在 `kg_builder/data`，而是在 workspace 層級：

```text
graphRag/workspace/data/recipe_and_nutrition/food_and_nutrition_mapping.json
graphRag/workspace/data/recipe_and_nutrition/nutrition_data_categorized.json
graphRag/workspace/data/recipe_and_nutrition/nutrition_components.json
graphRag/workspace/data/disease_and_biomarker/chronic_disease_rules_v2.json
```

主要工作：

1. 建立 Neo4j constraint 和 index。
2. 匯入 `Nutrition` 節點。
3. 匯入 `FoodItem` 節點和每 100g 營養資料。
4. 匯入 `Dish`、`Ingredient`、食材對應食品資料庫的關係。
5. 依照食材份量計算每份食材的營養量。
6. 匯入 `Disease` 節點和疾病飲食規則。

常用指令：

```bash
python knowledge_agent_importer.py --clear --mapping-path ..\\data\\recipe_and_nutrition\\food_and_nutrition_mapping.json
```

測試少量食譜：

```bash
python knowledge_agent_importer.py --clear --limit-recipes 10
```

預設會保留所有 Nutrition 與 FoodItem，並跳過沒有對應 FoodItem 的食材列；如果希望遇到缺失 mapping 時直接中止，可以加上：

```bash
python knowledge_agent_importer.py --strict-mapping
```

之後只要匯入另一份 recipe mapping JSON，或一個包含多個 JSON mapping 的資料夾，可以使用同一套一對一映射邏輯：

```bash
python append_recipe_mapping.py --mapping-path path\\to\\recipes.json
python append_recipe_mapping.py --mapping-path path\\to\\recipes_json
```

資料夾模式會依檔名排序讀取其中所有 `.json` 檔，並合併成同一批食譜匯入；重複執行不會重複建立 Dish、Ingredient 或關係。匯入前可加 `--dry-run` 檢查筆數、缺少的 FoodItem 與重複 recipe ID。

Recipe importer 會依 `Ingredient.matched_food_id` 先刪除舊的 `MAPS_TO`，再建立唯一的 `Ingredient -> FoodItem` 映射。對同一原始名稱但不同整合編號的資料，會使用 `原始名稱 [整合編號]` 作為內部 Ingredient key，避免一個 Ingredient 對到多個 FoodItem。

### normalizer.py

食材名稱正規化工具。

它定義 `IngredientNormalizer`，用途是把不同寫法的食材名稱統一成同一個名稱。例如某些別名、俗名、簡寫可以先轉成標準名稱，再進入比對流程。

目前這個檔案比較像輔助工具或早期流程留下的模組，主要 importer 目前沒有直接大量使用它。

### requirements.txt

Python 套件需求。

主要依賴：

- `fastapi`
- `uvicorn`
- `neo4j`
- `openai`
- `pydantic`
- `python-dotenv`

### query_examples_V6_1.cypher

Neo4j 查詢範例集。

裡面放了很多用來人工檢查圖譜的 Cypher，例如：

- 查有哪些 Dish / Ingredient / FoodItem / Nutrient / Disease。
- 查某道菜有哪些食材。
- 查食材對應到哪些食品資料庫項目。
- 查食材或食品有哪些營養素。
- 查營養素、疾病、生物指標之間的關係。

注意：這個檔案看起來是舊版範例，裡面常使用：

```text
Nutrient
MAP_TO
HAS_NUTRIENT
```

但目前 `knowledge_agent_importer.py` 和 `query_engine.py` 使用的是：

```text
Nutrition
MAPS_TO
HAS_NUTRITION
```

所以它適合當歷史參考或查詢思路參考，不能保證每一段都能直接套用在最新版圖譜。

### note.txt

開發備忘。

內容包含 GraphRAG CLI、Docker、workspace 路徑、資料路徑、舊版 builder 執行方式等筆記。這不是正式程式流程的一部分，比較像開發時留下的提醒。

### cypher/schema.cypher

早期的 Neo4j schema 草稿。

它建立了一些 constraint 和 index，例如：

- `Dish.name`
- `Ingredient.name`
- `FoodItem.name`
- `Nutrient.name`
- `Biomarker.name`
- `Disease.name`

注意：這份 schema 使用 `Nutrient`，但目前主程式使用 `Nutrition`。最新版 schema 實際上是在 `knowledge_agent_importer.py` 的 `create_schema()` 裡建立。

### cypher/seed.cypher

早期手寫 seed data 範例。

裡面多數內容都被註解起來，用來示範如何建立：

- Source
- Disease
- Biomarker
- Nutrient
- Dish
- Ingredient
- FoodItem
- 營養素關係

這份檔案目前比較像設計草稿，不是正式匯入流程。

### data/

這個資料夾放的是 kg_builder 早期或範例用資料。

目前看到的檔案有：

- `recipes.json`
  - 食譜資料。
  - 每筆食譜包含 `recipe_id`、`name`、`servings`、`ingredients`。
  - 每個 ingredient 會有原始名稱、標準名稱、份量、單位、備註。
- `nutrition_data.json`
  - 食品營養資料。
  - 依食品分類分組，例如乳品類、肉類、蔬菜類、魚貝類等。
  - 每個食品項目包含食品編號、樣品名稱、分類、俗名、每 100g 的營養數值。
- `disease_rules.json`
  - 舊版疾病規則。
  - 格式比較簡單，像是某疾病對鈉、糖、脂肪、蛋白質的 upper bound 或 ratio rule。
- `biomarker_nutrient_links.json`
  - 生物指標和營養素的關聯。
  - 例如血糖和糖、血壓和鈉之間的關係。

注意：目前新版 importer 使用的是 `graphRag/workspace/data/...` 底下的資料，不是這裡的 `data/`。這裡比較像舊版或測試資料。

### neo4j_query_table_data_csv/

Neo4j Browser 匯出的查詢表格資料。

這些 CSV 通常是人工查詢結果或除錯紀錄，不是程式主流程會讀取的輸入檔。

## 目前知識圖譜的節點設計

最新版程式主要使用以下節點。

### Dish

代表一道菜。

重要屬性：

- `recipe_id`
- `name`
- `servings`
- `source`
- `updated_by_version`

來源：食譜 mapping 資料。

### Ingredient

代表食譜中的食材名稱。

重要屬性：

- `name`
- `matched_food_id`
- `matched_food_name`
- `mapping_method`
- `updated_by_version`

來源：食譜解析和食品資料庫 mapping。

### FoodItem

代表食品營養資料庫中的食品項目。

重要屬性：

- `food_id`
- `name`
- `category`
- `description`
- `aliases`
- `source`

來源：`nutrition_data_categorized.json`。

### Nutrition

代表營養成分欄位。

重要屬性：

- `nutrition_id`
- `name`
- `name_zh`
- `name_en`
- `unit`
- `category`
- `source_column`

來源：`nutrition_components.json`。

### Disease

代表慢性疾病。

重要屬性：

- `disease_id`
- `name`
- `name_en`
- `diet_pattern`
- `risk_notes`

來源：`chronic_disease_rules_v2.json`。

### Biomarker

`query_engine.py` 的 schema 裡有保留 Biomarker 設計，例如血糖、血壓、血脂等。但目前正式 importer 的主流程沒有匯入 biomarker 關係，GraphRAG 問答主要依賴疾病飲食規則。

## 目前知識圖譜的關係設計

### Dish - CONTAINS -> Ingredient

表示一道菜包含哪些食材。

重要屬性：

- `amount_raw`
- `amount`
- `unit`
- `amount_note`
- `amount_per_serving`
- `matched_food_id`
- `matched_food_name`
- `mapping_method`

### Ingredient - MAPS_TO -> FoodItem

表示食譜中的食材對應到食品資料庫哪一個項目。

例如食譜寫「牛奶」，可能對應到食品資料庫的「高脂鮮乳」或其他乳品項目。

### FoodItem - HAS_NUTRITION -> Nutrition

表示食品資料庫項目每 100g 含有哪些營養素。

重要屬性：

- `amount_per_100g`
- `amount`
- `unit`
- `source_column`

### 每份營養量如何推算

目前圖譜不再建立 `Ingredient - HAS_NUTRITION -> Nutrition`。

某個食材在這道菜裡的營養量，會在查詢時從 `FoodItem - HAS_NUTRITION -> Nutrition` 的每 100g 營養值和 `Dish - CONTAINS -> Ingredient` 的食材份量推算：

```text
amount_per_serving = amount_per_100g * grams_per_serving / 100
```

如果食材沒有成功對應到 `FoodItem`，或沒有可用的份量，就可能沒有完整的每份營養量。

### Disease - HAS_DIET_RULE -> Nutrition

表示某疾病對某營養素有飲食規則。

重要屬性：

- `relation`
  - 例如 `recommend`、`limit`、`prohibit`。
- `direction`
  - 例如 increase、decrease、avoid、replace。
- `target_note`
- `note`
- `food_level_condition`
- `food_level`
- `food_level_note`
- `criteria_json`
- `food_level_rule_json`
- `example_foods_json`
- `reason`
- `sources_json`

疾病規則目前不是建立成獨立 Rule 節點，而是存在 `Disease -> Nutrition` 的 relationship 上。

## 建立知識圖譜的規則

目前 `knowledge_agent_importer.py` 的規則可以用白話整理成下面幾點。

### 1. 用 ID 保持主要節點唯一

Neo4j schema 會建立這些唯一限制：

- `Dish.recipe_id`
- `Ingredient.name`
- `FoodItem.food_id`
- `Nutrition.nutrition_id`
- `Disease.disease_id`

這樣重複匯入時會用 `MERGE` 更新同一個節點，而不是一直新增重複資料。

### 2. Nutrition 一律從 nutrition_components 建立

每個營養成分都要有：

- `nutrition_id`
- `name_zh`
- `name_en`
- `unit`
- `category`
- `source_column`

其中 `source_column` 很重要，因為它會拿來對應食品資料裡的欄位名稱，例如：

```text
鈉(mg)
粗蛋白(g)
脂肪酸M總量(mg)
```

如果某個營養成分的中文名稱重複，程式會用 `source_column` 當顯示名稱，避免 Neo4j 裡看起來像是同一個東西。

### 3. 食品營養值只匯入可轉成數字的欄位

`safe_float()` 會把數值轉成 float。

如果欄位是空字串、null、或不能轉成數字，就略過。

這代表 KG 裡的 `HAS_NUTRITION` 關係只會放真的有數值的營養資料。

### 4. 食材要先對應到 FoodItem，才能推算營養量

食譜裡的食材本身不一定等於食品資料庫項目，所以中間需要 mapping。

流程是：

```text
Ingredient 原始食材
  -> matched_food_id
  -> FoodItem
  -> FoodItem 的每 100g 營養資料
  -> 依照食材克數換算每份營養量
```

如果食材沒有 `matched_food_id`，就不會建立 `MAPS_TO`，也比較難推算營養。

### 5. 疾病規則目前只匯入有 nutrient_id 的規則

`import_disease_rules()` 會讀取：

```text
disease.disease_nutrient_relations
```

每筆 relation 必須有：

```text
nutrient_id
```

才會建立：

```cypher
(Disease)-[:HAS_DIET_RULE]->(Nutrition)
```

如果某些規則是概念型結構，例如：

```json
{
  "concept_name_zh": "不飽和脂肪",
  "mapped_nutrients": [...]
}
```

目前 importer 不會直接匯入這種 concept relation，除非先把它展開成有 `nutrient_id` 的 relation，或修改 importer 讓它支援 `mapped_nutrients`。

這點很重要，因為新版慢病規則如果開始使用概念型營養規則，KG builder 也要同步升級。

### 6. 疾病規則的詳細條件用 JSON 字串保存在 relationship 上

像 `target_rule.criteria`、`food_level_rule`、`example_foods`、`sources` 這些比較複雜的資料，不會拆成很多節點，而是用 JSON 字串存在 `HAS_DIET_RULE` 的屬性裡。

優點是匯入簡單，保留原始規則資訊。

缺點是 Cypher 不容易直接對 criteria 裡面的條件做精細查詢。

## GraphRAG 問答規則

GraphRAG 問答在 `query_engine.py` 裡，規則分成查詢生成、查詢安全、回答生成三層。

### 1. 優先使用穩定模板查詢

如果使用者問題同時提到一道菜和一個疾病，系統會先去 Neo4j 裡找：

```cypher
MATCH (n:Dish)
WHERE $question CONTAINS n.name
RETURN n.name
```

和：

```cypher
MATCH (n:Disease)
WHERE $question CONTAINS n.name
RETURN n.name
```

如果兩者都找到，就不讓模型自由產生查詢，而是使用固定的 dish-disease 查詢。

白話來說：

> 如果問題是「義式千層麵適合高血壓嗎」，系統會直接查這道菜的食材營養，並對照高血壓規則。

這樣比完全交給 LLM 產生 Cypher 穩定。

### 2. 沒有命中模板時才讓模型產生 Cypher

如果問題沒有同時命中 Dish 和 Disease，系統才會把 `GRAPH_SCHEMA` 和問題丟給模型，要求模型輸出：

```json
{
  "cypher": "...",
  "rationale": "..."
}
```

模型只能根據 schema 裡列出的節點、關係和屬性產生查詢。

### 3. Cypher 必須是唯讀

系統明確禁止模型產生會修改資料庫的語句。

允許的語法大致只有：

```text
MATCH
OPTIONAL MATCH
WITH
WHERE
RETURN
ORDER BY
LIMIT
```

禁止：

```text
CREATE
MERGE
SET
DELETE
DETACH
REMOVE
DROP
LOAD CSV
CALL
APOC
ALTER
GRANT
DENY
REVOKE
```

另外還要求：

- 查詢不能是空的。
- 不能有多個 statement。
- 必須從 `MATCH` 或 `OPTIONAL MATCH` 開始。
- 必須有 `RETURN`。

### 4. HAS_DIET_RULE 一定要綁 relationship 變數

prompt 裡特別要求：

```cypher
(dis:Disease)-[rule:HAS_DIET_RULE]->(n:Nutrition)
```

不能寫成：

```cypher
dis HAS_DIET_RULE AS diet_rules
```

原因是 `HAS_DIET_RULE` 的重點資訊都在 relationship 屬性上，例如：

```text
rule.relation
rule.direction
rule.note
rule.reason
rule.food_level_condition
```

如果沒有綁 `rule` 這個變數，就拿不到規則內容。

### 5. 查詢結果會轉成乾淨 JSON

Neo4j 回傳的 Node、Relationship、Path 物件不能直接給模型，所以 `_to_plain_value()` 會把它們轉成一般 JSON：

- Node -> labels + properties
- Relationship -> type + properties
- Path -> nodes + relationships
- list / dict -> 遞迴轉換

這樣回答模型看到的是乾淨資料，而不是 Neo4j driver 的 Python 物件。

### 6. 回答必須根據 graph rows

`generate_answer()` 會把下面資料交給模型：

```json
{
  "question": "...",
  "cypher": "...",
  "row_count": 10,
  "rows": [...]
}
```

也就是說，最後回答應該根據查回來的圖譜資料，而不是憑空建議。

## API 使用方式

安裝依賴：

```bash
pip install -r requirements.txt
```

啟動 API：

```bash
uvicorn app:app --reload
```

如果從專案根目錄啟動，可能需要指定模組路徑或先切到資料夾：

```bash
cd graphRag/workspace/src/kg_builder
uvicorn app:app --reload
```

問答：

```bash
curl -X POST http://localhost:8000/ask ^
  -H "Content-Type: application/json" ^
  -d "{\"question\":\"義式千層麵適合高血壓嗎？\"}"
```

推薦：

```bash
curl -X POST http://localhost:8000/recommend ^
  -H "Content-Type: application/json" ^
  -d "{\"dish_name\":\"義式千層麵\",\"disease_name\":\"高血壓\"}"
```

## 開發時要注意的地方

### 1. 現在的 active schema 是 Nutrition，不是 Nutrient

目前主程式使用：

```text
Nutrition
HAS_NUTRITION
MAPS_TO
```

部分舊檔案使用：

```text
Nutrient
HAS_NUTRIENT
MAP_TO
```

如果查不到資料，先確認自己用的是新版還是舊版命名。

### 2. disease rule 的 concept mapping 還需要 importer 支援

如果疾病規則檔裡出現像「不飽和脂肪」這種 concept relation，並且它沒有最外層 `nutrient_id`，目前 importer 會跳過。

要讓 KG 真的吃到這種結構，有兩種做法：

1. 匯入前先把 concept 展開成多筆 `nutrient_id` 規則。
2. 修改 `import_disease_rules()`，讓它支援 `mapped_nutrients`。

### 3. relationship 上存 JSON 字串，查詢彈性有限

目前 criteria 存成：

```text
criteria_json
food_level_rule_json
example_foods_json
sources_json
```

這保留資訊很方便，但如果未來要做精準條件查詢，例如「找 daily_limit < 2000 mg/day 的所有疾病規則」，可能需要把 criteria 拆成節點或 relationship。

### 4. 問答安全性靠 validate_read_only_cypher

任何 LLM 產生的 Cypher 都會先經過安全檢查。這是避免模型不小心修改資料庫的重要防線。

如果未來增加查詢語法，也要同步更新 `validate_read_only_cypher()`。

## 一句話總結

`kg_builder` 是把飲食資料整理成 Neo4j 知識圖譜，並提供 GraphRAG 問答能力的資料工程與查詢服務模組。它的核心邏輯是：先把菜、食材、食品營養、疾病飲食規則串起來，再讓問答系統沿著這些關係找證據，最後用查到的資料產生飲食建議。
