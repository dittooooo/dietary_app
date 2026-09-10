// Companion Agent 最終自然語言回覆的 LLM 設定與執行邏輯。
const { REPLY_SYSTEM_PROMPT } = require("./prompts/replyPrompt");

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
 * 呼叫 OpenAI Chat Completions 重組最終的陪伴式回覆。
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

  // 使用 Chat Completions API 產生最終自然語言回覆。
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

module.exports = {
  generateCompanionReply
};
