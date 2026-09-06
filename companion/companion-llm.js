// Path: c:\Users\User\Documents\Github_Repo\dietary_app\companion\companion-llm.js
// Description: All LLM-related configuration and execution logic

// 匯入抽離至 prompts/ 目錄中的系統提示詞與 Function Calling 工具定義
const {
  ANALYSIS_SYSTEM_PROMPT,
  tools,
  REPLY_SYSTEM_PROMPT,
  TRANSLATION_SYSTEM_PROMPT
} = require("./prompts");

/**
 * ============================================================================
 * 第一部分：輔助工具函數與環境變數載入
 * ============================================================================
 */

/**
 * 從環境變數中取得 OpenAI API 金鑰
 * @returns {string} API 金鑰
 */
function getApiKey() {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    throw new Error("Missing OPENAI_API_KEY.");
  }
  return apiKey;
}

/**
 * 從環境變數中取得欲使用的 OpenAI 模型名稱，預設為 "gpt-4o-mini"
 * @returns {string} 模型名稱
 */
function getModel() {
  return process.env.OPENAI_MODEL || "gpt-4o-mini";
}

/**
 * 帶有 Timeout 中斷防護的安全 Fetch 函式
 * @param {string} url - 請求目標 URL
 * @param {Object} options - Fetch 選項
 * @param {number} timeoutMs - 超時毫秒數 (預設 30000ms / 30秒)
 * @returns {Promise<Response>} Fetch Response 物件
 */
async function safeFetch(url, options = {}, timeoutMs = 30000) {
  return fetch(url, {
    ...options,
    signal: options.signal || AbortSignal.timeout(timeoutMs)
  });
}

/**
 * 呼叫 OpenAI Responses API 建立回應 (用於第一階段多功能平行分析)
 * @param {Object} body - 發送給 OpenAI 的請求主體 payload
 * @param {string} apiKey - OpenAI API 憑證金鑰
 * @returns {Promise<Object>} OpenAI API 回傳的 JSON 回應
 */
async function createOpenAIResponse(body, apiKey) {
  const response = await safeFetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`
    },
    body: JSON.stringify(body)
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`OpenAI API error ${response.status}: ${errorText}`);
  }

  return response.json();
}

/**
 * 從 OpenAI Response API 的回傳結果中提取出所有 Function Calls 的調用項目
 * @param {Object} responseJson - API 回傳的完整 JSON 資料
 * @returns {Array<Object>} function_call 類型的陣列
 */
function getFunctionCalls(responseJson) {
  return (responseJson.output || []).filter((item) => item.type === "function_call");
}

/**
 * 將多個平行 Function Calls 的參數解析並彙整成以工具名稱為 Key 的物件對照表
 * @param {Array<Object>} functionCalls - Function Call 呼叫項目陣列
 * @returns {Object} 以工具名稱為鍵、解析後參數為值的對照表
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
      question_type: undefined,
      confidence: 0,
      dish_info_list: {},
      meal_items: [],
      query_date: null
    };
  }

  const result = { ...raw };
  if (!Array.isArray(result.meal_items)) {
    result.meal_items = [];
  }
  if (!result.query_date) {
    result.query_date = null;
  }

  // ── 自動衍生欄位（Single Source of Truth）：從一維 meal_items 提煉所有食物名稱與份數，生成 dish_info_list 物件 ──
  const dishInfoList = {};
  for (const item of result.meal_items) {
    if (item && item.name) {
      const amount = (typeof item.quantity === "number" && item.quantity > 0) ? item.quantity : 1;
      dishInfoList[item.name] = amount;
    }
  }
  result.dish_info_list = dishInfoList;

  // 強制規則防護：如果意圖不是飲食建議，則 question_type 強制歸類為 "not_applicable"
  if (result.intent_category !== "dish_advice") {
    result.question_type = "not_applicable";
  } else if (!result.question_type) {
    result.question_type = "unknown";
  }

  return result;
}

/**
 * 情緒分析結果的容錯防呆機制
 * 當 OpenAI 沒有觸發情緒工具調用時，回傳預設的中性情緒與同理心指標
 * @param {Object} raw - 原始從 LLM 獲得的情緒參數物件
 * @returns {Object} 經過清理與預設值補齊後的情緒物件
 */
function sanitizeEmotion(raw) {
  // 容錯防呆：如果 OpenAI 沒有觸發情緒工具調用，給予預設情緒物件
  if (!raw) {
    return {
      primary_emotion: "neutral",
      psychological_context: "other_general_chat",
      companion_tone: "neutral",
      evidence: []
    };
  }

  return {
    primary_emotion: raw.primary_emotion || "neutral",
    psychological_context: raw.psychological_context || "other_general_chat",
    companion_tone: raw.companion_tone || "neutral",
    evidence: Array.isArray(raw.evidence) ? raw.evidence : []
  };
}

/**
 * ============================================================================
 * 第二部分：核心 LLM 處理流程 (Prompt、Schema 與 呼叫函數成對擺放)
 * ============================================================================
 */

// ----------------------------------------------------------------------------
// 階段 1：意圖篩選與情緒分析 (First-stage classification and emotion screening)
// ----------------------------------------------------------------------------

/**
 * 執行第一階段的意圖篩選與情緒分析流程
 * 透過呼叫 OpenAI Response API 並行調用 screen_user_request 與 analyze_emotion 兩個 Function。
 * @param {string} userPrompt - 使用者原始輸入訊息
 * @param {Array<Object>} tempStory - 前端傳入的近 3 則對話歷史
 * @returns {Promise<Object>} 包含意圖預檢 (screening) 與情緒分析 (emotion) 結果的物件
 */
async function runOpenAIFlow(userPrompt, tempStory = []) {
  // 取得台灣當前本地時間 (強制使用標準 24 小時制，方便 LLM 進行時間區間對比)
  const now = new Date();
  const localTimeStr = now.toLocaleString("zh-TW", {
    timeZone: "Asia/Taipei",
    hour12: false,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit"
  });

  // 格式化對話歷史供 Prompt 上下文使用 (解決省略句與比較指涉問題)
  const historyText = Array.isArray(tempStory) && tempStory.length > 0
    ? tempStory.map(m => `${m.role === 'user' ? '使用者' : '米粒'}: ${m.content}`).join('\n')
    : "無歷史對話";

  // 組合成富含 24 小時制時間與歷史對話上下文的提示輸入
  const promptWithTime = `【歷史對話紀錄】:\n${historyText}\n\n當前系統時間: ${localTimeStr}\n使用者最新輸入: "${userPrompt}"`;

  const response = await createOpenAIResponse(
    {
      model: getModel(),
      parallel_tool_calls: true, // 啟用平行 Function Calling
      tool_choice: "auto",
      tools: tools.map((tool) => ({
        type: "function",
        name: tool.function.name,
        description: tool.function.description,
        parameters: tool.function.parameters
      })),
      instructions: ANALYSIS_SYSTEM_PROMPT,
      input: [
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: promptWithTime
            }
          ]
        }
      ]
    },
    getApiKey()
  );

  // 解析與收集 Function Calls 參數結果
  const functionCalls = getFunctionCalls(response);
  const rawArgs = collectToolArgsByName(functionCalls);

  // 對回傳結果進行防呆格式化處理後返回
  return {
    screening: sanitizeScreening(rawArgs.screen_user_request),
    emotion: sanitizeEmotion(rawArgs.analyze_emotion)
  };
}

// ----------------------------------------------------------------------------
// 階段 2：陪伴式回覆重組與生成 (Second-stage reply rewrite and generation)
// ----------------------------------------------------------------------------


/**
 * 簡化 Dietary Agent 回傳的資料，將權威結論 conclusion 置頂，並保留完整餐點營養數據，精準導引 LLM 注意力。
 * @param {Object} response - 原始 Dietary Agent API 回傳物件
 * @returns {Object|null} 簡化後的資料結構，若無資料則回傳 null
 */
function minimizeDietaryResponse(response) {
  if (!response) return null;

  // DietaryAgent 的 HTTP 回應會以 { success, message, data } 包裝；
  // 也兼容直接傳入 NutritionistAgent 資料的呼叫方式。
  const data = response.data && typeof response.data === "object"
    ? response.data
    : response;
  const minimized = {};

  if (data.health_condition && typeof data.health_condition === "object") {
    minimized.health_condition = {
      has_chronic_disease: Boolean(data.health_condition.has_chronic_disease),
      chronic_diseases: Array.isArray(data.health_condition.chronic_diseases)
        ? data.health_condition.chronic_diseases.filter(name => typeof name === "string" && name.trim())
        : []
    };
  }

  // 1. 【重點】將最高權重的整體結論置於 JSON 最頂層，強引導 LLM 注意力
  if (data.conclusion) {
    minimized.conclusion = data.conclusion;
  }

  // 2. 保留各料理的專業建議、適合度、關鍵理由 (key_reasons) 與建議處置 (suggestions)
  if (Array.isArray(data.dish_advice)) {
    minimized.dish_advice = data.dish_advice.map(advice => ({
      dish_name: advice.dish_name,
      matched_name: advice.matched_name,
      matched_type: advice.matched_type,
      match_score: advice.match_score,
      match_reason: advice.match_reason,
      suitability: advice.suitability,
      key_reasons: Array.isArray(advice.key_reasons) ? advice.key_reasons : [],
      suggestions: Array.isArray(advice.suggestions) ? advice.suggestions : []
    }));
  }

  // 3. 保留餐點營養數據 (包含名稱、所有營養素項目如 Calories, Protein, Sodium 等、數值與單位)
  if (Array.isArray(data.dish_nutrition)) {
    minimized.dish_nutrition = data.dish_nutrition.map(dish => ({
      dish_name: dish.dish_name,
      matched_name: dish.matched_name,
      matched_type: dish.matched_type,
      match_score: dish.match_score,
      match_reason: dish.match_reason,
      retrieval_strategy: dish.retrieval_strategy,
      nutrients: (dish.nutrients || []).map(n => ({
        name: n.name,
        amount_per_serving: n.amount_per_serving,
        unit: n.unit
      }))
    }));
  }

  return minimized;
}

/**
 * 9. 呼叫 OpenAI Chat Completions 重組最終的陪伴式回覆 (generateCompanionReply)
 * 作用：將使用者原始提問、同理心/情緒分析設定與 Dietary Agent 的分析結果，
 * 包裝後發送給 OpenAI Chat Completions API 重組，生成溫馨自然的陪伴回覆。
 * 
 * @param {Object} params - 包含以下屬性：
 *   - {string} userPrompt - 使用者原始輸入文字
 *   - {Object} screening - 意圖與食物名稱的預檢篩選結果
 *   - {Object} emotion - 偵測到的情緒與同理心指標
 *   - {Object} dietaryAgentResponse - Dietary Agent API 回傳的營養與建議數據
 *   - {string} dietaryAgentError - 下游服務 API 呼叫的錯誤訊息 (如有)
 *   - {Array<Object>} tempStory - 前端傳入的近 3 則對話歷史
 * @returns {Promise<string>} LLM 重組潤飾後的對話文字
 */
async function generateCompanionReply({
  userPrompt,
  screening,
  emotion,
  dietaryAgentResponse,
  dietaryAgentError,
  tempStory = []
}) {
  const apiKey = process.env.OPENAI_API_KEY;
  const model = process.env.OPENAI_MODEL || "gpt-4o-mini";

  if (!apiKey) {
    throw new Error("Missing OPENAI_API_KEY.");
  }

  // 將 Dietary Agent 回傳的結構化資料進行簡化降噪後轉為易讀的 JSON 字串，以利 LLM 讀取理解
  const rawDataStr = dietaryAgentResponse
    ? JSON.stringify(minimizeDietaryResponse(dietaryAgentResponse), null, 2)
    : "無資料";

  // 將前置對話歷史轉換為符合 OpenAI Chat Completions 標準的 messages 格式
  const formattedHistory = Array.isArray(tempStory)
    ? tempStory.map(m => ({
      role: m.role === 'user' ? 'user' : 'assistant',
      content: m.content
    }))
    : [];

  // 呼叫 OpenAI 官方標準的 Chat Completions API
  // 【API 差異備忘說明】：
  // 1. 原本程式碼的「第一階段 (意圖與情緒分析)」使用的是 OpenAI Responses API (端點為 /v1/responses)，
  //    它是屬於新版/實驗性之 Agentic API，傳入參數使用 instructions 與 input 結構。
  // 2. 此處的「第二階段 (對話回覆生成)」則採用 Chat Completions API (端點為 /v1/chat/completions)，
  //    這是目前業界最通用的無狀態標準對話格式，藉由 messages (system / user) 陣列傳遞。
  //    它的相容性最高，未來若想更換成其他大型語言模型 (如 Google Gemini、Anthropic Claude)，程式碼無須重構。
  const response = await safeFetch("https://api.openai.com/v1/chat/completions", {
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
          // 帶入重組引導的系統 Prompt 規則 (包含數值免責聲明)
          content: REPLY_SYSTEM_PROMPT
        },
        ...formattedHistory,
        {
          role: "user",
          // 組合完整的上下文，供模型重組出最貼近的對話
          content: `使用者問句: "${userPrompt}"\n\n意圖與篩選設定 (screening): ${JSON.stringify(screening)}\n\n情緒與同理心設定: ${JSON.stringify(emotion)}\n\nDietary Agent 異常訊息 (dietaryAgentError): ${dietaryAgentError || "無"}\n\nDietary Agent 回傳資料:\n${rawDataStr}`
        }
      ],
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

  // 取得 LLM 生成並去除首尾空白後的內容
  return resJson.choices[0].message.content.trim();
}

// ----------------------------------------------------------------------------
// 階段 3：餐點/飲料名稱翻譯與標準化 (Third-stage food translation)
// ----------------------------------------------------------------------------

/**
 * 呼叫 OpenAI Chat Completions API 將花俏的餐點名稱翻譯/拆解為食品資料庫標準品名
 * @param {Array<string>} dishes - 原始擷取出的餐點名稱陣列
 * @returns {Promise<Array<string>>} 翻譯與標準化後的餐點名稱陣列
 */
async function translateDishes(dishes) {
  if (!Array.isArray(dishes) || dishes.length === 0) {
    return [];
  }

  const apiKey = getApiKey();
  const model = getModel();

  try {
    const response = await safeFetch("https://api.openai.com/v1/chat/completions", {
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
            content: TRANSLATION_SYSTEM_PROMPT
          },
          {
            role: "user",
            content: JSON.stringify(dishes)
          }
        ],
        response_format: { type: "json_object" }
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error(`Translation API error: ${response.status} - ${errorText}`);
      return dishes; // 失敗時降級回傳原始餐點名稱
    }

    const resJson = await response.json();
    const content = resJson.choices[0].message.content.trim();
    const parsed = JSON.parse(content);
    if (parsed && Array.isArray(parsed.translated_dishes)) {
      return parsed.translated_dishes;
    }
  } catch (error) {
    console.error("Failed to translate dishes:", error.message);
  }

  return dishes; // 失敗時降級回傳原始餐點名稱
}

// 匯出大語言模型服務層核心函數
module.exports = {
  runOpenAIFlow,
  generateCompanionReply,
  translateDishes
};
