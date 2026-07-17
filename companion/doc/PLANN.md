# Companion Agent + Nutrition API 本階段 MVP 實作計畫

## 1. 文件目的

本文件用於說明本專題目前階段的 `Companion Agent + Nutrition API` 技術實作範圍。

本文件聚焦於「本階段 MVP」。文件中會清楚區分：

- 本階段要做
- 本階段暫不做
- 未來可擴充
- 已存在的 Nutrition API
- 需要新做的 Companion Agent service


---

## 2. 本階段 MVP 範圍

### 2.1 本階段要做

本階段 MVP 需要完成以下功能：

1. Flutter 聊天輸入介面
2. `POST /companion/ask` endpoint
3. 飲食問題判斷
4. 情緒語氣調整
5. Nutrition API payload 整理
6. 呼叫 `https://dietary-app-kwz0.onrender.com/ask`
7. 整理 `conclusion` 與 `dish_advice`
8. 回傳自然語言回答
9. 處理資料不足、`422`、`500`、`timeout`

### 2.2 本階段暫不做

以下內容不列入本階段 MVP 實作範圍：

- 完整多代理人協作
- AutoGen orchestration
- Dietary Agent 額外獨立服務
- Knowledge Agent 額外獨立服務
- 自建 GraphRAG 流程
- 菜單 OCR
- 長期對話記憶
- 個人化學習推薦
- 後台管理系統完整整合

### 2.3 未來可擴充

待本階段 MVP 完成後，可再逐步擴充：

- 多代理人架構整合
- AutoGen 或其他 orchestration layer
- Spring Boot 統一 gateway
- 菜單辨識與餐廳上下文自動擷取
- 長期情緒追蹤
- 多輪對話記憶
- 個人化推薦策略
- 更完整的營養視覺化分析

### 2.4 已存在的元件

本階段已存在、可直接使用的元件如下：

1. `Nutrition Agent API`
   - URL：`https://dietary-app-kwz0.onrender.com`
   - 主要查詢 endpoint：`POST /ask`
   - 功能：根據問題、使用者資料、健康條件與近期飲食紀錄，回傳營養資訊與建議

### 2.5 需要新做的元件

本階段需要新實作的元件如下：

1. `Companion Agent service`
   - 接收 Flutter 訊息
   - 執行 function calling
   - 以程式碼組裝 Nutrition API request body
   - 呼叫 Nutrition API
   - 回傳自然語言回答

2. `Flutter 聊天介面`
   - 送出使用者飲食問題
   - 顯示 Companion Agent 回覆

### 2.6 與其他組員開發模組的關係

目前前端畫面展示、AutoGen、多代理人相關模組、Dietary Agent 與 Knowledge Agent 仍由其他組員持續開發中，因此本文件不表示這些模組「不存在」，而是表示：

- 它們不是本文件的核心交付範圍
- 本文件聚焦於 Companion Agent 與既有 Nutrition API 的實作
- 本階段 Companion Agent 應保留未來與這些模組整合的介面

---

## 3. 系統架構

### 3.1 本階段架構角色分工

本階段 MVP 僅包含兩個核心後端角色：

1. `Companion Agent`
   - 本階段要新實作
   - 作為 Flutter 與 Nutrition API 之間的中介服務
   - 負責意圖判斷、情緒分析、payload 整理、查詢與回覆生成

2. `Nutrition Agent API`
   - 已存在
   - 負責營養資訊查詢與建議回傳

`Future Dietary Agent / orchestration layer` 不納入本階段主要架構，只放在未來擴充討論。

### 3.2 本階段資料流

```text
User
-> Flutter Chat UI
-> POST /companion/ask
-> Companion Agent service
-> OpenAI function calling
-> Companion Agent service
-> POST https://dietary-app-kwz0.onrender.com/ask
-> Companion Agent service
-> Flutter Chat UI
-> User
```

### 3.3 詳細流程圖

```text
User
-> Flutter
-> POST /companion/ask
-> Companion Agent service
-> load user profile / health condition / weekly diet records
-> OpenAI function calling:
   -> screen_user_request
   -> analyze_emotion
-> if should_handle = true and data is sufficient:
   -> build Nutrition API request body in backend code
   -> POST https://dietary-app-kwz0.onrender.com/ask
   -> receive dish_nutrition / dish_advice / conclusion
-> generate final companion reply
-> return JSON response to Flutter
-> Flutter renders companion message
```

### 3.4 技術選型

本階段 MVP 建議使用：

- 前端：Flutter
- Companion Agent service：Node.js + Express
- 查詢後端：既有 Nutrition API

選擇 Node.js 的原因：

1. 適合快速串接 OpenAI Responses API 與 HTTP API
2. JSON schema 與 function calling 處理成本低
3. 適合本階段 MVP 快速驗證與展示

### 3.5 正式判斷原則

本階段 Companion Agent 的正式判斷原則如下：

1. `LLM function calling` 為主判斷機制
2. `rule-based` 為輔助與 fallback
3. Nutrition API 查詢是否發生，應以 `screen_user_request` 的結構化結果為主要依據

也就是說，正式流程不應以寫死的 regex 規則直接決定：

- `question_type`
- `should_handle`
- `requires_more_context`

較正確的做法是：

1. 先由 LLM 根據完整語意判斷
2. 再由本地 rule-based 邏輯進行驗證、補強或 fallback

---

## 4. LLM 主判斷 + Rule-based 輔助與 Fallback

### 4.1 為何不能只靠寫死規則

若只使用下列方式：

```js
if (/(哪個|比較|vs|versus|跟|和)/.test(message)) {
  return "dish_comparison";
}
```

雖然可以快速完成 prototype，但在正式系統中會有以下問題：

1. 對自然語言表達變化非常敏感
2. 很容易漏判不同說法
3. 每增加新料理、新語句就要修改規則
4. 無法穩定處理較模糊、口語、帶情緒的句子

例如以下句子，單靠 regex 容易判斷不準：

- `我今天中午已經吃很油了，晚餐還適合牛肉麵嗎？`
- `炸雞和咖哩飯哪個比較不容易超標？`
- `我現在有點罪惡感，但還是想吃鹹酥雞`
- `我今天這樣吃會不會太誇張`

因此正式實作應採：

- `LLM` 判斷語意
- `rule-based` 做保底與驗證

### 4.2 主判斷流程

正式執行順序如下：

```text
1. 接收使用者 message
2. 呼叫 OpenAI Responses API
3. 由 model 觸發 function calling
4. 執行 screen_user_request
5. 執行 analyze_emotion
6. 取得結構化結果
7. 使用本地 rule-based 檢查結果是否合理
8. 若合理，由後端程式碼組裝 Nutrition API request body
9. 呼叫 Nutrition API
10. 若不合理，啟動 fallback 或補問
```

### 4.3 LLM 負責什麼

LLM 應負責高語意理解工作，包括：

1. 這是不是飲食問題
2. 這是單一道料理問題還是比較問題
3. 是否需要補問
4. 使用者語句中真正的關注點是什麼
5. 情緒語氣應如何調整

本階段 LLM 不負責：

- 直接組裝最終 Nutrition API payload
- 決定後端預設欄位值
- 直接處理 HTTP request / response 錯誤

### 4.4 Rule-based 負責什麼

rule-based 不應取代 LLM，而應負責：

1. 快速攔截明顯 out-of-scope 問題
2. 快速攔截明顯醫療診斷語句
3. 檢查 LLM 結果是否明顯不合理
4. 在 LLM 無法回傳有效結果時提供 fallback
5. 提供 logging 與 debug 依據

### 4.5 合理的 hybrid 判斷設計

本階段建議採用以下 hybrid 設計：

#### 層 1：Pre-check rule

用途：

- 先做極輕量的快速篩選
- 過濾明顯與飲食無關或醫療診斷問題

例子：

- 是否包含明顯醫療診斷關鍵詞
- 是否完全沒有任何飲食相關語意

注意：

- 此層不可直接決定最終 `question_type`
- 只做快速攔截與風險保底

#### 層 2：LLM function calling

用途：

- 作為正式主判斷
- 輸出結構化結果

輸出重點：

- `should_handle`
- `intent_category`
- `question_type`
- `requires_more_context`
- `missing_information`

#### 層 3：Post-check rule

用途：

- 驗證 LLM 輸出是否合理

例子：

- LLM 判成 `dish_comparison`，但句子沒有任何比較語意，也沒有兩個料理實體
- LLM 判成 `single_dish`，但 message 內容像是純閒聊
- LLM 判 `should_handle=true`，但缺少最基本料理資訊

若發生上述情況，可採：

- 降級為 `unknown`
- 要求補問
- 記錄 anomaly log

### 4.6 Fallback 觸發條件

應啟動 rule-based fallback 的情況：

1. OpenAI API timeout
2. OpenAI API 回應格式錯誤
3. tool arguments 無法解析
4. `screen_user_request` 缺少必要欄位
5. LLM 結果與本地規則嚴重衝突

fallback 行為：

1. 使用本地 rule-based 做最低限度分類
2. 優先轉為補問，而不是直接做高信心判斷
3. 不應在 fallback 模式下做過度細緻的營養判斷

### 4.7 Rule-based 可保留到什麼程度

本階段可保留以下 rule-based 函式：

- `isLikelyFoodRelated(message)`
- `isMedicalOutOfScope(message)`
- `looksLikeComparison(message)`
- `extractMissingContextHints(message)`

但不建議維持大量寫死料理名稱的 regex 清單作為主要分類核心，例如：

- `拉麵`
- `炸雞`
- `沙拉`
- `便當`
- `火鍋`

這類詞可作為輔助特徵，但不應成為正式系統的主判斷基礎。

### 4.8 實作上的正確寫法

不建議：

```js
questionType = classifyQuestionType(message);
```

建議：

```js
screening = await runFunctionCalling("screen_user_request", {
  message,
  user_context
});

questionType = screening.question_type;
```

若 LLM 結果失敗，再 fallback：

```js
if (!screening || !screening.question_type) {
  questionType = fallbackClassifyQuestionType(message);
}
```

---

## 5. 本階段實作所需資源

### 5.1 外部服務

本階段需要以下外部資源：

1. `OpenAI Responses API`
   - 用途：function calling 主判斷
   - 功能：screening、emotion 結構化輸出

2. `Nutrition Agent API`
   - URL：`https://dietary-app-kwz0.onrender.com`
   - 用途：營養資訊與建議查詢

### 5.2 本地或專案端資源

1. `Companion Agent service`
   - Node.js 執行環境
   - Express HTTP server
   - function/tool schema
   - Nutrition API request body 組裝邏輯

2. `Flutter 前端`
   - 聊天輸入
   - 回覆顯示

3. `使用者資料來源`
   - `user_profile`
   - `health_condition`
   - `weekly_diet_records`

### 5.3 環境變數

建議使用以下環境變數：

- `OPENAI_API_KEY`
- `OPENAI_MODEL`
- `NUTRITION_API_URL`
- `COMPANION_API_PORT`
- `OPENAI_TIMEOUT_MS`
- `NUTRITION_TIMEOUT_MS`

### 5.4 Logging 與觀測資源

本階段至少應記錄以下資料：

1. 原始 message
2. `screen_user_request` 結果
3. `analyze_emotion` 結果
4. 後端組裝出的 `nutrition_api_request`
5. Nutrition API request / response status
6. fallback 是否被觸發
7. 失敗原因類型

這些資料可用於：

- debug
- demo 驗證
- 後續調整 prompt 與 rule

---

## 6. 本階段最終交付項目

本階段實際要交付的功能如下：

1. `POST /companion/ask` Express endpoint
2. Flutter 聊天介面可送出飲食問題
3. Companion Agent 可判斷是否為飲食問題
4. 可整理 Nutrition API request body
5. 可呼叫 `https://dietary-app-kwz0.onrender.com/ask`
6. 可解析 `dish_advice` 與 `conclusion`
7. 可產生自然語言回覆
8. 可處理資料不足、`422`、`500`、`timeout`

---

## 7. Companion Agent 實作方式

### 7.1 Companion Agent endpoint

本階段主要 endpoint：

`POST /companion/ask`

用途：

- 接收 Flutter 傳入的聊天訊息
- 執行飲食問題判斷
- 執行情緒分析
- 以程式碼組裝 Nutrition API request body
- 呼叫 Nutrition API
- 回傳結構化資料與前端顯示文字

### 7.2 Request body 範例

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
    "conversation_id": "conv-20260702-001"
  }
}
```

### 7.3 Response body 範例

```json
{
  "success": true,
  "screening": {
    "should_handle": true,
    "intent_category": "dish_advice",
    "question_type": "single_dish",
    "requires_more_context": false,
    "missing_information": [],
    "confidence": 0.92
  },
  "emotion": {
    "primary_emotion": "anxiety",
    "valence": "negative",
    "urgency": "medium",
    "needs_empathy": true,
    "companion_tone": "calm",
    "evidence": ["焦慮"]
  },
  "nutrition_api_request": {
    "question": "我今天中午已經吃炸雞了，晚上還能吃拉麵嗎？我有點焦慮。",
    "cypher": null,
    "question_type": "single_dish",
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
    "debug": false
  },
  "nutrition_api_response": {
    "question": "我今天中午已經吃炸雞了，晚上還能吃拉麵嗎？我有點焦慮。",
    "question_type": "single_dish",
    "dish_nutrition": [],
    "dish_advice": [],
    "conclusion": "若中午已攝取較高油脂與熱量，晚餐建議避免再選高油高鹽料理，可考慮清湯麵、燙青菜或蛋白質較清淡的搭配。"
  },
  "reply_text": "我有注意到你現在有點在意這次的選擇，先不用太緊張。以你今天中午已經吃了炸雞的情況，晚餐不太建議再選高油高鹽的拉麵，會比較適合改成清淡一些的選項。",
  "next_action": "show_reply"
}
```

---

## 8. Function Calling 設計

本階段 MVP 使用兩個主要 tool：

- `screen_user_request`
- `analyze_emotion`

### 8.1 Tool 重要性說明

1. `screen_user_request`
   - 必要
   - 用來判斷是否為飲食問題，以及是否需要補問

2. `analyze_emotion`
   - 用於回覆語氣調整
   - 不影響 Nutrition API 查詢結果
   - 正式流程仍建議使用 LLM 輸出結構化情緒結果

### 8.2 本階段 function calling 的實際作法

本階段採用的不是「本地函式自己做主判斷」，而是：

1. Companion Agent 先把 `message`、`user_context`、`user_profile`、`health_condition`、`weekly_diet_records` 一起送進 OpenAI Responses API
2. 由 LLM 根據語意主動呼叫兩個 tool
3. tool call 中的 `arguments` 就是模型產生的結構化判斷結果
4. Companion Agent 本地端只負責：
   - 驗證 schema
   - 做 post-check
   - 必要時啟動 fallback
   - 以程式碼組裝 Nutrition API request body

因此，本階段的兩個 tool 在技術上比較接近：

- `LLM 輸出格式`
- `結構化判斷結果容器`

而不是：

- 單純由本地程式寫死規則後回傳結果

換言之：

- `message` 等原始資料是送給模型的 input
- tool schema 是模型必須產生的 output 格式
- Nutrition API request body 則由後端程式碼依據結構化結果組裝

### 8.3 `screen_user_request`

#### 功能說明

由 LLM 根據使用者訊息與上下文，輸出是否屬於飲食建議流程、問題類型、是否缺少必要資訊等結構化判斷結果。

#### 模型可用輸入資料

- `message`
- `user_context.has_active_restaurant_context`
- `user_context.has_menu_context`
- `user_context.has_user_profile`

#### Tool argument schema

```json
{
  "type": "object",
  "properties": {
    "message": { "type": "string" },
    "user_context": {
      "type": "object",
      "properties": {
        "has_active_restaurant_context": { "type": "boolean" },
        "has_menu_context": { "type": "boolean" },
        "has_user_profile": { "type": "boolean" }
      },
      "required": [
        "has_active_restaurant_context",
        "has_menu_context",
        "has_user_profile"
      ],
      "additionalProperties": false
    }
  },
  "required": ["message", "user_context"],
  "additionalProperties": false
}
```

#### Tool call 範例

```json
{
  "should_handle": true,
  "intent_category": "dish_advice",
  "question_type": "single_dish",
  "requires_more_context": false,
  "missing_information": [],
  "confidence": 0.92
}
```

#### 本地驗證與 fallback

- 若 tool 缺少必要欄位，使用本地 fallback 補齊
- 若 LLM 判 `dish_comparison` 但句子不具有比較語意，則降級為 fallback 結果
- 若偵測到明顯醫療診斷語句，直接覆寫為 `medical_out_of_scope`

### 8.4 `analyze_emotion`

#### 功能說明

由 LLM 根據語句內容輸出情緒結構化結果，用於調整最終回覆語氣。此 tool 不影響 Nutrition API 查詢本身。

#### 模型可用輸入資料

- `message`

#### Tool argument schema

```json
{
  "type": "object",
  "properties": {
    "primary_emotion": { "type": "string" },
    "valence": { "type": "string" },
    "urgency": { "type": "string" },
    "needs_empathy": { "type": "boolean" },
    "companion_tone": { "type": "string" },
    "evidence": {
      "type": "array",
      "items": { "type": "string" }
    }
  },
  "required": [
    "primary_emotion",
    "valence",
    "urgency",
    "needs_empathy",
    "companion_tone",
    "evidence"
  ],
  "additionalProperties": false
}
```

#### Tool call 範例

```json
{
  "primary_emotion": "anxiety",
  "valence": "negative",
  "urgency": "medium",
  "needs_empathy": true,
  "companion_tone": "calm",
  "evidence": ["焦慮"]
}
```

#### 本地驗證與 fallback

- 若 tool 缺失或格式錯誤，使用本地簡易情緒規則補值
- fallback 情緒結果只影響語氣，不影響 Nutrition API request body

### 8.5 為何 `Nutrition API request body` 改由程式碼組裝

本階段已將原本的 `prepare_nutrition_api_request` 從 function calling tool 移除，改由後端程式碼直接組裝。

原因如下：

1. 這一段屬於固定欄位映射，不需要模型推理
2. 由程式碼組裝可避免模型輸出格式不穩定
3. 比較容易補預設值、做欄位驗證與除錯
4. 比較符合後端對外 API payload 應可控的設計原則

本階段的組裝方式如下：

```text
if screening.should_handle = true
and screening.requires_more_context = false
then build:
  question = message
  cypher = null
  question_type = screening.question_type
  user_profile = request body 或資料庫讀取結果
  health_condition = request body 或資料庫讀取結果
  weekly_diet_records = request body 或資料庫讀取結果
  debug = false
else
  nutrition_api_request = null
```

程式碼組裝後的 payload 範例如下：

```json
{
  "question": "我今天中午吃炸雞了，晚上還能吃拉麵嗎？我有點焦慮。",
  "cypher": null,
  "question_type": "single_dish",
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
  "debug": false
}
```

---

## 9. Nutrition API 串接

### 7.1 已存在的 Nutrition API

Base URL：

`https://dietary-app-kwz0.onrender.com`

主要 endpoint：

`POST /ask`

### 7.2 HTTP request 範例

```http
POST /ask HTTP/1.1
Host: dietary-app-kwz0.onrender.com
Content-Type: application/json
```

```json
{
  "question": "我今天中午吃炸雞了，晚上還能吃拉麵嗎？我有點焦慮。",
  "cypher": null,
  "question_type": "single_dish",
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
  "debug": false
}
```

### 7.3 回傳欄位處理方式

#### `dish_nutrition`

用途：

- 作為營養細節資料來源
- 本階段可先不完整展示所有欄位
- 只挑出與使用者問題最相關的重點補充進 `reply_text`

#### `dish_advice`

用途：

- 提供料理層級建議
- 可用來整理「不建議原因」與「替代建議」

本階段處理策略：

- 優先取主要建議
- 若有 `suggestions`，可轉成替代餐點文字

#### `conclusion`

用途：

- 作為最終回覆主體

本階段處理策略：

- Companion Agent 以 `conclusion` 為主
- 再依情緒調整開頭語氣

### 7.4 錯誤處理

#### 資料不足

處理方式：

- 不呼叫 Nutrition API
- 直接補問使用者

示例：

`我還需要一些資料，像是你想問的料理名稱，或你的基本健康資訊，才能幫你查詢比較準確的建議。`

#### 422 Validation Error

處理方式：

- 記錄 request payload
- 回傳前端可理解錯誤訊息
- 必要時轉成補問

示例：

`目前我收到的資料格式不完整，可能還缺少料理內容或個人資訊，補充後我才能幫你查詢更準確的建議。`

#### 500 Internal Server Error

處理方式：

- 記錄錯誤 log
- 不暴露內部錯誤細節
- 回傳 fallback 訊息

示例：

`我剛剛查詢建議時出了點問題，現在暫時沒辦法完成分析。你可以稍後再試一次。`

#### Timeout

建議：

- Companion Agent 呼叫 Nutrition API timeout 設定為 `8~12 秒`

處理方式：

- timeout 後中止 request
- 回傳 fallback 訊息

示例：

`這次查詢花的時間有點久，我先幫你把問題整理好了。你可以稍後再試一次，我會再幫你查詢完整建議。`

---

## 10. 對話流程設計

### 8.1 使用者詢問飲食問題

流程：

1. 使用者輸入飲食相關問題
2. Companion Agent 執行 `screen_user_request`
3. 執行 `analyze_emotion`
4. 若資料足夠，由後端程式碼組裝 Nutrition API request body
5. 呼叫 Nutrition API
6. 將 `conclusion` 與 `dish_advice` 轉成自然語言
7. 回傳給 Flutter 顯示

### 8.2 使用者詢問非飲食問題

流程：

1. 使用者輸入非飲食問題
2. `screen_user_request` 判定 `should_handle = false`
3. Companion Agent 不呼叫 Nutrition API
4. 回傳導向式回覆

示例：

`這個問題目前不在飲食建議模組的處理範圍內。如果你想問某道料理適不適合吃，可以直接告訴我料理名稱或今天已經吃了什麼。`

### 8.3 使用者資料不足時的補問策略

當 `missing_information` 不為空時，不應直接查詢 Nutrition API，而應補問。

補問優先順序：

1. 料理名稱或問題內容不明確
2. 缺少 user profile
3. 缺少 health condition
4. 缺少近期飲食紀錄

補問示例：

- 缺料理名稱：
  - `你想問的是哪一道料理呢？如果可以的話，也可以直接告訴我餐廳或菜單名稱。`

- 缺個人資料：
  - `我還需要一些基本資訊，像是年齡、身高、體重或健康狀況，才能幫你做比較合適的判斷。`

### 8.4 情緒語氣調整

#### 焦慮 `anxiety`

- 先安撫，再給建議
- 避免責備語氣

示例：

`我有注意到你現在有點擔心，先不用太緊張。我幫你看目前這個選擇，若中午已經攝取較高油脂，晚餐會比較適合清淡一點的搭配。`

#### 罪惡感 `guilt`

- 避免道德化語氣
- 強調下一餐可調整

示例：

`不用因為前一餐就太有壓力，我們可以把重點放在下一餐怎麼調整得更平衡。`

#### 好奇 `curious`

- 直接回答
- 語氣中性

#### 壓力或煩躁 `stress` / `frustration`

- 先承接感受
- 再提供簡單可執行建議

---

## 11. Companion Agent 實作 pseudocode

```text
function POST /companion/ask(request):
    message = request.message
    user_profile = request.user_profile
    health_condition = request.health_condition
    weekly_diet_records = request.weekly_diet_records
    context = request.context

    user_context = {
        has_active_restaurant_context: context.restaurant_name is not null,
        has_menu_context: length(context.menu_items) > 0,
        has_user_profile: user_profile is not null
    }

    precheck = run_rule_based_precheck(message)
    if precheck.is_medical_out_of_scope:
        return out_of_scope_medical_reply

    screening = run_function_call("screen_user_request", {
        message,
        user_context
    })

    emotion = run_function_call("analyze_emotion", {
        message
    })

    screening = run_rule_based_postcheck(screening, message)

    if screening.should_handle == false:
        reply_text = build_out_of_scope_reply()
        return {
            success: true,
            screening,
            emotion,
            nutrition_api_request: null,
            nutrition_api_response: null,
            reply_text
        }

    if screening.requires_more_context == true:
        reply_text = build_followup_question(screening.missing_information, emotion)
        return {
            success: true,
            screening,
            emotion,
            nutrition_api_request: null,
            nutrition_api_response: null,
            reply_text
        }

    nutrition_api_request = buildNutritionApiRequest(
        screening,
        message,
        user_profile,
        health_condition,
        weekly_diet_records
    )

    try:
        nutrition_api_response = POST Nutrition API /ask with nutrition_api_request
    catch openai failure before screening complete:
        screening = run_rule_based_fallback(message, user_context)
        if screening.requires_more_context:
            reply_text = build_followup_question(screening.missing_information, emotion)
            return fallback followup response
    catch timeout:
        reply_text = build_timeout_reply(emotion)
        return timeout fallback response
    catch validation error:
        reply_text = build_validation_reply(emotion)
        return validation fallback response
    catch server error:
        reply_text = build_server_error_reply(emotion)
        return server fallback response

    reply_text = build_final_reply(
        emotion,
        nutrition_api_response.conclusion,
        nutrition_api_response.dish_advice,
        nutrition_api_response.dish_nutrition
    )

    return {
        success: true,
        screening,
        emotion,
        nutrition_api_request,
        nutrition_api_response,
        reply_text
    }
```

---

## 12. 本階段實作任務順序

為避免誤解為不同版本，本文件不使用 `Phase 1 / Phase 2 / Phase 3`，改用本階段實作任務順序表示。

建議順序如下：

1. 建立 Express `POST /companion/ask` endpoint
2. 完成 OpenAI Responses API 串接
3. 完成 `screen_user_request`
4. 完成 `analyze_emotion`
5. 完成 pre-check / post-check / fallback rule-based 模組
6. 完成 `buildNutritionApiRequest()` 程式碼組裝邏輯
7. 串接 Nutrition API `/ask`
8. 完成 `dish_advice`、`conclusion` 解析與 `reply_text` 組裝
9. 完成資料不足、`422`、`500`、`timeout` 錯誤處理
10. 與 Flutter 聊天頁串接
11. 導入 request body 或資料庫讀取的 user profile / weekly diet records

---

## 13. 專題報告可用內容

### 11.1 系統設計

本研究於本階段 MVP 中，將 Companion Agent 視為使用者與 Nutrition Agent API 之間的前置互動代理。其主要功能為接收使用者自然語言輸入，判斷是否屬於飲食建議問題，分析使用者情緒，並由後端程式碼將訊息與使用者背景資料組裝為 Nutrition API 可接受之查詢格式。之後，Companion Agent 將 Nutrition API 回傳之分析結果轉換為自然語言回覆，再回傳至 Flutter 前端顯示。

系統整體資料流為：使用者透過 Flutter 聊天介面輸入問題，前端將資料送至 Express `POST /companion/ask`；Companion Agent service 執行飲食問題判斷、情緒分析與查詢資料整理後，呼叫既有 Nutrition API 的 `/ask` endpoint；最後再將查詢結果整理為具可讀性的自然語言回答回傳前端。

### 11.2 角色分工

本階段 MVP 中，Companion Agent 為新實作之 Express 服務，負責意圖判斷、情緒語氣調整、Nutrition API payload 程式碼組裝與最終回覆生成。Nutrition Agent API 為既有服務，負責依據使用者問題、個人資料、健康條件與近期飲食紀錄回傳營養資訊與建議內容。

### 11.3 實作流程

當使用者提出飲食問題時，Companion Agent 並非僅使用固定規則判斷，而是以大語言模型的 function calling 作為主要判斷機制，搭配本地 rule-based 邏輯作為輔助驗證與 fallback。系統先利用 `screen_user_request` 判斷問題是否屬於飲食建議情境，並辨識是否為單一道料理查詢、料理比較或未知類型；接著透過 `analyze_emotion` 分析使用者語句中的情緒線索，用於調整回答語氣。若問題屬於飲食建議範圍且資料足夠，系統再由後端程式碼組裝 Nutrition API request body，呼叫 Nutrition API `/ask`，取得 `dish_advice`、`dish_nutrition` 與 `conclusion` 等欄位。最後，由 Companion Agent 將上述資訊整理為自然語言回覆，返回 Flutter 前端顯示。

### 11.4 未來擴充

未來可在本階段 MVP 基礎上，擴充更多功能，例如多代理人協作架構、菜單 OCR、自動取得餐廳上下文、長期情緒追蹤、多輪對話記憶與更完整的個人化推薦策略。上述項目皆不屬於本階段必要交付內容。

---

## 14. 原本文件不足之處與本次調整內容

### 12.1 原本文件不足之處

原文件主要問題如下：

1. 持續使用「第一版」一詞，容易讓組員誤解哪些是現在必做，哪些是之後才做。
2. Companion Agent、Nutrition API 與未來多代理人內容混在一起，導致本階段範圍不清楚。
3. 未清楚區分已存在服務與需要新做服務。
4. `Phase 1 / Phase 2 / Phase 3` 容易讓人誤會是不同版本，而不是同一階段內的實作順序。
5. 未充分說明 `LLM function calling` 與 `rule-based fallback` 的實際分工與完成方式。
6. 未區分哪些欄位應由模型判斷，哪些應由後端程式碼組裝。

### 12.2 本次補強內容

本次已做以下整理：

1. 全文以「本階段 MVP」取代大部分「第一版」說法。
2. 新增「本階段 MVP 範圍」，明確區分要做、暫不做、未來可擴充、已存在元件與需要新做元件。
3. 將本階段架構收斂為 `Flutter + Companion Agent service + Nutrition API`。
4. 保留兩個主要 function/tool，並明確標示其角色與邊界。
5. 將 `Future Dietary Agent / orchestration layer` 移至未來擴充，不放在本階段主架構中。
6. 將 `Phase` 改為「本階段實作任務順序」，避免版本誤解。
7. 補上「LLM 主判斷 + rule-based 輔助與 fallback」的正式實作方案與所需資源。
8. 將 prototype 與文件同步調整為 Express API，並把 Nutrition API payload 改為後端程式碼組裝。
