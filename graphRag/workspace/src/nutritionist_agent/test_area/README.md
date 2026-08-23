# Dish matching test area

這個資料夾只用來測試目前的料理名稱匹配，不會修改 Neo4j，也不會修改 Nutritionist Agent 核心程式。

## 1. 建立標準答案

編輯 `dish_match_gold.csv`：

- `input_name`：真實使用者輸入的料理名稱
- `expected_label`：`exact`、`alias`、`same_dish_variant`、`ambiguous`、`no_match` 或 `unknown_restaurant_dish`
- `expected_dish_name`：人工確認的標準 Dish 名稱
- `acceptable_dish_names`：可接受的標準名稱，多個名稱用 `|` 分隔
- `review_status`：人工確認後才改成 `approved`

不要把無法確認食譜的餐廳特殊菜名硬配到其他料理，請使用 `ambiguous` 或 `unknown_restaurant_dish`。

## 2. 檢查對照表格式

在 `graphRag\workspace` 執行：

```powershell
.\.venv\Scripts\python.exe src\nutritionist_agent\test_area\run_dish_match_cases.py --validate-only
```

## 3. 執行目前的 DishMatcher

Neo4j 必須先啟動，且根目錄 `.env` 必須設定正確的 `NEO4J_URI`、`NEO4J_USER` 與 `NEO4J_PASSWORD`。

```powershell
.\.venv\Scripts\python.exe src\nutritionist_agent\test_area\run_dish_match_cases.py
```

結果會寫入：

```text
test_area\output\dish_match_results.jsonl
```

這個腳本只執行讀取查詢，不會寫入 Neo4j。

## 4. 產生評估報告

只有 `review_status=approved` 的案例會納入計算：

```powershell
.\.venv\Scripts\python.exe src\nutritionist_agent\test_area\evaluate_dish_match.py
```

報告會寫入：

```text
test_area\output\dish_match_report.json
```

報告會區分正確料理匹配、把料理誤判成 FoodItem、ingredient fallback、錯誤硬匹配，以及真正的 no-match。
