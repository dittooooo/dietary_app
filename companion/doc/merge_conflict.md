# Companion Agent 檔案差異與 V2 實作進度分析報告

本文件針對當前工作區中的三個核心 JS 檔案與原定開發手冊 [plan.md](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/doc/plan.md) 進行比對，並梳理即將實作的 [adjust_v2.md](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/adjust_v2.md) 需求之開發進度。

---

## 一、 當前 JS 檔案與 [plan.md](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/doc/plan.md) (V1) 的差異對照

目前工作區的檔案因為部分併入了您朋友的修改，與原始的 V1 手冊 [plan.md](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/doc/plan.md) 存在以下出入：

### 1. [companion-agent.js](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-agent.js)
* **API 回覆生成調用方式差異**：
  * **當前檔案（第 91-98 行）**：使用 `await` 調用，並額外傳入了 `userPrompt` 與 `dietaryAgentError`：
    ```javascript
    companion_reply: await buildCompanionReply({
      userPrompt: user_prompt,
      screening: openAiResult.screening,
      emotion: openAiResult.emotion,
      dietaryAgentResponse,
      dietaryAgentRequest: openAiResult.dietary_agent_request, 
      dietaryAgentError
    })
    ```
  * **[plan.md](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/doc/plan.md) 手冊（第 618-623 行）**：原始為同步調用，且傳入參數較少：
    ```javascript
    companion_reply: buildCompanionReply({
      screening: openAiResult.screening,
      emotion: openAiResult.emotion,
      dietaryAgentResponse,
      dietaryAgentRequest: openAiResult.dietary_agent_request
    })
    ```

### 2. [companion-agent-services.js](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-agent-services.js)
* **引用模組變更**：
  * **當前檔案（第 4-7 行）**：引入了意圖分析 `runOpenAIFlow` (重新命名為 `runLLMAnalysis`) 以及新增的第二段 LLM 回覆生成 `generateCompanionReply` (重新命名為 `runLLMReply`)：
    ```javascript
    const {
      runOpenAIFlow: runLLMAnalysis,
      generateCompanionReply: runLLMReply
    } = require("./companion-llm");
    ```
  * **[plan.md](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/doc/plan.md) 手冊（第 380-381 行）**：原始僅引入第一階段的 LLM 流程：
    ```javascript
    const { runOpenAIFlow: runLLM } = require("./companion-llm");
    ```
* **第一段流程內部名稱呼叫變更**：
  * **當前檔案（第 49-51 行）**：
    ```javascript
    const result = await runLLMAnalysis(userPrompt);
    ```
  * **[plan.md](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/doc/plan.md) 手冊（第 430 行）**：
    ```javascript
    const result = await runLLM(userPrompt);
    ```
* **【重要警訊】Dietary Agent API 連線端點衝突**：
  * **當前檔案（第 80 行）**：使用的是舊有 (V1) 端點：
    ```javascript
    const response = await fetch(`${baseUrl}/dietary-agent/ask`, {
    ```
  * **您朋友的分支 (Remote)**：已更新為新端點：
    ```javascript
    const response = await fetch(`${baseUrl}/api/dietary/ask-weekly-analysis`, {
    ```

### 3. [companion-llm.js](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-llm.js)
* **提示詞常數拆分與新增**：
  * **當前檔案（第 4 行與第 28 行）**：原始的 `SYSTEM_PROMPT` 被重新命名為 `ANALYSIS_SYSTEM_PROMPT`（第 4 行），並且新增了第二階段生成最終對話用的 `REPLY_SYSTEM_PROMPT`（第 28 行）。
  * **[plan.md](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/doc/plan.md) 手冊（第 80 行）**：只有單一全域的 `SYSTEM_PROMPT`。
* **API 設定模組化重構**：
  * **當前檔案（第 138-148 行）**：將取得 API 金鑰與 Model 名稱封裝成了 `getApiKey()` 與 `getModel()` 函數。
  * **[plan.md](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/doc/plan.md) 手冊**：無此函數，直接於 `runOpenAIFlow` 內部讀取 `process.env`。
* **新增 `generateCompanionReply` 函數**：
  * **當前檔案（第 269-308 行）**：定義了利用 OpenAI Responses API 生成最終自然語言回覆的 `generateCompanionReply` 函數。
  * **[plan.md](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/doc/plan.md) 手冊**：完全沒有此函數。

---

## 二、 [adjust_v2.md](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/adjust_v2.md) 實作進度 analysis

以下梳理 V2 的需求中，有哪些是「已做一半（代碼已部分存在但未完整串接）」、「完全未動」，以及「已完成」的部分：

| 需求項目 | 狀態 | 詳細說明與程式位置 |
| :--- | :--- | :--- |
| **2. 數值類提問免責聲明** | <font color="orange">**做一半**</font> | 1. **LLM Prompt 指令**：已定義於 `REPLY_SYSTEM_PROMPT` 中，但在英文規則中寫成了 "僅供參考"，而非 V2 要求的 `"關於數值類提問，本精靈只可提供參考數值"`。📍 [companion-llm.js: L36](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-llm.js#L36)<br>2. **後端代碼防呆**：在 `buildCompanionReply` 中利用關鍵字與正則表達式進行二次驗證的防呆機制**完全未實作**。 |
| **3. LLM 動態生成最終回覆** | <font color="orange">**做一半**</font> | 1. **LLM 回覆生成函數**：已在 `companion-llm.js` 中實現。📍 [companion-llm.js: L269](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-llm.js#L269)<br>2. **API 入口呼叫處**：已改為 `await` 非同步呼叫並傳入新參數。📍 [companion-agent.js: L91](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-agent.js#L91)<br>3. **【未完成核心】服務層串接**：當前 [companion-agent-services.js: L99-L136](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-agent-services.js#L99-L136) 的 `buildCompanionReply` 依然是**舊的 V1 同步拼接程式碼**。它根本沒有改為 `async`，也沒有調用 `runLLMReply`，也沒有實作醫療/非飲食攔截的 Fallback 保底機制。 |
| **4. 讀取最外層 .env 檔案** | <font color="red">**完全未動**</font> | [companion-agent.js: L5](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-agent.js#L5) 依然維持舊有的 `require("dotenv").config();`，並未改為讀取 `../../.env` 及其 Fallback 邏輯。 |

---

## 三、 合併與重構的下一步行動指南

為了完成 V2 的重構與安全的合併，我們需要手動解決 `companion-agent-services.js` 的衝突，並依據 [adjust_v2.md](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/adjust_v2.md) 補齊遺漏的程式碼：

1. **修正 `companion-agent.js` 的環境變數載入**：
   * 將 `require("dotenv").config()` 改為讀取外層 `../../.env`。
2. **完整重構 `buildCompanionReply`（位於 `companion-agent-services.js`）**：
   * 改為 `async` 函數。
   * 保留 Code-level 的醫療診斷與非飲食諮詢攔截（回傳寫死的文字，以節省 API 費用）。
   * 呼叫 `runLLMReply` 取得 LLM 動態潤飾回覆，並包裝於 `try...catch` 中。
   * 若 LLM 執行失敗，則進入保底 Fallback 機制（使用同理心前綴與 Dietary Agent 原始資料拼接）。
   * 在最末端實作程式碼防呆：若為數值提問且內容未含 `關於數值類提問，本精靈只可提供參考數值`，則強制在尾端拼接補上。
3. **對齊遠端 API 端點路徑**：
   * 將 `callDietaryAgent` 內的請求路徑由舊的 `/dietary-agent/ask` 修改為 `/api/dietary/ask-weekly-analysis`。
