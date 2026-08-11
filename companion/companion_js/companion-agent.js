// Path: c:\Users\User\Documents\Github_Repo\dietary_app\companion\companion_js\companion-agent.js
// Description: Main entry point for Express server, routing HTTP requests, and orchestrating flow

// 匯入 Node.js 內建 path 與 fs 模組，用於路徑解析及檔案系統檢查
const path = require("path");
const fs = require("fs");
// 匯入 dotenv 用於讀取 .env 設定，Express 用於建立 Web API，Cors 用於跨來源資源共用
const dotenv = require("dotenv");
const express = require("express");
const cors = require("cors");
// 匯入服務層 (services) 以呼叫各核心流程模組
const {
  runOpenAIFlow,
  callDietaryAgent,
  getCompanionReply
} = require("./companion-agent-services");

// 定義 .env 檔案可能的存放路徑 (依序往上層目錄搜尋)
const envCandidates = [
  path.resolve(__dirname, "../../.env"),
  path.resolve(__dirname, "../.env"),
  path.resolve(__dirname, ".env")
];

// 走訪候選路徑，載入第一個找到的 .env 設定檔
let loadedEnvPath = null;
for (const candidate of envCandidates) {
  if (!fs.existsSync(candidate)) {
    continue;
  }

  dotenv.config({ path: candidate });
  loadedEnvPath = candidate;
  break;
}

// 輸出 .env 載入的狀態日誌
if (loadedEnvPath) {
  console.log(`Loaded .env from: ${loadedEnvPath}`);
} else {
  dotenv.config();
  console.log("No explicit .env file found. Falling back to process environment.");
}

// 初始化 Express 應用程式並設定全域中間件 (Middleware)
const app = express();
app.use(cors()); // 啟用跨網域請求存取 (CORS)
app.use(express.json()); // 解析請求主體 (Request Body) 為 JSON 格式

/**
 * 處理陪伴精靈對話請求的主路由邏輯
 * 實作流程：1. 意圖/情緒預檢 -> 2. (可選) 呼叫飲食助理服務 -> 3. LLM 重組回覆並回傳
 * @param {express.Request} req - Express 請求物件，預期包含 body.user_prompt 與 headers.authorization
 * @param {express.Response} res - Express 回應物件
 */
async function handleCompanionAsk(req, res) {
  // 1. 驗證請求參數 user_prompt 是否符合格式
  const user_prompt = typeof req.body.user_prompt === "string" ? req.body.user_prompt.trim() : "";
  if (!user_prompt) {
    return res.status(400).json({
      success: false,
      error_code: "BAD_REQUEST",
      error_message: "The 'user_prompt' field is required and must be a non-empty string."
    });
  }

  console.log("\n======================================================================");
  console.log(`[Companion Agent] 📥 收到使用者提問: "${user_prompt}"`);
  console.log("======================================================================\n");

  // 2. 執行第一階段 OpenAI 意圖及情緒分析流程
  let openAiResult;
  try {
    openAiResult = await runOpenAIFlow(user_prompt);

    console.log("------------------ [LLM 階段 1：意圖與情緒分析] ------------------");
    console.log("🎯 意圖預檢 (Screening):", JSON.stringify({
      should_handle: openAiResult.screening.should_handle,
      intent_category: openAiResult.screening.intent_category,
      question_type: openAiResult.screening.question_type,
      confidence: openAiResult.screening.confidence,
      dish_info_list: openAiResult.screening.dish_info_list
    }, null, 2));
    console.log("💖 情緒分析 (Emotion):", JSON.stringify(openAiResult.emotion, null, 2));
    console.log("");
  } catch (error) {
    console.error("OpenAI flow failed:", error.message);
    return res.status(502).json({
      success: false,
      error_code: "OPENAI_SERVICE_ERROR",
      error_message: "Failed to communicate with OpenAI API. Please try again later.",
      debug_message: error.message
    });
  }

  // 3. 根據預檢結果決定是否呼叫飲食助理服務，並合成陪伴精靈回覆
  try {
    let dietaryAgentResponse = null;
    let dietaryAgentError = null;

    // 若預檢判定需要呼叫後端飲食助理
    if (openAiResult.dietary_agent_request) {
      console.log("------------------ [Dietary Agent 飲食後端服務] ------------------");
      console.log("🚀 發送請求 Payload:", JSON.stringify(openAiResult.dietary_agent_request, null, 2));
      try {
        const authHeader = req.headers.authorization;
        // 呼叫飲食助理 API，並代入身分驗證標頭
        dietaryAgentResponse = await callDietaryAgent(openAiResult.dietary_agent_request, authHeader);
        const adviceCount = Array.isArray(dietaryAgentResponse?.dish_advice) ? dietaryAgentResponse.dish_advice.length : 0;
        const nutritionCount = Array.isArray(dietaryAgentResponse?.dish_nutrition) ? dietaryAgentResponse.dish_nutrition.length : 0;
        console.log(`✅ 成功取得回應 (Dish Advice: ${adviceCount} 筆, Nutrition: ${nutritionCount} 筆)`);
      } catch (error) {
        // 捕獲飲食助理 API 錯誤，但不中斷流程，保留錯誤訊息以利降級回覆處理
        console.error("⚠️ Dietary Agent 呼叫失敗:", error.message);
        dietaryAgentError = error.message;
      }
      console.log("");
    }

    console.log("------------------ [LLM 階段 2：陪伴式回覆重組] ------------------");
    // 呼叫重組邏輯，生成最終親切的對話文字
    const companionReply = await getCompanionReply({
      userPrompt: user_prompt,
      screening: openAiResult.screening,
      emotion: openAiResult.emotion,
      dietaryAgentResponse,
      dietaryAgentRequest: openAiResult.dietary_agent_request,
      dietaryAgentError
    });
    console.log(`💬 生成最終對話: "${companionReply.substring(0, 80)}${companionReply.length > 80 ? "..." : ""}"\n`);

    console.log("======================================================================");
    console.log(`[Companion Agent] 📤 已成功回應前端 (Intent: ${openAiResult.screening.intent_category || "general_chat"})`);
    console.log("======================================================================\n");

    // 回傳精簡且平鋪的對話結果給客戶端
    return res.json({
      success: true,
      companion_reply: companionReply,
      intent_category: openAiResult.screening.intent_category || "general_chat",
      meal_records: openAiResult.screening.meal_records || [],
      dietary_agent_error: dietaryAgentError
    });
  } catch (error) {
    // 捕獲伺服器端非預期的未處理錯誤，回傳 500 狀態碼
    console.error("Server internal error:", error);
    return res.status(500).json({
      success: false,
      error_code: "INTERNAL_SERVER_ERROR",
      error_message: "An unexpected error occurred on the server."
    });
  }
}

// 註冊健康檢查 (Health Check) 路由，用來驗證伺服器是否正常運行
app.get("/health", (_req, res) => {
  res.json({ status: "ok" });
});

// 註冊陪伴助理詢問路由
app.post("/companion/ask", handleCompanionAsk);

// 設定監聽埠口並啟動 Express 伺服器服務
const port = Number(process.env.COMPANION_API_PORT || 3000);
app.listen(port, () => {
  console.log(`Companion Agent API listening on port ${port}`);
});
