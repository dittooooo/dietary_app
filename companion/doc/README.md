# Companion Agent Prototype

這個 prototype 已改為 `Express API` 形式，目的不是單純做 CLI demo，而是模擬你們實際系統中的 `Companion Agent service`。

## 功能

此服務會：

1. 接收前端送來的使用者訊息
2. 呼叫 OpenAI Responses API
3. 以 function calling 取得結構化判斷結果
4. 由程式碼組裝 Nutrition API request body
5. 呼叫既有 Nutrition Agent API `/ask`
6. 回傳最終 JSON 與自然語言回答

## 重要設計

### 1. Function calling 的角色

本 prototype 中，function calling 的角色是：

- 作為 `結構化輸出機制`
- 讓模型將語意理解結果輸出成固定 schema

它不是用來直接取代後端邏輯，也不是讓模型自由生成最終 API payload。

目前由 LLM 輸出的 tool 只有：

- `screen_user_request`
- `analyze_emotion`

而 `prepare_nutrition_api_request` 已改為由程式碼直接組裝，原因是這一段屬於固定欄位映射，使用程式碼更穩定、可控、容易除錯。

### 2. LLM 主判斷，rule fallback

正式流程：

- LLM function calling 當主判斷
- rule-based 當 post-check 與 fallback

也就是說：

- `question_type`
- `should_handle`
- `requires_more_context`

這些主要由模型判斷，再由本地程式做驗證與修正。

## 相關檔案

- `companion-agent.js`
- `package.json`
- `.env.example`

## 環境變數

```bash
OPENAI_API_KEY=your_api_key
OPENAI_MODEL=gpt-4.1-mini
NUTRITION_API_URL=https://dietary-app-kwz0.onrender.com
COMPANION_API_PORT=3000
```

## 安裝

```bash
cd prototype
npm install
```

## 啟動 API

```bash
cd prototype
npm start
```

啟動後預設會提供：

- `GET /health`
- `POST /companion/ask`

## API 範例

### Request

```json
{
  "message": "我今天中午已經吃炸雞了，晚上還能吃拉麵嗎？我有點焦慮。",
  "user_id": "user-001",
  "user_profile": {
    "height_cm": 165,
    "weight_kg": 60,
    "gender": "female",
    "age": 21
  },
  "health_condition": {
    "has_chronic_disease": false,
    "chronic_diseases": []
  },
  "weekly_diet_records": [
    {
      "date": "2026-07-02",
      "meal": "lunch",
      "dish_name": "炸雞",
      "note": "公司附近便當店"
    }
  ],
  "context": {
    "restaurant_name": null,
    "menu_items": [],
    "conversation_id": "conv-001"
  }
}
```

### Response

```json
{
  "success": true,
  "llm_fallback_used": false,
  "screening": {},
  "emotion": {},
  "nutrition_api_request": {},
  "nutrition_api_response": {},
  "nutrition_api_error": null,
  "companion_reply": "..."
}
```

## 注意

- 若 `OPENAI_API_KEY` 不可用，系統會退回 rule-based fallback
- 若 Nutrition API 失敗，仍會回傳 `screening`、`emotion` 與 `companion_reply`
- 目前 `user_profile` 可直接由 request body 傳入；未來可將 `loadUserData()` 改接資料庫
