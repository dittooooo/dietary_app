# Companion Agent Server 調整規劃 (V2)

本文件針對 Companion Agent Server 的第二輪調整需求進行分析，並提供具體的實作設計與程式碼修改指引，以便直接照著本文件進行維護與開發。

---

## 調整需求與實作設計

### 1. 意圖類別新增 `meal_record` 飲食紀錄 (列於延伸區塊)
* **需求說明**：
  * 此功能在本輪修改中先不實作，但規劃於「延伸區塊」中。
  * **功用**：當使用者輸入為飲食紀錄意圖（例如：「我早餐吃了蛋餅和豆漿」），系統會識別為 `meal_record`，並自動從 `user_prompt` 中擷取餐期（早餐/中餐/午餐/點心）以及具體的食物與數量。接著呼叫後端的飲食紀錄 API 進行儲存。
  * **補問機制**：如果使用者的輸入中缺少關鍵欄位（如未提到餐期，或是沒有具體食物），系統將進行引導補問，要求使用者補齊資訊。

---

### 2. 數值類提問免責聲明 (Disclaimer for Numerical Queries)
* **需求說明**：
  * 由於本專案的營養成分數據屬於粗估參考值，當使用者詢問營養成分、熱量、脂肪等數字類提問時，在回答後必須加上一個免責聲明：
    > **「關於數值類提問，本精靈只可提供參考數值」**
* **實作方案**：
  * **LLM Prompt 指令保障與低溫生成**：在最終生成 Companion Response 的 LLM System Prompt (`REPLY_SYSTEM_PROMPT`) 中，加入強制的生成準則，指示 LLM 若識別到數值相關提問，必須在結尾加上該免責聲明。同時，為確保 LLM 穩定且 100% 觸發此聲明，將 API 生成的 `temperature` 設定調低為 `0.2`。
  * 註：為了保持程式碼簡潔與信任大語言模型的語意分析能力，此功能完全由 LLM 的 Prompt 實現，移除後端硬編碼的關鍵字/正則防呆邏輯。

---

### 3. LLM 動態生成最終 Companion Response (非寫死格式)
* **需求說明**：
  * 目前的回覆格式是將同理心安撫前綴與 Dietary Agent 回傳的文字直接拼接，格式較為死板。
  * **調整方案**：將整個回覆生成流程交給 LLM。把「使用者原始問題」、「情緒分析結果（包含 needs_empathy）」以及「Dietary Agent 回傳的結構化資料」包裝成 Prompt 餵給 LLM，讓 LLM 重組並潤飾為一段更自然、溫馨且口語化的陪伴對話。
* **實作細節**：
  * 於 `companion-llm.js` 重構 `generateCompanionReply` 函數，呼叫標準的 OpenAI Chat Completions API (`/v1/chat/completions`)。
  * 將 `companion-agent-services.js` 的主要流程函數命名為 `getCompanionReply`，並修改為 `async` 函數，因為它需要等待 LLM 的生成結果。
  * 調整 `companion-agent.js` 中對 `getCompanionReply` 的調用，使用 `await` 接收非同步回傳值。

---

### 4. 讀取最外層 .env 檔案
* **需求說明**：
  * 目前 `.env` 檔案放在 `companion_js` 目錄下。為了方便集中管理，希望將其路徑改為讀取專案最外層（與 `frontend`、`backend`、`companion` 同級的資料夾）下的 `.env` 檔案。
* **實作方案**：
  * 在 `companion-agent.js` 的最上方，利用 Node.js 內建 of `path` 模組將路徑解析至專案根目錄，優先載入最外層目錄 `.env`，並保留本地 fallback 備用機制：
    ```javascript
    const path = require("path");
    const fs = require("fs");
    const outerEnvPath = path.resolve(__dirname, "../../.env");
    ```

---

## 受影響檔案與實作指引

### 1. [companion-agent.js](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-agent.js) (修改環境變數加載與異步調用)

* **修改 1：更改 `.env` 檔案載入路徑**
  改為優先讀取最外層目錄的 `.env` 檔案並附帶中文註解。
* **修改 2：將 `buildCompanionReply` 更名為 `getCompanionReply` 並以 `await` 調用**
  導入與調用皆變更為 `getCompanionReply`。

#### 【重要程式碼片段】

```javascript
// 載入環境變數設定檔 (.env)
const path = require("path");
const fs = require("fs");

// 定義最外層目錄 (與 companion 同級) 的 .env 路徑，以利進行集中管理
const outerEnvPath = path.resolve(__dirname, "../../.env");
if (fs.existsSync(outerEnvPath)) {
  // 如果最外層目錄的 .env 存在，則優先載入該環境變數檔
  require("dotenv").config({ path: outerEnvPath });
  console.log(`Loaded outer .env from: ${outerEnvPath}`);
} else {
  // 如果外層不存在，則讀取 companion_js 當前目錄的 .env 作為 Fallback 備用機制
  require("dotenv").config();
  console.log("Outer .env not found, loaded local .env instead.");
}
```

```javascript
      // 變動說明：
      // 1. 加上 await：呼叫 getCompanionReply 中控調度器以取得最終的對話文字（非同步操作）。
      // 2. 傳入 userPrompt：供 LLM 了解原始提問脈絡，並進行數值免責聲明的判定與產生。
      // 3. 傳入 dietaryAgentError：當下游服務發生錯誤時，供 LLM 保底機制做為友善引導。
      companion_reply: await getCompanionReply({
        userPrompt: user_prompt,
        screening: openAiResult.screening,
        emotion: openAiResult.emotion,
        dietaryAgentResponse,
        dietaryAgentRequest: openAiResult.dietary_agent_request,
        dietaryAgentError
      })
```

---

### 2. [companion-agent-services.js](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-agent-services.js) (重構回覆生成與改名)

* **修改 1：引入 `generateCompanionReply` 函數**
  導入對話重組生成模組（別名為 `runLLMReply`）。
* **修改 2：將原本 `buildCompanionReply` 改名為 `getCompanionReply` 並優化攔截邏輯**
  * 刪除舊的 `medical_out_of_scope` 獨立醫療過濾（醫療提問現在直接歸類為 `general_chat` 並走閒聊過濾分支）。
  * 在後端快速攔截非飲食問題或缺失關鍵參數的請求，省下 LLM API 費用。
  * 通過攔截後才呼叫 `runLLMReply` 進行生成。

#### 【重要程式碼片段】

```javascript
const {
  runOpenAIFlow: runLLMAnalysis,
  generateCompanionReply: runLLMReply
} = require("./companion-llm");
```

```javascript
/**
 * 4. 取得最終的陪伴式回覆 (getCompanionReply)
 */
async function getCompanionReply({ screening, emotion, dietaryAgentResponse, dietaryAgentRequest, userPrompt, dietaryAgentError }) {
  // 1. 非飲食諮詢的閒聊與其他不處理類別回覆  - 後端直接攔截防呆，省錢省時
  if (!screening.should_handle) {
    return "這句話目前不像是飲食建議模組要處理的內容。如果您有關於餐點選擇、熱量或減脂增肌的問題，隨時可以問我！";
  }

  // 2. 檢查是否因為參數攔截（未提供具體料理或問題類型未知）而沒有呼叫 Dietary Agent
  if (screening.should_handle && !dietaryAgentRequest) {
    if (!screening.dishes || screening.dishes.length === 0) {
      return "我目前無法從您的問題中提取出具體的食物名稱。可以請您提供想諮詢的餐點名稱嗎？例如：「晚餐吃炸雞適合嗎？」";
    }
    if (screening.question_type !== "single_dish" && screening.question_type !== "dish_comparison") {
      return "我目前無法判斷您問題的類型，請試著具體詢問單一食物的熱量，或是比較多個食物喔！";
    }
    return "抱歉，我目前無法理解您的問題，請重新輸入更具體的飲食問題。";
  }

  // 3. 通過攔截後，調用 LLM 動態生成重組後的回覆 (呼叫 runLLMReply 函數)
  let finalReply = "";
  try {
    finalReply = await runLLMReply({
      userPrompt,
      screening,
      emotion,
      dietaryAgentResponse,
      dietaryAgentRequest,
      dietaryAgentError
    });
  } catch (error) {
    console.error("Failed to generate companion response with LLM:", error.message);
    // Fallback 保底機制：若 LLM 重組失敗，使用原本的拼接方式
    const empathyPrefix = emotion.needs_empathy
      ? "我有注意到你現在有點在意這次的選擇，先不用太緊張喔。❤️\n"
      : "我先幫您整理這次的飲食建議：\n";
    const recommendation = dietaryAgentResponse?.reply_text || dietaryAgentResponse?.conclusion || JSON.stringify(dietaryAgentResponse) || "已成功記錄您的問題，正在為您尋求最佳飲食建議。";
    finalReply = `${empathyPrefix}${recommendation}`;
  }

  return finalReply;
}
```

---

### 3. [companion-llm.js](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-llm.js) (簡化意圖、更新 Prompt 與 API 端點)

* **修改 1：移除 `medical_out_of_scope` 意圖分類**
  * 在 `ANALYSIS_SYSTEM_PROMPT` 中，指示將醫療問答歸入 `general_chat`（其他不處理類別）。
  * 在 `tools` 定義中，將 `"medical_out_of_scope"` 從 `intent_category` 的 enum 清單中刪除。
* **修改 2：更新 `REPLY_SYSTEM_PROMPT`**
  * 常數名稱保持為 `REPLY_SYSTEM_PROMPT`，但內容改為 V2 的情緒重組與數值免責引導規則。
* **修改 3：重構 `generateCompanionReply` 函數**
  * 函數名稱保持為 `generateCompanionReply`。
  * 改用官方標準的 Chat Completions API (`/v1/chat/completions`) 進行 HTTP POST 請求。
  * 設定 `temperature: 0.2` 以確保免責聲明穩定且百分之百觸發。
  * 移除重複的 `GENERATE_RESPONSE_PROMPT` 與 `generateCompanionResponse` 函數。
  * 在 `sanitizeScreening` 與 `sanitizeEmotion` 中加入 `!raw`（未觸發工具）時的安全預設回傳機制，提升系統防崩潰能力。

#### 【重要程式碼片段】

```javascript
const ANALYSIS_SYSTEM_PROMPT = `
...
Rules for "screen_user_request":
...
2. intent_category:
   - "dish_advice": asking for dietary advice or recommendation.
   - "meal_record": recording what they ate.
   - "general_chat": unrelated small talk, off-topic requests, or medical questions (medicine, diagnosis, disease treatment, doctor advice).
...
`;
```

```javascript
const REPLY_SYSTEM_PROMPT = `
You are a warm, supportive, and professional dietary assistant called "Companion Agent" (飲食精靈).
Your task is to rewrite and embellish the raw data and analysis results provided by the "Dietary Agent" into a warm, empathetic, and conversational response for the user.

Follow these rules:
1. Tone & Style:
   - Match the tone recommended in the emotional analysis.
   - If "needs_empathy" is true, start or weave in a warm, caring statement to ease the user's guilt or anxiety about their meal choice. 
   - Keep the reply friendly, conversational, and written in natural Traditional Chinese (Taiwan). Avoid sounding like a rigid bot or just outputting raw JSON lists.
2. Context Integration:
   - Translate the analytical advice (like caloric warnings, food swaps, and macronutrient explanations) into easily understandable sentences.
   - Do NOT omit key recommendations from the Dietary Agent, but integrate them naturally.
3. Disclaimer Rule:
   - If the user's query asks about numbers (calories, fat, protein, carbs, nutrition metrics), you MUST append this exact phrase at the very end of your response: "關於數值類提問，本精靈只可提供參考數值".
4. Output format: Return ONLY the final dialogue response text. Do not include any JSON wrapping or markdown blocks unless it improves readability for the user.
`;
```

```javascript
async function generateCompanionReply({
  userPrompt,
  screening,
  emotion,
  dietaryAgentResponse,
  dietaryAgentRequest,
  dietaryAgentError
}) {
  const apiKey = process.env.OPENAI_API_KEY;
  const model = process.env.OPENAI_MODEL || "gpt-4o-mini";

  if (!apiKey) {
    throw new Error("Missing OPENAI_API_KEY.");
  }

  const rawDataStr = dietaryAgentResponse 
    ? JSON.stringify(dietaryAgentResponse, null, 2)
    : "無資料";

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model,
      messages: [
        {
          role: "system",
          content: REPLY_SYSTEM_PROMPT
        },
        {
          role: "user",
          content: `使用者問句: "${userPrompt}"\n\n情緒與同理心設定: ${JSON.stringify(emotion)}\n\nDietary Agent 回傳資料:\n${rawDataStr}`
        }
      ],
      temperature: 0.2, // 調低溫度以確保 100% 穩定輸出免責聲明
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`OpenAI Chat API error ${response.status}: ${errorText}`);
  }

  const resJson = await response.json();
  if (!resJson.choices || resJson.choices.length === 0) {
    throw new Error("Empty choices returned from OpenAI Chat API");
  }

  return resJson.choices[0].message.content.trim();
}
```
