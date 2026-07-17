// Path: c:\Users\User\Documents\Github_Repo\dietary_app\companion\companion_js\companion-agent-services.js
// Description: External API services for communicating with OpenAI and Dietary Agent

// 引入 OpenAI Prompt 與 Function Schema 的設定檔
const { SYSTEM_PROMPT, tools } = require("./companion-agent-config");
// 引入本地端輔助函數、保底評估與資料清理驗證的 Helpers
const {
  sanitizeScreening,
  sanitizeEmotion,
  buildDietaryAgentRequest,
  fallbackScreening,
  fallbackEmotion
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
async function runOpenAIFlow(bundle) {
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
      tools,
      instructions: SYSTEM_PROMPT,
      input: [
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: JSON.stringify(bundle), // 將包含使用者問句與 context 的 bundle 轉為 JSON 傳給模型
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
  const screening = sanitizeScreening(
    rawArgs.screen_user_request,
    bundle.message,
    bundle.user_context
  );
  const emotion = sanitizeEmotion(rawArgs.analyze_emotion, bundle.message);

  // 4.4 依據驗證結果組裝傳遞給 Dietary Agent 的三元素 payload
  const dietaryAgentRequest = buildDietaryAgentRequest(screening, bundle.message);

  return {
    screening,
    emotion,
    dietary_agent_request: dietaryAgentRequest
  };
}

/**
 * 5. 執行本地保底流程 (runFallbackFlow)
 * 當 OpenAI 連線失敗、超時或認證錯誤時，完全在本地端以 rule-based 邏輯產出保底數據，保障系統不崩潰。
 * @param {Object} bundle - 核心資料包
 */
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

/**
 * 6. 呼叫 Dietary Agent API
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
 * 7. 組裝最終的陪伴式回覆 (buildCompanionReply)
 * 根據意圖與情緒狀態，調整自然語言回覆，將 Dietary Agent 的推論結合安撫前綴。
 */
function buildCompanionReply({ screening, emotion, dietaryAgentResponse }) {
  // 醫療超出範圍的柔和拒絕
  if (screening.intent_category === "medical_out_of_scope") {
    return "這類問題比較接近醫療診斷或治療判斷，我目前不能直接替代專業醫療建議。建議您諮詢醫生或合格的醫療專家喔。";
  }

  // 非飲食諮詢的閒聊回覆
  if (!screening.should_handle) {
    return "這句話目前不像是飲食建議模組要處理的內容。如果您有關於餐點選擇、熱量或減脂增肌的問題，隨時可以問我！";
  }

  // 缺失 Profile 時的補問與引導
  if (screening.requires_more_context) {
    if (screening.missing_information.includes("user_profile")) {
      return "我還需要您的一些基本資訊（像是年齡、身高、體重或健康狀況），才能幫您做出比較精確的飲食推薦喔！";
    }
    return "為了給您更合適的建議，可以再多提供一些您的飲食狀況或細節嗎？";
  }

  // 根據同理心安撫指標 needs_empathy，決定回覆開頭的語氣
  const empathyPrefix = emotion.needs_empathy
    ? "我有注意到你現在有點在意這次的選擇，先不用太緊張喔。❤️\n"
    : "我先幫您整理這次的飲食建議：\n";

  // 將前綴與 Dietary Agent 回傳的建議融合
  let recommendation = "已成功記錄您的問題，正在為您尋求最佳飲食建議。";
  if (dietaryAgentResponse) {
    // 優先使用 response 裡面的 reply_text 或 conclusion 欄位作為自然語言回覆
    recommendation = dietaryAgentResponse.reply_text || dietaryAgentResponse.conclusion || JSON.stringify(dietaryAgentResponse);
  }

  return `${empathyPrefix}${recommendation}`;
}

// 導出服務模組供 companion-agent.js 使用
module.exports = {
  runOpenAIFlow,
  runFallbackFlow,
  callDietaryAgent,
  buildCompanionReply
};
