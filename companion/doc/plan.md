# Companion Agent 服務實作開發手冊

本文件為您提供一步一步（Step-by-Step）實作 **Companion Agent** 服務的具體程式碼與設定說明。此服務以 **Node.js + Express** 建構，作為 **Flutter 前端**與 **Dietary Agent** 之間的中介代理。

本服務之核心職責為：
1. 意圖分類（由 OpenAI 進行語意分析，判斷是否為飲食相關問題、是否為比較型問題）。
2. 料理實體擷取（擷取使用者問句中提及的所有料理或食物名稱）。
3. 情緒語氣分析（偵測使用者情緒，決定回覆時是否需先進行安撫）。
4. 安全性檢測（Pre-check/Post-check 攔截醫療超出範圍問題）。
5. 封裝傳遞（僅將 **問題本身**、**問題種類**、**料理名稱陣列** 這三項關鍵資料 POST 送至 Dietary Agent）。
6. 回覆生成（結合情緒安撫與 Dietary Agent 的回傳建議，產出自然且友善的陪伴式自然語言）。

---

## 1. 專案目錄結構與環境設定

### 專案目錄結構
建議在工作區中建立以下檔案結構：
```text
companion/
├── PLAN.md                       # 本手冊備份
├── doc/
│   ├── plan.md                   # 本開發手冊
│   └── test.md                   # 測試與驗證指南
└── companion_js/
    ├── .env
    ├── .env.example
    ├── package.json
    ├── companion-agent-config.js     # 存放 Prompt 與 Tools Schema
    ├── companion-agent-helpers.js    # 存放 Rule-based、Sanitize 與 Fallback 邏輯
    ├── companion-agent-services.js   # 處理 OpenAI 與 Dietary Agent 的 API 請求
    └── companion-agent.js            # 主進入點，處理 Express 路由與流程協調
```

### `package.json`
建立 `package.json` 檔案，引入需要的相依套件：
```json
{
  "name": "diet-application-companion-agent",
  "version": "1.0.0",
  "description": "Companion Agent service for dietary app",
  "main": "Companion/companion-agent.js",
  "scripts": {
    "start": "node Companion/companion-agent.js"
  },
  "dependencies": {
    "cors": "^2.8.5",
    "dotenv": "^16.4.5",
    "express": "^4.19.2"
  }
}
```

### `.env`
建立環境變數設定檔 `.env`（請替換為您個人的 OpenAI API 金鑰）：
```env
OPENAI_API_KEY=your-openai-api-key-here
OPENAI_MODEL=gpt-4o-mini
DIETARY_AGENT_API_URL=https://dietary-agent-service-placeholder.com
COMPANION_API_PORT=3000
```

---

## 2. 核心實作：`Companion/companion-agent.js`

請建立 `Companion/companion-agent.js` 並將以下完整的程式碼放入其中。此程式碼整合了 **OpenAI 雙 Tool 呼叫**、**自動化料理名稱擷取**、**本地 Rule-based 安全攔截**，以及**往後對接 Dietary Agent 的三元素封裝**：

```javascript
require("dotenv").config();
const express = require("express");
const cors = require("cors");
```

// 1. 系統 Prompt 定義：規範 LLM 扮演 Classifier，並精確抽取料理與情緒
### 2.1 設定與 Schema (`Companion/companion-agent-config.js`)
* **第一行**：檔案路徑
* **第二行**：檔案功用說明

```javascript
// Path: c:\Users\User\Desktop\DietApplication_CompanionAgent\Companion\companion-agent-config.js
// Description: Configuration containing SYSTEM_PROMPT and tools schemas for OpenAI Function Calling

const SYSTEM_PROMPT = `
You are the Companion Agent classifier and extractor for a dietary recommendation app.
Your task is to analyze the user's message and determine the context, questions types, emotions, and extract mentioned dishes.

You MUST execute both functions (parallel tool calls): "screen_user_request" and "analyze_emotion" to return your results.

Specific Instructions for "screen_user_request":
- Identify if the user's request is a dietary/food question (intent_category: dish_advice or meal_record).
- Classify question_type as:
  1. "single_dish": User asks about one specific food/meal.
  2. "dish_comparison": User compares two or more foods (e.g., "A vs B", "A or B", "compared to").
  3. "unknown": General chat or questions out of scope.
- Determine if more context is required (requires_more_context). If the user profile is missing but they ask a personal question like "Can I eat this?", set requires_more_context to true.
- "dishes": Extract all names of foods, dishes, or drinks mentioned in the user's text as a string array. (e.g., "拉麵", "炸雞"). If none, return an empty array.

Specific Instructions for "analyze_emotion":
- Analyze the user's emotional tone and set needs_empathy to true if they express anxiety, guilt, stress, or frustration.
- Determine companion_tone (e.g., calm, encouraging).
`;

// 2. OpenAI Function Calling (Tools) Schema 定義
const tools = [
  {
    type: "function",
    name: "screen_user_request",
    description: "Screen the user request to classify question type, intent, and extract mentioned dishes.",
    parameters: {
      type: "object",
      properties: {
        should_handle: { 
          type: "boolean",
          description: "Whether this request should be processed by the companion agent."
        },
        intent_category: {
          type: "string",
          enum: ["dish_advice", "meal_record", "medical_out_of_scope", "general_chat"]
        },
        question_type: {
          type: "string",
          enum: ["single_dish", "dish_comparison", "unknown"]
        },
        requires_more_context: {
          type: "boolean",
          description: "True if user profile or key details are missing for personalization."
        },
        missing_information: {
          type: "array",
          items: { type: "string" },
          description: "List of missing items, e.g., ['user_profile', 'restaurant_context']"
        },
        confidence: { type: "number" },
        dishes: {
          type: "array",
          items: { type: "string" },
          description: "List of all food or dish names mentioned in the user message."
        }
      },
      required: [
        "should_handle", 
        "intent_category", 
        "question_type", 
        "requires_more_context", 
        "missing_information", 
        "confidence",
        "dishes"
      ],
      additionalProperties: false
    }
  },
  {
    type: "function",
    name: "analyze_emotion",
    description: "Analyze the user's emotional state and tone to adjust companion responses.",
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
        needs_empathy: { type: "boolean" },
        companion_tone: {
          type: "string",
          enum: ["calm", "encouraging", "neutral"]
        },
        evidence: {
          type: "array",
          items: { type: "string" },
          description: "Keywords or phrases from the message indicating this emotion."
        }
      },
      required: [
        "primary_emotion",
        "valence",
        "urgency",
        "needs_empathy",
        "companion_tone",
        "evidence"
      ],
      additionalProperties: false
    }
  }
];
module.exports = {
  SYSTEM_PROMPT,
  tools
};
```

// 3. Rule-based 輔助安全性判斷函式 (Pre-check 與 Fallback)

### 2.2 輔助與保底邏輯 (`Companion/companion-agent-helpers.js`)
* **第一行**：檔案路徑
* **第二行**：檔案功用說明

```javascript
// Path: c:\Users\User\Desktop\DietApplication_CompanionAgent\Companion\companion-agent-helpers.js
// Description: Rule-based checks, pre-checks, fallback evaluations, and sanitize logic

function isMedicalOutOfScope(message) {
  return (
    /(診斷|處方|藥|醫生|治療|病名確診|服用方法)/.test(message) ||
    /(diagnosis|prescription|treatment|medicine|doctor)/i.test(message)
  );
}

function isLikelyFoodRelated(message) {
  return (
    /(吃|餐廳|料理|菜單|便當|晚餐|午餐|早餐|熱量|營養|外食|拉麵|火鍋|炸雞|沙拉|飲料|宵夜|牛肉麵|雞排|減脂|增肌|飲食)/.test(message) ||
    /(food|menu|restaurant|dish|meal|calorie|nutrition)/i.test(message)
  );
}

function looksLikeComparison(message) {
  return /(哪個|比較|vs|versus|跟|和|相比|比較適合)/i.test(message);
}

// 本地粗略抽取料理 (用於 OpenAI 失敗時的 Fallback 備援)
function fallbackDishesExtraction(message) {
  const commonFoods = ["拉麵", "炸雞", "火鍋", "沙拉", "便當", "牛肉麵", "雞排", "宵夜", "飲料", "咖哩飯", "披薩", "壽司"];
  const found = [];
  commonFoods.forEach(food => {
    if (message.includes(food)) {
      found.push(food);
    }
  });
  return found;
}

// 4. Fallback 備援函式
function fallbackClassifyQuestionType(message) {
  if (looksLikeComparison(message)) return "dish_comparison";
  if (isLikelyFoodRelated(message)) return "single_dish";
  return "unknown";
}

function fallbackScreening(message, userContext) {
  const isFood = isLikelyFoodRelated(message);
  const isMedical = isMedicalOutOfScope(message);
  
  if (isMedical) {
    return {
      should_handle: false,
      intent_category: "medical_out_of_scope",
      question_type: "unknown",
      requires_more_context: false,
      missing_information: [],
      confidence: 0.8,
      dishes: []
    };
  }

  return {
    should_handle: isFood,
    intent_category: isFood ? "dish_advice" : "general_chat",
    question_type: fallbackClassifyQuestionType(message),
    requires_more_context: isFood && !userContext.has_user_profile,
    missing_information: (isFood && !userContext.has_user_profile) ? ["user_profile"] : [],
    confidence: 0.6,
    dishes: fallbackDishesExtraction(message)
  };
}

function fallbackEmotion(message) {
  const containsAnxiety = /(焦慮|擔心|害怕|緊張|怎麼辦|會不會太|超標)/.test(message);
  const containsGuilt = /(罪惡感|內疚|後悔|偷吃)/.test(message);
  const containsStress = /(壓力|累|崩潰|煩)/.test(message);
  
  let primary_emotion = "neutral";
  let needs_empathy = false;
  let companion_tone = "neutral";
  
  if (containsAnxiety) {
    primary_emotion = "anxiety";
    needs_empathy = true;
    companion_tone = "calm";
  } else if (containsGuilt) {
    primary_emotion = "guilt";
    needs_empathy = true;
    companion_tone = "encouraging";
  } else if (containsStress) {
    primary_emotion = "stress";
    needs_empathy = true;
    companion_tone = "calm";
  }

  return {
    primary_emotion,
    valence: needs_empathy ? "negative" : "neutral",
    urgency: "medium",
    needs_empathy,
    companion_tone,
    evidence: []
  };
}

// 5. Sanitize 檢查修正函式 (Post-check 防止 LLM 產生不合理輸出)
function sanitizeScreening(raw, message, userContext) {
  if (!raw) {
    return fallbackScreening(message, userContext);
  }

  const result = { ...raw };

  // 強制規則 1: 若含有醫療詞彙，覆寫為醫療超出範圍
  if (isMedicalOutOfScope(message)) {
    result.should_handle = false;
    result.intent_category = "medical_out_of_scope";
    result.question_type = "unknown";
  }

  // 強制規則 2: 若缺少 user profile 但模型說可以直接處理，修正為需要 context
  if (result.should_handle && !userContext.has_user_profile && !result.requires_more_context) {
    result.requires_more_context = true;
    if (!result.missing_information.includes("user_profile")) {
      result.missing_information.push("user_profile");
    }
  }

  // 確保 dishes 必定是陣列
  if (!Array.isArray(result.dishes)) {
    result.dishes = Array.isArray(raw.dishes) ? raw.dishes : fallbackDishesExtraction(message);
  }

  return result;
}

function sanitizeEmotion(raw, message) {
  if (!raw) {
    return fallbackEmotion(message);
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

// 6. 簡化 Payload 組裝：僅組裝傳遞給 Dietary Agent 的三元素
function buildDietaryAgentRequest(screening, message) {
  if (!screening.should_handle || screening.requires_more_context) {
    return null;
  }

  return {
    question: message,
    question_type: screening.question_type,
    dish_names: screening.dishes || []
  };
}

//7.呼叫 openai responses api 
module.exports = {
  isMedicalOutOfScope,
  isLikelyFoodRelated,
  looksLikeComparison,
  fallbackDishesExtraction,
  fallbackClassifyQuestionType,
  fallbackScreening,
  fallbackEmotion,
  sanitizeScreening,
  sanitizeEmotion,
  buildDietaryAgentRequest
};
```

### 2.3 API 連線服務 (`Companion/companion-agent-services.js`)
* **第一行**：檔案路徑
* **第二行**：檔案功用說明

```javascript
// Path: c:\Users\User\Desktop\DietApplication_CompanionAgent\Companion\companion-agent-services.js
// Description: External API services for communicating with OpenAI and Dietary Agent

const { SYSTEM_PROMPT, tools } = require("./companion-agent-config");
const {
  sanitizeScreening,
  sanitizeEmotion,
  buildDietaryAgentRequest,
  fallbackScreening,
  fallbackEmotion
} = require("./companion-agent-helpers");

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

// 解析 function call 結果
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

// 執行 OpenAI 流程
async function runOpenAIFlow(bundle) {
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
      tools,
      input: [
        {
          role: "system",
          content: [{ type: "input_text", text: SYSTEM_PROMPT }],
        },
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: JSON.stringify(bundle),
            },
          ],
        },
      ],
    },
    apiKey
  );

  const functionCalls = getFunctionCalls(response);
  const rawArgs = collectToolArgsByName(functionCalls);

  const screening = sanitizeScreening(
    rawArgs.screen_user_request,
    bundle.message,
    bundle.user_context
  );
  const emotion = sanitizeEmotion(rawArgs.analyze_emotion, bundle.message);
  const dietaryAgentRequest = buildDietaryAgentRequest(screening, bundle.message);

  return {
    screening,
    emotion,
    dietary_agent_request: dietaryAgentRequest
  };
}

// 執行 Fallback 保底流程
function runFallbackFlow(bundle) {
  const screening = fallbackScreening(bundle.message, bundle.user_context);
  const emotion = fallbackEmotion(bundle.message);
  const dietaryAgentRequest = buildDietaryAgentRequest(screening, bundle.message);

  return {
    screening,
    emotion,
    dietary_agent_request: dietaryAgentRequest
  };
}

// 8. 呼叫 Dietary Agent
async function callDietaryAgent(requestBody) {
  const baseUrl = process.env.DIETARY_AGENT_API_URL;
  if (!baseUrl) {
    throw new Error("Missing DIETARY_AGENT_API_URL variable in .env");
  }

  // 往後傳遞給 Dietary Agent 的 Endpoint，可根據您組員的 API 修改路由 (如: /ask 或 /analyze)
  const response = await fetch(`${baseUrl}/api/dietary/ask-weekly-analysis`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify(requestBody),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Dietary Agent error ${response.status}: ${errorText}`);
  }

  return response.json();
}

function buildCompanionReply({ screening, emotion, dietaryAgentResponse }) {
  if (screening.intent_category === "medical_out_of_scope") {
    return "這類問題比較接近醫療診斷或治療判斷，我目前不能直接替代專業醫療建議。建議您諮詢醫生或合格的醫療專家喔。";
  }

  if (!screening.should_handle) {
    return "這句話目前不像是飲食建議模組要處理的內容。如果您有關於餐點選擇、熱量或減脂增肌的問題，隨時可以問我！";
  }

  if (screening.requires_more_context) {
    if (screening.missing_information.includes("user_profile")) {
      return "我還需要您的一些基本資訊（像是年齡、身高、體重或健康狀況），才能幫您做出比較精確的飲食推薦喔！";
    }
    return "為了給您更合適的建議，可以再多提供一些您的飲食狀況或細節嗎？";
  }

  // 情緒安撫前綴
  const empathyPrefix = emotion.needs_empathy
    ? "我有注意到你現在有點在意這次的選擇，先不用太緊張喔。❤️\n"
    : "我先幫您整理這次的飲食建議：\n";

  // 組合 Dietary Agent 的回覆內容
  let recommendation = "已成功記錄您的問題，正在為您尋求最佳飲食建議。";
  if (dietaryAgentResponse) {

    //TODO:仍需待討論回傳的格式為何，以下程式碼與_service 的不一樣
    // 1. 優先尋找同學後端產出的真實 AI 建議欄位
    recommendation = 
      dietaryAgentResponse.reply_text || 
      dietaryAgentResponse.conclusion || 
      dietaryAgentResponse.reply || 
      dietaryAgentResponse.message;

    // 2. 如果以上欄位都找不到，說明同學後端目前主要用於傳輸資料，我們利用回傳的資料在本地動態編排一個溫暖且逼真的引導回覆
    if (!recommendation) {
      const dishesStr = Array.isArray(dietaryAgentResponse.dish_names) && dietaryAgentResponse.dish_names.length > 0 
        ? dietaryAgentResponse.dish_names.join("、") 
        : "未知料理";
      const profile = dietaryAgentResponse.user_profile;
      const health = dietaryAgentResponse.health_condition;
      
      let detailText = "";
      if (profile) {
        detailText = `系統已順利讀取您的增肌/減脂設定（${profile.height_cm}cm / ${profile.weight_kg}kg，${profile.age}歲）`;
        if (health && health.has_chronic_disease) {
          detailText += "與慢性病健康史（如高血壓）";
        }
        detailText += "，並";
      }

      recommendation = `${detailText}成功記錄了您的提問。針對您問及的「${dishesStr}」，已完成與 Dietary Agent 的連結，目前正在為您載入詳細的熱量分析與飲食建議，請稍等片刻喔！`;
    }
  }

  return `${empathyPrefix}${recommendation}`;
}

module.exports = {
  runOpenAIFlow,
  runFallbackFlow,
  callDietaryAgent,
  buildCompanionReply
};

// Path: c:\Users\User\Desktop\DietApplication_CompanionAgent\Companion\companion-agent.js
// Description: Main entry point for Express server, routing HTTP requests, and orchestrating flow

require("dotenv").config();
const express = require("express");
const cors = require("cors");
const {
  runOpenAIFlow,
  runFallbackFlow,
  callDietaryAgent,
  buildCompanionReply
} = require("./companion-agent-services");

const app = express();
app.use(cors());
app.use(express.json());

// 10. 主要 API 路由邏輯
function createUserContext(requestBody) {
  return {
    has_active_restaurant_context: Boolean(requestBody.context?.restaurant_name),
    has_menu_context: Array.isArray(requestBody.context?.menu_items) && requestBody.context.menu_items.length > 0,
    has_user_profile: Boolean(requestBody.user_profile)
  };
}

async function handleCompanionAsk(req, res) {
  const message = typeof req.body.message === "string" ? req.body.message.trim() : "";
  if (!message) {
    return res.status(400).json({ success: false, error: "message is required" });
  }

  const bundle = {
    message,
    user_context: createUserContext(req.body)
  };

  let openAiResult;
  let llmFallbackUsed = false;

  // 第一階段：執行 OpenAI 分析與料理/情緒識別
  try {
    openAiResult = await runOpenAIFlow(bundle);
  } catch (error) {
    console.error("OpenAI flow failed, switching to fallback:", error.message);
    llmFallbackUsed = true;
    openAiResult = runFallbackFlow(bundle);
    openAiResult.llm_error = error.message;
  }

  let dietaryAgentResponse = null;
  let dietaryAgentError = null;

  // 第二階段：呼叫 Dietary Agent (若需要)
  if (openAiResult.dietary_agent_request) {
    try {
      dietaryAgentResponse = await callDietaryAgent(openAiResult.dietary_agent_request);
    } catch (error) {
      console.error("Dietary Agent call failed:", error.message);
      dietaryAgentError = error.message;
    }
  }

  // 第三階段：回傳整合的 JSON
  return res.json({
    success: true,
    llm_fallback_used: llmFallbackUsed,
    screening: {
      should_handle: openAiResult.screening.should_handle,
      intent_category: openAiResult.screening.intent_category,
      question_type: openAiResult.screening.question_type,
      requires_more_context: openAiResult.screening.requires_more_context,
      missing_information: openAiResult.screening.missing_information,
      confidence: openAiResult.screening.confidence,
      dishes: openAiResult.screening.dishes // 抽取的料理陣列
    },
    emotion: openAiResult.emotion,
    dietary_agent_request: openAiResult.dietary_agent_request, // 傳給 Dietary Agent 的三元素封裝
    dietary_agent_response: dietaryAgentResponse,
    dietary_agent_error: dietaryAgentError,
    companion_reply: buildCompanionReply({
      screening: openAiResult.screening,
      emotion: openAiResult.emotion,
      dietaryAgentResponse
    })
  });
}

// 11. 啟動 Express App
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

您可以啟動此服務後，使用 `curl` 在本機進行測試，驗證傳遞給 Dietary Agent 的資料結構與回覆結果：

### 驗證情境一：一般飲食問題且帶有焦慮情緒
```bash
curl -X POST http://localhost:3000/companion/ask \
-H "Content-Type: application/json" \
-d '{
  "message": "我今天中午吃炸雞了，晚上還能吃拉麵嗎？我有點焦慮。",
  "user_profile": {
    "height_cm": 165,
    "weight_kg": 60,
    "gender": "female",
    "age": 21
  }
}'
```
* **預期結果**：
  - `screening.dishes` 應該要正確包含 `["炸雞", "拉麵"]`。
  - `dietary_agent_request` 的 payload 為簡化格式：包含 `question`、`question_type: "single_dish"`、`dishes: ["炸雞", "拉麵"]`。
  - `emotion.needs_empathy` 為 `true`，回覆會帶有愛心與溫暖撫慰字句。

### 驗證情境二：比較兩項料理
```bash
curl -X POST http://localhost:3000/companion/ask \
-H "Content-Type: application/json" \
-d '{
  "message": "牛肉麵跟水餃哪一個熱量比較高？",
  "user_profile": {
    "height_cm": 165
  }
}'
```
* **預期結果**：
  - `screening.question_type` 為 `"dish_comparison"`。
  - `screening.dishes` 應包含 `["牛肉麵", "水餃"]`。

### 驗證情境三：醫療敏感詞過濾 (Pre-check 安全攔截)
```bash
curl -X POST http://localhost:3000/companion/ask \
-H "Content-Type: application/json" \
-d '{
  "message": "這個降血糖藥我應該怎麼服用？請幫我診斷。"
}'
```
* **預期結果**：
  - `screening.should_handle` 為 `false`。
  - `screening.intent_category` 為 `"medical_out_of_scope"`。
  - **不呼叫** Dietary Agent API。
  - 回覆提示使用者這屬於醫療問題，應尋求專業建議。
