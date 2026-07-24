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

  const response = await fetch(`${baseUrl}/api/dietary/ask-weekly-analysis`, {
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
 * Build the final user-facing reply with a second LLM pass.
 * @param {Object} params
 * @returns {Promise<string>}
 */
async function buildCompanionReply(params) {
  return runLLMReply(params);
}

module.exports = {
  runOpenAIFlow,
  callDietaryAgent,
  buildCompanionReply
};
