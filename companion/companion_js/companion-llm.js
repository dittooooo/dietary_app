// Path: c:\Users\User\Documents\Github_Repo\dietary_app\companion\companion_js\companion-llm.js
// Description: All LLM-related configuration and execution logic

/**
 * ============================================================================
 * 第一部分：輔助工具函數與環境變數載入
 * ============================================================================
 */

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
      question_type: undefined,
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

  // 強制規則防護：如果意圖不是飲食建議，則不應出現 question_type 欄位
  if (result.intent_category !== "dish_advice") {
    delete result.question_type;
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
 * ============================================================================
 * 第二部分：核心 LLM 處理流程 (Prompt、Schema 與 呼叫函數成對擺放)
 * ============================================================================
 */

// ----------------------------------------------------------------------------
// 階段 1：意圖篩選與情緒分析 (First-stage classification and emotion screening)
// ----------------------------------------------------------------------------

// 第一階段「意圖篩選與情緒分析」的系統提示詞 (ANALYSIS_SYSTEM_PROMPT)
// 指導 LLM 作為分類器與特徵擷取器，分析使用者輸入並決定是否應處理，以及提取餐點與判斷提問類型。
const ANALYSIS_SYSTEM_PROMPT = `
你是一個飲食推薦應用程式的 Companion Agent（陪伴助理）分類與特徵擷取器。
你的任務是分析使用者的輸入訊息（通常為繁體中文），並同時執行兩個工具調用："screen_user_request" 與 "analyze_emotion"。

請嚴格遵守以下分類與擷取規則：

【screen_user_request 的規則】
1. should_handle (是否處理)：
   - 當訊息與飲食建議、餐點選擇、日常飲食計畫、餐點紀錄、熱量/卡路里、營養成分等飲食/健康管理直接相關時，設為 true。
   - 當訊息為敏感的醫療諮詢、疾病診斷、藥物使用（例如：「頭痛要吃什麼藥」、「胃痛吃什麼胃藥」）、非飲食相關的閒聊（例如：天氣、純問候），設為 false。
2. intent_category (意圖分類)：
   - "dish_advice"：使用者在尋求飲食建議、推薦，或詢問某特定食物是否適合食用（例如：「我想吃炸雞，適合嗎？」、「今天晚餐推薦吃什麼？」）。若問句中同時包含「記錄已吃食物」與「尋求建議」，應優先歸類於 "dish_advice"。
   - "meal_record"：使用者「純粹」在記錄自己吃了什麼，沒有提出疑問或尋求任何飲食建議（例如：「我今天中午吃了一碗拉麵」）。
   - "general_chat"：非飲食主題的純閒聊、問候，或任何醫療/診斷/藥物問題（例如：「感冒發燒要看醫生嗎？」）。
3. question_type (問題類型) —— （注意：僅當 intent_category 為 "dish_advice" 時才可包含此欄位）：
   - "single_dish"：針對單一特定餐點或食物進行詢問（例如：「我吃炸雞排適合嗎？」）。
   - "dish_comparison"：比較兩樣或多樣餐點/食物（例如：「炸雞排跟拉麵哪個熱量低？」），或是詢問一天內多餐搭配（例如：「中午吃了炸雞，晚上還可以吃拉麵嗎？」）。
   - "unknown"：其他意圖不明或未明確提及任何食物名稱的飲食諮詢。
   - 注意：如果 intent_category 不是 "dish_advice"（即為 "meal_record" 或 "general_chat"），請勿在輸出的參數中包含 "question_type" 欄位。
4. dishes (餐點實體擷取)：
   - 擷取使用者問句中所有提及的具體食物、餐點或飲料名稱，以繁體中文陣列返回。
   - 若未提及任何具體食物名稱，則返回空陣列 []。
5. early_reply (早退回覆)：
   - 以溫馨、充滿同理心的台灣繁體中文（Traditional Chinese, Taiwan）生成一段對話式回覆，並融入 analyze_emotion 偵測到的語氣。
   - 當 should_handle 為 false 時：生成一段溫暖的回應，婉轉說明自己是飲食助理，並引導使用者回到餐點選擇、飲食計畫或熱量管理的範圍。
   - 當 should_handle 為 true，但 dishes 為空陣列 [] 或 question_type 為 "unknown" 時：以親切的語氣提示使用者，詢問他們具體想問哪樣食物，或者是否想針對單一食物或比較多樣食物來做諮詢。
   - 當上述條件都不滿足（即 should_handle 為 true，且 dishes 不為空，且 question_type 為 single_dish 或 dish_comparison）時：直接設定為空字串 ""。
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
          // "question_type", <-- 從此處移除，改為條件式必填
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

// ----------------------------------------------------------------------------
// 階段 2：陪伴式回覆重組與生成 (Second-stage reply rewrite and generation)
// ----------------------------------------------------------------------------

/**
 * 用於第二階段「最終回覆生成」的 System Prompt (REPLY_SYSTEM_PROMPT)
 * 指導 LLM 將意圖分析、同理心需求與 Dietary Agent 後端的營養分析結果，重組並潤飾為溫馨、台灣繁體中文的口語對話回覆。
 */
const REPLY_SYSTEM_PROMPT = `
你是一位溫暖、支持性強且專業的飲食陪伴助理，名稱為「飲食精靈」（Companion Agent）。
你的任務是將「Dietary Agent」（飲食助理後端）回傳的結構化分析數據與營養建議，重新整理並潤飾成一段親切、自然且富含同理心的台灣繁體中文對話回覆。

請嚴格遵守以下重組規則：
1. 語氣與同理心（Tone & Empathy）：
   - 結合第一階段情緒分析的結果。如果情緒分析指出 "needs_empathy" 為 true（代表使用者可能有罪惡感、焦慮、壓力或挫折感），請在回覆開頭或過程中，融入一句溫暖、關懷的話語，主動幫使用者排解對餐點選擇的心理負擔或罪惡感。
   - 回覆必須自然、口語化且親切，避免僵硬的機器人語氣或只是機械式地照抄 JSON 列表。
2. 內容整合（Context Integration）：
   - 將 Dietary Agent 提供的專業營養學建議（如熱量預警、食物替換方案、三大營養素比例分析等）轉化為通俗易懂的對話句子。
   - 不能漏失 Dietary Agent 的關鍵核心建議，但應將其融入溫馨的聊天情境中。
3. 免責聲明規則（Disclaimer Rule）：
   - 如果使用者的提問涉及到具體數值（如熱量、蛋白質、脂肪、碳水化合物、營養成分克數等），你必須在回覆的「最末尾」獨立換行加上這句完全一模一樣的聲明：「關於數值類提問，本精靈只可提供參考數值」。
4. 輸出格式：僅返回最終的對話文字，請勿用 JSON 格式包裝，亦避免不必要的 markdown 程式碼區塊（除非是為了排版好看）。
`;

/**
 * 簡化 Dietary Agent 回傳的資料，去除 LLM 不需要的一般 Metadata，以節省 Token 並降低干擾。
 * @param {Object} response - 原始 Dietary Agent API 回傳物件
 * @returns {Object|null} 簡化後的資料結構，若無資料則回傳 null
 */
function minimizeDietaryResponse(response) {
  if (!response) return null;

  const minimized = {};

  // 1. 簡化餐點營養數據 (僅保留名稱、營養素項目、數值與單位)
  if (Array.isArray(response.dish_nutrition)) {
    minimized.dish_nutrition = response.dish_nutrition.map(dish => ({
      dish_name: dish.dish_name,
      nutrients: (dish.nutrients || []).map(n => ({
        name: n.name,
        amount_per_serving: n.amount_per_serving,
        unit: n.unit
      }))
    }));
  }

  // 2. 簡化飲食建議 (只保留對話重組所需的適合度與建議)
  if (Array.isArray(response.dish_advice)) {
    minimized.dish_advice = response.dish_advice.map(advice => ({
      dish_name: advice.dish_name,
      suitability: advice.suitability,
      key_reasons: advice.key_reasons,
      suggestions: advice.suggestions
    }));
  }

  // 3. 保留整體結論
  if (response.conclusion) {
    minimized.conclusion = response.conclusion;
  }

  return minimized;
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
  emotion,
  dietaryAgentResponse
}) {
  const apiKey = process.env.OPENAI_API_KEY;
  const model = process.env.OPENAI_MODEL || "gpt-4o-mini";

  if (!apiKey) {
    throw new Error("Missing OPENAI_API_KEY.");
  }

  // 將 Dietary Agent 回傳的結構化資料進行簡化降噪後轉為易讀的 JSON 字串，以利 LLM 讀取理解
  const rawDataStr = dietaryAgentResponse
    ? JSON.stringify(minimizeDietaryResponse(dietaryAgentResponse), null, 2)
    : "無資料";

  // TODO: 第二階段API
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

// ----------------------------------------------------------------------------
// 階段 3：餐點/飲料名稱翻譯與標準化 (Third-stage food translation)
// ----------------------------------------------------------------------------

// 食品名稱翻譯與標準化的系統提示詞 (TRANSLATION_SYSTEM_PROMPT)
const TRANSLATION_SYSTEM_PROMPT = `
你是一個飲食推薦應用程式的食品名稱翻譯助理。你的工作是將使用者輸入的「花俏」餐點或飲料名稱，拆解並翻譯成最直白、標準、無冗餘形容詞的食品資料庫標準品名，以便進行後續的營養成分與熱量分析。
請只回傳符合 JSON 物件格式的結果，格式為：{"translated_dishes": ["標準品名1", "標準品名2"]}，請勿附帶任何額外的說明文字。

飲料與乳製品分類標準：
1. 乳製品分類標準：
   - 包含「歐蕾/那堤/拿鐵/鮮乳/鮮奶/鮮乳專門」：一律翻譯為「鮮乳」。
   - 包含「厚乳/濃乳/重乳」：若無法確認成分，一律翻譯為「濃鮮乳」。
   - 包含「奶茶/奶精/奶風味」：一律翻譯為「奶精」。
2. 茶底分類標準：
   - 包含「翡翠/春芽/碧螺春/茉香/窨花」：一律翻譯為「綠茶」。
   - 包含「熟成/琥珀/朝露/麗春/紅玉/錫蘭/祁門」：一律翻譯為「紅茶」。
   - 包含「金萱/翠玉/鐵觀音/炭培/四季春/烏龍」：一律翻譯為「烏龍茶」。
   - 包含「冷露」：一律翻譯為「冬瓜茶」。
3. 配料分類標準：
   - 包含「水玉/寒天」：一律翻譯為「寒天蒟蒻」。
   - 包含「墨玉/仙草」：一律翻譯為「仙草凍」。
   - 包含「波霸/珍珠」：一律翻譯為「粉圓」。

範例：
- "起司瀑布超厚牛肉堡" -> ["牛肉漢堡"]
- "特濃豚骨豚角煮拉麵" -> ["豬肉拉麵"]
- "低卡舒肥雞胸肉沙拉搭配胡麻醬" -> ["雞胸肉沙拉", "胡麻醬"]
- "熟成歐蕾" -> ["鮮乳", "紅茶"]
- "翡翠厚乳" -> ["鮮乳（強化）", "綠茶"]
- "炭培烏龍奶茶" -> ["奶精", "烏龍茶"]
- "冷露拿鐵" -> ["鮮乳", "冬瓜茶"]
- "波霸鮮奶茶" -> ["粉圓", "鮮乳", "紅茶"]
- "水玉冷露" -> ["寒天蒟蒻", "冬瓜茶"]
- "墨玉凍紅茶" -> ["仙草凍", "紅茶"]
`;

/**
 * 呼叫 OpenAI Chat Completions API 將花俏的餐點名稱翻譯/拆解為食品資料庫標準品名
 * @param {Array<string>} dishes - 原始擷取出的餐點名稱陣列
 * @returns {Promise<Array<string>>} 翻譯與標準化後的餐點名稱陣列
 */
async function translateDishes(dishes) {
  if (!Array.isArray(dishes) || dishes.length === 0) {
    return [];
  }

  const apiKey = getApiKey();
  const model = getModel();

  try {
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
            content: TRANSLATION_SYSTEM_PROMPT
          },
          {
            role: "user",
            content: JSON.stringify(dishes)
          }
        ],
        temperature: 0.1,
        response_format: { type: "json_object" }
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error(`Translation API error: ${response.status} - ${errorText}`);
      return dishes; // 失敗時降級回傳原始餐點名稱
    }

    const resJson = await response.json();
    const content = resJson.choices[0].message.content.trim();
    const parsed = JSON.parse(content);
    if (parsed && Array.isArray(parsed.translated_dishes)) {
      return parsed.translated_dishes;
    }
  } catch (error) {
    console.error("Failed to translate dishes:", error.message);
  }

  return dishes; // 失敗時降級回傳原始餐點名稱
}

// 匯出大語言模型服務層核心函數
module.exports = {
  runOpenAIFlow,
  generateCompanionReply,
  translateDishes,
  minimizeDietaryResponse
};
