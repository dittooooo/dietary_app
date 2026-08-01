// Path: c:\Users\User\Documents\Github_Repo\dietary_app\companion\companion_js\companion-agent-services.js
// Description: External API services for communicating with OpenAI and Dietary Agent

// 匯入 companion-llm 模組中的大語言模型串接函數
// runOpenAIFlow 用於分析意圖與情緒，generateCompanionReply 用於生成最終回覆
const {
  runOpenAIFlow: runLLMAnalysis,
  generateCompanionReply: runLLMReply,
  translateDishes
} = require("./companion-llm");

/**
 * 建立 Dietary Agent 請求物件
 * 驗證並整理預檢結果，若符合條件則組裝成發送給飲食助理的請求 Payload
 * @param {Object} screening - 第一階段意圖預檢結果
 * @param {string} message - 使用者原始輸入訊息
 * @returns {Object|null} 傳送給飲食助理的 API 請求物件，若不符合則回傳 null
 */
function buildDietaryAgentRequest(screening, message) {
  // 若預檢結果不存在，或者判定不需要處理，則直接忽略
  if (!screening || !screening.should_handle) {
    return null;
  }

  // 整理與清理使用者提問文字
  const question = typeof message === "string" ? message.trim() : "";
  const question_type = screening.question_type;
  const dish_names = screening.dishes || [];

  // 若提問為空，則不處理
  if (!question) {
    return null;
  }

  // 僅限「單一餐點建議」或「餐點比較」兩種問題類型才會發送給 Dietary Agent
  if (question_type !== "single_dish" && question_type !== "dish_comparison") {
    return null;
  }

  // 必須包含至少一項具體的餐點名稱
  if (!Array.isArray(dish_names) || dish_names.length === 0) {
    return null;
  }

  // 回傳格式化後的請求 Payload
  return {
    question,
    question_type,
    dish_names
  };
}

/**
 * 執行 OpenAI 分析流程
 * 呼叫 LLM 進行意圖篩選與情緒分析，並根據結果建立 Dietary Agent 的請求參數
 * @param {string} userPrompt - 使用者原始輸入訊息
 * @returns {Promise<Object>} 包含意圖篩選、情緒分析與飲食助理請求 Payload 的物件
 */
async function runOpenAIFlow(userPrompt) {
  // 呼叫 OpenAI 進行分析
  const result = await runLLMAnalysis(userPrompt);

  if (result.screening.dishes && result.screening.dishes.length > 0) {
    try {
      // 逐一翻譯每個原始餐點，並將翻譯出的多個原料組合回單一字串，確保最終元素個數與原始品項數目一致
      const translatedList = [];
      for (const dish of result.screening.dishes) {
        const translatedIngredients = await translateDishes([dish]);
        const combined = translatedIngredients.join("");
        translatedList.push(combined);
      }
      result.screening.dishes = translatedList;
    } catch (err) {
      console.error("Dish translation failed, using original names:", err.message);
    }
  }

  // 根據分析出的意圖決定是否建立傳送給 Dietary Agent 的請求 payload
  const dietaryAgentRequest = buildDietaryAgentRequest(result.screening, userPrompt);

  // 回傳整合後的結果
  return {
    screening: result.screening,
    emotion: result.emotion,
    dietary_agent_request: dietaryAgentRequest
  };
}

/**
 * 呼叫飲食助理 (Dietary Agent) API
 * 將請求發送至後端的飲食助理服務以取得專業的飲食/營養分析數據
 * @param {Object} requestBody - 飲食助理所需的請求 Payload
 * @param {string} authHeader - 使用者傳入的 Authorization Token (用於身份驗證)
 * @returns {Promise<Object>} 飲食助理 API 回傳的 JSON 數據
 */
async function callDietaryAgent(requestBody, authHeader) {
  // 從環境變數讀取 Dietary Agent API 的基礎網址
  const baseUrl = process.env.DIETARY_AGENT_API_URL;
  if (!baseUrl) {
    throw new Error("Missing DIETARY_AGENT_API_URL variable in .env");
  }

  // 設定 API 請求標頭，指定 JSON 格式
  const headers = {
    "Content-Type": "application/json"
  };

  // 若使用者請求中帶有 Authorization 標頭，則轉發給飲食助理
  if (authHeader) {
    headers.Authorization = authHeader;
  }

  // 發送 POST 請求至飲食助理的問答端點
  const response = await fetch(`${baseUrl}/dietary-agent/ask`, {
    method: "POST",
    headers,
    body: JSON.stringify(requestBody)
  });

  // 處理 API 錯誤狀態碼
  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Dietary Agent error ${response.status}: ${errorText}`);
  }

  // 解析並回傳飲食助理回覆的 JSON 內容
  return response.json();
}

/**
 * 產生陪伴精靈的最終回覆
 * 整合意圖、情緒以及飲食助理的回應，透過 LLM 生成溫馨、同理心且在地化的回覆。
 * 若意圖判定不需處理、或缺少必要資訊，則直接回傳預設防呆對話。
 * @param {Object} params - 參數物件，包含篩選結果、情緒分析、飲食助理回應與原始問題等
 * @returns {Promise<string>} 最終要呈現給使用者的對話文字
 */
async function getCompanionReply({
  screening,
  emotion,
  dietaryAgentResponse,
  dietaryAgentRequest,
  userPrompt,
  dietaryAgentError
}) {
  // 【早退機制 (Early Exit) 目的】：
  // 1. 當第一階段的 AI 分析判定不需處理 (!should_handle)，或飲食主題但資訊不足（如無餐點名稱）時，
  //    第一階段 API 的 tools (early_reply 欄位) 就會由 AI 預先生成溫馨的拒絕/閒聊引導或補問文字。
  // 2. 這時後端直接將 early_reply 回傳給前端，完全省下第二次 Chat Completions API 的調用，極大降低延遲。
  if (screening.early_reply) {
    return screening.early_reply;
  }

  // 情況 C：資訊完整且已完成 Dietary Agent 呼叫，進入第二階段 LLM 生成最終陪伴式回覆
  let finalReply = "";
  try {
    // 呼叫 OpenAI Chat Completions API 來生成並包裝最終的溫馨對話回覆
    finalReply = await runLLMReply({
      userPrompt,
      screening,
      emotion,
      dietaryAgentResponse,
      dietaryAgentRequest,
      dietaryAgentError
    });
  } catch (error) {
    // 當 LLM 回覆生成失敗時，進入容錯防呆與降級處理機制 (Fallback 保底)
    console.error("Failed to generate companion response with LLM:", error.message);
    // 能走到這步代表預檢與餐點資料皆齊全，只需處理對話生成失敗
    const empathyPrefix = emotion.needs_empathy
      ? "我知道你現在可能有點在意這餐怎麼吃，先別太有壓力，我陪你一起看。\n"
      : "我先幫你整理目前可用的資訊。\n";

    // 優先使用飲食助理傳回的 conclusion 段落
    const recommendation = dietaryAgentResponse?.conclusion || "目前還拿不到完整分析結果，稍後再試一次會比較穩。";

    // 拼接成備用回覆
    finalReply = `${empathyPrefix}${recommendation}`;

    // 數值免責聲明保底：如果使用者提問或回傳資料中含有熱量、克數等數值關鍵字，強制在結尾附加免責聲明
    const hasNutrients = Array.isArray(dietaryAgentResponse?.dish_nutrition) &&
      dietaryAgentResponse.dish_nutrition.some(d => Array.isArray(d.nutrients) && d.nutrients.length > 0);
    const mentionsNumbers = /熱量|卡路里|卡|克|g|kcal|蛋白質|脂肪|碳水化合物/i.test(userPrompt);

    if (hasNutrients || mentionsNumbers) {
      finalReply += "\n\n關於數值類提問，本精靈只可提供參考數值";
    }
  }

  return finalReply;
}

// 匯出外部服務層的核心函數
module.exports = {
  runOpenAIFlow,
  callDietaryAgent,
  getCompanionReply
};
