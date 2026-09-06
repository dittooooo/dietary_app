// Path: companion_js/prompts/analysisPrompt.js
// Description: System prompt and Function Calling tools schema for Stage 1 intent & emotion analysis

// 第一階段「意圖篩選與情緒分析」的系統提示詞 (ANALYSIS_SYSTEM_PROMPT)
// 指導 LLM 作為分類器與特徵擷取器，分析使用者輸入並決定是否應處理，以及提取餐點與判斷提問類型。
const ANALYSIS_SYSTEM_PROMPT = `
你是一個飲食推薦應用程式的 Companion Agent（陪伴助理）分類與特徵擷取器。
你的任務是分析使用者的輸入訊息（通常為繁體中文），並同時執行兩個工具調用："screen_user_request" 與 "analyze_emotion"。

請嚴格遵守以下分類與擷取規則：

【絕對防呆規則】
- **絕對防呆規則**：【歷史對話紀錄】僅供理解語境與指涉代名詞使用。在抽取 meal_items 時，**嚴禁抽取歷史紀錄中已提及的舊餐點**，僅能針對「使用者最新輸入」中提及的餐點進行抽取。

【screen_user_request 的規則】
1. should_handle (是否處理)：
   - 當訊息與飲食建議、餐點選擇、日常飲食計畫、餐點紀錄、熱量/卡路里、營養成分等飲食/健康管理直接相關時，設為 true。
   - 當訊息為敏感的醫療諮詢、疾病診斷、藥物使用（例如：「頭痛要吃什麼藥」）、非飲食相關的閒聊（例如：天氣、純問候），設為 false。
2. intent_category (意圖分類)：
   - "dish_advice"：使用者在尋求飲食建議、推薦，或詢問某特定食物是否適合食用（例如：「我想吃炸雞，適合嗎？」、「今天晚餐推薦吃什麼？」）。若問句中同時包含「記錄已吃食物」與「尋求建議」，應優先歸類於 "dish_advice"。
   - "meal_record"：使用者「純粹」在記錄自己吃了什麼，沒有提出疑問或尋求任何飲食建議（例如：「我今天中午吃了一碗拉麵」）。
   - "meal_query"：使用者在尋求「看/查過往某一天」記錄了什麼飲食（例如：「我 6/19 號吃了什麼？」、「我昨天晚餐吃了什麼？」）。
   - "general_chat"：非飲食主題的純閒聊、問候，或任何醫療/診斷/藥物問題。
3. question_type (問題類型) —— （無論哪種意圖均為必填常駐欄位）：
   - "single_dish"：問句中僅提及「單一」特定餐點或食物進行詢問（例如：「我吃炸雞排適合嗎？」）。
   - "dish_comparison"：問句中提及「兩樣或多樣」餐點/食物（包含比較熱量、抉擇/二選一猶豫「在想要吃 A 還是 B」、或是多餐搭配）。只要提及兩樣（含）以上的食物品項，一律歸為此類！
   - "unknown"：意圖為 "dish_advice" 但問句中「完全未提及任何具體食物名稱」的飲食諮詢（例如：「今天晚餐推薦吃什麼？」、「我這樣吃會太胖嗎？」）。【強烈禁令】：只要問句中有出現具體食物名稱，絕不可以設為 "unknown"！
   - "not_applicable"：非飲食諮詢意圖（即意圖為 "meal_record"、"meal_query" 或 "general_chat"）時，question_type 一律填入此值！
4. query_date (歷史飲食查詢目標日期)：
   - 當 intent_category 為 "meal_query" 時，請務必結合傳入之「當前系統時間」，將使用者表述之日期（如「6/19」、「昨天」、「前天」）精準推算轉換為標準 ISO 日期格式 YYYY-MM-DD（例如："2026-06-19"）。若無法識別明確日期或為未來日期，請設為 null。
5. meal_items (一維餐點明細陣列)：
   - 將訊息中所提及的每一個食物/飲料品項，抽取為一維扁平物件陣列。每個物件必須包含 "name"、"quantity"、"unit" 與推算之 "meal_period"（"早餐"、"中餐"、"晚餐"、"其他"）。
   - **絕對防呆規則**：【歷史對話紀錄】僅供理解語境與指涉代名詞使用。在抽取 meal_items 時，**嚴禁抽取歷史紀錄中已提及的舊餐點**，僅能針對「使用者最新輸入」中提及的餐點進行抽取。
   - 【餐期推算規則與強烈禁令】：
     * 若問句中已有明確時間詞（如「上午吃了...」、「晚餐想吃...」），優先採納該時間詞所對應之餐期。
     * 若問句中未明確提及餐期時間詞，請務必依據傳入之 24 小時制當前系統時間推算：
       - 05:00 - 10:30 推算為 "早餐"
       - 10:30 - 14:00 推算為 "中餐"
       - 14:00 - 17:00 推算為 "其他"
       - 17:00 - 21:00 推算為 "晚餐"
       - 21:00 - 05:00 推算為 "其他"
     * 只要含有食物或飲料品項，必須完整擷取。絕不可傳回空陣列。僅非飲食主題問句或歷史查詢問句才傳回空陣列 []。
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
      description: "Screen the user request to classify question type, intent, query date, and extract mentioned dishes into a 1D flat array.",
      parameters: {
        type: "object",
        properties: {
          should_handle: {
            type: "boolean",
            description: "Whether this request should be processed by the companion agent."
          },
          intent_category: {
            type: "string",
            enum: ["dish_advice", "meal_record", "general_chat", "meal_query"]
          },
          query_date: {
            type: ["string", "null"],
            description: "歷史飲食查詢 (meal_query) 時提取之目標日期，格式必須為 ISO YYYY-MM-DD（例如 2026-06-19）。非歷史查詢意圖時設為 null。"
          },
          question_type: {
            type: "string",
            enum: ["single_dish", "dish_comparison", "unknown", "not_applicable"],
            description: "飲食諮詢時依餐點數量選 single_dish / dish_comparison / unknown；非飲食諮詢 (meal_record, meal_query 或 general_chat) 一律選 not_applicable。"
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
      description: "Analyze the user's emotional state, psychological context, and key phrases to guide interactive companion replies.",
      parameters: {
        type: "object",
        properties: {
          primary_emotion: {
            type: "string",
            enum: ["neutral", "joy", "anxiety", "guilt", "stress", "frustration", "fatigue"]
          },
          psychological_context: {
            type: "string",
            enum: [
              "work_overtime_stress",
              "diet_relapse_guilt",
              "weather_or_mood",
              "social_dining",
              "routine_craving",
              "other_general_chat"
            ],
            description: "The primary situational category driving the user's message."
          },
          companion_tone: {
            type: "string",
            enum: ["comforting", "encouraging", "playful", "neutral"]
          },
          evidence: {
            type: "array",
            items: { type: "string" },
            description: "Key emotion words or situational phrases extracted directly from the user's prompt (e.g. ['下雨', '鞋子濕'], ['鹹酥雞', '太罪惡'])."
          }
        },
        required: [
          "primary_emotion",
          "psychological_context",
          "companion_tone",
          "evidence"
        ],
        additionalProperties: false
      }
    }
  }
];

module.exports = {
  ANALYSIS_SYSTEM_PROMPT,
  tools
};
