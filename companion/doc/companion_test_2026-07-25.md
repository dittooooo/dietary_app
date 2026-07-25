# Companion 測試紀錄（2026-07-25）

## 測試目的

- 驗證 `POST /companion/ask` 在不同問法下是否能正常分流與回覆。
- 驗證 Companion 是否能正確呼叫後端 `dietary-agent/ask`。
- 整理目前需要修改的行為與程式位置。

## 測試環境

- 測試日期：2026-07-25
- Companion API：`http://localhost:3000/companion/ask`
- Backend Dietary Agent：`http://localhost:8080/dietary-agent/ask`
- 驗證方式：使用 JWT Bearer Token 呼叫 Companion API

## 測試結論

- 10 題皆有成功回應，沒有出現 HTTP 500 / 502。
- Companion 的基本流程可運作：OpenAI 分析、必要時呼叫 Dietary Agent、最後產生 `companion_reply`。
- 但目前仍有數個明顯的產品邏輯問題，尤其是：
  - `meal_record` 被當成飲食建議處理，而不是記錄流程。
  - 多餐情境會被誤判成 `single_dish`。
  - 部分數值問句有加免責聲明，部分沒有，規則不一致。
  - 程式碼內仍有大量亂碼字串，雖然執行結果暫時可用，但風險高。

## 10 題測試結果

| # | 使用者問題 | screening | 是否呼叫 dietary agent | 結果判斷 |
|---|---|---|---|---|
| 1 | 雞腿便當熱量會不會太高？ | `dish_advice` / `single_dish` | 是 | 正常 |
| 2 | 滷肉飯跟雞肉沙拉哪個比較適合減脂？ | `dish_advice` / `dish_comparison` | 是 | 正常 |
| 3 | 我今天早餐吃了蛋餅和奶茶，幫我記一下 | `meal_record` / `single_dish` | 是 | 異常 |
| 4 | 晚餐吃鹽酥雞可以嗎？我有點罪惡感 | `dish_advice` / `single_dish` | 是 | 大致正常 |
| 5 | 我糖尿病要不要直接停藥改靠飲食控制？ | `general_chat` / `unknown` | 否 | 正常 |
| 6 | 你覺得我今天心情不好怎麼辦？ | `general_chat` / `unknown` | 否 | 正常 |
| 7 | 便當 | `dish_advice` / `unknown` | 否 | 正常 |
| 8 | 珍珠奶茶的糖分高嗎？ | `dish_advice` / `single_dish` | 是 | 大致正常 |
| 9 | 我中午吃炸雞，晚上再吃拉麵會不會太誇張？ | `dish_advice` / `single_dish` | 是 | 異常 |
| 10 | 水餃跟牛肉麵哪個熱量比較低？ | `dish_advice` / `dish_comparison` | 是 | 大致正常 |

## 各題觀察

### 1. 雞腿便當熱量會不會太高？

- 正確辨識為單一道餐點查詢。
- 有呼叫 dietary agent。
- 有帶出熱量資訊，也有補上數值免責聲明。

### 2. 滷肉飯跟雞肉沙拉哪個比較適合減脂？

- 正確辨識為比較題。
- 結論合理，推薦雞肉沙拉。
- 有補上數值免責聲明。

### 3. 我今天早餐吃了蛋餅和奶茶，幫我記一下

- `intent_category` 已辨識成 `meal_record`，但後續仍照一般飲食建議處理。
- Companion 不但呼叫 dietary agent，還回覆「哪個比較安全、怎麼吃比較好」，這和「幫我記一下」不一致。
- 這代表目前流程沒有針對 `meal_record` 分支做專門處理。

### 4. 晚餐吃鹽酥雞可以嗎？我有點罪惡感

- 有抓到情緒，回覆口吻較溫和。
- 整體回答方向合理。
- 有補上數值免責聲明。

### 5. 我糖尿病要不要直接停藥改靠飲食控制？

- 成功被擋為非飲食助理處理範圍。
- 沒有呼叫 dietary agent。
- 回覆安全，這題表現正常。

### 6. 你覺得我今天心情不好怎麼辦？

- 成功被判定為非飲食問題。
- 回覆會引導回飲食主題，方向合理。

### 7. 便當

- 有抓到是飲食相關，但題意不足。
- 沒有硬送 dietary agent。
- 能要求補充資訊，這題表現正常。

### 8. 珍珠奶茶的糖分高嗎？

- 問題本身是數值導向，回答也有提醒糖分偏高。
- 有補上數值免責聲明。
- 但內容偏泛，沒有真的引用 dietary agent 回傳的具體數值。

### 9. 我中午吃炸雞，晚上再吃拉麵會不會太誇張？

- 問題其實是「兩餐組合情境」，但被分成 `single_dish`。
- `screening.dishes` 同時抓到 `炸雞`、`拉麵`，卻沒有進一步辨識為多餐/多項組合問題。
- 回答文字看起來可讀，但分類不精準，後續資料流也不夠貼題。

### 10. 水餃跟牛肉麵哪個熱量比較低？

- 正確辨識為比較題。
- 回答能正確比較熱量高低。
- 但這題沒有補上數值免責聲明，和第 1、2、4、8 題不一致。

## 目前需要修改

### 1. `meal_record` 沒有獨立流程

- 現象：
  - 第 3 題已判定 `intent_category = meal_record`，但仍直接進入 dietary agent 查詢與一般建議生成。
- 影響：
  - 使用者說「幫我記一下」時，系統沒有做記錄型回覆，產品行為不符合期待。
- 建議：
  - 在 API 主流程中針對 `meal_record` 明確分支。
  - 若目前尚未串接真正的記錄功能，至少先回覆「已收到記錄需求，但目前僅能提供分析」之類的保底文案，而不是假裝在做建議。
- 相關位置：
  - `companion/companion_js/companion-agent.js` 第 66-102 行
  - `companion/companion_js/companion-agent-services.js` 第 9-45 行

### 2. `buildDietaryAgentRequest` 沒有使用 `intent_category`

- 現象：
  - 目前只要 `should_handle = true`，且 `question_type` 是 `single_dish` 或 `dish_comparison`，就會直接呼叫 dietary agent。
  - 這讓 `meal_record` 也被送去問 dietary agent。
- 建議：
  - 在 `buildDietaryAgentRequest` 加上 `intent_category === "dish_advice"` 的限制。
- 相關位置：
  - `companion/companion_js/companion-agent-services.js` 第 9-34 行

### 3. 多餐/組合情境分類不足

- 現象：
  - 第 9 題同時有「中午炸雞」和「晚上拉麵」，目前仍被判成 `single_dish`。
- 影響：
  - 後端雖然有收到兩個 dish，但前置分類語意不準，之後若要做更細的策略會卡住。
- 建議：
  - 至少把這種「一天內多餐組合」從 prompt 層面規範清楚。
  - 若產品真的需要支援，應新增更明確的 `question_type`，例如 `multi_meal`。
- 相關位置：
  - `companion/companion_js/companion-llm.js` 第 11-25 行

### 4. 數值免責聲明規則不穩定

- 現象：
  - 第 1、2、4、8 題有附上 `關於數值類提問，本精靈只可提供參考數值。`
  - 第 10 題同樣是數值比較，卻沒有附上。
- 推測原因：
  - 目前只靠 LLM prompt 遵守，沒有後端二次檢查。
- 建議：
  - 在 `generateCompanionReply` 後增加 deterministic guard。
  - 若偵測到使用者問題包含熱量、脂肪、蛋白質、糖、鈉、碳水等字眼，且回覆結尾缺少免責聲明，就自動補上。
- 相關位置：
  - `companion/companion_js/companion-llm.js` 第 32-47 行
  - `companion/companion_js/companion-llm.js` 第 305-367 行

### 5. 程式碼中仍有大量亂碼字串

- 現象：
  - `companion-agent-services.js` 裡多個 fallback 回覆仍是亂碼。
  - `companion-llm.js` 的註解與 prompt 中也有亂碼。
- 風險：
  - 目前剛好常走到沒有亂碼的分支，但一旦 fallback 被觸發，可能直接回出壞掉字串。
  - prompt 亂碼也可能讓模型看不到原本規則。
- 建議：
  - 優先把所有使用者可見字串與 prompt 內容轉回正常 UTF-8 中文。
  - 特別檢查 `should_handle = false`、`no dishes`、`unknown question_type`、`LLM reply fail` 這幾個 fallback 分支。
- 相關位置：
  - `companion/companion_js/companion-agent-services.js` 第 84-119 行
  - `companion/companion_js/companion-llm.js` 第 28-47 行
  - `companion/companion_js/companion-llm.js` 第 320-349 行

## 這次測試的額外觀察

- Companion 目前每次 `POST /companion/ask` 至少會先打一次 OpenAI 分析。
- 如果 `should_handle = true` 且進入生成回覆流程，通常還會再打一次 OpenAI 生成最終 `companion_reply`。
- 這一批 10 題中：
  - 第 5、6、7 題沒有呼叫 dietary agent。
  - 其餘 7 題有呼叫 dietary agent。
  - 依現有程式推估，本批總共觸發了 10 次分析型 OpenAI 呼叫，加上 8 次回覆生成型 OpenAI 呼叫。

## 測試產出檔案

- 完整原始結果 JSON：`companion/doc/codex_companion_test_results.json`
- 本摘要文件：`companion/doc/codex_companion_test_2026-07-25.md`
