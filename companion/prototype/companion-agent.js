const express = require("express");

const SYSTEM_PROMPT = `
You are the Companion Agent classifier for a dietary recommendation app.

Your job is to read the user's message and available context, then use function calls
to produce structured outputs for:
1. screen_user_request
2. analyze_emotion

Rules:
- Function calls are the primary structured outputs.
- Do not provide medical diagnosis.
- Treat dietary recommendation as in-scope.
- Treat pure medical diagnosis, prescription, or unrelated casual chat as out-of-scope.
- If the message is in-scope, call:
  1) screen_user_request
  2) analyze_emotion
- If the message is out-of-scope, call:
  1) screen_user_request
  2) analyze_emotion
- If information is insufficient, still call screen_user_request and analyze_emotion.
- Use these enums exactly:
  - question_type: single_dish | dish_comparison | unknown
  - intent_category: dish_advice | meal_record | medical_out_of_scope | general_chat
  - primary_emotion: neutral | curious | anxiety | guilt | stress | frustration | joy
  - valence: negative | neutral | positive
  - urgency: low | medium | high
  - companion_tone: calm | encouraging | neutral | positive
`;

const tools = [
  {
    type: "function",
    name: "screen_user_request",
    description:
      "Return the structured screening result for whether this message should be handled by dietary recommendation.",
    strict: true,
    parameters: {
      type: "object",
      properties: {
        should_handle: { type: "boolean" },
        intent_category: {
          type: "string",
          enum: [
            "dish_advice",
            "meal_record",
            "medical_out_of_scope",
            "general_chat",
          ],
        },
        question_type: {
          type: "string",
          enum: ["single_dish", "dish_comparison", "unknown"],
        },
        requires_more_context: { type: "boolean" },
        missing_information: {
          type: "array",
          items: { type: "string" },
        },
        confidence: { type: "number" },
      },
      required: [
        "should_handle",
        "intent_category",
        "question_type",
        "requires_more_context",
        "missing_information",
        "confidence",
      ],
      additionalProperties: false,
    },
  },
  {
    type: "function",
    name: "analyze_emotion",
    description:
      "Return the structured emotional analysis used only for response tone control.",
    strict: true,
    parameters: {
      type: "object",
      properties: {
        primary_emotion: {
          type: "string",
          enum: [
            "neutral",
            "curious",
            "anxiety",
            "guilt",
            "stress",
            "frustration",
            "joy",
          ],
        },
        valence: {
          type: "string",
          enum: ["negative", "neutral", "positive"],
        },
        urgency: {
          type: "string",
          enum: ["low", "medium", "high"],
        },
        needs_empathy: { type: "boolean" },
        companion_tone: {
          type: "string",
          enum: ["calm", "encouraging", "neutral", "positive"],
        },
        evidence: {
          type: "array",
          items: { type: "string" },
        },
      },
      required: [
        "primary_emotion",
        "valence",
        "urgency",
        "needs_empathy",
        "companion_tone",
        "evidence",
      ],
      additionalProperties: false,
    },
  },
];

// 這是一個快速安全檢查，用來攔截明顯超出範圍的醫療問題。
// 它不是主要的意圖分類器，只負責在 LLM 判斷前後補上一層保護，
// 避免把醫療診斷或治療類問題誤當成一般飲食建議查詢。
function isMedicalOutOfScope(message) {
  return (
    /(診斷|處方|藥|醫生|治療|病名確診)/.test(message) ||
    /(diagnosis|prescription|treatment|medicine)/i.test(message)
  );
}

// 這是一個輕量級的飲食相關訊號偵測器，供 rule-based fallback 使用。
// 主要用途是在以下情況提供粗略的「看起來像飲食問題」提示：
// 1. LLM 暫時不可用
// 2. LLM 輸出格式不正確
// 3. 需要做 post-check 合理性驗證
// 它不應被視為系統主要的語意理解邏輯。
function isLikelyFoodRelated(message) {
  return (
    /(吃|餐廳|料理|菜單|便當|晚餐|午餐|早餐|熱量|營養|外食|拉麵|火鍋|炸雞|沙拉|飲料|宵夜|牛肉麵|雞排|減脂|增肌|飲食)/.test(
      message,
    ) || /(food|menu|restaurant|dish|meal|calorie|nutrition)/i.test(message)
  );
}

function looksLikeComparison(message) {
  return /(哪個|比較|vs|versus|跟|和|相比|比較適合)/i.test(message);
}

// 這是僅供 fallback 使用的問題類型推測器。
// 只有在 LLM 輸出不存在或驗證失敗時才會使用。
// 它不能取代 LLM 作為 question_type 的主要來源。
function fallbackClassifyQuestionType(message) {
  if (looksLikeComparison(message)) {
    return "dish_comparison";
  }
  if (isLikelyFoodRelated(message)) {
    return "single_dish";
  }
  return "unknown";
}

// 這是本地端最小化的 screening 備援分類器。
// 主要在以下情況產生粗略的 screening 結果：
// 1. OpenAI 無法使用
// 2. tool 輸出格式錯誤
// 3. 需要一個安全基準做 post-check 修正
// 這個結果刻意設計得較保守，不能視為等同於 LLM 的完整語意判斷。
function fallbackScreening(message, userContext) {
  const missingInformation = [];
  let shouldHandle = false;
  let intentCategory = "general_chat";
  let requiresMoreContext = false;

  if (isMedicalOutOfScope(message)) {
    intentCategory = "medical_out_of_scope";
  } else if (isLikelyFoodRelated(message)) {
    shouldHandle = true;
    intentCategory = "dish_advice";
    if (!userContext.has_user_profile) {
      missingInformation.push("user_profile");
      requiresMoreContext = true;
    }
  }

  return {
    should_handle: shouldHandle,
    intent_category: intentCategory,
    question_type: fallbackClassifyQuestionType(message),
    requires_more_context: requiresMoreContext,
    missing_information: missingInformation,
    confidence: shouldHandle || intentCategory === "medical_out_of_scope" ? 0.7 : 0.5,
  };
}

// 這是僅供 fallback 路徑使用的本地簡化情緒偵測器。
// 它的目的，是在 LLM 沒有回傳有效情緒分析時，仍保留一個可用的回覆語氣。
// 它不會影響 Nutrition API 的查詢邏輯。
function fallbackEmotion(message) {
  const checks = [
    ["anxiety", /(焦慮|擔心|怕|緊張|不安)/],
    ["guilt", /(罪惡感|內疚|後悔)/],
    ["frustration", /(煩|麻煩|受不了|生氣)/],
    ["stress", /(壓力|累死|崩潰)/],
    ["joy", /(開心|期待|太好了)/],
    ["curious", /(可以嗎|適合嗎|想問|請問)/],
  ];

  let primaryEmotion = "neutral";
  for (const [label, pattern] of checks) {
    if (pattern.test(message)) {
      primaryEmotion = label;
      break;
    }
  }

  const valenceMap = {
    anxiety: "negative",
    guilt: "negative",
    frustration: "negative",
    stress: "negative",
    joy: "positive",
    curious: "neutral",
    neutral: "neutral",
  };

  const urgencyMap = {
    anxiety: "medium",
    guilt: "low",
    frustration: "medium",
    stress: "medium",
    joy: "low",
    curious: "low",
    neutral: "low",
  };

  const toneMap = {
    anxiety: "calm",
    guilt: "encouraging",
    frustration: "calm",
    stress: "calm",
    joy: "positive",
    curious: "neutral",
    neutral: "neutral",
  };

  const evidence = [];
  ["焦慮", "擔心", "罪惡感", "後悔", "壓力", "煩", "開心", "期待"].forEach((token) => {
    if (message.includes(token)) {
      evidence.push(token);
    }
  });

  return {
    primary_emotion: primaryEmotion,
    valence: valenceMap[primaryEmotion],
    urgency: urgencyMap[primaryEmotion],
    needs_empathy: ["anxiety", "guilt", "frustration", "stress"].includes(primaryEmotion),
    companion_tone: toneMap[primaryEmotion],
    evidence,
  };
}

// 這個函式負責驗證並標準化 LLM 產生的 screening 結果。
// 它是主要的 post-check 層，會負責：
// - 用 fallback screening 補齊缺漏欄位
// - 修正明顯不安全或不一致的分類結果
// - 套用像是醫療超出範圍這類明確的安全覆寫規則
function sanitizeScreening(raw, message, userContext) {
  const fallback = fallbackScreening(message, userContext);
  if (!raw || typeof raw !== "object") {
    return fallback;
  }

  const result = {
    should_handle:
      typeof raw.should_handle === "boolean" ? raw.should_handle : fallback.should_handle,
    intent_category:
      typeof raw.intent_category === "string"
        ? raw.intent_category
        : fallback.intent_category,
    question_type:
      typeof raw.question_type === "string" ? raw.question_type : fallback.question_type,
    requires_more_context:
      typeof raw.requires_more_context === "boolean"
        ? raw.requires_more_context
        : fallback.requires_more_context,
    missing_information: Array.isArray(raw.missing_information)
      ? raw.missing_information
      : fallback.missing_information,
    confidence: typeof raw.confidence === "number" ? raw.confidence : fallback.confidence,
  };

  if (isMedicalOutOfScope(message)) {
    result.should_handle = false;
    result.intent_category = "medical_out_of_scope";
    result.question_type = "unknown";
    result.requires_more_context = false;
  }

  if (result.question_type === "dish_comparison" && !looksLikeComparison(message)) {
    result.question_type = fallbackClassifyQuestionType(message);
  }

  if (!userContext.has_user_profile && result.should_handle) {
    if (!result.missing_information.includes("user_profile")) {
      result.missing_information.push("user_profile");
    }
    result.requires_more_context = true;
  }

  if (!isLikelyFoodRelated(message) && result.intent_category === "dish_advice") {
    result.should_handle = false;
    result.intent_category = "general_chat";
    result.question_type = "unknown";
  }

  return result;
}

// 這個函式負責驗證並標準化 LLM 產生的情緒分析結果。
// 若模型回應不完整或無效，就退回本地簡化情緒估計，
// 讓最終回覆仍保有合理的語氣。
function sanitizeEmotion(raw, message) {
  const fallback = fallbackEmotion(message);
  if (!raw || typeof raw !== "object") {
    return fallback;
  }

  return {
    primary_emotion:
      typeof raw.primary_emotion === "string"
        ? raw.primary_emotion
        : fallback.primary_emotion,
    valence: typeof raw.valence === "string" ? raw.valence : fallback.valence,
    urgency: typeof raw.urgency === "string" ? raw.urgency : fallback.urgency,
    needs_empathy:
      typeof raw.needs_empathy === "boolean" ? raw.needs_empathy : fallback.needs_empathy,
    companion_tone:
      typeof raw.companion_tone === "string"
        ? raw.companion_tone
        : fallback.companion_tone,
    evidence: Array.isArray(raw.evidence) ? raw.evidence : fallback.evidence,
  };
}

// 將 Nutrition API request body 改為程式碼組裝，而不是交給 LLM 生成。
// 原因是這一段主要屬於結構映射與欄位組裝，規則明確、可預測，
// 由後端直接組裝能降低模型輸出不穩定風險，也更容易維護與除錯。
function buildNutritionApiRequest(screening, bundle) {
  if (!screening.should_handle || screening.requires_more_context) {
    return null;
  }

  return {
    question: bundle.message,
    cypher: null,
    question_type: screening.question_type,
    user_profile: bundle.user_profile,
    health_condition: bundle.health_condition,
    weekly_diet_records: bundle.weekly_diet_records,
    debug: false,
  };
}

// 預留的資料載入層。若 request body 沒有直接帶 user_profile、
// health_condition 或 weekly_diet_records，未來可在此改接資料庫查詢。
async function loadUserData(requestBody) {
  return {
    user_profile: requestBody.user_profile ?? null,
    health_condition:
      requestBody.health_condition ?? {
        has_chronic_disease: false,
        chronic_diseases: [],
      },
    weekly_diet_records: Array.isArray(requestBody.weekly_diet_records)
      ? requestBody.weekly_diet_records
      : [],
  };
}

// 呼叫 OpenAI Responses API，讓模型以 function calling 方式輸出結構化結果。
// 在本階段中，function calling 的角色是「結構化輸出機制」，
// 也就是把語意理解結果轉成固定 schema，而不是直接產生最終對話文字。
async function createOpenAIResponse(body, apiKey) {
  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`OpenAI API error ${response.status}: ${errorText}`);
  }

  return response.json();
}

// 呼叫既有 Nutrition Agent API，取得營養分析與建議結果。
async function callNutritionApi(requestBody) {
  const baseUrl =
    process.env.NUTRITION_API_URL || "https://dietary-app-kwz0.onrender.com";

  const response = await fetch(`${baseUrl}/ask`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify(requestBody),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Nutrition API error ${response.status}: ${errorText}`);
  }

  return response.json();
}

function getFunctionCalls(responseJson) {
  return (responseJson.output || []).filter((item) => item.type === "function_call");
}

function collectToolArgsByName(functionCalls) {
  const byName = {};
  for (const call of functionCalls) {
    try {
      byName[call.name] = JSON.parse(call.arguments || "{}");
    } catch {
      byName[call.name] = null;
    }
  }
  return byName;
}

// 將結構化結果與 Nutrition API 結論整理成最終回覆文字。
// 這裡的重點不是重新推論，而是把已知結果轉成對使用者較自然的回覆。
function buildCompanionReply({ screening, emotion, nutritionApiResponse }) {
  if (!screening.should_handle) {
    if (screening.intent_category === "medical_out_of_scope") {
      return "這類問題比較接近醫療診斷或治療判斷，我目前不能直接替代專業醫療建議。如果你想問的是某道料理是否較適合目前狀況，我可以幫你從飲食角度整理。";
    }
    return "這句話目前不像是飲食建議模組要處理的內容。如果你想問某道料理適不適合吃，可以直接告訴我料理名稱或目前情境。";
  }

  if (screening.requires_more_context) {
    if (screening.missing_information.includes("user_profile")) {
      return "我還需要一些基本資訊，像是年齡、身高、體重或健康狀況，才能幫你做比較合適的判斷。";
    }
    return "我還需要一些資料，像是料理名稱、餐廳或菜單資訊，才能幫你查詢更準確的建議。";
  }

  const empathyPrefix = emotion.needs_empathy
    ? "我有注意到你現在有點在意這次的選擇，先不用太緊張。"
    : "我先幫你整理這次的飲食問題。";

  if (!nutritionApiResponse) {
    return `${empathyPrefix} 我已經把資料整理成可送到 Nutrition API 的格式，接下來就能查詢更完整的建議。`;
  }

  const suggestionText =
    Array.isArray(nutritionApiResponse.dish_advice) &&
    nutritionApiResponse.dish_advice.length > 0 &&
    Array.isArray(nutritionApiResponse.dish_advice[0].suggestions) &&
    nutritionApiResponse.dish_advice[0].suggestions.length > 0
      ? ` 你也可以考慮：${nutritionApiResponse.dish_advice[0].suggestions.join("、")}。`
      : "";

  return `${empathyPrefix} ${nutritionApiResponse.conclusion}${suggestionText}`;
}

// 這是主要的 LLM 判斷流程。
// 模型透過 function calling 回傳 screening 與 emotion，
// 再由本地程式做 sanitize / post-check，最後交由程式碼組裝 Nutrition API request。
async function runOpenAIFlow(bundle) {
  const apiKey = process.env.OPENAI_API_KEY;
  const model = process.env.OPENAI_MODEL || "gpt-4.1-mini";

  if (!apiKey) {
    throw new Error("Missing OPENAI_API_KEY.");
  }

  const response = await createOpenAIResponse(
    {
      model,
      parallel_tool_calls: true,
      tool_choice: "auto",
      tools,
      input: [
        {
          role: "system",
          content: [{ type: "input_text", text: SYSTEM_PROMPT }],
        },
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: JSON.stringify(bundle),
            },
          ],
        },
      ],
    },
    apiKey,
  );

  const functionCalls = getFunctionCalls(response);
  const rawArgs = collectToolArgsByName(functionCalls);

  const screening = sanitizeScreening(
    rawArgs.screen_user_request,
    bundle.message,
    bundle.user_context,
  );
  const emotion = sanitizeEmotion(rawArgs.analyze_emotion, bundle.message);
  const nutritionApiRequest = buildNutritionApiRequest(screening, bundle);

  return {
    screening,
    emotion,
    nutrition_api_request: nutritionApiRequest,
  };
}

// 當 OpenAI 無法使用時，退回本地 rule-based fallback 路徑。
function runFallbackFlow(bundle) {
  const screening = fallbackScreening(bundle.message, bundle.user_context);
  const emotion = fallbackEmotion(bundle.message);
  const nutritionApiRequest = buildNutritionApiRequest(screening, bundle);

  return {
    screening,
    emotion,
    nutrition_api_request: nutritionApiRequest,
  };
}

function createUserContext(requestBody, loadedUserData) {
  return {
    has_active_restaurant_context: Boolean(requestBody.context?.restaurant_name),
    has_menu_context:
      Array.isArray(requestBody.context?.menu_items) &&
      requestBody.context.menu_items.length > 0,
    has_user_profile: Boolean(loadedUserData.user_profile),
  };
}

// 這是 Express API 的主要處理流程，對應 POST /companion/ask。
// 它會：
// 1. 接收 request body
// 2. 載入使用者資料
// 3. 執行 LLM 主判斷
// 4. 必要時退回 fallback
// 5. 呼叫 Nutrition API
// 6. 回傳最終 JSON
async function handleCompanionAsk(req, res) {
  const message = typeof req.body.message === "string" ? req.body.message.trim() : "";

  if (!message) {
    res.status(400).json({
      success: false,
      error: "message is required",
    });
    return;
  }

  const loadedUserData = await loadUserData(req.body);
  const bundle = {
    message,
    user_context: createUserContext(req.body, loadedUserData),
    user_profile: loadedUserData.user_profile,
    health_condition: loadedUserData.health_condition,
    weekly_diet_records: loadedUserData.weekly_diet_records,
  };

  let openAiResult;
  let llmFallbackUsed = false;

  try {
    openAiResult = await runOpenAIFlow(bundle);
  } catch (error) {
    llmFallbackUsed = true;
    openAiResult = runFallbackFlow(bundle);
    openAiResult.llm_error = error.message;
  }

  let nutritionApiResponse = null;
  let nutritionApiError = null;

  if (openAiResult.nutrition_api_request) {
    try {
      nutritionApiResponse = await callNutritionApi(openAiResult.nutrition_api_request);
    } catch (error) {
      nutritionApiError = error.message;
    }
  }

  res.json({
    success: true,
    llm_fallback_used: llmFallbackUsed,
    screening: openAiResult.screening,
    emotion: openAiResult.emotion,
    nutrition_api_request: openAiResult.nutrition_api_request,
    nutrition_api_response: nutritionApiResponse,
    nutrition_api_error: nutritionApiError,
    companion_reply: buildCompanionReply({
      screening: openAiResult.screening,
      emotion: openAiResult.emotion,
      nutritionApiResponse,
    }),
  });
}

const app = express();
app.use(express.json());

app.get("/health", (_req, res) => {
  res.json({ status: "ok" });
});

app.post("/companion/ask", async (req, res) => {
  try {
    await handleCompanionAsk(req, res);
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

const port = Number(process.env.COMPANION_API_PORT || 3000);
app.listen(port, () => {
  console.log(`Companion Agent API listening on port ${port}`);
});
