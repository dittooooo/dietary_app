// Companion Agent 最終自然語言回覆的 LLM 設定與執行邏輯。
const {
  REPLY_SYSTEM_PROMPT,
  CURRENT_TURN_RESPONSE_POLICY
} = require("./prompts/replyPrompt");

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
 *   - {Object} userProfileContext - 登入使用者的個人資料、疾病與飲食目標
 *   - {Array<Object>} tempStory - 前端傳入的近 10 組來回歷史對話
 * @returns {Promise<string>} LLM 重組潤飾後的對話文字
 */
async function generateCompanionReply({
  userPrompt,
  screening,
  emotion,
  dietaryAgentResponse,
  dietaryAgentError,
  userProfileContext,
  tempStory = []
}) {
  const apiKey = process.env.OPENAI_API_KEY;
  const model = process.env.OPENAI_MODEL || "gpt-4o-mini";

  if (!apiKey) {
    throw new Error("Missing OPENAI_API_KEY.");
  }

  // 將 Dietary Agent 回傳的結構化資料進行簡化降噪後轉為易讀的 JSON 字串，以利 LLM 讀取理解
  const dietaryContext = dietaryAgentResponse
    ? minimizeDietaryResponse(dietaryAgentResponse)
    : null;
  const rawDataStr = JSON.stringify(dietaryContext || {}, null, 2);
  const replyTemperature = screening?.date_validation?.is_future ? 0.7 : 0.2;
  const futureDateContext = screening?.date_validation?.is_future
    ? `\n\n本輪日期限制情境：指定日期為 ${screening.date_validation.requested_date}，意圖為 ${screening.intent_category}，餐點為 ${JSON.stringify((screening.meal_items || []).map(item => item.name).filter(Boolean))}。請根據這些實際內容重新組織自然回覆，不可使用通用模板；meal_record 有餐點時必須提到餐點名稱。`
    : "";

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
      temperature: replyTemperature,
      messages: [
        {
          role: "system",
          // 帶入重組引導的系統 Prompt 規則 (包含數值免責聲明)
          content: REPLY_SYSTEM_PROMPT
        },
        ...formattedHistory,
        {
          role: "system",
          content: CURRENT_TURN_RESPONSE_POLICY
        },
        {
          role: "user",
          // 組合完整的上下文，供模型重組出最貼近的對話
          content: `使用者問句: "${userPrompt}"\n\n意圖與篩選設定 (screening): ${JSON.stringify(screening)}\n\n情緒與同理心設定: ${JSON.stringify(emotion)}\n\n使用者個人資料 (userProfileContext): ${JSON.stringify(userProfileContext || {})}\n\nDietary Agent 回傳資料:\n${rawDataStr}${futureDateContext}\n\n請直接生成給使用者的實用回覆。不得提及資料缺口、系統錯誤、查詢狀態或無法提供建議。`
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
  const reply = sanitizeCompanionReply(resJson.choices[0].message.content);
  return ensureReadableParagraphs(reply, screening);
}

/**
 * 移除不應出現在使用者介面的內部限制說明與裝飾符號。
 */
function sanitizeCompanionReply(reply) {
  const forbiddenStatus = /[^。！？!?\n]*(?:(?:沒有|缺少|欠缺)[^。！？!?\n]*(?:資料|資訊)|(?:無法|沒辦法|沒有辦法)[^。！？!?\n]*(?:提供|判斷|評估|確定)|(?:資料|資訊)不足|(?:評估|判斷)[^。！？!?\n]*(?:困難|挑戰))[^。！？!?\n]*[。！？!?]?/g;
  return String(reply || "")
    .replace(/\r\n/g, "\n")
    .replace(forbiddenStatus, "")
    .replace(/[\p{Extended_Pictographic}\uFE0F]/gu, "")
    .replace(/^\s*[-•●▪◆◇▶▷■□]+\s*/gm, "")
    .replace(/[＊*＃#＿_～~]/g, "")
    .replace(/[ \t]+$/gm, "")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

/**
 * 確保飲食建議不會退化成一整段文字。
 * 若模型沒有輸出空行，依中文句號切成至少三個短段落；已有段落時則保留原格式。
 */
function ensureReadableParagraphs(reply, screening) {
  if (screening?.intent_category !== "dish_advice") return reply;

  const normalized = reply.replace(/\r\n/g, "\n").trim();
  const paragraphs = normalized.split(/\n\s*\n/).map(part => part.trim()).filter(Boolean);
  if (paragraphs.length >= 3) return normalized;

  let sentences = normalized
    .split(/(?<=[。！？!?])/)
    .map(sentence => sentence.trim())
    .filter(Boolean);
  if (sentences.length < 3) {
    sentences = normalized
      .split(/(?<=[。！？!?；;，,])/)
      .map(sentence => sentence.trim())
      .filter(Boolean);
  }
  if (sentences.length < 3) return normalized;

  const paragraphCount = 3;
  const groups = Array.from({ length: paragraphCount }, () => []);
  sentences.forEach((sentence, index) => {
    groups[Math.min(Math.floor(index * paragraphCount / sentences.length), paragraphCount - 1)].push(sentence);
  });
  return groups.map(group => group.join("")).filter(Boolean).join("\n\n");
}

module.exports = {
  generateCompanionReply
};
