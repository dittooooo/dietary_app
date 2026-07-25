// Path: c:\Users\User\Documents\Github_Repo\dietary_app\companion\companion_js\companion-agent.js
// Description: Main entry point for Express server, routing HTTP requests, and orchestrating flow

const path = require("path");
const fs = require("fs");
const dotenv = require("dotenv");
const express = require("express");
const cors = require("cors");
const {
  runOpenAIFlow,
  callDietaryAgent,
  getCompanionReply
} = require("./companion-agent-services");

const envCandidates = [
  path.resolve(__dirname, "../../.env"),
  path.resolve(__dirname, "../.env"),
  path.resolve(__dirname, ".env")
];

let loadedEnvPath = null;
for (const candidate of envCandidates) {
  if (!fs.existsSync(candidate)) {
    continue;
  }

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

const app = express();
app.use(cors());
app.use(express.json());

async function handleCompanionAsk(req, res) {
  const user_prompt = typeof req.body.user_prompt === "string" ? req.body.user_prompt.trim() : "";
  if (!user_prompt) {
    return res.status(400).json({
      success: false,
      error_code: "BAD_REQUEST",
      error_message: "The 'user_prompt' field is required and must be a non-empty string."
    });
  }

  let openAiResult;
  try {
    openAiResult = await runOpenAIFlow(user_prompt);
  } catch (error) {
    console.error("OpenAI flow failed:", error.message);
    return res.status(502).json({
      success: false,
      error_code: "OPENAI_SERVICE_ERROR",
      error_message: "Failed to communicate with OpenAI API. Please try again later.",
      debug_message: error.message
    });
  }

  try {
    let dietaryAgentResponse = null;
    let dietaryAgentError = null;

    if (openAiResult.dietary_agent_request) {
      try {
        const authHeader = req.headers.authorization;
        dietaryAgentResponse = await callDietaryAgent(openAiResult.dietary_agent_request, authHeader);
      } catch (error) {
        console.error("Dietary Agent call failed:", error.message);
        dietaryAgentError = error.message;
      }
    }

    return res.json({
      success: true,
      llm_fallback_used: false,
      screening: {
        should_handle: openAiResult.screening.should_handle,
        intent_category: openAiResult.screening.intent_category,
        question_type: openAiResult.screening.question_type,
        confidence: openAiResult.screening.confidence,
        dishes: openAiResult.screening.dishes
      },
      emotion: openAiResult.emotion,
      dietary_agent_request: openAiResult.dietary_agent_request,
      dietary_agent_response: dietaryAgentResponse,
      dietary_agent_error: dietaryAgentError,
      companion_reply: await getCompanionReply({
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

app.get("/health", (_req, res) => {
  res.json({ status: "ok" });
});

app.post("/companion/ask", handleCompanionAsk);

const port = Number(process.env.COMPANION_API_PORT || 3000);
app.listen(port, () => {
  console.log(`Companion Agent API listening on port ${port}`);
});
