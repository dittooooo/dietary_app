// Companion Agent: final natural-language response generation only.
// Request routing and intake/normalization are owned by the MAF Workflow.
const path = require("path");
const fs = require("fs");
const dotenv = require("dotenv");
const express = require("express");
const cors = require("cors");
const { getCompanionReply } = require("./companion-agent-services");

const envCandidates = [
  path.resolve(__dirname, "../../.env"),
  path.resolve(__dirname, "../.env"),
  path.resolve(__dirname, ".env")
];

let loadedEnvPath = null;
for (const candidate of envCandidates) {
  if (!fs.existsSync(candidate)) continue;
  dotenv.config({ path: candidate });
  loadedEnvPath = candidate;
  break;
}

if (loadedEnvPath) {
  console.log(`Loaded .env from: ${loadedEnvPath}`);
} else {
  dotenv.config();
  console.log("No explicit .env file found. Falling back to process environment.");
}

if (!process.env.OPENAI_API_KEY) {
  console.error("❌ [FATAL] 缺少必要的環境變數: OPENAI_API_KEY");
  process.exit(1);
}

const app = express();
app.use(cors());
app.use(express.json());

function summarize(value, limit = 80) {
  const text = String(value || "").replace(/\s+/g, " ").trim();
  return text.length <= limit ? text : `${text.slice(0, limit)}…`;
}

function trace(req, state, message) {
  const traceId = String(req.get("X-Trace-Id") || "-").slice(0, 12);
  console.log(`[${traceId}] [CompanionAgent] [${state}] ${message}`);
}

app.get("/health", (_req, res) => {
  res.json({ status: "ok" });
});

app.post("/companion/reply", async (req, res) => {
  const userPrompt = typeof req.body.user_prompt === "string"
    ? req.body.user_prompt.trim()
    : "";
  if (!userPrompt) {
    return res.status(400).json({
      success: false,
      error_code: "BAD_REQUEST",
      error_message: "The 'user_prompt' field is required and must be a non-empty string."
    });
  }

  try {
    const intent = req.body.screening?.intent_category || "general_chat";
    trace(req, "STARTED", `產生最終回覆 intent=${intent} question=${summarize(userPrompt)}`);
    const companionReply = await getCompanionReply({
      userPrompt,
      screening: req.body.screening || {},
      emotion: req.body.emotion || {},
      dietaryAgentResponse: req.body.dietary_agent_response || null,
      dietaryAgentError: req.body.dietary_agent_error || null,
      tempStory: Array.isArray(req.body.temp_story) ? req.body.temp_story : []
    });
    trace(req, "COMPLETED", `回覆生成完成 length=${companionReply.length}`);
    trace(req, "OUTPUT", `companion_reply=${JSON.stringify(companionReply)}`);
    return res.json({ success: true, companion_reply: companionReply });
  } catch (error) {
    trace(req, "FAILED", `回覆生成失敗：${summarize(error.message)}`);
    return res.status(502).json({
      success: false,
      error_code: "OPENAI_SERVICE_ERROR",
      error_message: "Failed to generate the companion reply. Please try again later."
    });
  }
});

const port = Number(process.env.COMPANION_API_PORT || 3000);
app.listen(port, () => {
  console.log(`Companion Agent API listening on port ${port}`);
});
