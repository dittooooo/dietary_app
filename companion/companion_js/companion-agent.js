// Path: c:\Users\User\Documents\Github_Repo\dietary_app\companion\companion_js\companion-agent.js
// Description: Companion reply-generation API used by the MAF workflow

// 匯入 Node.js 內建 path 與 fs 模組，用於路徑解析及檔案系統檢查
const path = require("path");
const fs = require("fs");
// 匯入 dotenv 用於讀取 .env 設定，Express 用於建立 Web API，Cors 用於跨來源資源共用
const dotenv = require("dotenv");
const express = require("express");
const cors = require("cors");
const { getCompanionReply } = require("./companion-agent-services");

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

/**
 * 伺服器啟動時環境變數嚴格預檢 (Boot Validation)
 * 確保必要環境變數均已正確設定，避免執行期拋出非預期的 500 錯誤。
 */
function validateEnv() {
  const required = ["OPENAI_API_KEY"];
  const missing = required.filter(key => !process.env[key]);
  if (missing.length > 0) {
    console.error(`❌ [FATAL] 缺少必要的環境變數: ${missing.join(", ")}`);
    console.error("請在 .env 檔案中補充上述設定欄位後再重新啟動 Companion Agent。");
    process.exit(1);
  }
}

// 執行伺服器啟動環境變數預檢
validateEnv();

// 初始化 Express 應用程式並設定全域中間件 (Middleware)
const app = express();
app.use(cors()); // 啟用跨網域請求存取 (CORS)
app.use(express.json()); // 解析請求主體 (Request Body) 為 JSON 格式

/**
 * 接收 MAF Workflow 已處理完成的結果，只負責產生最終回覆。
 * @param {express.Request} req - Express 請求物件
 * @param {express.Response} res - Express 回應物件
 */
async function handleCompanionReply(req, res) {
  const user_prompt = typeof req.body.user_prompt === "string" ? req.body.user_prompt.trim() : "";
  if (!user_prompt) {
    return res.status(400).json({
      success: false,
      error_code: "BAD_REQUEST",
      error_message: "The 'user_prompt' field is required and must be a non-empty string."
    });
  }

  // 安全解析與清洗前端傳入的 temp_story 歷史紀錄 (防 Prompt 注入、防爆 Token)
  const rawTempStory = Array.isArray(req.body.temp_story) ? req.body.temp_story : [];
  const sanitizedTempStory = rawTempStory
    .filter(item => item && (item.role === 'user' || item.role === 'assistant') && typeof item.content === 'string')
    .map(item => ({
      role: item.role,
      content: item.content.trim().substring(0, 300) // 限制每筆最大 300 字
    }))
    .slice(-3); // 限制最多保留最近 3 則

  const screening = req.body.screening;
  const emotion = req.body.emotion;
  if (!screening || typeof screening !== "object" || !emotion || typeof emotion !== "object") {
    return res.status(400).json({
      success: false,
      error_code: "BAD_REQUEST",
      error_message: "The 'screening' and 'emotion' fields are required."
    });
  }

  try {
    const companionReply = await getCompanionReply({
      userPrompt: user_prompt,
      screening,
      emotion,
      dietaryAgentResponse: req.body.dietary_agent_response || null,
      dietaryAgentError: req.body.dietary_agent_error || null,
      tempStory: sanitizedTempStory
    });
    return res.json({
      success: true,
      companion_reply: companionReply
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

// 註冊健康檢查 (Health Check) 路由，用來驗證伺服器是否正常運行
app.get("/health", (_req, res) => {
  res.json({ status: "ok" });
});

// Companion 只提供最終回覆生成；對話入口與分流由 MAF Workflow 負責。
app.post("/companion/reply", handleCompanionReply);

// 設定監聽埠口並啟動 Express 伺服器服務
const port = Number(process.env.COMPANION_API_PORT || 3000);
if (require.main === module) {
  app.listen(port, () => {
    console.log(`Companion Agent API listening on port ${port}`);
  });
}

module.exports = { app, handleCompanionReply };
