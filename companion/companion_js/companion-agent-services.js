// Path: c:\Users\User\Documents\Github_Repo\dietary_app\companion\companion_js\companion-agent-services.js
// Description: External API services for communicating with OpenAI and Dietary Agent

// 引入 LLM 核心生成邏輯
const { runOpenAIFlow: runLLM } = require("./companion-llm");

/**
 * 1. 封裝傳遞給 Dietary Agent 的三元素 Payload (嚴格檢查與攔截機制)
 * 針對 payload 的三個參數（question, question_type, dish_names）進行強型態與嚴格的有效性驗證：
 * 1. question：必須是非空字串。
 * 2. question_type：必須是合法的列舉值（single_dish 或 dish_comparison），且不能是 "unknown"。
 * 3. dish_names：必須是長度大於 0 的陣列。
 * 只要有任何一個不符合，就立刻中斷、完全不呼叫 Dietary Agent (返回 null)。
 * @param {Object} screening - LLM 意圖過濾結果
 * @param {string} message - 使用者問句
 * @returns {Object|null} 傳遞給 Java 後端的參數 Payload，若不符條件則回傳 null
 */
function buildDietaryAgentRequest(screening, message) {
  if (!screening || !screening.should_handle) {
    return null;
  }

  const question = typeof message === "string" ? message.trim() : "";
  const question_type = screening.question_type;
  const dish_names = screening.dishes || [];

  // 1. question 必須是非空字串
  if (!question) {
    return null;
  }
  // 2. question_type 必須是合法的列舉值（single_dish 或 dish_comparison），且不能是 "unknown"
  if (question_type !== "single_dish" && question_type !== "dish_comparison") {
    return null;
  }
  // 3. dish_names 必須是長度大於 0 的陣列
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
 * 2. 執行 OpenAI 主要流程並包裝三元素 Payload
 * 調用 companion-llm 取得語意分析結果，並利用 buildDietaryAgentRequest 決定是否攔截。
 * @param {string} userPrompt - 使用者問句
 * @returns {Promise<Object>} 包含意圖預檢、情緒與發送 Java 後端封裝 Payload 的物件
 */
async function runOpenAIFlow(userPrompt) {
  const result = await runLLM(userPrompt);
  const dietaryAgentRequest = buildDietaryAgentRequest(result.screening, userPrompt);
  return {
    screening: result.screening,
    emotion: result.emotion,
    dietary_agent_request: dietaryAgentRequest
  };
}

/**
 * 3. 呼叫 Dietary Agent API
 * 將組裝好的三元素 Payload POST 發送給 Dietary Agent。
 * @param {Object} requestBody - 包含 question, question_type, dish_names 的三元素物件
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
  // 根據後端 Controller 的 @RequestMapping("/dietary-agent") 與 @PostMapping("/ask") 進行對接
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
 * 4. 組裝最終的陪伴式回覆 (buildCompanionReply)
 * 根據意圖與情緒狀態，調整自然語言回覆，將 Dietary Agent 的推論結合安撫前綴。
 */
function buildCompanionReply({ screening, emotion, dietaryAgentResponse, dietaryAgentRequest }) {
  // TODO: 跟原本寫死的 isMedicalOutOfScope 不同，其是交給「OpenAI (大語言模型)」去判斷的(對應System_Prompt、tools的intent_catagory)。
  // 醫療超出範圍的柔和拒絕
  if (screening.intent_category === "medical_out_of_scope") {
    return "這類問題比較接近醫療診斷或治療判斷，我目前不能直接替代專業醫療建議。建議您諮詢醫生或合格的醫療專家喔。";
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

  // TODO: 等待蔓蔓Dietary Agent 完整回覆結構進行調整
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
