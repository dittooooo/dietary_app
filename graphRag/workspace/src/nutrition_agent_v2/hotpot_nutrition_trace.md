# 火鍋營養結果追蹤說明

建立日期：2026-06-06

這份文件用來追蹤這個問題：

```json
{
  "question": "你覺得我吃火鍋要配奶茶還是紅茶",
  "question_type": "dish_comparison",
  "health_condition": {
    "chronic_diseases": ["糖尿病"]
  }
}
```

API 回傳中，火鍋營養摘要顯示：

```json
{
  "dish_name": "火鍋",
  "matched_name": "泡菜海鮮豬肉火鍋",
  "matched_type": "dish",
  "retrieval_strategy": "dish_match",
  "nutrients": [
    {"name": "熱量", "amount_per_serving": 227.76, "unit": "kcal"},
    {"name": "蛋白質", "amount_per_serving": 19.82, "unit": "g"},
    {"name": "脂肪", "amount_per_serving": 5.57, "unit": "g"},
    {"name": "碳水化合物", "amount_per_serving": 24.59, "unit": "g"},
    {"name": "糖", "amount_per_serving": 15.77, "unit": "g"},
    {"name": "鈉", "amount_per_serving": 590.02, "unit": "mg"},
    {"name": "膳食纖維", "amount_per_serving": 2.94, "unit": "g"},
    {"name": "飽和脂肪", "amount_per_serving": 1.07, "unit": "g"}
  ]
}
```

結論先講：這個火鍋熱量偏低，不是因為火鍋本身資料真的只有 227 kcal，而是目前多料理比較查詢會一次查 `火鍋`、`奶茶`、`紅茶`，Neo4j 查詢最後有全域 `LIMIT 1000`，導致火鍋只拿到部分食材的 nutrition rows，後面的火鍋食材沒有被聚合進來。

## 1. 候選料理抽取

目前 `text_to_cypher.py` 會先把使用者問題拆成候選項目。

這句：

```text
你覺得我吃火鍋要配奶茶還是紅茶
```

會抽出：

```json
["火鍋", "奶茶", "紅茶"]
```

## 2. Neo4j Match 結果

`dish_matcher.py` 會把候選項目拿去 Neo4j 的 `(:Dish)` 做名稱比對。

實際 match 結果：

```json
[
  {
    "input_name": "奶茶",
    "matched_dish_name": "阿薩姆鮮乳奶茶",
    "match_score": 82,
    "match_reason": "name similarity",
    "retrieval_strategy": "dish_match"
  },
  {
    "input_name": "火鍋",
    "matched_dish_name": "泡菜海鮮豬肉火鍋",
    "match_score": 82,
    "match_reason": "name similarity",
    "retrieval_strategy": "dish_match"
  },
  {
    "input_name": "紅茶",
    "matched_dish_name": "醇濃紅茶鮮豆奶",
    "match_score": 82,
    "match_reason": "name similarity",
    "retrieval_strategy": "dish_match"
  }
]
```

所以火鍋不是直接查「火鍋」這個資料，而是用圖譜中最相近的 `泡菜海鮮豬肉火鍋` 來估算。

## 3. 送進 Neo4j 的查詢邏輯

查詢由 `text_to_cypher.py` 的 `build_graph_retrieval_cypher()` 產生。

核心邏輯是：

```cypher
UNWIND [
  {input_name: "奶茶", matched_dish_name: "阿薩姆鮮乳奶茶", retrieval_strategy: "dish_match"},
  {input_name: "火鍋", matched_dish_name: "泡菜海鮮豬肉火鍋", retrieval_strategy: "dish_match"},
  {input_name: "紅茶", matched_dish_name: "醇濃紅茶鮮豆奶", retrieval_strategy: "dish_match"}
] AS target

OPTIONAL MATCH (d:Dish)-[c:CONTAINS]->(dish_ing:Ingredient)
WHERE target.retrieval_strategy = "dish_match"
  AND d.name = target.matched_dish_name

WITH target, d, c, dish_ing AS ing
WHERE ing IS NOT NULL

MATCH (ing)-[hn:HAS_NUTRITION]->(n:Nutrition)

OPTIONAL MATCH (dis:Disease)-[rule:HAS_DIET_RULE]->(n)
WHERE dis.name IN ["糖尿病"]

OPTIONAL MATCH (f:FoodItem {food_id: hn.source_food_id})
WHERE c IS NULL OR c.matched_food_id IS NULL OR hn.source_food_id = c.matched_food_id

RETURN
  target.input_name AS dish_name,
  d.name AS matched_name,
  "dish" AS matched_type,
  target.retrieval_strategy AS retrieval_strategy,
  ing.name AS ingredient_name,
  coalesce(f.name, hn.source_food_name) AS food_item_name,
  n.name_zh AS nutrition_name_zh,
  hn.amount_per_serving AS amount_per_serving,
  hn.unit AS nutrition_unit

ORDER BY dish_name, retrieval_strategy, ingredient_name, nutrition_name
LIMIT 1000
```

重要的是最後這句：

```cypher
LIMIT 1000
```

這是全域 limit，不是每一道料理各 1000 筆。

## 4. 這次 Neo4j 實際回傳 rows

這次多目標查詢回來的 rows 數剛好是：

```json
{
  "row_count": 1000,
  "rows_by_dish": {
    "奶茶": 370,
    "火鍋": 630
  }
}
```

注意：`紅茶` 完全沒有進到這 1000 rows 裡。

這代表查詢已經撞到 `GRAPH_QUERY_LIMIT=1000`，資料被截斷了。

火鍋在這 630 rows 裡只包含以下食材：

```json
[
  "大蒜",
  "嫩豆腐",
  "文蛤",
  "水",
  "洋蔥",
  "烤肉醬"
]
```

但只查火鍋時，可以看到更多火鍋食材：

```json
[
  "大蒜",
  "嫩豆腐",
  "文蛤",
  "水",
  "洋蔥",
  "烤肉醬",
  "砂糖",
  "老薑",
  "花枝丸",
  "蝦仁餛飩",
  "豬肉片"
]
```

也就是多目標比較時，`砂糖`、`老薑`、`花枝丸`、`蝦仁餛飩`、`豬肉片` 這些火鍋食材沒有進到計算裡。

這就是火鍋熱量被低估的主因。

## 5. 火鍋 227.76 kcal 是怎麼算出來的

程式在 `nutrition_calculator.py` 裡做兩件事：

1. 只保留常見營養素，例如熱量、蛋白質、脂肪、碳水、糖、鈉、膳食纖維、飽和脂肪。
2. 原本 graph rows 裡的熱量會先當參考值，最後用三大營養素重新計算熱量。

這次被截斷後，火鍋聚合到的三大營養素是：

```json
{
  "protein_g": 19.819036999999998,
  "carbohydrate_g": 24.591833,
  "fat_g": 5.569032,
  "graph_calories_kcal_reference": 460.33
}
```

系統最後不用 graph 原本的 460.33 kcal，而是用公式重算：

```text
protein_g * 4 + carbohydrate_g * 4 + fat_g * 9
```

代入後：

```text
19.819036999999998 * 4
+ 24.591833 * 4
+ 5.569032 * 9
= 227.76 kcal
```

所以最後 API 顯示：

```json
{
  "name": "熱量",
  "amount_per_serving": 227.76,
  "calculation_method": "macro_calculation",
  "formula": "protein_g*4 + carbohydrate_g*4 + fat_g*9",
  "calorie_status": "calculated"
}
```

## 6. 對照：只查火鍋時的結果

只查 `火鍋` 一個目標時，雖然查詢一樣是 `LIMIT 1000`，但 1000 rows 全部都給火鍋用，所以可聚合到更多食材。

只查火鍋時的摘要：

```json
{
  "dish_name": "火鍋",
  "matched_name": "泡菜海鮮豬肉火鍋",
  "nutrients": [
    {"name": "熱量", "amount_per_serving": 1256.83, "unit": "kcal"},
    {"name": "蛋白質", "amount_per_serving": 92.09, "unit": "g"},
    {"name": "脂肪", "amount_per_serving": 73.79, "unit": "g"},
    {"name": "碳水化合物", "amount_per_serving": 56.08, "unit": "g"},
    {"name": "糖", "amount_per_serving": 22.68, "unit": "g"},
    {"name": "鈉", "amount_per_serving": 1338.73, "unit": "mg"},
    {"name": "膳食纖維", "amount_per_serving": 5.38, "unit": "g"},
    {"name": "飽和脂肪", "amount_per_serving": 3.4, "unit": "g"}
  ]
}
```

只查火鍋時的熱量重算 debug：

```json
{
  "protein_g": 92.094587,
  "carbohydrate_g": 56.080218,
  "fat_g": 73.79261199999999,
  "calories_kcal": 1256.83,
  "graph_calories_kcal_reference": 2313.46,
  "formula": "protein_g*4 + carbohydrate_g*4 + fat_g*9"
}
```

也就是：

```text
92.094587 * 4
+ 56.080218 * 4
+ 73.79261199999999 * 9
= 1256.83 kcal
```

## 7. 目前邏輯上的風險

這次調查看到幾個風險：

1. 多料理比較時，所有料理共用同一個 `LIMIT 1000`。
   - 這會讓前面的料理吃掉 row quota。
   - 後面的料理可能資料不完整，甚至完全不出現。

2. 查詢一次拿全部營養素。
   - 包含維生素、脂肪酸、胺基酸等大量資料。
   - 但最後摘要其實只需要幾個常見營養素。
   - 這讓 row 數很快爆掉。

3. 食材對應有可能一個 Ingredient 對到多個 FoodItem。
   - 例如 `洋蔥` 對到 `白洋蔥`、`洋蔥頭`、`洋蔥`、`洋蔥粉`。
   - 例如 `水` 同時出現 `純水` 和 `檸檬汁(非原汁)`。
   - 這可能會造成營養加總偏高或偏怪。

4. 熱量會被重新計算。
   - graph 原始熱量只保留在 `graph_calories_kcal_reference`。
   - API 回傳熱量以三大營養素公式重算為準。

## 8. 建議修正方向

比較合理的修正方向是：

1. Neo4j 查詢先限制營養素種類，只查摘要需要的營養素。
   - 熱量
   - 粗蛋白 / 蛋白質
   - 粗脂肪 / 脂肪
   - 總碳水化合物 / 碳水化合物
   - 糖質總量 / 糖
   - 鈉
   - 膳食纖維
   - 飽和脂肪

2. 不要讓多個料理共用一個全域 `LIMIT`。
   - 可以改成每個 target 分開查。
   - 或在 Cypher 裡做 per-target collect / limit。

3. 若 `row_count == GRAPH_QUERY_LIMIT`，應該在 debug_trace 或 response 中標示 `retrieval_truncated=true`。

4. 食材對應多個 FoodItem 時，應該只選最可信的一個，或保留 mapping score 後取最佳 match，不應直接全部加總。

## 9. 這次問題的白話版結論

你覺得 227 kcal 不像一般火鍋，這個直覺是對的。

目前 227 kcal 不是完整火鍋，而是「泡菜海鮮豬肉火鍋」被查詢截斷後，只拿到前半部分食材算出的結果。

真正接近目前資料庫中這道 `泡菜海鮮豬肉火鍋` 的估算，至少會接近只查火鍋時的 1256.83 kcal。不過這個數字也還需要注意食材 mapping 重複加總的問題。

