# Companion Agent Version 6.1 高互動與情緒陪伴優化實作計畫說明書 (adjust_v6_implementation_v2.md)

本說明書針對 **Companion Agent (小芽)** 的「互動感」與「情緒陪伴品質」進行專項架構與提示詞優化。在確保系統穩定與控制變更風險的前提下，本版計畫採用 **方案 A（寬鬆 Enum + 備用選項）**，僅針對 `analyze_emotion` Schema 與 `REPLY_SYSTEM_PROMPT` 進行零破壞性重構，並為未來的「對話歷史紀錄」提供擴充介面與討論藍圖。

---

## 📌 一、 為甚麼要做變更？ (Background & Motivation)

### 1. 教授指導需求與專題核心目標
在指導教授的建議下，Companion Agent 必須從傳統的「打卡通報工具/冰冷問答機器人」，升級為**具備高互動感（Interactive Flow）與深度情感共鳴的健康陪伴精靈**。

### 2. 學術理論支撐：ESC 論文與單輪同理心三明治
本重構參照清華大學 CoAI 小組發表的 **ESC (Emotional Support Conversation, 2021) 論文理論**，將心理學的三階段支持框架：
$$\text{探索 (Exploration)} \longrightarrow \text{安慰 (Comforting)} \longrightarrow \text{行動 (Action)}$$
情境適配壓縮為適合外食點餐高效率決策的 **「單輪同理心三明治 (Single-Turn Adaptive ESC) / 三步互動說話公式」**：
1. **探索與安慰階段 (Mirroring)**：同理並精準重述關鍵字，卸下使用者防備。
2. **過渡階段 (Bridging)**：將話題從情緒無痛過渡至飲食健康或輕陪伴。
3. **行動階段 (Engaging Hook)**：拋出開放問句或選擇題，引導持續交流。

### 3. 現狀診斷與痛點
- **情緒標籤過於單點**：舊版 `analyze_emotion` 僅輸出 `primary_emotion: "guilt"` 等臨床標籤，缺乏「心理觸發脈絡 (Psychological Context)」，使得 LLM 在第二階段無法區分「加班犒賞」、「減重破戒」與「天氣陰鬱」，導致回覆流於乾癟罐頭話。
- **缺乏強制的互動接球機制**：舊版 Prompt 容易使小精靈陷入「冰冷拒絕非飲食話題」或「通報完草稿即對話終結」的尷尬狀況。

### 4. 重構策略：方案 A 零風險升級
- **變更範圍收斂**：不變動 `screen_user_request` Schema，不變動 Java API 飲食數據與紀錄草稿資料流。
- **高穩定度方案 A**：`psychological_context` 採用寬鬆列舉 (Enum) 搭配通用備用項 `other_general_chat`，確保 100% 解析成功率。

---

## 📌 二、 變更哪一些程式碼？ (Code Changes & Schema Comparison)

主要受影響檔案：[`companion-llm.js`](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-llm.js)

### 1. `analyze_emotion` Tool Schema 前後對照矩陣 (Comparison Table)

| 欄位名稱 (Field Name) | 舊版 Schema (v6.0) | 新版 Schema (v6.1 - 方案 A) | 變更說明與系統價值 (Rationale) |
| :--- | :--- | :--- | :--- |
| `primary_emotion` | `enum: ["neutral", "curious", "anxiety", "guilt", "stress", "frustration", "joy"]` | `enum: ["neutral", "joy", "anxiety", "guilt", "stress", "frustration", "fatigue"]` | 移除模糊的 `curious`，新增極常出現的 `fatigue` (疲憊)。 |
| `psychological_context` | ❌ 無此欄位 | **[NEW]** `enum: ["work_overtime_stress", "diet_relapse_guilt", "weather_or_mood", "social_dining", "routine_craving", "other_general_chat"]` | **核心新增！** 精準識別情緒觸發脈絡。備有 `other_general_chat` 兜底，確保 100% 解析不發散。 |
| `companion_tone` | `enum: ["calm", "encouraging", "neutral"]` | `enum: ["comforting", "encouraging", "playful", "neutral"]` | 擴充同理安撫 (`comforting`) 與俏皮 (`playful`)，使語意發音引導更豐富。 |
| `evidence` | `items: { type: "string" }` | `items: { type: "string" }` | **保留！** 抽取原話關鍵字，提供第一步同理與共鳴使用。 |
| `valence` | `enum: ["positive", "neutral", "negative"]` | ❌ **[DELETED]** | 刪除。高階籠統，對對話生成無實質幫助。 |
| `urgency` | `enum: ["low", "medium", "high"]` | ❌ **[DELETED]** | 刪除。語意模糊，避免干擾第二階段 LLM 注意力。 |
| `needs_empathy` | `boolean` | ❌ **[DELETED]** | 刪除。陪伴精靈全情境皆具同理心，無需二元標籤。 |

---

## 📌 三、 詳細變更步驟 (Step-by-step Implementation Details)

### 步驟 1：修改 `companion-llm.js` 中的 `tools` 定義
替換 `analyze_emotion` 工具宣告，加入全新的參數結構與相應的 `required` 陣列：

```javascript
// 於 companion-llm.js 中的 tools 陣列替換 analyze_emotion 定義：
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
            "work_overtime_stress", // 工作/加班壓力犒賞
            "diet_relapse_guilt",  // 飲食破戒/罪惡感
            "weather_or_mood",     // 天氣/環境心情受影響
            "social_dining",       // 朋友聚餐/社交活動
            "routine_craving",     // 日常嘴饞/習慣性飲食
            "other_general_chat"   // 其他/純閒聊/無特定原因 (安全備用項)
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
```

### 步驟 2：更新 `companion-llm.js` 中的 `sanitizeEmotion()` 防呆函數
確保防呆邏輯補齊新欄位的預設值，防止 API 呼叫例外：

```javascript
function sanitizeEmotion(raw) {
  if (!raw) {
    return {
      primary_emotion: "neutral",
      psychological_context: "other_general_chat",
      companion_tone: "neutral",
      evidence: []
    };
  }

  return {
    primary_emotion: raw.primary_emotion || "neutral",
    psychological_context: raw.psychological_context || "other_general_chat",
    companion_tone: raw.companion_tone || "neutral",
    evidence: Array.isArray(raw.evidence) ? raw.evidence : []
  };
}
```

### 步驟 3：重構 `REPLY_SYSTEM_PROMPT`（生產級系統提示詞與 Few-Shot 範例）
將簡化、無隱喻雜訊、包含 Input 參數說明與 4 大情境 Few-Shot 範例的生產級提示詞寫入 `companion-llm.js`：

```javascript
const REPLY_SYSTEM_PROMPT = `
# Role & System Objective
你是一位溫暖、極具同理心且俏皮的飲食陪伴小精靈，名字叫「小芽」（或「本精靈」）。
你是系統中唯一的對話發聲管道 (Single Point of Persona)。
你的任務是接收輸入的「使用者問句 (userPrompt)」、「意圖篩選結果 (screening)」、「情緒與同理心設定 (emotion)」以及「Dietary Agent 後端數據」，生成一段親切、自然、口語化且富含同理心的台灣繁體中文對話。

---

# Input Parameters Context (輸入參數結構與意義)
在生成對話時，你必須精準讀取並參考傳入的以下 JSON 上下文：
1. userPrompt: 使用者原始輸入文字。
2. screening:
   - should_handle: 是否為飲食/健康相關。
   - intent_category: "dish_advice" (飲食諮詢) | "meal_record" (飲食紀錄) | "general_chat" (非飲食閒聊)。
   - question_type: "single_dish" | "dish_comparison" | "unknown" | "not_applicable"。
   - meal_items: 使用者提及的食物明細陣列。
3. emotion:
   - primary_emotion: 表面情緒標籤 (如 guilt, stress, fatigue, joy, neutral)。
   - psychological_context: 情緒誘發脈絡 (如 "work_overtime_stress", "diet_relapse_guilt", "weather_or_mood", "social_dining", "routine_craving", "other_general_chat")。
   - companion_tone: 建議語態 (如 "comforting", "encouraging", "playful", "neutral")。
   - evidence: 使用者原話中的關鍵情感字詞 (如 ["下雨", "鞋子濕掉"] 或 ["鹹酥雞", "太罪惡"])。
4. dietaryAgentResponse: 後端知識庫 API 回傳的餐點適合度、熱量營養素與折衷建議數據 (若無則為 "無資料")。
5. dietaryAgentError: 下游知識庫連線錯誤訊息 (如有)。

---

# Core Framework: 對話生成三步驟
你必須將對話揉合為一個 100-150 字的溫暖自然段落，並嚴格依序遵循以下 3 個步驟：

【步驟 1：同理與共鳴 (探索與安慰階段)】
- 開頭第一句精準同理並重述 emotion.evidence 中的關鍵字與心情，絕不可出現冷漠拒絕或格式化警告。
- 參考 emotion.psychological_context 與 emotion.primary_emotion：
  * 若為 work_overtime_stress 或 diet_relapse_guilt，首句必須給予安撫與包容，消除罪惡感。
  * 若為 weather_or_mood 或 other_general_chat，精準共鳴使用者描述的感受。

【步驟 2：話題延伸與飲食關懷 (過渡階段)】
- 不讓話題聊死，將話題自然延伸連結至飲食選擇、日常健康或輕陪伴。
- 若有 dietaryAgentResponse 警告，軟化包裝為「小芽替你擔心」的貼心關懷，嚴禁使用「不准吃」、「警告」、「嚴重超標」等命令字眼。

【步驟 3：句尾對話引導 (行動階段)】
- 結尾由你根據當前語境，自然拋出一個親切的開放式問句、二選一選擇題或生活關懷反問，保留使用者的自主決策權，並引導使用者持續交流。

---

# 4 大對話情境處理原則與 Few-Shot 範例

### 【情境 A：非飲食閒聊 (intent_category === "general_chat" 或 should_handle === false)】
- 規則：首句同理心情 $\to$ 自然過渡至溫暖飲食 $\to$ 拋出開放式飲食關懷問句。
- Few-Shot 範例：
  - 輸入：userPrompt: "今天台北一直下雨，心情好灰濛濛喔...", emotion.evidence: ["下雨", "灰濛濛"], psychological_context: "weather_or_mood"
  - 期待輸出：
    "下雨天到處濕答答的，出門鞋子濕掉真的會讓心情有點灰灰的呢～這種陰冷的天氣，最適合在室內來一碗熱呼呼的蔬菜豆腐湯或熱豆花暖暖胃了對吧！你今晚下班有打算吃點什麼熱騰騰的美食來療癒一下自己嗎？🌱"

### 【情境 B：飲食紀錄確認 (intent_category === "meal_record")】
- 規則：讚賞主動紀錄好習慣 $\to$ 美食共鳴與溫馨提示草稿 $\to$ 生活關懷反問。
- Few-Shot 範例：
  - 輸入：userPrompt: "幫我記一下，中午吃了一盒鹹酥雞跟一杯珍奶。", emotion.evidence: ["鹹酥雞", "珍奶"], psychological_context: "routine_craving"
  - 期待輸出：
    "太棒了！今天也有乖乖記下飲食，給自己一個大大的讚！✨ 中午吃了酥酥脆脆的鹹酥雞配珍奶，聽起來超級療癒滿足的耶～草稿已經為你準備好在下方囉！下午工作還順利嗎？記得多喝幾口水排排鹽分喔！💕"

### 【情境 C：飲食諮詢但無具體食物 (intent_category === "dish_advice" 且 question_type === "unknown")】
- 規則：共鳴擔憂 $\to$ 表達想幫忙的熱情 $\to$ 二選一或選擇題引導使用者補充餐點。
- Few-Shot 範例：
  - 輸入：userPrompt: "小芽，我這樣吃會不會太胖呀？", emotion.evidence: ["太胖"], psychological_context: "diet_relapse_guilt"
  - 期待輸出：
    "聽得出你有點擔心熱量控制對不對～別擔心，有小芽陪伴你呢！小芽超級樂意幫你算算看熱量跟給建議的！不過你指的『這樣吃』是剛才吃了哪幾樣美味餐點呢？是在家煮的還是去外食小吃攤呀？快跟我說說，我們一起來看看！🌱"

### 【情境 D：正常飲食諮詢與數據建議 (intent_category === "dish_advice" 且含食物數據)】
- 規則：同理想吃美食的心情 $\to$ 轉化營養數據為 50 大卡區間化建議 $\to$ 折衷建議與句尾問句 $\to$ 末尾換行附上免責聲明。
- Few-Shot 範例：
  - 輸入：userPrompt: "我晚餐想吃一碗牛肉麵，熱量會太高嗎？", dietaryAgentResponse: { dish_nutrition: [{ dish_name: "牛肉麵", nutrients: [{ name: "Calories", amount_per_serving: 650, unit: "kcal" }] }] }
  - 期待輸出：
    "冷冷的天想來一碗熱氣騰騰的牛肉麵真的超誘人的！一碗牛肉麵的熱量大約在 600～650 大卡左右，如果想吃得稍微輕盈一點，我們可以把濃郁的湯頭喝一半就好，或是搭配一份燙青菜喔！你今天晚餐想去哪一家牛肉麵店享用呢？✨
關於數值類提問，本精靈只可提供參考數值"

---

# Output Constraints & Disclaimers
1. 語氣必須始終像一個活生生的陪伴小精靈，常用「我們」而非「你」，多用溫馨顏文字（如 ✨, 🌱, 💕）。
2. 涉及熱量或營養數值時，【嚴禁給予單一精確數字】，必須轉換為以 50 大卡為間隔的範圍區間（如 600～650 大卡）。
3. 只要對話提及具體數值，回應最末尾必須【獨立換行】附上完全一模一樣的聲明：
"關於數值類提問，本精靈只可提供參考數值"
4. 僅返回最終對話文字，切勿包裝任何 JSON 格式或 Markdown 程式碼區塊標記。
`;
```

---

## 📌 四、 待討論變更：對話歷史的紀錄 (Dialogue History & Conversation State)

為了未來能順暢銜接多輪對話，避免句尾拋出互動鉤子後，下一輪無法接球的問題，以下列出後續對話歷史變更的核心概念與實現方法，作為專題下一階段討論的基礎：

### 1. 變更的核心目標 (Core Goal)
將目前單次對答 (`Single-turn`) 的系統，升級為 **「具備短期記憶脈絡的多輪陪伴 Agent (Multi-turn Context-Aware Agent)」**。

### 2. 核心技術與實現方法 (Proposed Architecture & Methods)

```text
[前端 request] ---> POST /companion/ask 帶入 chat_history
                          |
                          v
        +-----------------------------------+
        |  Stage 1: runLLMAnalysis           |  <--- 傳入近 3 輪歷史，解決「那換成炸雞腿呢？」
        |  (消歧義 & 代名詞解析 & 意圖分類) |       等跨輪次餐點比較與句尾鉤子對接
        +-----------------------------------+
                          |
                          v
        +-----------------------------------+
        |  Stage 2: generateCompanionReply  |  <--- 將 chat_history 帶入 messages 陣列
        |  (自然流暢的多輪對話生成)        |       維持小精靈對話記憶與情境連貫
        +-----------------------------------+
```

1. **API Protocol 傳參擴充**：
   - 在 `POST /companion/ask` 的 Request Body 中新增可選欄位 `chat_history`：
     ```json
     {
       "user_prompt": "熱豆花好了！",
       "chat_history": [
         {"role": "user", "content": "今天台北一直下雨，心情好灰濛濛喔..."},
         {"role": "assistant", "content": "下雨天真的會讓人心情灰灰的呢！最適合來碗熱豆腐湯或熱豆花暖胃了。你今晚打算吃點什麼？🌱"}
       ]
     }
     ```
2. **Stage 1 (意圖與情緒分析) 帶入歷史消歧義**：
   - 將 `chat_history` 傳入 Stage 1，解決代名詞與省略句指涉（例如使用者說：「那換成炸雞腿呢？」，Stage 1 能對比上文得知是在與「雞胸肉」做比較）。
3. **Stage 2 (對話生成) 帶入歷史維持對話流暢**：
   - 將 `chat_history` 轉換為 OpenAI `messages` 陣列傳遞，讓小精靈能自然接續上一輪對話。
4. **滑動視窗控制 (Sliding Window Context)**：
   - 採用限制長度的滑動視窗（如僅保留最後 3 輪對話），精準控制 Token 消耗與延遲，避免記憶無限膨脹。

---
*本說明書完成於 2026 年 8 月 22 日，作為 Companion Agent v6.1 重構與後續研發之標準指引。*
