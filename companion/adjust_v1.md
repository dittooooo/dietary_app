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

---

## 專案多語言架構設計討論 (Architecture Discussion)

### 問題背景
在當前的專案架構中，採用了多種不同的程式語言與框架，包括 **Java (Spring Boot)**、**Flutter (Dart)**，以及 **JavaScript (Node.js + Express)**。針對「為何需要使用這麼多種程式語言，以及 Companion Agent 為何選擇 JavaScript + Express」進行以下架構與設計上的說明：

### 1. 為什麼整個專案使用那麼多不同的語言？
現代微服務（Microservices）與領域驅動設計（Domain-Driven Design, DDD）的核心原則之一就是**「以最適當的工具解決特定的問題 (Right tool for the right job)」**。各個技術選型背後的定位與目的如下：

* **Flutter (前端行動 App)：**
  * **定位**：跨平台行動端使用者介面。
  * **目的**：飲食記錄與健康管理高度依賴行動端（隨時隨地記錄、拍照等）。Flutter 可以使用單一 codebase (Dart) 同時編譯出 iOS 與 Android 兩大平台的高效能原生 App，大幅節省開發與維護成本，並提供流暢的 UI/UX。
* **Java / Spring Boot (Dietary Agent & 核心後端業務服務)：**
  * **定位**：企業級業務邏輯、資料庫存取與安全性管理。
  * **目的**：Spring Boot 是企業級後端開發的行業標準，具備極佳的強型態安全（Type Safety）、穩定的多執行緒併發處理能力與成熟的生態系（例如使用 Spring Security 驗證 JWT Token、Spring Data JPA 進行資料庫操作）。Dietary Agent 作為需要處理具體飲食推論、整合使用者 Profile 與進行敏感資料存取的核心後端，使用 Java + Spring Boot 能確保系統的強健性與易維護性。
* **JavaScript / Node.js + Express (Companion Agent / API Gateway / 中繼協調服務)：**
  * **定位**：輕量級 API Gateway、請求攔截與流程控制中繼站。
  * **目的**：負責銜接前端 App 與後端的多個 AI 服務，進行初步的 LLM 語意拆解、輸入驗證、參數攔截與請求分流（如下詳述）。

---

### 2. 為什麼 Companion Agent 要使用 JavaScript + Express？
Companion Agent 在架構中扮演的是 **API 閘道 (API Gateway) 與中繼器 (Orchestrator)** 的角色。選擇 Node.js + Express 的關鍵考量包括：

* **非阻塞 I/O 與高併發 (Asynchronous & Non-blocking I/O)：**
  * Node.js 採用單執行緒、事件驅動與非阻塞 I/O 的特性，非常適合用來處理大量「I/O 密集型 (I/O-Bound)」的請求（例如：接收前端 HTTP 請求、呼叫外部 OpenAI API、轉發請求給 Java 後端）。這比多執行緒的傳統後端架構能以更低的記憶體和 CPU 資源承受更高的併發請求量。
* **輕量、啟動快速 (Lightweight & Low Overhead)：**
  * Express 是一個極簡的 Web 框架，沒有臃腫的開箱即用功能。這使 Companion Agent 可以保持極度輕量、部署迅速，非常適合微服務架構或 Serverless (如 AWS Lambda, Google Cloud Functions) 的無伺服器部署方案。
* **前端與中繼層的語言一致性：**
  * JavaScript/TypeScript 是 Web 開發的通用語言。使用 JavaScript 撰寫 API 中繼站，在 JSON 資料格式處理上（如解析前端 Payload、整理 OpenAI Tool Calls 格式）極為自然且無縫。
* **強大的軟體生態系 (NPM Ecosystem)：**
  * NPM 擁有全宇宙最龐大的第三方套件庫。對於 Companion Agent 而言，可以輕鬆整合如官方的 `@google/generative-ai` 或 `openai` SDK，以及 `zod` / `joi` 等強大的資料驗證套件，極大加速了 API 串接與參數攔截機制的實作。

### 總結
透過這種**混和語言架構 (Polyglot Architecture)**，專案得以兼顧**「前端跨平台開發效率 (Flutter)」**、**「中繼層高併發與輕量傳輸 (JS + Express)」**以及**「後端業務邏輯與系統穩定性 (Java + Spring Boot)」**。每種語言在各自擅長的領域發揮最大優勢，再透過標準化的 RESTful API 進行溝通，這是現代高品質軟體系統非常經典且穩健的架構設計。

---

## 模糊輸入與防呆攔截機制討論 (Ambiguous Input & Safeguard Discussion)

### 1. 目前專案對於輸入較模糊的內容，是如何處理？在哪裡可以看到相關程式碼？
在當前架構設計中，我們移除了「需要維護上下文狀態的引導補問機制（Stateful）」，改為採用**「無狀態的參數攔截與引導回覆機制（Stateless Safeguard & Guidance）」**。

具體運作流程如下：
1. **語意解析與特徵擷取 (OpenAI)**：
   - 當使用者輸入模糊或不完整句（如「晚餐要吃這個嗎」或單純閒聊「你好」），OpenAI 會呼叫 `screen_user_request` 工具。在此過程中，由於沒有具體食物或意圖模糊，LLM 會將 `question_type` 判定為 `"unknown"`，且提取的 `dishes` 陣列為空。
   - 相關程式碼請參考 [companion-llm.js: L9-L32 (SYSTEM_PROMPT)](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-llm.js#L9-L32) 與 [companion-llm.js: L40-L86 (screen_user_request Schema)](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-llm.js#L40-L86)。
2. **三元素參數嚴格攔截**：
   - 在傳遞給後端 Dietary Agent 之前，`buildDietaryAgentRequest` 函數會針對 `question`、`question_type` 及 `dish_names` 進行嚴格的有效性驗證。
   - 只要有任何一個引數不符條件（如 `question_type === "unknown"` 或 `dish_names` 長度為 0），便會**立刻攔截並回傳 `null`，完全不呼叫後端 Dietary Agent**。
   - 相關程式碼請參考 [companion-agent-services.js: L18-L45 (buildDietaryAgentRequest)](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-agent-services.js#L18-L45)。
3. **引導式陪伴回覆組裝**：
   - 如果意圖被判定為飲食諮詢（`should_handle === true`）但因為上述三元素檢查未過而被攔截時，`buildCompanionReply` 會判斷是缺漏了料理（`dishes` 為空）還是無法識別問題類型，並回傳相對應的具體引導話術（而不是丟出錯誤或空白回覆）。
   - 相關程式碼請參考 [companion-agent-services.js: L111-L121 (buildCompanionReply 攔截處理)](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-agent-services.js#L111-L121)。

---

### 2. 這樣的補救措施夠嗎？
**「足夠確保後端穩定，但使用者體驗上還有優化空間。」**

#### 為什麼說它足夠？
* **百分之百保護後端**：後端 Java Dietary Agent 可以完全信任傳入的三元素 Payload，無需撰寫額外的容錯或特異語意解析。
* **輕量與無狀態**：Server 不需要快取、資料庫或 Session 來記憶對話歷史（State），極大地維持了 API 中繼站的高效能與易擴展性。
* **具備明確指引**：相比於回報系統錯誤，提供具體的錯誤說明與提問範例，能引導使用者修正提問。

#### 還有哪些不足與痛點？
* **重覆的引導語**：若使用者持續輸入無意義或模糊的內容，系統只會重覆返回幾句寫死的引導話術，顯得有些生硬與機械化。
* **閒聊拒絕過於死板**：對於非飲食相關話題（`should_handle === false`），系統會以固定的硬編碼文字婉拒，破壞了「Companion (陪伴者)」的對話體驗。

---

### 3. 未來可以如何進一步補強？

#### 補強方案一：LLM 閒聊拒絕生成 (LLM-generated Out-of-Scope Response) — 推薦度：⭐⭐⭐⭐
* **概念**：當 LLM 判定為非飲食問題時，不由程式進行冷冰冰的寫死拒絕，而是讓 LLM 根據當前輸入，自己生成一段溫暖的、導回飲食正軌的陪伴式回覆。
* **實作方式**：
  1. 在 `screen_user_request` 的 Tool 定義或 LLM 返回欄位中，增加 `companion_fallback_message` (string) 欄位。
  2. 若 `should_handle` 為 `false`，則直接回傳 LLM 產生的文字。
  3. 例如使用者打字：「我今天工作好累。」LLM 回覆：*「辛苦你了！累的時候特別容易想吃甜食或炸雞來放鬆。如果想知道怎麼吃點好吃的又不會有負擔，隨時可以告訴我喔！」*

#### 補強方案二：快捷推薦問句選項 (Quick Suggestions API) — 推薦度：⭐⭐⭐⭐⭐
* **概念**：當系統攔截到模糊輸入時，後端不要只給提示文字，而是**主動附帶幾個推薦的具體問句**。前端將這些問句渲染為點擊按鈕，點擊後自動送出。
* **實作方式**：
  1. 後端 `POST /companion/ask` 回傳 JSON 中，若被攔截，多帶一個陣列 `suggestions`。
  2. 例如使用者僅輸入「炸雞」，攔截後回傳：
     ```json
     {
       "companion_reply": "您提到了『炸雞』，想了解關於它的什麼呢？",
       "suggestions": ["減脂期吃炸雞好嗎？", "炸雞熱量是多少？", "炸雞跟烤雞哪個健康？"]
     }
     ```
  3. 前端 Flutter 將建議問句轉化成按鈕，使用者點一下即可送出，免除打字心智負擔。

#### 補強方案三：前端 UI 層級的引導與驗證 (Frontend UX Guide) — 推薦度：⭐⭐⭐
* **概念**：在使用者送出前，就將不良輸入擋下。
* **實作方式**：
  1. 行動端輸入框的 Placeholder 定期輪播健康飲食問句範例。
  2. 在聊天室初始狀態提供常見提問的推薦按鈕（Chips）。
  3. 限制提問的最少字數（例如必須大於 3 個字才能送出）。

