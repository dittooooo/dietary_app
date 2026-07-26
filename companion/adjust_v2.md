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

### 3. LLM 動態生成與第一階段早退機制 (Early Exit)
* **需求說明**：
  * 為了提升效能並降低費用，當預檢判定為「非處理範圍 (should_handle is false)」或「飲食範圍但資訊不足以呼叫後端 (!dietaryAgentRequest)」時，系統不應再呼叫第二次 LLM API。
  * **調整方案**：在第一階段的預檢工具（`screen_user_request`）中，新增一個 `early_reply` 輸出欄位。若預檢失敗或資訊不足，LLM 將在此欄位中直接生成溫馨的拒絕或引導回覆。後端只要偵測到 `early_reply` 有內容，便「早退 (Early Exit)」直接回傳，不再呼叫第二次 Chat Completions API。只有在預檢通過且成功調用 Dietary Agent 取得營養數據時，才會呼叫第二輪 LLM（`generateCompanionReply`）進行重組。
* **實作細節**：
  * 在 `companion-llm.js` 調整 `screen_user_request` 工具的定義，新增 `early_reply` 屬性。
  * 調整第一階段的 `ANALYSIS_SYSTEM_PROMPT` 規則，加入在 `should_handle: false` 或資訊缺失時生成 `early_reply` 的指示。
  * 在 `companion-agent-services.js` 的 `getCompanionReply` 中，開頭先行判斷是否有 `early_reply`，若有則直接回傳。
  * 調整第二階段 `generateCompanionReply` 傳入參數，在 messages 內額外傳入 `screening` 資料。
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
* **修改 2：將原本 `buildCompanionReply` 改名為 `getCompanionReply` 並整合第一階段早退邏輯**
  * 在開頭檢查 `screening.early_reply`。若有值，則代表無須呼叫第二階段 LLM，直接回傳早退對話，達到省時與省費用的目的。
  * 舊有的 `!screening.should_handle` 和缺失必要參數的靜態攔截邏輯移入 `catch` 保底區塊中，做為 LLM API 出錯時的 Fallback。

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
async function getCompanionReply({
  screening,
  emotion,
  dietaryAgentResponse,
  dietaryAgentRequest,
  userPrompt,
  dietaryAgentError
}) {
  // 早退機制 (Early Exit)：若第一階段已經由 AI 生好 early_reply（如非飲食範圍或資訊缺失），則直接回傳，省下第二次 API 呼叫
  if (screening.early_reply) {
    return screening.early_reply;
  }

  // 情況 C：資訊完整，進入 LLM 生成回覆階段
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
    
    // Fallback 保底防呆機制：若 AI 生成出錯，依據篩選狀態回傳靜態預設訊息
    if (!screening.should_handle) {
      return "這個問題比較不是飲食助理的處理範圍。如果你願意，我還是可以幫你回到餐點選擇、熱量方向，或日常飲食建議來一起看。";
    }

    if (screening.should_handle && !dietaryAgentRequest) {
      if (!screening.dishes || screening.dishes.length === 0) {
        return "我目前還不太確定你想問的是哪一道食物。你可以直接告訴我餐點名稱，或補充你吃了什麼，我再幫你一起看。";
      }
      if (screening.question_type !== "single_dish" && screening.question_type !== "dish_comparison") {
        return "我有抓到你在問飲食，但還差一點資訊。你可以補充是想問單一道餐點，還是要比較兩種以上的食物嗎？";
      }
      return "我有收到你的問題，但目前資訊還不夠完整。你可以再多描述一點你想問的食物或情境，我就能更準確幫你整理。";
    }

    // 正常流程的 Fallback 拼接
    const empathyPrefix = emotion.needs_empathy
      ? "我知道你現在可能有點在意這餐怎麼吃，先別太有壓力，我陪你一起看。\n"
      : "我先幫你整理目前可用的資訊。\n";
    const recommendation = 
      dietaryAgentResponse?.reply_text || 
      dietaryAgentResponse?.conclusion || 
      (dietaryAgentResponse ? JSON.stringify(dietaryAgentResponse) : "目前還拿不到完整分析結果，稍後再試一次會比較穩。");
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
* **修改 2：更新第一階段分析與新增 `early_reply` 欄位**
  * 在 `ANALYSIS_SYSTEM_PROMPT` 新增 rule 5，要求 LLM 在 `should_handle: false`（閒聊/醫療）或 `should_handle: true` 但資訊缺失時，直接在 `early_reply` 中生成溫馨對話；其餘情況則留空。
  * 在 `tools` 的 `screen_user_request` 參數中新增屬性 `early_reply`，並設為 `required`。
  * 修改 `sanitizeScreening`，處理並防呆 `early_reply` 欄位。
* **修改 3：重構 `generateCompanionReply` 函數**
  * 函數名稱保持為 `generateCompanionReply`。
  * 改用官方標準的 Chat Completions API (`/v1/chat/completions`) 進行 HTTP POST 請求。
  * 設定 `temperature: 0.2` 以確保免責聲明穩定且百分之百觸發。
  * 在 messages 的 `user` message 中，除了傳入情緒分析，額外傳入意圖預檢 `screening`。
  * 移除重複的 `GENERATE_RESPONSE_PROMPT` 與 `generateCompanionResponse` 函數。

#### 【重要程式碼片段】

```javascript
const ANALYSIS_SYSTEM_PROMPT = `
...
Rules for "screen_user_request":
...
2. intent_category:
   - "dish_advice": asking for dietary advice, recommendations, or whether they can eat a certain food... If a message contains BOTH recording what they ate and asking for advice, ALWAYS prioritize "dish_advice".
   - "meal_record": ONLY when the user is purely recording what they ate without asking any questions or seeking advice...
3. question_type:
   - "single_dish": asking about one dish or meal...
   - "dish_comparison": comparing two or more dishes, or asking about eating multiple different dishes in a day (e.g., "中午吃炸雞，晚上還可以吃拉麵嗎").
5. early_reply:
   - Generate this response in warm, empathetic Traditional Chinese (Taiwan繁體中文).
   - If should_handle is false: Write a warm dialog response explaining that you are a dietary helper...
   - If should_handle is true but dishes is empty OR question_type is "unknown": Write a friendly prompt asking them to specify what dish they are referring to...
   - If should_handle is true AND dishes is NOT empty AND question_type is single_dish or dish_comparison: Set it to "".
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
