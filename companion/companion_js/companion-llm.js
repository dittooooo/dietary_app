// Path: c:\Users\User\Documents\Github_Repo\dietary_app\companion\companion_js\companion-llm.js
// Description: All LLM-related configuration (prompts, tools schema) and execution logic (fetch call, outputs sanitization)

/**
 * 1. 系統 Prompt 定義 (SYSTEM_PROMPT)
 * 這是給 OpenAI 模型的全局系統指令。
 * 用於指導大語言模型扮演飲食推薦應用的 Companion Agent，分析使用者問句的意圖、問題種類、情緒並擷取料理名稱。
 */
const SYSTEM_PROMPT = `
You are a Companion Agent classifier and extractor for a dietary recommendation app.
Your task is to analyze the user's message (which is usually in Traditional Chinese) and determine the intent, question type, emotion, and extract mentioned food/dish names.

You MUST execute both functions (parallel tool calls): "screen_user_request" and "analyze_emotion" to return your results.

Specific Instructions for "screen_user_request":
1. should_handle (boolean): 
   - Set to true if the request is about diet, food, meal recommendation, or calorie queries.
   - Set to false if it involves sensitive medical diagnosis, prescription drugs, disease treatment, seeking a doctor's advice (e.g., "what medicine to take for gastric ulcers"), general chat, or unrelated topics.
2. intent_category (string):
   - "dish_advice": User is consulting for dietary advice or recommendation.
   - "meal_record": User is recording their meal/diet.
   - "medical_out_of_scope": User mentions medicine, prescriptions, disease treatment, diagnosis, or doctor queries.
   - "general_chat": General chat or unrelated topics.
3. question_type (string):
   - "single_dish": User asks about a single food item or meal.
   - "dish_comparison": User compares multiple foods (e.g., "A or B, which is better?", "A vs B").
   - "unknown": None of the above.
4. dishes (array of strings):
   - Extract all specific food, dish, or drink names mentioned in the user's input (e.g., ["拉麵", "炸雞"]). 
   - Extract them in their original language as written in the user message (usually Traditional Chinese, e.g., "拉麵"). 
   - Return an empty array if no food or dish is mentioned.
`;

/**
 * 2. OpenAI Function Calling (Tools) Schema 定義
 * 這是傳給 OpenAI 的結構化輸出合約。定義了模型「必須呼叫」的函數名稱以及參數的 JSON Schema。
 * 當模型回覆時，會依此格式返回 JSON 參數，後端程式可以直接解析。
 */
const tools = [
  {
    // 指定 Tool 類型為函數呼叫 (function)
    type: "function",
    function: {
      name: "screen_user_request",
      // 對此函數用途的描述，幫助 LLM 理解何時以及如何填寫此結構
      description: "Screen the user request to classify question type, intent, and extract mentioned dishes.",
      // 定義此函數需要接收的參數 (JSON Schema 格式)
      parameters: {
        type: "object", // 參數最外層為一個 JSON 物件
        properties: {
          // should_handle: 決定 Companion Agent 是否要接手處理此問題的 boolean 值
          should_handle: {
            type: "boolean",
            description: "Whether this request should be processed by the companion agent."
          },
          // intent_category: 意圖分類，限定模型只能在以下四個選項中選擇其一
          intent_category: {
            type: "string",
            enum: ["dish_advice", "meal_record", "medical_out_of_scope", "general_chat"]
          },
          // question_type: 問題的種類 (單料理、料理比較或未知)，決定後續 Dietary Agent 組裝的邏輯
          question_type: {
            type: "string",
            enum: ["single_dish", "dish_comparison", "unknown"]
          },
          // confidence: 模型對此分類判斷的信心分數 (0.0 到 1.0 之間)
          confidence: { type: "number" },
          // dishes: 存放 LLM 從問句中自動抽取出的料理或食物名稱陣列 (例如: ["炸雞", "拉麵"])
          dishes: {
            type: "array",
            items: { type: "string" },
            description: "List of all food or dish names mentioned in the user message."
          }
        },
        required: [
          "should_handle",
          "intent_category",
          "question_type",
          "confidence",
          "dishes"
        ],
        // additionalProperties: false 是一項安全設定，嚴格限制模型不可輸出 properties 定義以外的自訂欄位
        additionalProperties: false
      }
    }
  },
  {
    type: "function",
    function: {
      name: "analyze_emotion",
      // 描述此函數用途：分析情緒以動態調整回覆語氣
      description: "Analyze the user's emotional state and tone to adjust companion responses.",
      parameters: {
        type: "object",
        properties: {
          // primary_emotion: 偵測到的主情緒列舉 (中性、好奇、焦慮、罪惡、壓力、挫折、開心)
          primary_emotion: {
            type: "string",
            enum: ["neutral", "curious", "anxiety", "guilt", "stress", "frustration", "joy"]
          },
          // valence: 情緒的正負向分類 (正向、中性、負向)
          valence: {
            type: "string",
            enum: ["positive", "neutral", "negative"]
          },
          // urgency: 使用者此時此刻心情的緊迫程度
          urgency: {
            type: "string",
            enum: ["low", "medium", "high"]
          },
          // needs_empathy: 決定最後回覆前是否需要安撫前綴。若為 true，會觸發同理心文字安撫
          needs_empathy: { type: "boolean" },
          // companion_tone: 建議的陪伴者語氣 (冷靜、鼓勵、中性)
          companion_tone: {
            type: "string",
            enum: ["calm", "encouraging", "neutral"]
          },
          // evidence: 支撐情緒判斷的對話中關鍵字依據 (例如使用者打的: ["焦慮", "吃太多了"])
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
        // additionalProperties: false 是一項安全設定，嚴格限制模型不可輸出 properties 定義以外的自訂欄位
        additionalProperties: false
      }
    }
  }
];

/**
 * 3. Post-check 意圖修正 (sanitizeScreening)
 * 當 OpenAI 回傳結果後，以此函式進行二次檢驗，確保格式正確。
 * @param {Object} raw - OpenAI 回傳的原始 arguments 物件
 * @returns {Object} 經過格式修復與預設值補齊後的意圖預檢結果
 */
function sanitizeScreening(raw) {
  if (!raw) {
    throw new Error("Missing 'screen_user_request' function call arguments from OpenAI response.");
  }

  const result = { ...raw };

  // 確保 dishes 必定是陣列結構，若模型漏填，預設為空陣列
  if (!Array.isArray(result.dishes)) {
    result.dishes = [];
  }

  return result;
}

/**
 * 4. Post-check 情緒修正 (sanitizeEmotion)
 * 驗證 OpenAI 回傳的情緒結構。若無回傳或屬性缺漏，填入預設值防呆。
 * @param {Object} raw - OpenAI 回傳的原始 arguments 物件
 * @returns {Object} 經過格式檢查後的情緒特徵結果
 */
function sanitizeEmotion(raw) {
  if (!raw) {
    throw new Error("Missing 'analyze_emotion' function call arguments from OpenAI response.");
  }
  return {
    primary_emotion: raw.primary_emotion || "neutral",
    valence: raw.valence || "neutral",
    urgency: raw.urgency || "medium",
    // 確保 needs_empathy 是正確的 boolean 型態，不為 undefined
    needs_empathy: typeof raw.needs_empathy === "boolean" ? raw.needs_empathy : false,
    companion_tone: raw.companion_tone || "neutral",
    evidence: Array.isArray(raw.evidence) ? raw.evidence : []
  };
}

/**
 * 5. 呼叫 OpenAI Responses API
 * 使用原生 fetch 發送 POST 請求至 OpenAI 伺服器端點。
 * @param {Object} body - OpenAI 要求的 Request Payload 格式
 * @param {string} apiKey - 系統載入之 OpenAI API Key 金鑰
 * @returns {Promise<Object>} OpenAI 解析完的 JSON 回應
 */
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

/**
 * 6. 解析並篩選出所有的 Function Call 項目
 * 從 OpenAI Responses API 回傳的 output 陣列中，過濾出屬於 function_call 類型的項目。
 * @param {Object} responseJson - OpenAI 回應的 JSON 數據
 * @returns {Array<Object>} function_call 項目陣列
 */
function getFunctionCalls(responseJson) {
  return (responseJson.output || []).filter((item) => item.type === "function_call");
}

/**
 * 7. 收集並轉換所有的 Tool 參數物件
 * 將多個 function call 的 arguments 欄位由 JSON 字串轉換成 JavaScript 物件。
 * @param {Array<Object>} functionCalls - Function Call 項目陣列
 * @returns {Object} 以函數名稱為 Key，參數物件為 Value 的映射
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
 * 8. 執行 OpenAI 主要流程 (runOpenAIFlow)
 * @param {string} userPrompt - 使用者原始文字提問
 * @returns {Promise<Object>} 包含意圖預檢 (screening)、情緒特徵 (emotion)
 */
async function runOpenAIFlow(userPrompt) {
  const apiKey = process.env.OPENAI_API_KEY;
  const model = process.env.OPENAI_MODEL || "gpt-4o-mini";

  if (!apiKey) {
    throw new Error("Missing OPENAI_API_KEY.");
  }

  // 發送至 OpenAI 進行 parallel tool calls
  const response = await createOpenAIResponse(
    {
      model,
      parallel_tool_calls: true, // 啟用平行工具呼叫，單次請求同時執行意圖與情緒判定
      tool_choice: "auto",
      // 將 tools 陣列元素拉平，轉換成 Responses API 所規定的扁平（Flat）格式
      tools: tools.map(t => {
        if (t.type === "function" && t.function) {
          return {
            type: "function",
            name: t.function.name,
            description: t.function.description,
            parameters: t.function.parameters
          };
        }
        return t;
      }),
      instructions: SYSTEM_PROMPT,
      input: [
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: userPrompt,
            },
          ],
        },
      ],
    },
    apiKey
  );

  // 收集 Tool arguments 結果
  const functionCalls = getFunctionCalls(response);
  const rawArgs = collectToolArgsByName(functionCalls);

  // 執行 Post-check 驗證與欄位修正
  const screening = sanitizeScreening(rawArgs.screen_user_request);
  const emotion = sanitizeEmotion(rawArgs.analyze_emotion);

  return {
    screening,
    emotion
  };
}

module.exports = {
  runOpenAIFlow
};
