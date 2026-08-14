# 第五次程式碼修正計畫 - Dietary Agent 介面參數調整與字典結構重構 (adjust_v5.md)

## 📌 變更概要說明 (Overview)

本修正計畫旨在規範 Companion Agent 與下游服務 Dietary Agent（飲食助理後端）之間的 API 傳輸介面重構，並針對餐點數量進行更精準的結構化處理。

在先前的架構中，Companion Agent 傳送給 Dietary Agent 的餐點清單為一維陣列 `dish_names: ["炸雞", "拉麵"]`。這導致 Dietary Agent 無法得知使用者針對各餐點所輸入的具體份數/數量（例如「吃了 2 塊炸雞和 1 碗拉麵」），使得營養學計算只能一律假設為預設值 1 份。

為了提昇營養分析與熱量累積計算的精確度，系統將執行以下三項主要修正：
1. **傳輸介面變更**：往後發送給 Dietary Agent (`/dietary-agent/ask`) 的請求 Payload 中，原 `dish_names` 欄位更名為 **`dish_info_list`**，資料型態由原本的「字串陣列 (Array)」改為 **「字典物件 (Dictionary / Object)」**。
2. **Key-Value 結構與欄位清理**：`dish_info_list` 以 `dish_name` 作為 Key，`amount`（份數/數量）作為 Value。原有的 `dish` / `dishes` 陣列欄位將於下游傳輸介面與 Companion 內部回應中全面移除，由 `dish_info_list` 取代。
3. **數量預設機制 (`amount`)**：若使用者在輸入訊息中有提及明確數量（如「2塊」、「3份」），LLM 解析出的 `quantity` 將會填入作為 `amount`；若 Prompt 中未明確提及數量，系統將自動 **預設為 1**。

---

## 一、 變更核心共識 (Core Consensus)

1. **Dietary Agent API Payload 結構替換**：
   * 舊結構：`"dish_names": ["炸雞", "拉麵"]`
   * 新結構：`"dish_info_list": { "炸雞": 1, "拉麵": 2 }`

2. **舊欄位 `dishes` 徹底清理**：
   * Companion Agent 在第一階段意圖篩選回傳物 `screening` 之中，將不再使用 `dishes` 陣列，改為統一輸出 `dish_info_list` 物件。

3. **`amount` 的提取與保底預設**：
   * 來源：從第一階段 LLM 解析出的 `meal_records` -> `meal_items` 中的 `quantity` 提煉。
   * 規則：若 `quantity` 為正數字則取用；若為 `undefined`、`null` 或非數字，則預設賦予數值 `1`。

4. **翻譯模組 (`translateDishes`) 對應調整**：
   * 當進行花俏餐點/飲料名稱翻譯（例如「起司瀑布超厚牛肉堡」->「牛肉漢堡」）時，需確保 Key 替換為標準品名後，對應的 `amount` 數量能夠完整轉移至新 Key 下，避免份數遺失。

---

## 二、 詳細修改檔案與程式碼區段 (Detailed Changes)

### 1. 修改 [companion-llm.js](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-llm.js)

* **修改目標**：更新 `sanitizeScreening(raw)` 容錯防呆與資料提煉函數。
* **位置**：約第 88 行至 128 行。
* **詳細修改內容**：
  - 移除原 `extractedNames` 陣列與 `result.dishes` 賦值邏輯。
  - 新增 `dishInfoList` 物件提煉邏輯，走訪 `meal_records` 裡每個餐期的 `meal_items`：
    * 讀取 `item.name` 作為 Key。
    * 讀取 `item.quantity`，若存在且大於 0 則使用，否則預設為 `1` 作為 Value。
  - 將結果寫入 `result.dish_info_list = dishInfoList`，並確保刪除舊有的 `result.dishes`。

---

### 2. 修改 [companion-agent-services.js](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-agent-services.js)

* **修改目標 A**：更新 `buildDietaryAgentRequest(screening, message)` 請求組裝函數。
* **位置**：約第 19 行至 51 行。
* **詳細修改內容**：
  - 讀取 `screening.dish_info_list`。
  - 判斷若 `dish_info_list` 為空物件（`Object.keys(dish_info_list).length === 0`）時回傳 `null`。
  - 組裝傳給 Dietary Agent 的 Payload 物件：
    ```javascript
    return {
      question,
      question_type,
      dish_info_list
    };
    ```

* **修改目標 B**：更新 `runOpenAIFlow(userPrompt)` 裡面的餐點翻譯整合區塊。
* **位置**：約第 64 行至 81 行。
* **詳細修改內容**：
  - 當 `intent_category === "dish_advice"` 且 `screening.dish_info_list` 有值時：
  - 取出 `dish_info_list` 的所有 Keys 進行 `translateDishes` 翻譯。
  - 建立新的 `translatedDishInfoList` 物件，將翻譯後的品名作為 Key，並保留原本的 `amount` 數量作為 Value。
  - 將 `result.screening.dish_info_list` 指派為 `translatedDishInfoList`。

---

### 3. 修改 [companion-agent.js](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-agent.js)

* **修改目標**：更新 Express 路由主處理函數 `handleCompanionAsk` 的 Response 結構。
* **位置**：約第 103 行至 110 行。
* **詳細修改內容**：
  - 將回傳給前端 JSON 結構中的 `screening.dishes` 欄位更名/替換為：
    `dish_info_list: openAiResult.screening.dish_info_list`

---

### 4. 修改測試檔與文件

* **[test_prompt.js](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/test_prompt.js)**：更新 Prompt 測試腳本，確保 Log 印出時包含 `dish_info_list`。
* **[fromendConnectcompanion.md](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/doc/fromendConnectcompanion.md)**：同步更新 API 介面範例說明。

---

## 三、 API 請求與回應 Payload 範例對比 (Payload Comparison)

### 1. 發送給 Dietary Agent 的 POST `/dietary-agent/ask` Body

* **修改前 (Before)**：
  ```json
  {
    "question": "中午吃了 2 塊炸雞，晚上還可以吃 1 碗拉麵嗎？",
    "question_type": "dish_comparison",
    "dish_names": [
      "炸雞",
      "拉麵"
    ]
  }
  ```

* **修改後 (After)**：
  ```json
  {
    "question": "中午吃了 2 塊炸雞，晚上還可以吃 1 碗拉麵嗎？",
    "question_type": "dish_comparison",
    "dish_info_list": {
      "炸雞": 2,
      "拉麵": 1
    }
  }
  ```

### 2. Companion Agent API (`POST /companion/ask`) 之 Response 結構

* **修改前 (Before)**：
  ```json
  {
    "success": true,
    "screening": {
      "should_handle": true,
      "intent_category": "dish_advice",
      "question_type": "dish_comparison",
      "confidence": 0.95,
      "dishes": ["炸雞", "拉麵"],
      "meal_records": [...]
    },
    ...
  }
  ```

* **修改後 (After)**：
  ```json
  {
    "success": true,
    "screening": {
      "should_handle": true,
      "intent_category": "dish_advice",
      "question_type": "dish_comparison",
      "confidence": 0.95,
      "dish_info_list": {
        "炸雞": 2,
        "拉麵": 1
      },
      "meal_records": [...]
    },
    ...
  }
  ```

---

## 四、 API Response Payload 精簡與 Console Log 重構 (Response Slimming & Logging)

### 1. 變更背景與目標
先前 Companion Agent 傳給 Flutter 前端（`POST /companion/ask`）的回傳資料包含整包內部分析物件（例如多層巢狀的 `screening`、`emotion` 情緒分析細節、`dietary_agent_request` 與龐大的 `dietary_agent_response` 原始數據）。

這造成了兩個問題：
1. **傳輸過大 (Over-fetching)**：移動端傳輸多餘的內部除錯資料，增加網路負擔與延遲。
2. **前後端合約不齊**：前端 Flutter (`diet_service.dart`) 原本企圖在 JSON 頂層存取 `intent_category` 與 `meal_records`，但後端卻藏在 `screening` 巢狀物件內部。

因此，系統進行 Response 瘦身與 Log 重構：
* **前端 API**：只保留 UI 渲染與互動所必需的欄位，並將 `intent_category` 與 `meal_records` **平鋪 (Flatten) 至頂層**。
* **後端 Log**：將被精簡掉的內部分析細節轉為後端伺服器控制台 (Console) 的結構化 Log，方便維護與 Debug。

---

### 2. 精簡後的 Companion API 回應結構 (`POST /companion/ask`)

```json
{
  "success": true,
  "companion_reply": "今天想吃炸雞排呀！炸雞排熱量大約在 550～600 大卡...",
  "intent_category": "dish_advice",
  "meal_records": [],
  "dietary_agent_error": null
}
```

---

### 3. 詳細修改檔案與區段 (Detailed Code Changes)

#### A. 修改 [companion-agent.js](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-agent.js)
* **修改目標**：重構 `handleCompanionAsk` 回傳之 JSON 結構，並加入結構化 Console Log。
* **修改內容**：
  1. 將 `res.json({...})` 的回傳欄位調整為精簡後的頂層結構（包含 `success`, `companion_reply`, `intent_category`, `meal_records`, `dietary_agent_error`）。
  2. 在 API 執行生命週期中加入 console log：
     * **[階段 1]** 收到 User Prompt、LLM 第一階段預檢 (Screening) 結果與情緒 (Emotion) 分析結果。
     * **[階段 2]** 呼叫 Dietary Agent API 的狀態（成功/失敗）與數據摘要。
     * **[階段 3]** 最終產出的 `companion_reply` 內容摘要與成功回應 Log。

#### B. 修改 [diet_service.dart](file:///c:/Users/User/Documents/Github_Repo/dietary_app/frontend/lib/services/diet_service.dart)
* **修改目標**：簡化 `sendCompanionUserPrompt` 中的 JSON 解包與讀取邏輯。
* **修改內容**：
  * 直接讀取頂層的 `data['intent_category']` 與 `data['meal_records']`，簡化原有的備用判斷邏輯。

---

### 4. 後端 console.log 輸出規範範例 (Backend Log Example)

伺服器運行時控制台將印出以下結構化 Log：

```text
======================================================================
[Companion Agent] 📥 收到使用者提問: "我吃炸雞排適合嗎？"
======================================================================

------------------ [LLM 階段 1：意圖與情緒分析] ------------------
🎯 意圖預檢 (Screening): {
  should_handle: true,
  intent_category: 'dish_advice',
  question_type: 'single_dish',
  dish_info_list: { '炸雞排': 1 }
}
💖 情緒分析 (Emotion): {
  primary_emotion: 'anxiety',
  needs_empathy: true,
  companion_tone: 'encouraging'
}

------------------ [Dietary Agent 飲食後端服務] ------------------
🚀 發送請求 Payload: { question: "...", dish_info_list: { '炸雞排': 1 } }
✅ 成功取得回應 (Dish Advice: 1 筆, Nutrition: 1 筆)

------------------ [LLM 階段 2：陪伴式回覆重組] ------------------
💬 生成最終對話: "今天想吃炸雞排呀！炸雞排熱量大約在 550～600 大卡..."

======================================================================
[Companion Agent] 📤 已成功回應前端 (Intent: dish_advice)
======================================================================
```

