# 第四次程式碼修正計畫 - 飲食紀錄意圖實作 (adjust_v4.md)

## 📌 功能概要說明 (Overview)

當使用者以自然語言表達飲食紀錄意圖（例如：「我早餐吃了兩個蛋餅和一杯無糖豆漿」或「我上午吃了一顆茶葉蛋，下午喝了一杯豆漿」）時，Companion Agent 服務將執行以下完整處理流程：

1. **意圖辨識 (Intent Classification)**：
   * 系統第一階段語意分析器會自動將使用者的自然語言輸入識別為 `meal_record`（飲食紀錄意圖），與尋求建議的 `dish_advice`（飲食諮詢意圖）及純閒聊 `general_chat` 進行明確區隔。

2. **跨餐期分組與時間上下文推算 (Grouped Feature Extraction & Temporal Inference)**：
   * **紀錄分組 (Meal Records Array - 方案 A)**：系統支援單一句子包含**單一或多個餐期**的紀錄。LLM 會將食物自動依照「餐期」進行分組，輸出 `meal_records` 陣列。
   * **餐期 (Meal Period)**：從輸入中擷取「早餐」、「中餐」、「晚餐」、「其他」。若未明確提及，系統會結合**伺服器當前系統時間**進行推算（例如：15:30 推算為「其他」）。
   * **食物明細與數量 (Meal Items)**：每個餐期群組內包含具體的食物名稱、數量與常用單位（例如：`[{"meal_period": "早餐", "meal_items": [{"name": "茶葉蛋", "quantity": 1, "unit": "顆"}]}, {"meal_period": "其他", "meal_items": [{"name": "豆漿", "quantity": 1, "unit": "杯"}]}]`）。

3. **草稿回傳與前端確認 (Draft Preview & Confirmation UI)**：
   * Companion Agent 在 `/companion/ask` 端點完成分析後，**不直接呼叫寫入資料庫的 API**，而是將上述結構化資訊作為「紀錄草稿」 (`companion_reply`) 回傳給前端。
   * 前端收到 `meal_records` 陣列後，可直接以「一餐期一張卡片」的方式彈出確認 UI，讓使用者直觀確認 AI 辨識出的各餐期與食物明細。

4. **前端持久化寫入 (Final Persistence)**：
   * 使用者於前端確認內容無誤（或微調數量/餐期）後，點擊「確認儲存」，由前端直接發送 POST 請求至後端飲食紀錄 API (`/dietary-record/save`) 完成資料庫持久化寫入。這能 100% 避免 LLM 語意誤判或幻覺導致錯誤資料直接寫入資料庫。

---

## 一、 核心設計共識

1. **採用「方案 A：餐期分組紀錄陣列 (meal_records)」**：
   * 解決單一句子包含跨餐期（如「上午吃茶葉蛋，下午喝豆漿」）的盲點。
   * 結構為 `meal_records: [{ meal_period, meal_items }, ...]`。
   * 前端能直接以物件陣列為單位畫出卡片，完全不需要在 Dart/Flutter 前端寫額外的 `groupBy` 分組演算法。

2. **Schema 欄位設計簡化（不分意圖皆生成）**：
   * 無論 `intent_category` 是 `dish_advice` 還是 `meal_record`，LLM 均統一輸出 `meal_records` 陣列（若非飲食問句則為 `[]`）。
   * **移除重複的 `dishes` 欄位（改由後端自動衍生）**：從 OpenAI 工具 Schema 中**徹底移除 `dishes` 欄位**，LLM 僅需集中精力輸出 `meal_records`。這能節省 API 輸出 Token 並避免 `dishes` 與 `meal_records` 之間的內容矛盾。
   * **後端衍生與下游相容**：在 `sanitizeScreening` 函數中，由 Node.js 後端自動將 `meal_records` 中的食物名稱提煉出來賦值給 `screening.dishes`。下游服務 `translateDishes`（餐點翻譯）與 `buildDietaryAgentRequest`（飲食助理請求）繼續讀取衍生好的 `screening.dishes`，系統 100% 完美解耦且相容！

3. **當前時間與餐期推算**：
   * 在發送請求給 LLM 前，Node.js 服務會獲取當前的系統時間與日期（例如 `2026-08-07 15:20`）代入 User Prompt 作為上下文，提供 LLM 推算「剛才」、「剛剛」等模糊餐期的基準。

4. **暫不進行食物名稱標準化**：
   * 對於 `meal_record` 流程，**暫時不要調用標準化翻譯 (`translateDishes`)**。直接將原始食物名稱傳送至前端。

5. **採用「模式 B：草稿預覽模式 (Draft Mode)」**：
   * **不安裝/不發送資料庫寫入請求**：Companion Agent 服務作為語意理解與陪伴對話的中介層，在 `/companion/ask` 端點處理 `meal_record` 意圖時，**不會直接連線或呼叫寫入資料庫的儲存 API**。
   * **職責專一與預覽草稿輸出**：Companion Agent 專注於將自然語言解析為結構化的 JSON 紀錄草稿 (`meal_records` 陣列)，並搭配親切自然的預覽對話 (`companion_reply`)，將資料組合好回傳給前端。
   * **前端展示與最終保存**：Flutter 前端接收到草稿 JSON 後，彈出預覽確認 UI 卡片。使用者能在介面上直接核對（或修改）AI 解析出來的餐期、食物名稱、數量與單位。當使用者確認無誤按下「確認儲存」後，才由前端主動發送 POST 請求至後端飲食紀錄 API (`POST /dietary-record/save`) 完成資料庫持久化儲存。
   * **核心優勢**：徹底防止 LLM 語意誤判（例如數量誤判或餐期放錯）導致錯誤資料直接寫入資料庫的問題，確保資料庫內容的高品質與使用者高度的可控性。

---

## 二、 第一階段：LLM 分析調整 (修改 `companion-llm.js`)

修改 [companion-llm.js](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-llm.js) 的系統提示詞與工具宣告。

### 1. 修改 `tools` 宣告的 JSON Schema

在 `screen_user_request` 中，**移除舊有 `dishes` 欄位**，僅保留 `meal_records` 陣列：

```javascript
        properties: {
          should_handle: {
            type: "boolean",
            description: "Whether this request should be processed by the companion agent."
          },
          intent_category: {
            type: "string",
            enum: ["dish_advice", "meal_record", "general_chat"]
          },
          question_type: {
            type: "string",
            enum: ["single_dish", "dish_comparison", "unknown"]
          },
          confidence: {
            type: "number"
          },
          // ── 注意：已從 LLM Schema 移除 dishes 欄位，改由後端 sanitizeScreening 自動衍生 ──
          meal_records: {
            type: "array",
            description: "依餐期分組之飲食紀錄列表。可包含一至多個餐期的紀錄組合（例如早餐一組、其他一組）。若為非飲食問句，請傳回空陣列 []。",
            items: {
              type: "object",
              properties: {
                meal_period: {
                  type: "string",
                  enum: ["早餐", "中餐", "晚餐", "其他"],
                  description: "該筆紀錄對應的餐期。"
                },
                meal_items: {
                  type: "array",
                  description: "該餐期內含的食物明細、數量與單位。",
                  items: {
                    type: "object",
                    properties: {
                      name: { type: "string", description: "食物或飲料名稱，例如：蛋餅" },
                      quantity: { type: "number", description: "數量，例如：1 (若未提及則設為 1)" },
                      unit: { type: "string", description: "單位，例如：份、杯、個 (若未提及則設為 '份' 或 '個' 等合理預設值)" }
                    },
                    required: ["name", "quantity", "unit"]
                  }
                }
              },
              required: ["meal_period", "meal_items"]
            }
          },
          early_reply: {
            type: "string",
            description: "If should_handle is false, OR if should_handle is true but dishes is empty or question_type is 'unknown', generate a warm, Taiwanese Traditional Chinese response. Otherwise, set it to \"\"."
          }
        },
        required: [
          "should_handle",
          "intent_category",
          "confidence",
          "meal_records",
          "early_reply"
        ],
```

### 2. 修改 `ANALYSIS_SYSTEM_PROMPT` 規則

```javascript
const ANALYSIS_SYSTEM_PROMPT = `
你是一個飲食推薦應用程式的 Companion Agent（陪伴助理）分類與特徵擷取器。
你的任務是分析使用者的輸入訊息（通常為繁體中文），並同時執行兩個工具調用："screen_user_request" 與 "analyze_emotion"。

請嚴格遵守以下分類與擷取規則：

【screen_user_request 的規則】
1. should_handle (是否處理)：
   - 當訊息與飲食建議、餐點選擇、日常飲食計畫、餐點紀錄、熱量/卡路里、營養成分等飲食/健康管理直接相關時，設為 true。
   - 當訊息為敏感的醫療諮詢、疾病診斷、藥物使用（例如：「頭痛要吃什麼藥」）、非飲食相關的閒聊（例如：天氣、純問候），設為 false。
2. intent_category (意圖分類)：
   - "dish_advice"：使用者在尋求飲食建議、推薦，或詢問某特定食物是否適合食用。若問句中同時包含「記錄已吃食物」與「尋求建議」，應優先歸類於 "dish_advice"。
   - "meal_record"：使用者「純粹」在記錄自己吃了什麼，沒有提出疑問或尋求任何飲食建議（例如：「我今天中午吃了一碗拉麵」、「我剛吃了蛋餅和豆漿」）。
   - "general_chat"：非飲食主題的純閒聊、問候，或任何醫療/診斷/藥物問題。
3. question_type (問題類型) —— 僅當 intent_category 為 "dish_advice" 時才可包含此欄位：
   - "single_dish"、"dish_comparison"、"unknown"。如果 intent_category 不是 "dish_advice"，請勿在輸出的參數中包含 "question_type" 欄位。
4. meal_records (依餐期分組之紀錄陣列)：
   - 擷取或推算使用者此段訊息對應的一至多個餐期紀錄組合。
   - 每個物件包含 "meal_period"（"早餐"、"中餐"、"晚餐"、"其他"）與 "meal_items" 陣列。
   - 若使用者在單一句子中提及多個餐期（例如「上午吃了茶葉蛋，下午喝了豆漿」），請將其拆解為多個餐期物件：
     [
       {"meal_period": "早餐", "meal_items": [{"name": "茶葉蛋", "quantity": 1, "unit": "顆"}]},
       {"meal_period": "其他", "meal_items": [{"name": "豆漿", "quantity": 1, "unit": "杯"}]}
     ]
   - 若使用者沒有明確提及餐期（例如「我剛才吃了...」），請根據「當前系統時間」進行推算：
     * 05:00 - 10:30 推算為 "早餐"
     * 10:30 - 14:00 推算為 "中餐"
     * 14:00 - 17:00 推算為 "其他"
     * 17:00 - 21:00 推算為 "晚餐"
     * 21:00 - 05:00 推算為 "其他"
   - 若為非飲食相關問句，meal_records 必須傳回空陣列 []。
5. early_reply (早退回覆)：
   - 當 should_handle 為 false，或 should_handle 為 true 但 meal_records 為空時，生成一段親切引導的台灣繁體中文對話。若符合正常流程則設為 ""。
`;
```

### 3. 修改 `sanitizeScreening`（自動衍生 `dishes` 陣列）

在 `sanitizeScreening` 函數中，由 Node.js 後端從 `meal_records` 提煉衍生 `dishes` 陣列，無縫供給後續的 `translateDishes` 與 `buildDietaryAgentRequest` 呼叫：

```javascript
function sanitizeScreening(raw) {
  if (!raw) {
    return {
      should_handle: false,
      intent_category: "general_chat",
      question_type: undefined,
      confidence: 0,
      dishes: [],
      meal_records: [],
      early_reply: "這個問題比較不是飲食助理的處理範圍。如果你願意，我還是可以幫你回到餐點選擇、熱量方向，或日常飲食建議來一起看。"
    };
  }

  const result = { ...raw };
  if (!Array.isArray(result.meal_records)) {
    result.meal_records = [];
  }

  // ── 自動衍生 dishes 陣列：從 meal_records 提煉所有食物名稱 ──
  const extractedNames = [];
  for (const rec of result.meal_records) {
    if (Array.isArray(rec.meal_items)) {
      for (const item of rec.meal_items) {
        if (item.name) extractedNames.push(item.name);
      }
    }
  }
  result.dishes = extractedNames;

  if (typeof result.early_reply !== "string") {
    result.early_reply = "";
  }

  if (result.intent_category !== "dish_advice") {
    delete result.question_type;
  }

  return result;
}
```

---

## 三、 第二階段：服務層與控制器（草稿模式與流程相容）

### 1. 修改 Express 控制器 (`companion-agent.js`)

在 `screening` 回傳物件中返回 `dishes`（衍生欄位）與 `meal_records` 陣列給前端：

```javascript
// handleCompanionAsk 修改片斷：
    return res.json({
      success: true,
      llm_fallback_used: false,
      screening: {
        should_handle: openAiResult.screening.should_handle,
        intent_category: openAiResult.screening.intent_category,
        question_type: openAiResult.screening.question_type,
        confidence: openAiResult.screening.confidence,
        dishes: openAiResult.screening.dishes, // 後端衍生欄位，相容舊有前端
        meal_records: openAiResult.screening.meal_records // 方案 A 分組草稿
      },
      emotion: openAiResult.emotion,
      dietary_agent_request: openAiResult.dietary_agent_request,
      dietary_agent_response: dietaryAgentResponse,
      dietary_agent_error: dietaryAgentError,
      companion_reply: await getCompanionReply({
        userPrompt: user_prompt,
        screening: openAiResult.screening,
        emotion: openAiResult.emotion,
        dietaryAgentResponse,
        userPrompt
      })
    });
```

### 2. `companion-agent-services.js` 服務層運作機制

* **`runOpenAIFlow` 中的餐點翻譯 (`translateDishes`)**：
  * 當 `intent_category === "dish_advice"` 時，`runOpenAIFlow` 讀取衍生好的 `result.screening.dishes`（如 `["起司瀑布超厚牛肉堡"]`），呼叫 `translateDishes` 將其更新為 `["牛肉漢堡"]`。
* **`buildDietaryAgentRequest` 呼叫**：
  * `buildDietaryAgentRequest` 繼續使用 `screening.dishes`（已翻譯後的名單）發送給下游飲食助理 API，流程 100% 順暢！
* **`getCompanionReply` 草稿對話生成**：
  * 針對跨餐期紀錄，依據 `screening.meal_records` 生成溫馨對話預覽。

---

## 四、 測試與驗證計畫

### 🛠️ 測試情境一：標準單餐紀錄（帶明確餐期、數量與單位）
* **輸入 (Request JSON)**
  ```json
  {
    "user_prompt": "我早餐吃了兩個蛋餅和一杯無糖豆漿"
  }
  ```
* **預期 `screening` 輸出**
  ```json
  "screening": {
    "should_handle": true,
    "intent_category": "meal_record",
    "dishes": ["蛋餅", "無糖豆漿"],
    "meal_records": [
      {
        "meal_period": "早餐",
        "meal_items": [
          { "name": "蛋餅", "quantity": 2, "unit": "個" },
          { "name": "無糖豆漿", "quantity": 1, "unit": "杯" }
        ]
      }
    ]
  }
  ```
* **預期 `companion_reply` 輸出**
  ```text
  "幫你整理好早餐的「2個蛋餅與1杯無糖豆漿」草稿囉！請在下方確認一下內容是否正確，按下確認就可以幫你存起來囉！✨"
  ```

---

### 🛠️ 測試情境二：模糊時間紀錄（無明確餐期，由系統時間推算）
假設當前本地系統時間為 `12:30`：
* **輸入 (Request JSON)**
  ```json
  {
    "user_prompt": "我剛剛吃了一碗排骨麵和一顆滷蛋"
  }
  ```
* **預期 `screening` 輸出**
  ```json
  "screening": {
    "should_handle": true,
    "intent_category": "meal_record",
    "dishes": ["排骨麵", "滷蛋"],
    "meal_records": [
      {
        "meal_period": "中餐", // 依 12:30 系統時間推算為中餐
        "meal_items": [
          { "name": "排骨麵", "quantity": 1, "unit": "碗" },
          { "name": "滷蛋", "quantity": 1, "unit": "顆" }
        ]
      }
    ]
  }
  ```
* **預期 `companion_reply` 輸出**
  ```text
  "幫你整理好中餐的「1碗排骨麵與1顆滷蛋」草稿囉！請在下方確認一下內容是否正確，按下確認就可以幫你存起來囉！✨"
  ```

---

### 🛠️ 測試情境三：跨餐期單句紀錄（單一句子包含多個餐期）
* **輸入 (Request JSON)**
  ```json
  {
    "user_prompt": "我上午吃了一顆茶葉蛋，下午喝了一杯大杯無糖綠茶"
  }
  ```
* **預期 `screening` 輸出**
  ```json
  "screening": {
    "should_handle": true,
    "intent_category": "meal_record",
    "dishes": ["茶葉蛋", "大杯無糖綠茶"],
    "meal_records": [
      {
        "meal_period": "早餐",
        "meal_items": [
          { "name": "茶葉蛋", "quantity": 1, "unit": "顆" }
        ]
      },
      {
        "meal_period": "其他",
        "meal_items": [
          { "name": "大杯無糖綠茶", "quantity": 1, "unit": "杯" }
        ]
      }
    ]
  }
  ```
* **預期 `companion_reply` 輸出**
  ```text
  "幫你整理好早餐的「1顆茶葉蛋」，以及其他的「1杯大杯無糖綠茶」草稿囉！請在下方確認一下內容是否正確，按下確認就可以幫你存起來囉！✨"
  ```

---

### 🛠️ 測試情境四：口語省略數量紀錄（自動補齊預設數量與單位）
* **輸入 (Request JSON)**
  ```json
  {
    "user_prompt": "今天晚餐吃肯德基炸雞、大薯跟可樂"
  }
  ```
* **預期 `screening` 輸出**
  ```json
  "screening": {
    "should_handle": true,
    "intent_category": "meal_record",
    "dishes": ["肯德基炸雞", "大薯", "可樂"],
    "meal_records": [
      {
        "meal_period": "晚餐",
        "meal_items": [
          { "name": "肯德基炸雞", "quantity": 1, "unit": "份" },
          { "name": "大薯", "quantity": 1, "unit": "份" },
          { "name": "可樂", "quantity": 1, "unit": "杯" }
        ]
      }
    ]
  }
  ```
* **預期 `companion_reply` 輸出**
  ```text
  "幫你整理好晚餐的「1份肯德基炸雞與1份大薯與1杯可樂」草稿囉！請在下方確認一下內容是否正確，按下確認就可以幫你存起來囉！✨"
  ```

---

### 🛠️ 測試情境五：點心/宵夜紀錄（餐期統一歸類為「其他」）
* **輸入 (Request JSON)**
  ```json
  {
    "user_prompt": "剛剛宵夜吃了一包洋芋片跟一罐啤酒"
  }
  ```
* **預期 `screening` 輸出**
  ```json
  "screening": {
    "should_handle": true,
    "intent_category": "meal_record",
    "dishes": ["洋芋片", "啤酒"],
    "meal_records": [
      {
        "meal_period": "其他", // 宵夜/點心依規格統一歸類為「其他」
        "meal_items": [
          { "name": "洋芋片", "quantity": 1, "unit": "包" },
          { "name": "啤酒", "quantity": 1, "unit": "罐" }
        ]
      }
    ]
  }
  ```
* **預期 `companion_reply` 輸出**
  ```text
  "幫你整理好其他的「1包洋芋片與1罐啤酒」草稿囉！請在下方確認一下內容是否正確，按下確認就可以幫你存起來囉！✨"
  ```

