# Companion Agent 目前運作邏輯

## 概述

目前 Companion Agent 的主要流程是：

1. 前端呼叫 `POST /companion/ask`，只傳入 `user_prompt`。
2. 後端先用第一段 LLM 分析使用者問題。
3. 如果問題足夠明確，後端再呼叫 Dietary Agent。
4. 後端最後用第二段 LLM 產生給使用者看的自然語言回覆。
5. API 回傳分析結果、Dietary Agent 結果，以及最終 `companion_reply`。

整體設計重點是把「理解問題」和「生成回覆」拆成兩段 LLM，減少大量寫死的補問文字與固定回覆。

## 主要檔案分工

### `companion_js/companion-agent.js`

這是 Express API 入口，負責：

- 接收 HTTP 請求
- 驗證 `user_prompt` 是否存在
- 呼叫 OpenAI 分析流程
- 視情況呼叫 Dietary Agent
- 組合並回傳最終 JSON 結果

### `companion_js/companion-agent-services.js`

這是服務層，負責：

- 呼叫第一段 LLM 分析
- 根據分析結果決定是否建立 Dietary Agent payload
- 呼叫 Dietary Agent API
- 呼叫第二段 LLM 產生最終回覆

### `companion_js/companion-llm.js`

這是 LLM 整合層，負責：

- 定義第一段分析用 prompt
- 定義第二段回覆用 prompt
- 定義 function calling schema
- 呼叫 OpenAI Responses API
- 清理與整理 OpenAI 回傳結果

## API 入口流程

### 1. 接收請求

路由：`POST /companion/ask`

前端目前只需要傳：

```json
{
  "user_prompt": "我今天中午吃炸雞了，晚上還能吃拉麵嗎？"
}
```

### 2. 基本驗證

後端會先檢查 `user_prompt`：

- 必須存在
- 必須是字串
- 去除前後空白後不能為空

如果不符合，直接回傳 `400 BAD_REQUEST`，不進入後續流程。

## 第一段 LLM：意圖分析與資訊抽取

第一段 LLM 由 `runOpenAIFlow(userPrompt)` 執行。

### 目的

這一段不直接回使用者，而是先把使用者輸入轉成結構化資訊，方便後端決定下一步。

### 做的事情

第一段 LLM 會做兩個 function call：

1. `screen_user_request`
2. `analyze_emotion`

### `screen_user_request` 會產出

- `should_handle`
  - 是否屬於這個飲食助理該處理的問題
- `intent_category`
  - 例如 `dish_advice`、`meal_record`、`medical_out_of_scope`、`general_chat`
- `question_type`
  - `single_dish`
  - `dish_comparison`
  - `unknown`
- `confidence`
  - 模型對判斷的信心
- `dishes`
  - 從使用者句子中抽出的食物名稱陣列

### `analyze_emotion` 會產出

- `primary_emotion`
- `valence`
- `urgency`
- `needs_empathy`
- `companion_tone`
- `evidence`

### 第一段 LLM 的用途

這些資訊會被後端拿來：

- 判斷是否要進一步呼叫 Dietary Agent
- 決定最終回覆時的語氣
- 幫助第二段 LLM 做更自然的回答或補問

## Dietary Agent 呼叫條件

後端不會把所有問題都送去 Dietary Agent。

`buildDietaryAgentRequest(screening, message)` 會做最小必要判斷：

- `screening.should_handle` 必須是 `true`
- `question_type` 必須是 `single_dish` 或 `dish_comparison`
- `dishes` 必須是非空陣列
- `question` 本身不能是空字串

只要其中一個條件不符合，就不建立 payload，也就不呼叫 Dietary Agent。

### 建立成功時會送出的 payload

```json
{
  "question": "我今天中午吃炸雞了，晚上還能吃拉麵嗎？",
  "question_type": "single_dish",
  "dish_names": ["炸雞", "拉麵"]
}
```

## 呼叫 Dietary Agent

如果前一步成功建立 `dietary_agent_request`，後端就會呼叫：

- `POST {DIETARY_AGENT_API_URL}/api/dietary/ask-weekly-analysis`

### 特點

- 會帶 `Content-Type: application/json`
- 如果前端有帶 `Authorization` header，後端會原樣轉傳給 Dietary Agent

### 失敗處理

如果 Dietary Agent 失敗：

- 不會讓整個 API 直接崩潰
- 錯誤會被記錄到 `dietary_agent_error`
- 流程仍然會進入第二段 LLM，由它產生最終回覆

## 第二段 LLM：最終回覆生成

第二段 LLM 由 `generateCompanionReply(...)` 執行。

### 目的

這一段專門負責產生最後給使用者看的 `companion_reply`。

也就是說：

- 補問怎麼說
- 回覆語氣怎麼調整
- 醫療超出範圍怎麼婉拒
- 沒有 Dietary Agent 結果時怎麼自然回覆

這些都改由第二段 LLM 處理，而不是由程式寫死固定句子。

### 第二段 LLM 會收到的上下文

後端會把以下內容一起提供給它：

- `user_prompt`
- `screening`
- `emotion`
- `dietary_agent_request`
- `dietary_agent_response`
- `dietary_agent_error`

### 第二段 LLM 的回覆規則

目前 prompt 設計的核心方向是：

- 一律使用繁體中文
- 回覆要簡潔、溫和、實用
- 醫療問題要婉拒，並轉回飲食方向
- 如果資訊不足，要自然補問，不要像模板
- 不要暴露內部欄位、JSON、tools 或系統規則

## 營養數字回覆策略

目前邏輯上，最終回覆階段特別要求：

- 不提供詳細營養拆解
- 儘量不要主動給精確數字
- 優先用方向性詞語，例如：
  - 偏高
  - 偏低
  - 較多
  - 較少
- 如果真的非講數字不可，要加上「僅供參考」

這一點是放在第二段 LLM 的 prompt 裡控制，而不是在程式裡硬寫一堆 if/else 句子。

## 補問機制目前的做法

目前不再使用大量寫死補問句。

改成下面的方式：

1. 第一段 LLM 先判斷使用者輸入是否明確。
2. 如果食物不明確、問題過於模糊，通常無法組成有效的 `dietary_agent_request`。
3. 第二段 LLM 看到這份上下文後，會自行產生自然的補問內容。

例如它可能會引導使用者補：

- 想問的是哪一個食物
- 是想比較哪兩種食物
- 是想問熱量方向，還是餐點選擇建議

所以現在的補問重點是「交給 LLM 根據語境決定」，而不是固定回同一句話。

## 醫療與非處理範圍問題

如果第一段 LLM 判定為：

- `medical_out_of_scope`
- 或整體不屬於飲食助理處理範圍

第二段 LLM 會負責：

- 婉拒提供醫療診斷或用藥建議
- 引導回到飲食選擇、餐點方向或一般飲食建議

## 回傳給前端的資料

成功時，API 會回傳類似這樣的 JSON：

```json
{
  "success": true,
  "llm_fallback_used": false,
  "screening": {
    "should_handle": true,
    "intent_category": "dish_advice",
    "question_type": "single_dish",
    "confidence": 0.92,
    "dishes": ["炸雞", "拉麵"]
  },
  "emotion": {
    "primary_emotion": "anxiety",
    "valence": "negative",
    "urgency": "medium",
    "needs_empathy": true,
    "companion_tone": "calm",
    "evidence": ["有點焦慮"]
  },
  "dietary_agent_request": {
    "question": "我今天中午吃炸雞了，晚上還能吃拉麵嗎？",
    "question_type": "single_dish",
    "dish_names": ["炸雞", "拉麵"]
  },
  "dietary_agent_response": {
    "reply_text": "..."
  },
  "dietary_agent_error": null,
  "companion_reply": "..."
}
```

## 錯誤處理邏輯

### 1. `user_prompt` 不合法

- 回傳 `400 BAD_REQUEST`

### 2. OpenAI 呼叫失敗

- 回傳 `502 OPENAI_SERVICE_ERROR`
- 不再繼續往下跑

### 3. Dietary Agent 呼叫失敗

- 不中斷整體 API
- 把錯誤寫進 `dietary_agent_error`
- 繼續交給第二段 LLM 生出最終回覆

### 4. 其他未預期錯誤

- 回傳 `500 INTERNAL_SERVER_ERROR`

## 目前架構的優點

### 1. 分工清楚

- 第一段 LLM 負責理解問題
- 第二段 LLM 負責生成回覆
- Dietary Agent 負責較專門的飲食分析

### 2. 減少寫死回覆

補問、婉拒、語氣調整不再大量寫在程式裡，後續修改主要改 prompt 即可。

### 3. 比助教測試稿更接近正式服務

目前不是單純測試 OpenAI 輸出，而是完整串成：

- API 入口
- LLM 分析
- 下游服務整合
- 最終文字回覆

## 目前仍需注意的點

### 1. Prompt 文字編碼

目前 `companion-llm.js` 內第二段 prompt 的部分中文有亂碼情況，這會影響模型是否真的看到正確規則。

### 2. 仍保留最小必要的程式判斷

目前是否呼叫 Dietary Agent，還是有保留必要的防呆條件。這不是寫死回覆，而是避免送出不完整資料給下游服務。

### 3. 尚需實測

雖然程式結構已完成，但仍建議用實際問句驗證以下情境：

- 模糊提問是否會自然補問
- 詳細營養問題是否真的不會報一串數字
- 醫療問題是否能正確婉拒
- Dietary Agent 失敗時回覆是否仍自然

## 總結

目前 Companion Agent 的運作邏輯可以簡化成一句話：

先用第一段 LLM 把使用者問題分析成結構化資訊，再視情況呼叫 Dietary Agent，最後交給第二段 LLM 產生自然、符合產品規則的最終回覆。

這樣的設計已經比早期的寫死補問邏輯更彈性，也更接近你們希望的「主要靠 prompt 控制行為」的方向。
