# Companion Agent Server 調整規劃 (V1)

本文件整理了針對 Companion Agent Server 的五大調整需求、對應的程式碼受影響範圍以及重構設計方案。

---

## 調整需求與實作設計
### 1. OpenAI 錯誤攔截與無 Fallback 機制
* **現狀：** 
  當呼叫 `runOpenAIFlow` 發生錯誤時，系統會自動切換到 `runFallbackFlow` 進行本地 Rule-based 的保底分析，最後將 `llm_fallback_used` 設為 `true` 回傳前端。
* **調整方案：**
  * **移除 fallback 流程**：完全刪除 `runFallbackFlow` 及其相關的本地保底函數（如 `fallbackScreening`、`fallbackEmotion`、`fallbackDishesExtraction`、`fallbackClassifyQuestionType`）。
  * **錯誤直接中斷與拋出**：在 API 中繼站 `handleCompanionAsk` 中，若 OpenAI 呼叫失敗，將直接回傳特定 HTTP 狀態碼與 JSON 錯誤格式，由前端根據 `error_code` 決定顯示畫面。
  * **錯誤回應格式與狀態碼設計**：
    * **引數錯誤 (HTTP 400 Bad Request)**
      當前端發送的請求不含 `user_prompt` 或其值為空字串。
      ```json
      {
        "success": false,
        "error_code": "BAD_REQUEST",
        "error_message": "The 'user_prompt' field is required and must be a non-empty string."
      }
      ```
    * **OpenAI 服務異常 (HTTP 502 Bad Gateway)**
      當 OpenAI API 呼叫失敗（網路超時、API Key 錯誤、配額用盡等）。
      ```json
      {
        "success": false,
        "error_code": "OPENAI_SERVICE_ERROR",
        "error_message": "Failed to communicate with OpenAI API. Please try again later.",
        "debug_message": "OpenAI API error 429: Insufficient quota."
      }
      ```
      *說明：前端可依據 `OPENAI_SERVICE_ERROR` 顯示對應的「服務暫時不可用」提示，後端則將具體抓出的 OpenAI 錯誤原因記錄於 `debug_message` 中。*
    * **伺服器內部未知錯誤 (HTTP 500 Internal Server Error)**
      當 Express 後端發生未預期的 runtime exception。
      ```json
      {
        "success": false,
        "error_code": "INTERNAL_SERVER_ERROR",
        "error_message": "An unexpected error occurred on the server."
      }
      ```

---

### 2. 省略硬編碼 (Hardcoded) 的 Pre-check / Post-check 函數
* **現狀：** 
  目前程式碼中有寫死的 regex 比對函數（如 `isMedicalOutOfScope`、`isLikelyFoodRelated`、`looksLikeComparison`）來過濾醫療詞、判斷是否與食物相關、判定是否為比較問題。
* **調整方案：**
  * **刪除寫死函數**：全面移除 `companion-agent-helpers.js` 中的 `isMedicalOutOfScope`、`isLikelyFoodRelated`、`looksLikeComparison`。
  * **完全信賴 LLM 語意解析**：將這些過濾與判斷邏輯完全移交給 LLM，並撰寫結構更加嚴謹、指令更明確的 `SYSTEM_PROMPT`。由于已完全刪除「補問機制」，LLM 的 Schema 中也將不再包含 `requires_more_context` 與 `missing_information` 欄位。
  * **系統 Prompt 優化草案**：
    ```markdown
    你是一個飲食推薦應用程式的 Companion Agent。你的任務是分析使用者的 Prompt，並決定意圖、問題類型、情緒，以及提取料理名稱。
    
    你必須同時呼叫 "screen_user_request" 與 "analyze_emotion" 兩個工具。
    
    【screen_user_request 的判定準則】：
    1. should_handle (boolean): 
       - 若是關於飲食、食物、餐點推薦或熱量查詢，設為 true。
       - 若是敏感醫療診斷、處方藥物、疾病治療或尋求醫師診斷（如「吃什麼藥治胃潰瘍」），設為 false。
       - 若是一般閒聊或與飲食無關的話題，設為 false。
    2. intent_category (string):
       - "dish_advice": 諮詢飲食建議或推薦。
       - "meal_record": 記錄飲食。
       - "medical_out_of_scope": 提及藥物、處方、疾病治療、病名確診、醫生等醫療問題。
       - "general_chat": 一般閒聊或無關內容。
    3. question_type (string):
       - "single_dish": 使用者詢問單一食物或餐點。
       - "dish_comparison": 使用者比較多個食物（例如「A 跟 B 哪個好」、「A vs B」）。
       - "unknown": 非上述兩者。
    4. dishes (array of string):
       - 提取使用者輸入中提及的所有具體食物或飲料名稱（例如：["拉麵", "炸雞"]）。若沒有提到任何食物，返回空陣列。
    ```

---

### 3. 所有 LLM 相關的生成與配置集中於單一檔案
* **現狀：** 
  目前 LLM 相關的程式碼分散在三個檔案中（config、services、helpers）。
* **調整方案：**
  * 將與 LLM 相關的所有配置、API 呼叫與輸出清理（Sanitize）邏輯**整併至單一檔案**（例如命名為 `companion-llm.js` 或直接集中於 `companion-agent-services.js`）。
  * 外部只需要載入此 LLM 整合檔案，傳入使用者 `user_prompt`，即可得到結構化後的 LLM 分析結果，提升維護便利性。

---

### 4. 嚴格檢查傳遞給 Dietary Agent 的三個參數 (攔截機制)
* **現狀：** 
  目前在 `buildDietaryAgentRequest` 中，只有簡單檢查 `should_handle` 和 `requires_more_context`。若通過，則直接組裝並傳遞給 Dietary Agent。
* **調整方案：**
  * 在傳遞給 Dietary Agent 之前，針對 payload 的三個參數（`question`, `question_type`, `dish_names`）進行**強型態與嚴格的有效性驗證**：
    1. **`question`**：必須是**非空字串**（從 `user_prompt` 取得）。
    2. **`question_type`**：必須是**合法的列舉值**（如 `single_dish` 或 `dish_comparison`），且**不能**是 `"unknown"`。
    3. **`dish_names`**：必須是**長度大於 0 的陣列** (由於是飲食問題，必須包含至少一個被擷取出的料理名稱)。
  * **攔截邏輯**：只要這三個參數中**有任何一個不符合上述條件**，就立刻中斷、**完全不呼叫 Dietary Agent**，並在回覆中直接引導使用者（或者回傳錯誤提示），確保垃圾資料一個都不會往後傳遞。

---

### 5. 簡化前端輸入至僅有 `user_prompt`
* **現狀：** 
  前端傳入後端的資料包含 `message`、`context` (包含當前餐廳、選單資訊) 以及 `user_profile`。後端會使用 `createUserContext` 建立 Boolean 的上下文，一併轉為 JSON 丟給 OpenAI。
* **調整方案：**
  * **移除上下文依賴**：完全移除後端的 `createUserContext` 函數，以及對 `req.body.context` 和 `req.body.user_profile` 的所有讀取與處理。
  * **前端 Payload 簡化**：後端 `POST /companion/ask` 介面將僅接收 `{ "user_prompt": "使用者輸入的內容" }`，不再需要其他欄位。
  * **對應簡化**：LLM 呼叫 payload 將只把純文字的 `user_prompt` 作為 input 傳入，不再打包 context 物件，使前後端串接極度輕量化。

---

## 受影響檔案清單

以下為後續處理時需要修改/重構的檔案：
1. **[companion-agent.js](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-agent.js)**: 
   * 修改 API 接收參數為 `{ user_prompt }`。
   * 移除 `createUserContext`。
   * 修改錯誤處理 (catch)，若 OpenAI 失敗，捕獲具體錯誤並回傳設計好的 JSON 錯誤回應與對應的 HTTP 狀態碼。
2. **[companion-agent-services.js](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-agent-services.js)**:
   * 移除 `runFallbackFlow` 與 `buildCompanionReply` 中關於補問的邏輯（移除 `requires_more_context` 相關代碼）。
   * 合併 `companion-agent-config.js` 的 Prompt 與 Tools 定義，以及 `companion-agent-helpers.js` 的 LLM 回傳整理邏輯。
3. **[companion-agent-helpers.js](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-agent-helpers.js)**:
   * 刪除所有寫死的正則過濾函數與 fallback 函數。
   * 重新實作 `buildDietaryAgentRequest`，加入針對三參數（`question`, `question_type`, `dish_names`）的嚴格攔截檢查。
4. **[companion-agent-config.js](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-agent-config.js)**:
   * 內容整併至 LLM 服務檔案後，此檔案可被**刪除 [DELETE]**。
