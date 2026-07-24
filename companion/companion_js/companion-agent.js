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
      companion_reply: await buildCompanionReply({
        userPrompt: user_prompt,
        screening: openAiResult.screening,
        emotion: openAiResult.emotion,
        dietaryAgentResponse,
        dietaryAgentRequest: openAiResult.dietary_agent_request,
        dietaryAgentError
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
