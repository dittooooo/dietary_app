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
  // 容錯防呆：如果 OpenAI 沒有觸發意圖工具調用，預設為不需處理的閒聊分類
  if (!raw) {
    return {
      should_handle: false,
      intent_category: "general_chat",
      question_type: undefined,
      confidence: 0,
      dish_info_list: {},
      meal_items: []
    };
  }

  const result = { ...raw };
  if (!Array.isArray(result.meal_items)) {
    result.meal_items = [];
  }

  // ── 自動衍生欄位（Single Source of Truth）：從一維 meal_items 提煉所有食物名稱與份數，生成 dish_info_list 物件 ──
  const dishInfoList = {};
  for (const item of result.meal_items) {
    if (item && item.name) {
      const amount = (typeof item.quantity === "number" && item.quantity > 0) ? item.quantity : 1;
      dishInfoList[item.name] = amount;
    }
  }
  result.dish_info_list = dishInfoList;
  delete result.dishes;

  // 強制規則防護：如果意圖不是飲食建議，則 question_type 強制歸類為 "not_applicable"
  if (result.intent_category !== "dish_advice") {
    result.question_type = "not_applicable";
  } else if (!result.question_type) {
    result.question_type = "unknown";
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
   - 當訊息為敏感的醫療諮詢、疾病診斷、藥物使用（例如：「頭痛要吃什麼藥」）、非飲食相關的閒聊（例如：天氣、純問候），設為 false。
2. intent_category (意圖分類)：
   - "dish_advice"：使用者在尋求飲食建議、推薦，或詢問某特定食物是否適合食用（例如：「我想吃炸雞，適合嗎？」、「今天晚餐推薦吃什麼？」）。若問句中同時包含「記錄已吃食物」與「尋求建議」，應優先歸類於 "dish_advice"。
   - "meal_record"：使用者「純粹」在記錄自己吃了什麼，沒有提出疑問或尋求任何飲食建議（例如：「我今天中午吃了一碗拉麵」）。
   - "general_chat"：非飲食主題的純閒聊、問候，或任何醫療/診斷/藥物問題。
3. question_type (問題類型) —— （無論哪種意圖均為必填常駐欄位）：
   - "single_dish"：問句中僅提及「單一」特定餐點或食物進行詢問（例如：「我吃炸雞排適合嗎？」）。
   - "dish_comparison"：問句中提及「兩樣或多樣」餐點/食物（包含比較熱量、抉擇/二選一猶豫「在想要吃 A 還是 B」、或是多餐搭配）。只要提及兩樣（含）以上的食物品項，一律歸為此類！
   - "unknown"：意圖為 "dish_advice" 但問句中「完全未提及任何具體食物名稱」的飲食諮詢（例如：「今天晚餐推薦吃什麼？」、「我這樣吃會太胖嗎？」）。【強烈禁令】：只要問句中有出現具體食物名稱，絕不可以設為 "unknown"！
   - "not_applicable"：非飲食諮詢意圖（即意圖為 "meal_record" 或 "general_chat"）時，question_type 一律填入此值！
4. meal_items (一維餐點明細陣列)：
   - 將訊息中所提及的每一個食物/飲料品項，抽取為一維扁平物件陣列。每個物件必須包含 "name"、"quantity"、"unit" 與推算之 "meal_period"（"早餐"、"中餐"、"晚餐"、"其他"）。
   - 【餐期推算規則與強烈禁令】：
     * 若問句中已有明確時間詞（如「上午吃了...」、「晚餐想吃...」），優先採納該時間詞所對應之餐期。
     * 若問句中未明確提及餐期時間詞，請務必依據傳入之 24 小時制當前系統時間推算：
       - 05:00 - 10:30 推算為 "早餐"
       - 10:30 - 14:00 推算為 "中餐"
       - 14:00 - 17:00 推算為 "其他"
       - 17:00 - 21:00 推算為 "晚餐"
       - 21:00 - 05:00 推算為 "其他"
     * 只要含有食物或飲料品項，必須完整擷取。絕不可傳回空陣列。僅非飲食主題問句才傳回空陣列 []。
   - 【Few-shot 範例 1：單一餐點諮詢 (single_dish)】
     - 使用者輸入：「我今天晚餐想吃一碗紅燒牛肉麵，請問這樣會不會太油或熱量太高？」
     - 期待 meal_items 輸出：
       [
         {"name": "紅燒牛肉麵", "quantity": 1, "unit": "碗", "meal_period": "晚餐"}
       ]
   - 【Few-shot 範例 2：餐點比較諮詢 (dish_comparison)】
     - 使用者輸入：「午餐想吃便當，主食選烤雞腿便當跟滷排骨便當，哪一個比較推薦？」
     - 期待 meal_items 輸出：
       [
         {"name": "烤雞腿便當", "quantity": 1, "unit": "個", "meal_period": "中餐"},
         {"name": "滷排骨便當", "quantity": 1, "unit": "個", "meal_period": "中餐"}
       ]
   - 【Few-shot 範例 3：跨餐期紀錄 (meal_record)】
     - 使用者輸入：「幫我記一下飲食，我上午吃了一份鮪魚蛋吐司，中午吃了一盒舒肥雞胸肉沙拉。」
     - 期待 meal_items 輸出：
       [
         {"name": "鮪魚蛋吐司", "quantity": 1, "unit": "份", "meal_period": "早餐"},
         {"name": "舒肥雞胸肉沙拉", "quantity": 1, "unit": "盒", "meal_period": "中餐"}
       ]
`;

// 定義提供給 OpenAI Function Calling 的工具清單 (包含意圖篩選與情緒分析工具的參數規格描述)
const tools = [
  {
    type: "function",
    function: {
      name: "screen_user_request",
      description: "Screen the user request to classify question type, intent, and extract mentioned dishes into a 1D flat array.",
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
            enum: ["single_dish", "dish_comparison", "unknown", "not_applicable"],
            description: "飲食諮詢時依餐點數量選 single_dish / dish_comparison / unknown；非飲食諮詢 (meal_record 或 general_chat) 一律選 not_applicable。"
          },
          confidence: {
            type: "number"
          },
          meal_items: {
            type: "array",
            description: "一維餐點明細陣列。無論是記錄或諮詢，只要訊息中含有具體食物名稱，均必須完整擷取至此列表中，絕不可傳回空陣列。僅非飲食主題問句（如天氣）才傳回空陣列 []。",
            items: {
              type: "object",
              properties: {
                name: { type: "string", description: "食物或飲料名稱，例如：蛋餅" },
                quantity: { type: "number", description: "數量，例如：1 (若未提及則設為 1)" },
                unit: { type: "string", description: "單位，例如：份、碗、個 (若未提及則設為 '份' 或 '個' 等合理預設值)" },
                meal_period: {
                  type: "string",
                  enum: ["早餐", "中餐", "晚餐", "其他"],
                  description: "該餐點對應或推算之餐期。"
                }
              },
              required: ["name", "quantity", "unit", "meal_period"]
            }
          }
        },
        required: [
          "should_handle",
          "intent_category",
          "question_type",
          "confidence",
          "meal_items"
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
  // 取得台灣當前本地時間 (強制使用標準 24 小時制，方便 LLM 進行時間區間對比)
  const now = new Date();
  const localTimeStr = now.toLocaleString("zh-TW", {
    timeZone: "Asia/Taipei",
    hour12: false,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit"
  });

  // 組合成富含 24 小時制時間上下文的提示輸入
  const promptWithTime = `當前系統時間: ${localTimeStr}\n使用者輸入: "${userPrompt}"`;

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
              text: promptWithTime //TODO: 把系統時間一同傳給openai， 有助時間的判斷。
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
 * 指導 LLM 作為小精靈本尊對話生成器 (100% 集中注入 Persona 靈魂)，將意圖分析、情緒同理與營養數據重組為溫馨口語對話。
 */
const REPLY_SYSTEM_PROMPT = `
你是一位溫暖、支持性強且專業的飲食陪伴助理，名稱為「飲食精靈」（Companion Agent）。
你是系統中唯一的對話發聲管道 (Single Point of Persona)。
你的任務是根據輸入的「意圖篩選結果 (screening)」、「情緒與同理心設定 (emotion)」以及「Dietary Agent 後端數據」，生成一段親切、自然、口語化且富含同理心的台灣繁體中文對話。

請嚴格遵循以下 Persona 靈魂與對話生成規範：

【1. Persona 性格與口吻】
- 稱呼自己為「本精靈」或「小芽」。
- 語氣必須極具同理心、溫暖且鼓勵性強，適度使用親切的繁體中文標點與溫馨顏文字（如 ✨, 🌱, 💕, 😋）。
- 嚴禁冷漠機械式的清單列舉或機器人口吻。

【2. 4 大對話情境處理規則】
- 情境 A：【非飲食相關 (screening.should_handle === false 或 intent_category === "general_chat")】
  * 溫柔同理使用者的心情，婉轉說明自己是飲食健康陪伴助理，並親切引導使用者回到餐點選擇、日常飲食或熱量管理的範圍。
- 情境 B：【飲食紀錄確認 (intent_category === "meal_record")】
  * 以熱情、讚賞的語氣肯定使用者主動紀錄飲食的好習慣，並簡短溫馨地說明已幫忙整理好草稿供點擊確認。
- 情境 C：【飲食諮詢但無具體食物 (intent_category === "dish_advice" 且 meal_items 為空陣列或 question_type === "unknown")】
  * 以親切關懷的語氣提示使用者，說明自己很想幫忙給予建議，但需要使用者再多告訴你具體想吃或想比較的餐點名稱。
- 情境 D：【正常飲食諮詢建議 (intent_category === "dish_advice" 且含具體食物數據與建議)】
  * 將 Dietary Agent 提供的專業營養數據，轉化為親切通俗的飲食選擇建議。
  * 【例外情境】：若 context 中帶有 dietaryAgentError (下游知識庫修整中)，請誠實親切告知，並提供常識性的飲食大原則。

【3. 語氣與同理心 (Empathy Handling)】
- 若情緒分析中的 needs_empathy 為 true（使用者表現出罪惡感、焦慮或壓力），請務必在回應開頭主動提供安撫與溫暖關懷，協助排解心理負擔。

【4. 數值範圍化估算規則 (Numerical Range Rule)】
- 當回答涉及熱量大卡或營養數值時，【嚴禁給予精確單一數字】（如 380 大卡）。
- 必須轉換為【以 50 大卡為間隔的範圍區間】（如「350～400 大卡」、「550～600 大卡左右」）。

【5. 數值類免責聲明規則 (Required Disclaimer Rule)】
- 只要對話中提及具體數值（熱量大卡、三大營養素克數等），你必須在回應的【最末尾獨立換行】附上完全一模一樣的聲明：
"關於數值類提問，本精靈只可提供參考數值"

【6. 輸出格式】
- 僅返回最終呈現給使用者的對話文字，切勿使用 JSON 格式或 markdown 程式碼區塊包裝。
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
  screening,
  emotion,
  dietaryAgentResponse,
  dietaryAgentError
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
          content: `使用者問句: "${userPrompt}"\n\n意圖與篩選設定 (screening): ${JSON.stringify(screening)}\n\n情緒與同理心設定: ${JSON.stringify(emotion)}\n\nDietary Agent 異常訊息 (dietaryAgentError): ${dietaryAgentError || "無"}\n\nDietary Agent 回傳資料:\n${rawDataStr}`
        }
      ],
      // 【temperature 作用說明與相容性調整】：
      // temperature 控制模型的隨機度與創造力 (範圍 0.0~2.0)。數值越低輸出越穩定精準。
      // 修改原因：部分新型模型 (如 o1/o3 或特殊代理模型) 不支援自訂 temperature 參數，會引發 HTTP 400 錯誤。
      // 故暫時註解，改為使用模型的預設值 (1.0)。
      // temperature: 0.2,
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
        // 【temperature 作用說明與相容性調整】：
        // temperature 控制翻譯解構的隨機度。修改原因同上，避免部分模型不支援自訂值而報錯。
        // temperature: 0.1,
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
