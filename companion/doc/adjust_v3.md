# 第三次程式碼修正計畫 (adjust_v3.md)

本文件紀錄第三次程式碼修正的具體規劃與調整內容。本次修正包含兩大核心任務：
1. **System Prompt 加深加廣**（加強分類邊界、早退機制引導、同理心展現，並討論是否使用中文呈現）。
2. **`question_type` 欄位條件化**（僅在 `intent_category === 'dish_advice'` 時才出現在 `screen_user_request` 中）。

---

## 一、 System Prompt 加深加廣與中文呈現討論

### 1. 語言呈現建議：改為「繁體中文」系統提示詞 (Taiwan Traditional Chinese)
> [!TIP]
> **建議：** 將 `ANALYSIS_SYSTEM_PROMPT` 與 `REPLY_SYSTEM_PROMPT` 改為**繁體中文**呈現。
>
> **原因：**
> 1. 本專案的輸入（使用者訊息）與輸出（陪伴對話、早退對話）皆為台灣繁體中文，使用中文 System Prompt 能讓模型更直觀地理解台灣口語的微妙語境（例如「吃拉麵適合嗎」與「中午吃拉麵，晚上吃排骨飯」的差異）。
> 2. 後續維護時，開發團隊能更精準地調整提示詞定義，避免英文翻譯造成的語意偏差。
> 3. 對於早退回覆 (`early_reply`) 與同理心生成的要求，中文 Prompt 能提供更生動的語氣範例。

### 2. 調整後的 Prompt 設計 (以繁體中文為例)

#### (1) 第一階段：`ANALYSIS_SYSTEM_PROMPT`
主要強化以下邊界條件與規則：
* **明確定義 `should_handle` 的範圍**：劃分為「日常飲食與飲食紀錄」設為 `true`，而「其他非飲食類的詢問（包含非飲食閒聊、敏感的醫療/藥物諮詢）」設為 `false`。
* **新增 `question_type` 條件限制說明**（明確指示當 `intent_category` 非 `dish_advice` 時，不可生成此欄位）。
* **細化 `early_reply` 的引導字眼**，確保生成溫馨、符合特定情境的對話提示。

```javascript
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
3. question_type (問題類型) —— ★僅當 intent_category 為 "dish_advice" 時才可包含此欄位：
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
```

#### (2) 第二階段：`REPLY_SYSTEM_PROMPT`
* 加強同理心的具體範例，引導模型避免生硬的條列式說明。
* 重申免責聲明「關於數值類提問，本精靈只可提供參考數值」的附加邏輯。

```javascript
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
```

---

## 二、 `question_type` 欄位條件化修改方案

為了讓 `screen_user_request` 中的 `question_type` 僅在 `intent_category === 'dish_advice'` 時出現，我們將在程式中進行兩層防護：

### 1. 修改 `tools` 的 JSON Schema (在 [companion-llm.js](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-llm.js))
* **修改點：** 將 `question_type` 從 `required` 陣列中移除。
* **說明：** 因為 `additionalProperties: false` 存在，移除 `required` 代表模型可以自主決定是否返回此欄位。結合 System Prompt 的引導，LLM 只有在判斷為 `dish_advice` 時才會附加此欄位。

```javascript
        required: [
          "should_handle",
          "intent_category",
          // "question_type", <-- 從此處移除，改為選填/條件填寫
          "confidence",
          "dishes",
          "early_reply"
        ],
```

### 2. 修改防呆過濾器 `sanitizeScreening` (在 [companion-llm.js](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-llm.js))
* **修改點：** 在後端防呆處理中，如果 API 回傳了 `question_type` 但 `intent_category` 不是 `"dish_advice"`，主動將其刪除。
* **說明：** 這樣能確保即使 LLM 出錯或忽略了 Prompt 指示，後端輸出依然百分之百符合「`intent_category` 不是 `dish_advice` 時沒有 `question_type`」的邏輯。

```javascript
function sanitizeScreening(raw) {
  // 容錯防呆：如果 OpenAI 沒有觸發意圖工具調用，預設為不需處理的閒聊分類
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
```

---

## 三、 新增餐點名稱翻譯二次呼叫

為了防止使用者輸入多樣且花俏的餐點名稱導致後續的 Dietary Agent 無法精準辨識（例如：「起司瀑布超厚牛肉堡」或「低卡舒肥雞胸肉沙拉搭配胡麻醬」），我們將新增第二次 OpenAI 呼叫，在第一階段識別出餐點後，對其進行標準化翻譯與拆解。

### 1. 實作 API 呼叫函數 `translateDishes` (在 [companion-llm.js](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-llm.js))
* **功能：** 接收一個餐點名稱陣列，呼叫 OpenAI 將其翻譯/拆解為食品資料庫標準品名。
* **回傳格式：** `{"translated_dishes": ["標準品名1", "標準品名2", ...]}`

```javascript
// 定義食品名稱翻譯的 System Prompt
const TRANSLATION_SYSTEM_PROMPT = `
你是一個飲食推薦應用程式的食品名稱翻譯助理。你的工作是將使用者輸入的「花俏」餐點或飲料名稱，拆解並翻譯成最直白、標準、無冗餘形容詞的食品資料庫標準品名，以便進行後續的營養成分與熱量分析。
請只回傳符合 JSON 物件格式的結果，格式為：{"translated_dishes": ["標準品名1", "標準品名2"]}，請勿附帶任何額外的說明文字。

飲料與乳製品分類標準：
1. 乳製品分類標準：
   - 包含「歐蕾/那堤/拿鐵/鮮乳/鮮奶/鮮乳專門」：一律翻譯為「鮮乳」。
   - 包含「厚乳/濃乳/重乳」：若無法確認成分，一律翻譯為「鮮乳（強化）」。
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
```

### 2. 整合至分析流程 `runOpenAIFlow` (在 [companion-agent-services.js](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-agent-services.js))
* **修改點：** 在取得第一階段的 `screening` 結果後，若 `screening.dishes` 有餐點名稱，則調用 `translateDishes` 進行翻譯，並覆寫 `screening.dishes`。
* **優點：** 這樣可以讓後面傳給 `Dietary Agent` 的 `dish_names` 自動升級為翻譯後的標準品名，同時回傳給前端的 `screening.dishes` 也會是標準品名。

```javascript
// 修改後的 runOpenAIFlow 結構示意：
async function runOpenAIFlow(userPrompt) {
  // 1. 呼叫 OpenAI 進行意圖與情緒分析
  const result = await runLLMAnalysis(userPrompt);
  
  // 2. 新增餐點翻譯：若有擷取到餐點名稱，進行食品資料庫標準品名翻譯
  if (result.screening.dishes && result.screening.dishes.length > 0) {
    try {
      const translated = await translateDishes(result.screening.dishes);
      result.screening.dishes = translated;
    } catch (err) {
      console.error("Dish translation failed, using original names:", err.message);
    }
  }

  // 3. 根據翻譯後的意圖與餐點建立傳送給 Dietary Agent 的請求 payload
  const dietaryAgentRequest = buildDietaryAgentRequest(result.screening, userPrompt);

  // 回傳整合後的結果
  return {
    screening: result.screening,
    emotion: result.emotion,
    dietary_agent_request: dietaryAgentRequest
  };
}
```

---

## 四、 Dietary Agent 回傳資料剪枝優化方案

### 1. 修改說明
為節省 Token 成本、降低延遲並避免 LLM 被內部配對分數與計算公式干擾，在將 `dietaryAgentResponse` 傳遞給第二階段 `generateCompanionReply` 的 LLM 之前，將對其進行剪枝（Pruning）。

### 2. 剪枝過濾邏輯（在 [companion-llm.js](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-llm.js) 實作）
* **保留欄位**：
  * `dish_nutrition`：包含 `dish_name`，以及各項營養素的 `name`、`amount_per_serving` 與 `unit`。
  * `dish_advice`：包含 `dish_name`、`suitability`（適合度）、`key_reasons`（關鍵原因）、`suggestions`（建議）。
  * `conclusion`：結論段落。
* **捨棄欄位**：
  * 資料庫檢索相關的 metadata（如 `matched_name`, `matched_type`, `match_score`, `match_reason`, `retrieval_strategy`）。
  * 營養素計算的內部細節（如 `calculation_method`, `formula`, `calorie_status`）。

### 3. 代碼修改示意 (在 [companion-llm.js](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-llm.js))
新增一個輔助函數 `minimizeDietaryResponse(response)`，並在 `generateCompanionReply` 中，將 `dietaryAgentResponse` 經由該函數過濾後再轉為 JSON 字串。

---

## 五、 修正步驟規劃 (等待確認後執行)

1. **第一步：** 與您確認此修正計畫（包含 Prompt 中文化、`question_type` 條件化、二次呼叫餐點翻譯、以及 Dietary Agent 回傳資料剪枝）。
2. **第二步：** 修改 `companion/companion_js/companion-llm.js`：
   - 修改 Prompt 內容（改為繁體中文、調整 `should_handle` / `question_type` 說明）。
   - 修改 `tools` 宣告（移去 `question_type` 必填屬性）。
   - 修改 `sanitizeScreening` 防呆函數（主動清除 `intent_category !== 'dish_advice'` 時的 `question_type`）。
   - 新增 `translateDishes` 翻譯函數。
   - 新增 `minimizeDietaryResponse` 剪枝過濾函數，並在 `generateCompanionReply` 中調用它。
3. **第三步：** 修改 `companion/companion_js/companion-agent-services.js`，在 `runOpenAIFlow` 中整合 `translateDishes` 邏輯。
4. **第四步：** 執行測試驗證，確認：
   - 翻譯機制運作正常。
   - `question_type` 條件出現規則符合預期。
   - 傳送給第二階段 LLM 的 `rawDataStr` 已被精簡，移除了資料庫與計算相關的無用 metadata。
