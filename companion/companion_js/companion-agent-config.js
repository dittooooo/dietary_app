// Path: c:\Users\User\Documents\Github_Repo\dietary_app\companion\companion_js\companion-agent-config.js
// Description: Configuration containing SYSTEM_PROMPT and tools schemas for OpenAI Function Calling

/**
 * 1. 系統 Prompt 定義 (SYSTEM_PROMPT)
 * 這是給 OpenAI 模型的全局系统指令。
 * 它用來規範 LLM (大語言模型) 扮演的角色、如何分類問題、如何偵測情緒、以及如何擷取料理名稱。
 */
const SYSTEM_PROMPT = `
You are the Companion Agent classifier and extractor for a dietary recommendation app.
Your task is to analyze the user's message and determine the context, questions types, emotions, and extract mentioned dishes.

You MUST execute both functions (parallel tool calls): "screen_user_request" and "analyze_emotion" to return your results.

Specific Instructions for "screen_user_request":
- Identify if the user's request is a dietary/food question (intent_category: dish_advice or meal_record).
- Classify question_type as:
  1. "single_dish": User asks about one specific food/meal.
  2. "dish_comparison": User compares two or more foods (e.g., "A vs B", "A or B", "compared to").
  3. "unknown": General chat or questions out of scope.
- Determine if more context is required (requires_more_context). If the user profile is missing but they ask a personal question like "Can I eat this?", set requires_more_context to true.
- "dishes": Extract all names of foods, dishes, or drinks mentioned in the user's text as a string array. (e.g., "拉麵", "炸雞"). If none, return an empty array.

Specific Instructions for "analyze_emotion":
- Analyze the user's emotional tone and set needs_empathy to true if they express anxiety, guilt, stress, or frustration.
- Determine companion_tone (e.g., calm, encouraging).
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
          // requires_more_context: 代表資料是否足夠。若為 true，後端將不再傳給 Dietary Agent 而是回頭補問使用者
          requires_more_context: {
            type: "boolean",
            description: "True if user profile or key details are missing for personalization."
          },
          // missing_information: 記錄具體缺失哪些資料的字串陣列 (例如缺少 user_profile)
          missing_information: {
            type: "array",
            items: { type: "string" },
            description: "List of missing items, e.g., ['user_profile', 'restaurant_context']"
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
          "requires_more_context",
          "missing_information",
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

// 3. 模組導出 (Exports)
// 將 prompt 字串與 tools 定義導出，供主服務 companion-agent-services.js 引用
module.exports = {
  SYSTEM_PROMPT,
  tools
};
