// Path: c:\Users\User\Documents\Github_Repo\dietary_app\companion\companion_js\companion-agent-services.js
// Description: External API services for communicating with OpenAI and Dietary Agent

const {
  runOpenAIFlow: runLLMAnalysis,
  generateCompanionReply: runLLMReply
} = require("./companion-llm");

/**
 * Build Dietary Agent request payload from the LLM screening result.
 * Only well-formed requests are forwarded downstream.
 * @param {Object} screening
 * @param {string} message
 * @returns {Object|null}
 */
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

/**
 * Run the first LLM pass to classify the request and extract structured data.
 * @param {string} userPrompt
 * @returns {Promise<Object>}
 */
async function runOpenAIFlow(userPrompt) {
  const result = await runLLMAnalysis(userPrompt);
  const dietaryAgentRequest = buildDietaryAgentRequest(result.screening, userPrompt);

  return {
    screening: result.screening,
    emotion: result.emotion,
    dietary_agent_request: dietaryAgentRequest
  };
}

/**
 * Call the downstream Dietary Agent API when the request is specific enough.
 * @param {Object} requestBody
 * @param {string} authHeader
 * @returns {Promise<Object>}
 */
async function callDietaryAgent(requestBody, authHeader) {
  const baseUrl = process.env.DIETARY_AGENT_API_URL;
  if (!baseUrl) {
    throw new Error("Missing DIETARY_AGENT_API_URL variable in .env");
  }

  const headers = {
    "Content-Type": "application/json"
  };

  if (authHeader) {
    headers.Authorization = authHeader;
  }
  // 根據後端 Controller 的 @RequestMapping("/dietary-agent") 與 @PostMapping("/ask") 進行對接
  const response = await fetch(`${baseUrl}/dietary-agent/ask`, {
    method: "POST",
    headers,
    body: JSON.stringify(requestBody)
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
 * 
 * @param {Object} params - 包含對話所需的完整上下文資料
 * @returns {Promise<string>} 最終生成的陪伴回覆文字
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
