// Path: c:\Users\User\Documents\Github_Repo\dietary_app\companion\companion_js\companion-llm.js
// Description: All LLM-related configuration and execution logic

// 第一階段「意圖篩選與情緒分析」的系統提示詞 (ANALYSIS_SYSTEM_PROMPT)
// 指導 LLM 作為分類器與特徵擷取器，分析使用者輸入並決定是否應處理，以及提取餐點與判斷提問類型。

const ANALYSIS_SYSTEM_PROMPT = `
You are a Companion Agent classifier and extractor for a dietary recommendation app.
Your task is to analyze the user's message, which is usually in Traditional Chinese.

You MUST execute both functions in parallel: "screen_user_request" and "analyze_emotion".

Rules for "screen_user_request":
1. should_handle:
   - true when the request is about food, diet, meal choice, meal planning, eating advice, or calories.
   - false when it is medical diagnosis, medication usage, disease treatment, doctor advice, or unrelated chat.
2. intent_category:
   - "dish_advice": asking for dietary advice, recommendations, or whether they can eat a certain food (even if they mention what they already ate). If a message contains BOTH recording what they ate and asking for advice, ALWAYS prioritize "dish_advice".
   - "meal_record": ONLY when the user is purely recording what they ate without asking any questions or seeking advice (e.g., "我今天中午吃了拉麵").
   - "general_chat": unrelated small talk, off-topic requests, or medical questions (medicine, diagnosis, disease treatment, doctor advice).
3. question_type:
   - "single_dish": asking about one dish or meal (e.g., "我吃炸雞排適合嗎").
   - "dish_comparison": comparing two or more dishes (e.g., "炸雞排跟拉麵哪個熱量低"), or asking about eating multiple different dishes in a day (e.g., "中午吃炸雞，晚上還可以吃拉麵嗎").
   - "unknown": unclear, unrelated topics, or no food/dish name is mentioned at all.
4. dishes:
   - extract all specific food, dish, or drink names mentioned in the user's original language.
   - return [] when none are clearly mentioned.
5. early_reply:
   - Generate this response in warm, empathetic Traditional Chinese (Taiwan繁體中文) matching the tone detected by analyze_emotion.
   - If should_handle is false: Write a warm dialog response explaining that you are a dietary helper and politely guide them back to topics like meal suggestions, calories, or diet planning.
   - If should_handle is true but dishes is empty OR question_type is "unknown": Write a friendly prompt asking them to specify what dish they are referring to or whether they want to ask about a single food or compare multiple foods.
   - If should_handle is true AND dishes is NOT empty AND question_type is single_dish or dish_comparison (meaning the request is valid to be processed): Set it to an empty string "".
`;

/**
 * 用於第二階段「最終回覆生成」的 System Prompt (REPLY_SYSTEM_PROMPT)
 * 指導 LLM 將意圖分析、同理心需求與 Dietary Agent 後端的營養分析結果，重組並潤飾為溫馨、台灣繁體中文的口語對話回覆。
 */
const REPLY_SYSTEM_PROMPT = `
You are a warm, supportive, and professional dietary assistant called "Companion Agent" (飲食精靈).
Your task is to rewrite and embellish the raw data and analysis results provided by the "Dietary Agent" into a warm, empathetic, and conversational response for the user.

Follow these rules:
1. Tone & Style:
   - Match the tone recommended in the emotional analysis.
   - If "needs_empathy" is true, start or weave in a warm, caring statement to ease the user's guilt or anxiety about their meal choice. 
   - Keep the reply friendly, conversational, and written in natural Traditional Chinese (Taiwan). Avoid sounding like a rigid bot or just outputting raw JSON lists.
2. Context Integration:
   - Translate the analytical advice (like caloric warnings, food swaps, and macronutrient explanations) into easily understandable sentences.
   - Do NOT omit key recommendations from the Dietary Agent, but integrate them naturally.
3. Disclaimer Rule:
   - If the user's query asks about numbers (calories, fat, protein, carbs, nutrition metrics), you MUST append this exact phrase at the very end of your response: "關於數值類提問，本精靈只可提供參考數值".
4. Output format: Return ONLY the final dialogue response text. Do not include any JSON wrapping or markdown blocks unless it improves readability for the user.
`;

// 定義提供給 OpenAI Function Calling 的工具清單 (包含意圖篩選與情緒分析工具的參數規格描述)
const tools = [
  {
    type: "function",
    function: {
      name: "screen_user_request",
      description: "Screen the user request to classify question type, intent, and extract mentioned dishes.",
      parameters: {
        type: "object",
        properties: {
          should_handle: {
            type: "boolean",
            description: "Whether this request should be processed by the companion agent."
          },
          intent_category: {
            type: "string",
            enum: ["dish_advice", "meal_record", "general_chat"]
          },
          question_type: {
            type: "string",
            enum: ["single_dish", "dish_comparison", "unknown"]
          },
          confidence: {
            type: "number"
          },
          dishes: {
            type: "array",
            items: { type: "string" },
            description: "List of all food or dish names mentioned in the user message."
          },
          early_reply: {
            type: "string",
            description: "If should_handle is false, OR if should_handle is true but dishes is empty or question_type is 'unknown', generate a warm, Taiwanese Traditional Chinese dialog response to guide or reply to the user. Otherwise, set it to an empty string \"\"."
          }
        },
        required: [
          "should_handle",
          "intent_category",
          "question_type",
          "confidence",
          "dishes",
          "early_reply"
        ],
        additionalProperties: false
      }
    }
  },
  {
    type: "function",
    function: {
      name: "analyze_emotion",
      description: "Analyze the user's emotional state and tone to adjust companion responses.",
      parameters: {
        type: "object",
        properties: {
          primary_emotion: {
            type: "string",
            enum: ["neutral", "curious", "anxiety", "guilt", "stress", "frustration", "joy"]
          },
          valence: {
            type: "string",
            enum: ["positive", "neutral", "negative"]
          },
          urgency: {
            type: "string",
            enum: ["low", "medium", "high"]
          },
          needs_empathy: {
            type: "boolean"
          },
          companion_tone: {
            type: "string",
            enum: ["calm", "encouraging", "neutral"]
          },
          evidence: {
            type: "array",
            items: { type: "string" },
            description: "Keywords or phrases from the message indicating this emotion."
          }
        },
        required: [
          "primary_emotion",
          "valence",
          "urgency",
          "needs_empathy",
          "companion_tone",
          "evidence"
        ],
        additionalProperties: false
      }
    }
  }
];

/**
 * 從環境變數中取得 OpenAI API 金鑰
 * @returns {string} API 金鑰
 */
function getApiKey() {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    throw new Error("Missing OPENAI_API_KEY.");
  }
  return apiKey;
}

/**
 * 從環境變數中取得欲使用的 OpenAI 模型名稱，預設為 "gpt-4o-mini"
 * @returns {string} 模型名稱
 */
function getModel() {
  return process.env.OPENAI_MODEL || "gpt-4o-mini";
}

/**
 * 呼叫 OpenAI Responses API 建立回應 (用於第一階段多功能平行分析)
 * @param {Object} body - 發送給 OpenAI 的請求主體 payload
 * @param {string} apiKey - OpenAI API 憑證金鑰
 * @returns {Promise<Object>} OpenAI API 回傳的 JSON 回應
 */
async function createOpenAIResponse(body, apiKey) {
  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`
    },
    body: JSON.stringify(body)
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`OpenAI API error ${response.status}: ${errorText}`);
  }

  return response.json();
}

/**
 * 從 OpenAI Response API 的回傳結果中提取出所有 Function Calls 的調用項目
 * @param {Object} responseJson - API 回傳的完整 JSON 資料
 * @returns {Array<Object>} function_call 類型的陣列
 */
function getFunctionCalls(responseJson) {
  return (responseJson.output || []).filter((item) => item.type === "function_call");
}

/**
 * 將多個平行 Function Calls 的參數解析並彙整成以工具名稱為 Key 的物件對照表
 * @param {Array<Object>} functionCalls - Function Call 呼叫項目陣列
 * @returns {Object} 以工具名稱為鍵、解析後參數為值的對照表
 */
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

/**
 * 【Function Calling 容錯防呆機制說明】：
 * 當使用者輸入與飲食完全無關的內容（如天氣、用藥等）時，OpenAI API 雖正常成功回傳，
 * 但會判定不需要調用我們提供的工具。此時 `rawArgs.screen_user_request` 將會是 `undefined`（!raw 為真）。
 * 為了避免後端在後續讀取 `openAiResult.screening.should_handle` 等欄位時因為讀到 undefined 
 * 而造成伺服器拋出 500/502 異常，此處主動「虛擬」回傳一個帶有完整欄位的預設物件。
 * 這會引導後續的 Node.js 程式走入 should_handle: false 的 off-topic 攔截流程，對使用者回傳親切的閒聊防呆提示。
 */
function sanitizeScreening(raw) {
  // 容錯防呆：如果 OpenAI 沒有觸發意圖工具調用，預設為不需處理的閒聊分類，並給予預設早退回覆
  if (!raw) {
    return {
      should_handle: false,
      intent_category: "general_chat",
      question_type: "unknown",
      confidence: 0,
      dishes: [],
      early_reply: "這個問題比較不是飲食助理的處理範圍。如果你願意，我還是可以幫你回到餐點選擇、熱量方向，或日常飲食建議來一起看。"
    };
  }

  const result = { ...raw };
  if (!Array.isArray(result.dishes)) {
    result.dishes = [];
  }
  if (typeof result.early_reply !== "string") {
    result.early_reply = "";
  }

  return result;
}

/**
 * 情緒分析結果的容錯防呆機制
 * 當 OpenAI 沒有觸發情緒工具調用時，回傳預設的中性情緒與同理心指標
 * @param {Object} raw - 原始從 LLM 獲得的情緒參數物件
 * @returns {Object} 經過清理與預設值補齊後的情緒物件
 */
function sanitizeEmotion(raw) {
  // 容錯防呆：如果 OpenAI 沒有觸發情緒工具調用，給予中性情緒預設值
  if (!raw) {
    return {
      primary_emotion: "neutral",
      valence: "neutral",
      urgency: "low",
      needs_empathy: false,
      companion_tone: "neutral",
      evidence: []
    };
  }

  return {
    primary_emotion: raw.primary_emotion || "neutral",
    valence: raw.valence || "neutral",
    urgency: raw.urgency || "medium",
    needs_empathy: typeof raw.needs_empathy === "boolean" ? raw.needs_empathy : false,
    companion_tone: raw.companion_tone || "neutral",
    evidence: Array.isArray(raw.evidence) ? raw.evidence : []
  };
}

/**
 * 從 OpenAI Response API 的回傳結果中提取純文字輸出內容
 * 遍歷輸出結構以找出第一個文字回覆片段
 * @param {Object} responseJson - API 回傳的完整 JSON 資料
 * @returns {string} 提取出的純文字內容
 */
function extractOutputText(responseJson) {
  if (typeof responseJson.output_text === "string" && responseJson.output_text.trim()) {
    return responseJson.output_text.trim();
  }

  for (const item of responseJson.output || []) {
    if (!Array.isArray(item.content)) {
      continue;
    }

    for (const content of item.content) {
      if (content.type === "output_text" && typeof content.text === "string" && content.text.trim()) {
        return content.text.trim();
      }
    }
  }

  throw new Error("Missing text output from OpenAI response.");
}

/**
 * 執行第一階段的意圖篩選與情緒分析流程
 * 透過呼叫 OpenAI Response API 並行調用 screen_user_request 與 analyze_emotion 兩個 Function。
 * @param {string} userPrompt - 使用者原始輸入訊息
 * @returns {Promise<Object>} 包含意圖預檢 (screening) 與情緒分析 (emotion) 結果的物件
 */
async function runOpenAIFlow(userPrompt) {
  const response = await createOpenAIResponse(
    {
      model: getModel(),
      parallel_tool_calls: true, // 啟用平行 Function Calling
      tool_choice: "auto",
      tools: tools.map((tool) => ({
        type: "function",
        name: tool.function.name,
        description: tool.function.description,
        parameters: tool.function.parameters
      })),
      instructions: ANALYSIS_SYSTEM_PROMPT,
      input: [
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: userPrompt
            }
          ]
        }
      ]
    },
    getApiKey()
  );

  // 解析與收集 Function Calls 參數結果
  const functionCalls = getFunctionCalls(response);
  const rawArgs = collectToolArgsByName(functionCalls);

  // 對回傳結果進行防呆格式化處理後返回
  return {
    screening: sanitizeScreening(rawArgs.screen_user_request),
    emotion: sanitizeEmotion(rawArgs.analyze_emotion)
  };
}

/**
 * 9. 呼叫 OpenAI Chat Completions 重組最終的陪伴式回覆 (generateCompanionReply)
 * 作用：將使用者原始提問、同理心/情緒分析設定與 Dietary Agent 的分析結果，
 * 包裝後發送給 OpenAI Chat Completions API 重組，生成溫馨自然的陪伴回覆。
 * 
 * @param {Object} params - 包含以下屬性：
 *   - {string} userPrompt - 使用者原始輸入文字
 *   - {Object} screening - 意圖與食物名稱的預檢篩選結果
 *   - {Object} emotion - 偵測到的情緒與同理心指標
 *   - {Object} dietaryAgentResponse - Dietary Agent API 回傳的營養與建議數據
 *   - {Object} dietaryAgentRequest - 傳送給 Dietary Agent 的 Payload
 *   - {string} dietaryAgentError - 下游服務 API 呼叫的錯誤訊息 (如有)
 * @returns {Promise<string>} LLM 重組潤飾後的對話文字
 */
async function generateCompanionReply({
  userPrompt,
  screening,
  emotion,
  dietaryAgentResponse,
  dietaryAgentRequest,
  dietaryAgentError
}) {
  const apiKey = process.env.OPENAI_API_KEY;
  const model = process.env.OPENAI_MODEL || "gpt-4o-mini";

  if (!apiKey) {
    throw new Error("Missing OPENAI_API_KEY.");
  }

  // 將 Dietary Agent 回傳的結構化資料轉為易讀的 JSON 字串，以利 LLM 讀取理解
  const rawDataStr = dietaryAgentResponse
    ? JSON.stringify(dietaryAgentResponse, null, 2)
    : "無資料";

  // 呼叫 OpenAI 官方標準的 Chat Completions API
  // 【API 差異備忘說明】：
  // 1. 原本程式碼的「第一階段 (意圖與情緒分析)」使用的是 OpenAI Responses API (端點為 /v1/responses)，
  //    它是屬於新版/實驗性之 Agentic API，傳入參數使用 instructions 與 input 結構。
  // 2. 此處的「第二階段 (對話回覆生成)」則採用 Chat Completions API (端點為 /v1/chat/completions)，
  //    這是目前業界最通用的無狀態標準對話格式，藉由 messages (system / user) 陣列傳遞。
  //    它的相容性最高，未來若想更換成其他大型語言模型 (如 Google Gemini、Anthropic Claude)，程式碼無須重構。
  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model,
      messages: [
        {
          role: "system",
          // 帶入重組引導的系統 Prompt 規則 (包含數值免責聲明)
          content: REPLY_SYSTEM_PROMPT
        },
        {
          role: "user",
          // 組合完整的上下文，供模型重組出最貼近的對話
          content: `使用者問句: "${userPrompt}"\n\n情緒與同理心設定: ${JSON.stringify(emotion)}\n\nDietary Agent 回傳資料:\n${rawDataStr}`
        }
      ],
      temperature: 0.2,
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`OpenAI Chat API error ${response.status}: ${errorText}`);
  }

  const resJson = await response.json();
  if (!resJson.choices || resJson.choices.length === 0) {
    throw new Error("Empty choices returned from OpenAI Chat API");
  }

  // 取得 LLM 生成並去除首尾空白後的內容
  return resJson.choices[0].message.content.trim();
}

// 匯出大語言模型服務層核心函數
module.exports = {
  runOpenAIFlow,
  generateCompanionReply
};
