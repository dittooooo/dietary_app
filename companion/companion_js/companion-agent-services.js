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
  const dish_info_list = screening.dish_info_list || {};

  // 若提問為空，則不處理
  if (!question) {
    return null;
  }

  // 僅限「單一餐點建議」或「餐點比較」兩種問題類型才會發送給 Dietary Agent
  if (question_type !== "single_dish" && question_type !== "dish_comparison") {
    return null;
  }

  // 必須包含至少一項具體的餐點名稱
  if (Object.keys(dish_info_list).length === 0) {
    return null;
  }

  // 將物件格式 { "餐點名": 份數 } 轉為 Java 後端 DietaryAskRequest 所需的 Array 格式 [ { dish_name: "餐點名", amount: 份數 } ]
  const formattedDishInfoList = Object.entries(dish_info_list).map(([dishName, amount]) => ({
    dish_name: dishName,
    amount: (typeof amount === "number" && amount > 0) ? amount : 1
  }));

  // 回傳格式化後的請求 Payload
  return {
    question,
    question_type,
    dish_info_list: formattedDishInfoList
  };
}

/**
 * 執行 OpenAI 分析流程
 * 呼叫 LLM 進行意圖篩選與情緒分析，並依據三路分流機制建立 Dietary Agent 請求參數：
 * - 分流 A (閒聊/非飲食) / 分流 B (飲食紀錄)：不安插翻譯與 Java 請求
 * - 分流 C (飲食諮詢)：包含具體食物才進行翻譯與 Java 請求；無食物時自動跳過
 * @param {string} userPrompt - 使用者原始輸入訊息
 * @param {Array<Object>} tempStory - 前端傳入的近 3 則對話歷史
 * @returns {Promise<Object>} 包含意圖預檢 (screening)、情緒分析 (emotion) 與飲食助理請求 Payload 的物件
 */
async function runOpenAIFlow(userPrompt, tempStory = []) {
  // 1. 呼叫 OpenAI 進行 Stage 1 JSON 分析 (帶入歷史對話)
  const result = await runLLMAnalysis(userPrompt, tempStory);
  const { screening, emotion } = result;

  // 2. 多路分流機制處理
  // 旁路處理：閒聊/非飲食 (should_handle === false 或 intent_category === "general_chat")
  // 旁路處理：飲食紀錄 (intent_category === "meal_record")
  // 旁路處理：歷史飲食查詢 (intent_category === "meal_query")
  if (
    !screening.should_handle ||
    screening.intent_category === "general_chat" ||
    screening.intent_category === "meal_record" ||
    screening.intent_category === "meal_query"
  ) {
    return {
      screening,
      emotion,
      dietary_agent_request: null
    };
  }

  // 分流 C：飲食諮詢 (intent_category === "dish_advice")
  // 檢查是否包含具體食物資訊 (dish_info_list 非空)
  if (
    screening.intent_category === "dish_advice" &&
    screening.dish_info_list &&
    Object.keys(screening.dish_info_list).length > 0
  ) {
    try {
      // 條件觸發：逐一翻譯每個原始餐點名稱為資料庫標準名，並保持對應之數量
      const translatedDishInfoList = {};
      for (const [dishName, amount] of Object.entries(screening.dish_info_list)) {
        const translatedIngredients = await translateDishes([dishName]);
        const combined = Array.isArray(translatedIngredients) ? translatedIngredients.join("") : "";
        const finalDishName = combined.trim() ? combined : dishName;
        translatedDishInfoList[finalDishName] = amount;
      }
      screening.dish_info_list = translatedDishInfoList;
    } catch (err) {
      console.error("Dish translation failed, using original names:", err.message);
    }
  }

  // 建立傳送給 Dietary Agent 的請求 payload (若無食物資訊則會回傳 null)
  const dietaryAgentRequest = buildDietaryAgentRequest(screening, userPrompt);

  return {
    screening,
    emotion,
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
 * @param {Object} params - 參數物件，包含篩選結果、情緒分析、飲食助理回應、原始問題與歷史紀錄等
 * @returns {Promise<string>} 最終要呈現給使用者的對話文字
 */
async function getCompanionReply({
  screening,
  emotion,
  dietaryAgentResponse,
  userPrompt,
  dietaryAgentError,
  tempStory = []
}) {
  // 飲食紀錄意圖處理 (分流 B 極速草稿文字組裝)
  if (screening?.intent_category === "meal_record") {
    if (Array.isArray(screening.meal_items) && screening.meal_items.length > 0) {
      const summaryList = screening.meal_items.map(item => {
        return `${item.meal_period || "即時"}的「${item.quantity}${item.unit}${item.name}」`;
      }).join('，以及');

      return `幫你整理好${summaryList}草稿囉！請在下方確認一下內容是否正確，按下確認就可以幫你存起來囉！✨`;
    } else {
      return `收到你想記錄飲食，但似乎沒有聽到具體的餐點名稱。你可以再跟我說一次你吃了什麼喔！`;
    }
  }

  // 飲食紀錄查詢意圖處理 (分流 D 極速日期卡片對話組裝)
  if (screening?.intent_category === "meal_query") {
    if (screening.query_date) {
      const dateParts = screening.query_date.split("-");
      const formattedDateStr = dateParts.length === 3
        ? `${parseInt(dateParts[1], 10)}/${parseInt(dateParts[2], 10)}`
        : screening.query_date;
      return `幫你找到 ${formattedDateStr} 號的飲食紀錄囉！請在下方卡片確認當天記錄的內容吧！✨`;
    } else {
      return `收到你想查詢歷史飲食紀錄，但似乎沒有聽到具體的日期。你可以再跟我說一次你想看哪一天的紀錄喔！（例如：「我 6/19 吃了什麼」）`;
    }
  }

  // 進入 Stage 3 LLM 生成對話回覆 (100% 集中注入 Persona 靈魂，動態應答各種情境與異常)
  let finalReply = "";
  try {
    finalReply = await runLLMReply({
      userPrompt,
      screening,
      emotion,
      dietaryAgentResponse,
      dietaryAgentError,
      tempStory
    });
  } catch (error) {
    // 當 LLM 回覆生成崩潰或連線失敗時 (OpenAI API 保底)
    console.error("Failed to generate companion response with LLM:", error.message);
    finalReply = "AI 功能目前發生異常，請稍後再試。";
  }

  return finalReply;
}

// 匯出外部服務層的核心函數
module.exports = {
  runOpenAIFlow,
  callDietaryAgent,
  getCompanionReply
};
