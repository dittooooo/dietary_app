# Companion Agent 服務實作開發手冊

本文件為您提供一步一步（Step-by-Step）實作 **Companion Agent** 服務的具體程式碼與設定說明。此服務以 **Node.js + Express** 建構，作為 **Flutter 前端**與 **Dietary Agent** 之間的中介代理。

本服務之核心職責為：
1. 意圖分類（由 OpenAI 進行語意分析，判斷是否為飲食相關問題、是否為比較型問題）。
2. 料理實體擷取（擷取使用者問句中提及的所有料理或食物名稱）。
3. 情緒語氣分析（偵測使用者情緒，決定回覆時是否需先進行安撫）。
4. 安全性檢測與容錯攔截（將非飲食主題與醫療問題統一歸類於閒聊分類，並在後端中控進行攔截以節省 Token 費用）。
5. 封裝傳遞（僅將 **問題本身**、**問題種類**、**料理名稱陣列** 這三項關鍵資料 POST 送至 Dietary Agent）。
6. 回覆生成（結合情緒安撫與 Dietary Agent 的回傳建議，利用大模型 Chat Completions 進行對話重組，生成自然且友善的陪伴式自然語言）。

---

## 1. 專案目錄結構與環境設定

### 專案目錄結構
建議在工作區中建立以下檔案結構：
```text
companion/
├── doc/
│   ├── plan.md                   # 本開發手冊
│   └── test.md                   # 測試與驗證指南
└── companion_js/
    ├── package.json
    ├── companion-llm.js             # 存放 Prompt, Schema 與 OpenAI 呼叫/Sanitize邏輯
    ├── companion-agent-services.js   # 處理三參數校驗、對外連線與回覆組裝
    └── companion-agent.js            # 主進入點，處理 Express 路由與流程協調
```

### `package.json`
建立 `package.json` 檔案，引入需要的相依套件：
```json
{
  "name": "diet-application-companion-agent",
  "version": "1.0.0",
  "description": "Companion Agent service for dietary app",
  "main": "companion-agent.js",
  "scripts": {
    "start": "node companion-agent.js"
  },
  "dependencies": {
    "cors": "^2.8.5",
    "dotenv": "^16.4.5",
    "express": "^4.19.2"
  }
}
```

### `.env` (通常置於專案最外層資料夾，亦可置於 companion_js 下作為備用)
建立環境變數設定檔 `.env`（請替換為您個人的 OpenAI API 金鑰）：
```env
OPENAI_API_KEY=your-openai-api-key-here
OPENAI_MODEL=gpt-4o-mini
DIETARY_AGENT_API_URL=https://dietary-agent-service-placeholder.com
COMPANION_API_PORT=3000
```

---

## 2. 核心實作說明

本服務由三個主要程式檔案組成，各自承擔不同的職責。以下是各檔案的完整實作內容與說明：

### 2.1 設定、Schema 與 LLM 核心處理 (`companion-llm.js`)
* **路徑**：`companion/companion_js/companion-llm.js`
* **功用**：存放第一階段分析 Prompt、第二階段重組 Prompt、Tool 描述 Schema 與 OpenAI API 呼叫/Sanitize 容錯邏輯。

```javascript
// Path: c:\Users\User\Documents\Github_Repo\dietary_app\companion\companion_js\companion-llm.js
// Description: All LLM-related configuration and execution logic

// TODO: 移除醫療Catagory
const ANALYSIS_SYSTEM_PROMPT = `
You are a Companion Agent classifier and extractor for a dietary recommendation app.
Your task is to analyze the user's message, which is usually in Traditional Chinese.
You must determine the user's intent, the question type, and extract any food or dish names mentioned.

You MUST execute both functions (parallel tool calls): "screen_user_request" and "analyze_emotion" to return your analysis.

Rules for "screen_user_request":
1. should_handle (boolean):
   - Set to true ONLY if the message is related to food advice, cooking methods, calories, dietary intake, or meal recording.
   - Set to false if the message is off-topic (e.g., weather, generic greeting), or if the user asks for sensitive medical advice, prescription drugs, disease diagnosis, or treatment (e.g. "what medicine to take for headache").
2. intent_category:
   - "dish_advice": asking for dietary advice or recommendation.
   - "meal_record": recording what they ate.
   - "general_chat": unrelated small talk, off-topic requests, or medical questions (medicine, diagnosis, disease treatment, doctor advice).
3. question_type:
   - "single_dish": asking about one specific food/dish.
   - "dish_comparison": comparing two or more foods (e.g. "A or B, which is better?", "A vs B").
   - "unknown": none of the above.
4. dishes:
   - Extract all specific food/dish names in Traditional Chinese (Taiwan preferred) as array. If none, return empty array [].
`;

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

const tools = [
  {
    type: "function",
    function: {
      name: "screen_user_request",
      description: "Classify the intent category, determine if it should be handled, extract dishes, and identify question type.",
      parameters: {
        type: "object",
        properties: {
          should_handle: {
            type: "boolean",
            description: "True if food or dietary advice related. False for medicine, diagnostics, weather, etc."
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
            type: "number",
            description: "Confidence level of classification (0.0 to 1.0)"
          },
          dishes: {
            type: "array",
            items: {
              type: "string"
            },
            description: "List of dish names in traditional Chinese extracted from query."
          }
        },
        required: ["should_handle", "intent_category", "question_type", "confidence", "dishes"],
        additionalProperties: false
      }
    }
  },
  {
    type: "function",
    function: {
      name: "analyze_emotion",
      description: "Analyze user emotions to adjust response tone and style.",
      parameters: {
        type: "object",
        properties: {
          primary_emotion: {
            type: "string",
            enum: ["neutral", "curious", "anxiety", "guilt", "stress", "frustration", "joy"]
          },
          valence: {
            type: "string",
            enum: ["positive", "neutral", "negative"]
          },
          urgency: {
            type: "string",
            enum: ["low", "medium", "high"]
          },
          needs_empathy: {
            type: "boolean",
            description: "True if guilt, frustration, stress, or anxiety is detected and needs reassurance."
          },
          companion_tone: {
            type: "string",
            enum: ["calm", "encouraging", "neutral"]
          },
          evidence: {
            type: "array",
            items: {
              type: "string"
            },
            description: "Substrings from query that justify emotional analysis."
          }
        },
        required: ["primary_emotion", "valence", "urgency", "needs_empathy", "companion_tone", "evidence"],
        additionalProperties: false
      }
    }
  }
];

/**
 * 【Function Calling 容錯防呆機制說明】：
 * 當使用者輸入與飲食完全無關的內容（如天氣、用藥等）時，OpenAI API 雖正常成功回傳，
 * 但會判定不需要調用我們提供的工具。此時 `rawArgs.screen_user_request` 將會是 `undefined`（!raw 為真）。
 * 為了避免後端在後續讀取 `openAiResult.screening.should_handle` 等欄位時因為讀到 undefined 
 * 而造成伺服器拋出 500/502 異常，此處主動「虛擬」回傳一個帶有完整欄位的預設物件。
 * 這會引導後續的 Node.js 程式走入 should_handle: false 的 off-topic 攔截流程，對使用者回傳親切的閒聊防呆提示。
 */
function sanitizeScreening(raw) {
  // 容錯防呆：如果 OpenAI 沒有觸發意圖工具調用，預設為不需處理的閒聊分類
  if (!raw) {
    return {
      should_handle: false,
      intent_category: "general_chat",
      question_type: "unknown",
      confidence: 0,
      dishes: []
    };
  }

  const result = { ...raw };
  if (!Array.isArray(result.dishes)) {
    result.dishes = [];
  }

  return result;
}

function sanitizeEmotion(raw) {
  // 容錯防呆：如果 OpenAI 沒有觸發情緒工具調用，給予中性情緒預設值
  if (!raw) {
    return {
      primary_emotion: "neutral",
      valence: "neutral",
      urgency: "low",
      needs_empathy: false,
      companion_tone: "neutral",
      evidence: []
    };
  }

  return {
    primary_emotion: raw.primary_emotion || "neutral",
    valence: raw.valence || "neutral",
    urgency: raw.urgency || "medium",
    needs_empathy: typeof raw.needs_empathy === "boolean" ? raw.needs_empathy : false,
    companion_tone: raw.companion_tone || "neutral",
    evidence: Array.isArray(raw.evidence) ? raw.evidence : []
  };
}

async function createOpenAIResponse(body, apiKey) {
  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`OpenAI API error ${response.status}: ${errorText}`);
  }

  return response.json();
}

function getFunctionCalls(responseJson) {
  return (responseJson.output || []).filter((item) => item.type === "function_call");
}

function collectToolArgsByName(functionCalls) {
  const byName = {};
  for (const call of functionCalls) {
    try {
      byName[call.name] = JSON.parse(call.arguments || "{}");
    } catch {
      byName[call.name] = null;
    }
  }
  return byName;
}

async function runOpenAIFlow(userPrompt) {
  const apiKey = process.env.OPENAI_API_KEY;
  const model = process.env.OPENAI_MODEL || "gpt-4o-mini";

  if (!apiKey) {
    throw new Error("Missing OPENAI_API_KEY.");
  }

  const response = await createOpenAIResponse(
    {
      model,
      parallel_tool_calls: true,
      tool_choice: "auto",
      tools: tools.map((t) => {
        if (t.type === "function" && t.function) {
          return {
            type: "function",
            name: t.function.name,
            description: t.function.description,
            parameters: t.function.parameters
          };
        }
        return t;
      }),
      instructions: ANALYSIS_SYSTEM_PROMPT,
      input: [
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: userPrompt
            }
          ]
        }
      ]
    },
    apiKey
  );

  const functionCalls = getFunctionCalls(response);
  const rawArgs = collectToolArgsByName(functionCalls);

  const screening = sanitizeScreening(rawArgs.screen_user_request);
  const emotion = sanitizeEmotion(rawArgs.analyze_emotion);

  return {
    screening,
    emotion
  };
}

/**
 * 9. 呼叫 OpenAI Chat Completions 重組最終的陪伴式回覆 (generateCompanionReply)
 * 作用：將使用者原始提問、同理心/情緒分析設定與 Dietary Agent 的分析結果，
 * 包裝後發送給 OpenAI Chat Completions API 重組，生成溫馨自然的陪伴回覆。
 */
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

  // 呼叫 OpenAI 官方標準的 Chat Completions API
  // 【API 差異備忘說明】：
  // 1. 原本程式碼的「第一階段 (意圖與情緒分析)」使用的是 OpenAI Responses API (端點為 /v1/responses)，
  //    傳入參數使用 instructions 與 input 結構。
  // 2. 此處的「第二階段 (對話回覆生成)」則採用 Chat Completions API (端點為 /v1/chat/completions)，
  //    這是目前業界最通用的無狀態標準對話格式，藉由 messages (system / user) 陣列傳遞。
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

module.exports = {
  runOpenAIFlow,
  generateCompanionReply
};
```

---

### 2.2 API 連線與校驗調度服務 (`companion-agent-services.js`)
* **路徑**：`companion/companion_js/companion-agent-services.js`
* **功用**：處理發送給 Dietary Agent 的三元素封裝與呼叫，以及作為後端「省錢/速度」攔截器調度最終的陪伴回覆。

```javascript
// Path: c:\Users\User\Documents\Github_Repo\dietary_app\companion\companion_js\companion-agent-services.js
// Description: External API services for communicating with OpenAI and Dietary Agent

const {
  runOpenAIFlow: runLLMAnalysis,
  generateCompanionReply: runLLMReply
} = require("./companion-llm");

function buildDietaryAgentRequest(screening, message) {
  if (!screening || !screening.should_handle) {
    return null;
  }

  const question = typeof message === "string" ? message.trim() : "";
  const question_type = screening.question_type;
  const dish_names = screening.dishes || [];

  if (!question) {
    return null;
  }
  if (question_type !== "single_dish" && question_type !== "dish_comparison") {
    return null;
  }
  if (!Array.isArray(dish_names) || dish_names.length === 0) {
    return null;
  }

  return {
    question,
    question_type,
    dish_names
  };
}

async function runOpenAIFlow(userPrompt) {
  const result = await runLLMAnalysis(userPrompt);
  const dietaryAgentRequest = buildDietaryAgentRequest(result.screening, userPrompt);
  return {
    screening: result.screening,
    emotion: result.emotion,
    dietary_agent_request: dietaryAgentRequest
  };
}

async function callDietaryAgent(requestBody, authHeader) {
  const baseUrl = process.env.DIETARY_AGENT_API_URL;
  if (!baseUrl) {
    throw new Error("Missing DIETARY_AGENT_API_URL variable in .env");
  }
  const headers = {
    "Content-Type": "application/json",
  };
  if (authHeader) {
    headers["Authorization"] = authHeader;
  }
  const response = await fetch(`${baseUrl}/dietary-agent/ask`, {
    method: "POST",
    headers,
    body: JSON.stringify(requestBody),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Dietary Agent error ${response.status}: ${errorText}`);
  }

  return response.json();
}

/**
 * 4. 取得最終的陪伴式回覆 (getCompanionReply)
 * 此函數作為後端中控調度器：
 * - 在後端快速攔截非飲食問題或缺失關鍵參數的請求，省下 LLM API 費用。
 * - 只有在正常的飲食諮詢流程下，才異步呼叫 runLLMReply (由大模型重組回覆，免責警語完全交給 LLM Prompt 自行生成)。
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

module.exports = {
  runOpenAIFlow,
  callDietaryAgent,
  getCompanionReply
};
```

---

### 2.3 主進入點與伺服器路由 (`companion-agent.js`)
* **路徑**：`companion/companion_js/companion-agent.js`
* **功用**：主進入點，處理根目錄 `.env` 環境變數加載、Express 路由、並調度整個大腦決策流程。

```javascript
// Path: c:\Users\User\Documents\Github_Repo\dietary_app\companion\companion_js\companion-agent.js
// Description: Main entry point for Express server, routing HTTP requests, and orchestrating flow

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

// 引入 Express 框架用以建立 HTTP API 服務
const express = require("express");
// 引入 CORS 套件，允許 Flutter 前端跨網域存取後端 API
const cors = require("cors");
// 引入外部 API 服務模組 (包含 OpenAI 串接、保底流程、Dietary Agent 串接以及文字組裝)
const {
  runOpenAIFlow,
  callDietaryAgent,
  getCompanionReply
} = require("./companion-agent-services");

// 1. 初始化 Express App 實例
const app = express();
// 2. 啟用 CORS 跨域支援
app.use(cors());
// 3. 解析請求主體為 JSON 格式 (req.body)
app.use(express.json());

/**
 * 5. 主要 API 請求調度器 (handleCompanionAsk)
 * 串接完整流程：前端請求 -> 意圖情緒分析 (OpenAI) -> 呼叫 Dietary Agent -> 回覆生成 (LLM) -> 前端回應。
 */
async function handleCompanionAsk(req, res) {
  const user_prompt = typeof req.body.user_prompt === "string" ? req.body.user_prompt.trim() : "";
  if (!user_prompt) {
    return res.status(400).json({
      success: false,
      error_code: "BAD_REQUEST",
      error_message: "The 'user_prompt' field is required and must be a non-empty string."
    });
  }

  let openAiResult;

  try {
    openAiResult = await runOpenAIFlow(user_prompt);
  } catch (error) {
    console.error("OpenAI flow failed:", error.message);
    return res.status(502).json({
      success: false,
      error_code: "OPENAI_SERVICE_ERROR",
      error_message: "Failed to communicate with OpenAI API. Please try again later.",
      debug_message: error.message
    });
  }

  try {
    let dietaryAgentResponse = null;
    let dietaryAgentError = null;

    if (openAiResult.dietary_agent_request) {
      try {
        const authHeader = req.headers.authorization;
        dietaryAgentResponse = await callDietaryAgent(openAiResult.dietary_agent_request, authHeader);
      } catch (error) {
        console.error("Dietary Agent call failed:", error.message);
        dietaryAgentError = error.message;
      }
    }

    return res.json({
      success: true,
      llm_fallback_used: false,
      screening: {
        should_handle: openAiResult.screening.should_handle,
        intent_category: openAiResult.screening.intent_category,
        question_type: openAiResult.screening.question_type,
        confidence: openAiResult.screening.confidence,
        dishes: openAiResult.screening.dishes
      },
      emotion: openAiResult.emotion,
      dietary_agent_request: openAiResult.dietary_agent_request,
      dietary_agent_response: dietaryAgentResponse,
      dietary_agent_error: dietaryAgentError,
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
    });
  } catch (error) {
    console.error("Server internal error:", error);
    return res.status(500).json({
      success: false,
      error_code: "INTERNAL_SERVER_ERROR",
      error_message: "An unexpected error occurred on the server."
    });
  }
}

app.get("/health", (_req, res) => {
  res.json({ status: "ok" });
});

app.post("/companion/ask", handleCompanionAsk);

const port = Number(process.env.COMPANION_API_PORT || 3000);
app.listen(port, () => {
  console.log(`Companion Agent API listening on port ${port}`);
});
```

---

## 3. 測試與驗證指南

您可以啟動此服務後，使用 `curl` 或 API 測試工具在本地進行驗證：

### 驗證情境一：一般飲食問題且帶有情緒
```bash
curl -X POST http://localhost:3000/companion/ask \
-H "Content-Type: application/json" \
-d '{
  "user_prompt": "我今天中午吃炸雞了，晚餐吃拉麵熱量會超標嗎？我有點罪惡。"
}'
```
* **預期結果**：
  * `screening.dishes` 應正確包含 `["炸雞", "拉麵"]`。
  * `dietary_agent_request` 正確封裝發送給 Dietary Agent。
  * `companion_reply` 由 LLM 依同理心要求重組，且**結尾包含數值免責聲明** `"關於數值類提問，本精靈只可提供參考數值"`。

### 驗證情境二：醫療或無關閒聊問題 (後端直接攔截攔截)
```bash
curl -X POST http://localhost:3000/companion/ask \
-H "Content-Type: application/json" \
-d '{
  "user_prompt": "感冒頭痛要吃什麼藥比較有效？"
}'
```
* **預期結果**：
  * `screening.should_handle` 為 `false`。
  * `screening.intent_category` 為 `"general_chat"`。
  * **不呼叫** Dietary Agent API。
  * `companion_reply` 回傳防呆閒聊提示，不調用 LLM，**零 Token 消耗，響應極快**。
