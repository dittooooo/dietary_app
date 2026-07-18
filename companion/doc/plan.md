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
├── doc/
│   ├── plan.md                   # 本開發手冊
│   └── test.md                   # 測試與驗證指南
└── companion_js/
    ├── .env
    ├── .env.example
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

## 2. 核心實作說明

本服務由三個主要程式檔案組成，各自承擔不同的職責。以下是各檔案的完整實作內容與說明：

### 2.1 設定、Schema 與 LLM 核心處理 (`Companion/companion-llm.js`)
* **第一行**：檔案路徑
* **第二行**：檔案功用說明

```javascript
// Path: c:\Users\User\Documents\Github_Repo\dietary_app\companion\companion_js\companion-llm.js
// Description: All LLM-related configuration (prompts, tools schema) and execution logic (fetch call, outputs sanitization)

/**
 * 1. 系統 Prompt 定義 (SYSTEM_PROMPT)
 * 這是給 OpenAI 模型的全局系統指令。
 * 用於指導大語言模型扮演飲食推薦應用的 Companion Agent，分析使用者問句的意圖、問題種類、情緒並擷取料理名稱。
 */
const SYSTEM_PROMPT = `
You are a Companion Agent classifier and extractor for a dietary recommendation app.
Your task is to analyze the user's message (which is usually in Traditional Chinese) and determine the intent, question type, emotion, and extract mentioned food/dish names.

You MUST execute both functions (parallel tool calls): "screen_user_request" and "analyze_emotion" to return your results.

Specific Instructions for "screen_user_request":
1. should_handle (boolean): 
   - Set to true if the request is about diet, food, meal recommendation, or calorie queries.
   - Set to false if it involves sensitive medical diagnosis, prescription drugs, disease treatment, seeking a doctor's advice (e.g., "what medicine to take for gastric ulcers"), general chat, or unrelated topics.
2. intent_category (string):
   - "dish_advice": User is consulting for dietary advice or recommendation.
   - "meal_record": User is recording their meal/diet.
   - "medical_out_of_scope": User mentions medicine, prescriptions, disease treatment, diagnosis, or doctor queries.
   - "general_chat": General chat or unrelated topics.
3. question_type (string):
   - "single_dish": User asks about a single food item or meal.
   - "dish_comparison": User compares multiple foods (e.g., "A or B, which is better?", "A vs B").
   - "unknown": None of the above.
4. dishes (array of strings):
   - Extract all specific food, dish, or drink names mentioned in the user's input (e.g., ["拉麵", "炸雞"]). 
   - Extract them in their original language as written in the user message (usually Traditional Chinese, e.g., "拉麵"). 
   - Return an empty array if no food or dish is mentioned.
`;

/**
 * 2. OpenAI Function Calling (Tools) Schema 定義
 * 這是傳給 OpenAI 的結構化輸出合約。定義了模型「必須呼叫」的函數名稱以及參數的 JSON Schema。
 * 當模型回覆時，會依此格式返回 JSON 參數，後端程式可以直接解析。
 */
const tools = [
  {
    // 指定 Tool 類型為函數呼叫 (function)
    type: "function",
    function: {
      name: "screen_user_request",
      // 對此函數用途的描述，幫助 LLM 理解何時以及如何填寫此結構
      description: "Screen the user request to classify question type, intent, and extract mentioned dishes.",
      // 定義此函數需要接收的參數 (JSON Schema 格式)
      parameters: {
        type: "object", // 參數最外層為一個 JSON 物件
        properties: {
          // should_handle: 決定 Companion Agent 是否要接手處理此問題的 boolean 值
          should_handle: {
            type: "boolean",
            description: "Whether this request should be processed by the companion agent."
          },
          // intent_category: 意圖分類，限定模型只能在以下四個選項中選擇其一
          intent_category: {
            type: "string",
            enum: ["dish_advice", "meal_record", "medical_out_of_scope", "general_chat"]
          },
          // question_type: 問題的種類 (單料理、料理比較或未知)，決定後續 Dietary Agent 組裝的邏輯
          question_type: {
            type: "string",
            enum: ["single_dish", "dish_comparison", "unknown"]
          },
          // confidence: 模型對此分類判斷的信心分數 (0.0 到 1.0 之間)
          confidence: { type: "number" },
          // dishes: 存放 LLM 從問句中自動抽取出的料理或食物名稱陣列 (例如: ["炸雞", "拉麵"])
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
          "confidence",
          "dishes"
        ],
        // additionalProperties: false 是一項安全設定，嚴格限制模型不可輸出 properties 定義以外的自訂欄位
        additionalProperties: false
      }
    }
  },
  {
    type: "function",
    function: {
      name: "analyze_emotion",
      // 描述此函數用途：分析情緒以動態調整回覆語氣
      description: "Analyze the user's emotional state and tone to adjust companion responses.",
      parameters: {
        type: "object",
        properties: {
          // primary_emotion: 偵測到的主情緒列舉 (中性、好奇、焦慮、罪惡、壓力、挫折、開心)
          primary_emotion: {
            type: "string",
            enum: ["neutral", "curious", "anxiety", "guilt", "stress", "frustration", "joy"]
          },
          // valence: 情緒的正負向分類 (正向、中性、負向)
          valence: {
            type: "string",
            enum: ["positive", "neutral", "negative"]
          },
          // urgency: 使用者此時此刻心情的緊迫程度
          urgency: {
            type: "string",
            enum: ["low", "medium", "high"]
          },
          // needs_empathy: 決定最後回覆前是否需要安撫前綴。若為 true，會觸發同理心文字安撫
          needs_empathy: { type: "boolean" },
          // companion_tone: 建議的陪伴者語氣 (冷靜、鼓勵、中性)
          companion_tone: {
            type: "string",
            enum: ["calm", "encouraging", "neutral"]
          },
          // evidence: 支撐情緒判斷的對話中關鍵字依據 (例如使用者打的: ["焦慮", "吃太多了"])
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
        // additionalProperties: false 是一項安全設定，嚴格限制模型不可輸出 properties 定義以外的自訂欄位
        additionalProperties: false
      }
    }
  }
];

/**
 * 3. Post-check 意圖修正 (sanitizeScreening)
 * 當 OpenAI 回傳結果後，以此函式進行二次檢驗，確保格式正確。
 * @param {Object} raw - OpenAI 回傳的原始 arguments 物件
 * @returns {Object} 經過格式修復與預設值補齊後的意圖預檢結果
 */
function sanitizeScreening(raw) {
  if (!raw) {
    throw new Error("Missing 'screen_user_request' function call arguments from OpenAI response.");
  }

  const result = { ...raw };

  // 確保 dishes 必定是陣列結構，若模型漏填，預設為空陣列
  if (!Array.isArray(result.dishes)) {
    result.dishes = [];
  }

  return result;
}

/**
 * 4. Post-check 情緒修正 (sanitizeEmotion)
 * 驗證 OpenAI 回傳的情緒結構。若無回傳或屬性缺漏，填入預設值防呆。
 * @param {Object} raw - OpenAI 回傳的原始 arguments 物件
 * @returns {Object} 經過格式檢查後的情緒特徵結果
 */
function sanitizeEmotion(raw) {
  if (!raw) {
    throw new Error("Missing 'analyze_emotion' function call arguments from OpenAI response.");
  }
  return {
    primary_emotion: raw.primary_emotion || "neutral",
    valence: raw.valence || "neutral",
    urgency: raw.urgency || "medium",
    // 確保 needs_empathy 是正確的 boolean 型態，不為 undefined
    needs_empathy: typeof raw.needs_empathy === "boolean" ? raw.needs_empathy : false,
    companion_tone: raw.companion_tone || "neutral",
    evidence: Array.isArray(raw.evidence) ? raw.evidence : []
  };
}

/**
 * 5. 呼叫 OpenAI Responses API
 * 使用原生 fetch 發送 POST 請求至 OpenAI 伺服器端點。
 * @param {Object} body - OpenAI 要求的 Request Payload 格式
 * @param {string} apiKey - 系統載入之 OpenAI API Key 金鑰
 * @returns {Promise<Object>} OpenAI 解析完的 JSON 回應
 */
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

/**
 * 6. 解析並篩選出所有的 Function Call 項目
 * 從 OpenAI Responses API 回傳的 output 陣列中，過濾出屬於 function_call 類型的項目。
 * @param {Object} responseJson - OpenAI 回應的 JSON 數據
 * @returns {Array<Object>} function_call 項目陣列
 */
function getFunctionCalls(responseJson) {
  return (responseJson.output || []).filter((item) => item.type === "function_call");
}

/**
 * 7. 收集並轉換所有的 Tool 參數物件
 * 將多個 function call 的 arguments 欄位由 JSON 字串轉換成 JavaScript 物件。
 * @param {Array<Object>} functionCalls - Function Call 項目陣列
 * @returns {Object} 以函數名稱為 Key，參數物件為 Value 的映射
 */
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

/**
 * 8. 執行 OpenAI 主要流程 (runOpenAIFlow)
 * @param {string} userPrompt - 使用者原始文字提問
 * @returns {Promise<Object>} 包含意圖預檢 (screening)、情緒特徵 (emotion)
 */
async function runOpenAIFlow(userPrompt) {
  const apiKey = process.env.OPENAI_API_KEY;
  const model = process.env.OPENAI_MODEL || "gpt-4o-mini";

  if (!apiKey) {
    throw new Error("Missing OPENAI_API_KEY.");
  }

  // 發送至 OpenAI 進行 parallel tool calls
  const response = await createOpenAIResponse(
    {
      model,
      parallel_tool_calls: true, // 啟用平行工具呼叫，單次請求同時執行意圖與情緒判定
      tool_choice: "auto",
      // 將 tools 陣列元素拉平，轉換成 Responses API 所規定的扁平（Flat）格式
      tools: tools.map(t => {
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
      instructions: SYSTEM_PROMPT,
      input: [
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: userPrompt,
            },
          ],
        },
      ],
    },
    apiKey
  );

  // 收集 Tool arguments 結果
  const functionCalls = getFunctionCalls(response);
  const rawArgs = collectToolArgsByName(functionCalls);

  // 執行 Post-check 驗證與欄位修正
  const screening = sanitizeScreening(rawArgs.screen_user_request);
  const emotion = sanitizeEmotion(rawArgs.analyze_emotion);

  return {
    screening,
    emotion
  };
}

module.exports = {
  runOpenAIFlow
};
```

### 2.2 API 連線與校驗調度服務 (`Companion/companion-agent-services.js`)
* **第一行**：檔案路徑
* **第二行**：檔案功用說明

```javascript
// Path: c:\Users\User\Documents\Github_Repo\dietary_app\companion\companion_js\companion-agent-services.js
// Description: External API services for communicating with OpenAI and Dietary Agent

// 引入 OpenAI Prompt 與 Function Schema 的設定檔
const { SYSTEM_PROMPT, tools } = require("./companion-agent-config");
// 引入本地端輔助函數、保底評估與資料清理驗證的 Helpers
const {
  sanitizeScreening,
  sanitizeEmotion,
  buildDietaryAgentRequest
} = require("./companion-agent-helpers");


/**
 * 1. 呼叫 OpenAI Responses API
 * 使用原生 fetch (javascript內建模組，用來發送網路請求) ，將整理好的 payload(實際要傳送的內容) 送往 OpenAI 終端。
 * @param {Object} body - 送給 OpenAI 的請求內容 (包含 prompt, inputs, tools 等)
 * @param {string} apiKey - 您的 OpenAI API Key
 */

async function createOpenAIResponse(body, apiKey) {
  const response = await fetch("https://api.openai.com/v1/responses", {//TODO:填入OPENAI_API_KEY
    method: "POST",
    headers: {//設定標頭資訊，告知伺服器
      "Content-Type": "application/json",//說明送過去的格式是 json
      Authorization: `Bearer ${apiKey}`,//驗證身分，附上金鑰
    },
    body: JSON.stringify(body), //將整理好的 payload 轉為 JSON 字串
  });

  // 錯誤處理：若 API 回傳非 200 OK(例如網路問題或權限問題)，拋出錯誤，讓上層 catch 機制能順利捕捉並切換到 Fallback 流程
  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`OpenAI API error ${response.status}: ${errorText}`);
  }

  return response.json();
}

/**
 * 2. 解析並篩選出所有的 Function Call項目
 * 從 OpenAI Responses API 回傳的 output 陣列中，過濾出屬於 function_call 類型的項目。
 */
function getFunctionCalls(responseJson) {
  return (responseJson.output || []).filter((item) => item.type === "function_call");
}

/**
 * 3. 收集並轉換所有的 Tool 參數物件
 * 將多個 function call 的 arguments 欄位由 JSON 字串轉換成 JavaScript 物件，
 * 並依 function name (例如: screen_user_request, analyze_emotion) 作為 key 分類儲存。
 */
function collectToolArgsByName(functionCalls) {
  const byName = {};
  for (const call of functionCalls) {
    try {
      // 將 arguments (JSON string) 解析為 JS 物件，若為空則預設為空物件 {}
      byName[call.name] = JSON.parse(call.arguments || "{}");
    } catch {
      // 容錯機制：若模型產出損毀的 JSON，設為 null，以在 sanitize 階段進行 Fallback
      byName[call.name] = null;
    }
  }
  return byName;
}

/**
 * 4. 執行 OpenAI 主要流程 (runOpenAIFlow)
 * 整合：發送 API 請求 -> 解析回傳 parameters -> Post-check 清理驗證 -> 封裝三元素 request。
 * @param {Object} bundle - 包含 message 與 user_context 的核心資料包
 */
async function runOpenAIFlow(userPrompt) {
  const apiKey = process.env.OPENAI_API_KEY;
  const model = process.env.OPENAI_MODEL || "gpt-4o-mini";

  if (!apiKey) {
    throw new Error("Missing OPENAI_API_KEY.");
  }

  // 4.1 發送至 OpenAI 進行 parallel tool calls
  const response = await createOpenAIResponse(
    {
      model,
      parallel_tool_calls: true, // 啟用平行工具呼叫，讓模型在單次請求中同時執行意圖與情緒判定
      tool_choice: "auto",
      tools: tools.map(t => {
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
      instructions: SYSTEM_PROMPT,
      input: [
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: userPrompt, // 將使用者的純文字問句傳給模型
            },
          ],
        },
      ],
    },
    apiKey
  );

  // 4.2 抽取並收集 Tool arguments 結果
  const functionCalls = getFunctionCalls(response);
  const rawArgs = collectToolArgsByName(functionCalls);

  // 4.3 執行 Post-check 驗證與欄位修正
  const screening = sanitizeScreening(rawArgs.screen_user_request);
  const emotion = sanitizeEmotion(rawArgs.analyze_emotion);

  // 4.4 依據驗證結果組裝傳遞給 Dietary Agent 的三元素 payload
  const dietaryAgentRequest = buildDietaryAgentRequest(screening, userPrompt);

  return {
    screening,
    emotion,
    dietary_agent_request: dietaryAgentRequest
  };
}

/**
 * 5. 呼叫 Dietary Agent API
 * 將組裝好的三元素 Payload POST 發送給 Dietary Agent。
 * @param {Object} requestBody - 包含 question, question_type, dishes 的三元素物件
 * @param {string} authHeader - 前端傳來的 Authorization Header
 */
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
  // TODO:根據蔓蔓給的 Dietary Agent API 路徑(DietaryAgentController)
  const response = await fetch(`${baseUrl}/api/dietary/ask-weekly-analysis`, {
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
 * 6. 組裝最終的陪伴式回覆 (buildCompanionReply)
 * 根據意圖與情緒狀態，調整自然語言回覆，將 Dietary Agent 的推論結合安撫前綴。
 */
function buildCompanionReply({ screening, emotion, dietaryAgentResponse, dietaryAgentRequest }) {
  // 醫療超出範圍的柔和拒絕
  if (screening.intent_category === "medical_out_of_scope") {
    return "這類問題比較接近醫療診斷或治療判斷，我目前不能直接替代專業醫療建議。建議您諮詢醫生 or 合格的醫療專家喔。";
  }

  // 非飲食諮詢的閒聊回覆
  if (!screening.should_handle) {
    return "這句話目前不像是飲食建議模組要處理的內容。如果您有關於餐點選擇、熱量或減脂增肌的問題，隨時可以問我！";
  }

  // TODO: 有點類似於「引導補問機制」，偵測到資料不足以進行下一步時，不直接報錯，但要如何將抓到更多錯誤，讓回復的方式更多元以及貼合。
  // 檢查是否因為參數攔截（未提供具體料理或問題類型未知）而沒有呼叫 Dietary Agent
  if (screening.should_handle && !dietaryAgentRequest) {
    if (!screening.dishes || screening.dishes.length === 0) {
      return "我目前無法從您的問題中提取出具體的食物名稱。可以請您提供想諮詢的餐點名稱嗎？例如：「晚餐吃炸雞適合嗎？」";
    }
    if (screening.question_type !== "single_dish" && screening.question_type !== "dish_comparison") {
      return "我目前無法判斷您問題的類型，請試著具體詢問單一食物的熱量，或是比較多個食物喔！";
    }
    return "抱歉，我目前無法理解您的問題，請重新輸入更具體的飲食問題。";
  }

  // 根據同理心安撫指標 needs_empathy，決定回覆開頭的語氣
  const empathyPrefix = emotion.needs_empathy
    ? "我有注意到你現在有點在意這次的選擇，先不用太緊張喔。❤️\n"
    : "我先幫您整理這次的飲食建議：\n";

  // TODO: 等待蔓蔓Dietary Agent 完整回覆結構
  // 將前綴與 Dietary Agent 回傳的建議融合
  let recommendation = "已成功記錄您的問題，正在為您尋求最佳飲食建議。";
  if (dietaryAgentResponse) {
    recommendation = dietaryAgentResponse.reply_text || dietaryAgentResponse.conclusion || JSON.stringify(dietaryAgentResponse);
  }

  return `${empathyPrefix}${recommendation}`;
}

// 導出服務模組供 companion-agent.js 使用
module.exports = {
  runOpenAIFlow,
  callDietaryAgent,
  buildCompanionReply
};
```

### 2.3 主進入點與伺服器路由 (`Companion/companion-agent.js`)
* **第一行**：檔案路徑
* **第二行**：檔案功用說明

```javascript
// Path: c:\Users\User\Documents\Github_Repo\dietary_app\companion\companion_js\companion-agent.js
// Description: Main entry point for Express server, routing HTTP requests, and orchestrating flow

// 載入環境變數設定檔 (.env)，叫 Node.js 去讀取並載入 .env 檔案裡的變數。
require("dotenv").config();

// 引入 Express 框架用以建立 HTTP API 服務
const express = require("express");
// 引入 CORS 套件，允許 Flutter 前端跨網域存取後端 API
const cors = require("cors");
// 引入外部 API 服務模組 (包含 OpenAI 串接、保底流程、Dietary Agent 串接以及文字組裝)
const {
  runOpenAIFlow,
  callDietaryAgent,
  buildCompanionReply
} = require("./companion-agent-services");

// 1. 初始化 Express App 實例
const app = express();
// 2. 啟用 CORS 跨域支援
app.use(cors());
// 3. 解析請求主體為 JSON 格式 (req.body)
app.use(express.json());

/**
 * 5. 主要 API 請求調度器 (handleCompanionAsk)
 * 串接完整流程：前端請求 -> 意圖情緒分析 (OpenAI/保底) -> 呼叫 Dietary Agent -> 回覆生成 -> 前端回應。
 */
async function handleCompanionAsk(req, res) {
  // 1. 引數錯誤 (HTTP 400 Bad Request)
  const user_prompt = typeof req.body.user_prompt === "string" ? req.body.user_prompt.trim() : "";
  if (!user_prompt) {
    return res.status(400).json({
      success: false,
      error_code: "BAD_REQUEST",
      error_message: "The 'user_prompt' field is required and must be a non-empty string."
    });
  }

  let openAiResult;

  // 【第一階段】：執行意圖分析、料理名稱擷取與情緒識別
  try {
    // 優先嘗試執行 OpenAI responses API 流程
    openAiResult = await runOpenAIFlow(user_prompt);
  } catch (error) {
    // 容錯機制：若 OpenAI 呼叫失敗，印出 log，回傳 502 Bad Gateway 錯誤
    console.error("OpenAI flow failed:", error.message);
    return res.status(502).json({
      success: false,
      error_code: "OPENAI_SERVICE_ERROR",
      error_message: "Failed to communicate with OpenAI API. Please try again later.",
      debug_message: error.message
    });
  }

  // 2. 其餘流程包裝在 try...catch 以捕捉 500 內部伺服器錯誤
  try {
    let dietaryAgentResponse = null;
    let dietaryAgentError = null;

    // 【第二階段】：呼叫 Dietary Agent (只在 should_handle = true 且資料足夠時呼叫)
    if (openAiResult.dietary_agent_request) {
      try {
        // 獲取並傳遞 Authorization 標頭，供 Java 後端 Spring Security 驗證使用者身份
        const authHeader = req.headers.authorization;
        dietaryAgentResponse = await callDietaryAgent(openAiResult.dietary_agent_request, authHeader);
      } catch (error) {
        // 容錯機制：若 Dietary Agent API 掛掉，捕捉錯誤並記錄，但不使主進程崩潰
        console.error("Dietary Agent call failed:", error.message);
        dietaryAgentError = error.message;
      }
    }

    // 【第三階段】：整合所有分析結果，回傳結構化 JSON 回應給前端
    return res.json({
      success: true,
      llm_fallback_used: false, // 固定為 false
      // 輸出經後端 Sanitize 修正後的結構化預檢資訊
      screening: {
        should_handle: openAiResult.screening.should_handle,
        intent_category: openAiResult.screening.intent_category,
        question_type: openAiResult.screening.question_type,
        confidence: openAiResult.screening.confidence,
        dishes: openAiResult.screening.dishes
      },
      emotion: openAiResult.emotion,
      // 輸出實際發往 Dietary Agent 的三元素 Payload 內容，供前端觀察驗證
      dietary_agent_request: openAiResult.dietary_agent_request,
      dietary_agent_response: dietaryAgentResponse,
      dietary_agent_error: dietaryAgentError,
      // 生成最終顯示在 Flutter UI 上的陪伴式對話文字
      companion_reply: buildCompanionReply({
        screening: openAiResult.screening,
        emotion: openAiResult.emotion,
        dietaryAgentResponse,
        dietaryAgentRequest: openAiResult.dietary_agent_request
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

// 6. 設定基礎健康檢查路由 (Health Check Endpoint)
// 檢查companion_agent是否正常運作:只要有收到請求，就回傳{status:"ok"}
app.get("/health", (_req, res) => {
  res.json({ status: "ok" });
});

// TODO:Companion Agent 提供的API
// 7. 設定主要對話 Endpoint，供 Flutter 呼叫
app.post("/companion/ask", handleCompanionAsk);

// 8. 讀取 .env 中的埠口設定，啟動 Express 伺服器監聽請求
const port = Number(process.env.COMPANION_API_PORT || 3000);
app.listen(port, () => {
  console.log(`Companion Agent API listening on port ${port}`);
});
```

## 3. 測試與驗證指南

您可以啟動此服務後，使用 `curl` 在本機進行測試，驗證傳遞給 Dietary Agent 的資料結構與回覆結果：

### 驗證情境一：一般飲食問題且帶有焦慮情緒
```bash
curl -X POST http://localhost:3000/companion/ask \
-H "Content-Type: application/json" \
-d '{
  "user_prompt": "我今天中午吃炸雞了，晚上還能吃拉麵嗎？我有點焦慮。",
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
  "user_prompt": "牛肉麵跟水餃哪一個熱量比較高？",
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
  "user_prompt": "這個降血糖藥我應該怎麼服用？請幫我診斷。"
}'
```
* **預期結果**：
  - `screening.should_handle` 為 `false`。
  - `screening.intent_category` 為 `"medical_out_of_scope"`。
  - **不呼叫** Dietary Agent API。
  - 回覆提示使用者這屬於醫療問題，應尋求專業建議。
