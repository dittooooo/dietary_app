// Path: c:\Users\User\Documents\Github_Repo\dietary_app\companion\companion_js\companion-agent-services.js
// Description: External API services for communicating with OpenAI and Dietary Agent

const {
  runOpenAIFlow: runLLMAnalysis,
  generateCompanionReply: runLLMReply
} = require("./companion-llm");

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

async function runOpenAIFlow(userPrompt) {
  const result = await runLLMAnalysis(userPrompt);
  const dietaryAgentRequest = buildDietaryAgentRequest(result.screening, userPrompt);

  return {
    screening: result.screening,
    emotion: result.emotion,
    dietary_agent_request: dietaryAgentRequest
  };
}

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

async function getCompanionReply({
  screening,
  emotion,
  dietaryAgentResponse,
  dietaryAgentRequest,
  userPrompt,
  dietaryAgentError
}) {
  if (!screening.should_handle) {
    return "這個問題比較不是飲食助理的處理範圍。如果你願意，我還是可以幫你回到餐點選擇、熱量方向，或日常飲食建議來一起看。";
  }

  if (screening.should_handle && !dietaryAgentRequest) {
    if (!screening.dishes || screening.dishes.length === 0) {
      return "我目前還不太確定你想問的是哪一道食物。你可以直接告訴我餐點名稱，或補充你吃了什麼，我再幫你一起看。";
    }

    if (screening.question_type !== "single_dish" && screening.question_type !== "dish_comparison") {
      return "我有抓到你在問飲食，但還差一點資訊。你可以補充是想問單一道餐點，還是要比較兩種以上的食物嗎？";
    }

    return "我有收到你的問題，但目前資訊還不夠完整。你可以再多描述一點你想問的食物或情境，我就能更準確幫你整理。";
  }

  let finalReply = "";
  try {
    finalReply = await runLLMReply({
      userPrompt,
      screening,
      emotion,
      dietaryAgentResponse,
      dietaryAgentRequest,
      dietaryAgentError
    });
  } catch (error) {
    console.error("Failed to generate companion response with LLM:", error.message);
    const empathyPrefix = emotion.needs_empathy
      ? "我知道你現在可能有點在意這餐怎麼吃，先別太有壓力，我陪你一起看。\n"
      : "我先幫你整理目前可用的資訊。\n";
    const recommendation =
      dietaryAgentResponse?.reply_text ||
      dietaryAgentResponse?.conclusion ||
      (dietaryAgentResponse ? JSON.stringify(dietaryAgentResponse) : "目前還拿不到完整分析結果，稍後再試一次會比較穩。");
    finalReply = `${empathyPrefix}${recommendation}`;
  }

  return finalReply;
}

module.exports = {
  runOpenAIFlow,
  callDietaryAgent,
  getCompanionReply
};
