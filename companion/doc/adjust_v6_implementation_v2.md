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

### 3. 多輪對話核心挑戰與解決方案藍圖 (Multi-turn Key Challenges & Solutions)

為了確保多輪對話系統的穩定性與高品質互動體驗，本專案針對實作「對話歷史紀錄」時的 5 大核心潛在困難點進行深度評估，並提出對應的架構解決方案：

#### 【困難點 1】話題延續與切換辨識 (Topic Continuation vs. Topic Shift)
- **潛在問題**：Agent 需精準判斷使用者最新輸入是「回答小芽上一輪句尾鉤子（如：『熱豆花好了』）」還是「開啟無關新話題（如：『今天工作好累』）」。若判斷錯誤，會產生語意脫節或離題回應。
- **解決方案**：
  1. **Stage 1 LLM 新增 `topic_relation` 判定與語意補全**：
     - **關鍵參數 `last_agent_hook`**：小芽上一輪對話最後拋出的引導問句（例如：「你今晚想吃熱豆花還是蔬菜湯？」）。帶入 Stage 1 作為上下文判定基準。
     - **`topic_relation` 4 大 Enum 值說明與範例**：
       * `reply_to_hook` **(直接回答上句問句)**：使用者直接回答了 `last_agent_hook`（例如上輪問吃什麼，答：「熱豆花好了！」）。Stage 1 會自動將省略句補全為完整意圖（如「點心選擇熱豆花」）。
       * `topic_continuation` **(同一話題延伸與比較)**：未直接回答問句，但針對原話題做條件修改或延伸比較（例如原聊雞胸肉，輸入：「那如果換成炸雞腿呢？」）。
       * `topic_shift_diet` **(切換至新飲食話題)**：完全忽視舊話題，拋出新的飲食諮詢或紀錄（例如原聊下雨熱湯，突然傳：「幫我記一下剛才吃了洋洋洋芋片」）。舊話題自動歸檔。
       * `topic_shift_general` **(切換至非飲食閒聊/心情)**：切換至生活閒聊或情緒傾訴（例如：「老闆突然叫我加班到 11 點...」）。系統轉入高同理撫慰模式。
  2. **時間差超時機制 (Idle Timeout Heuristic)**：
     - 設定時間閾值（如 30 分鐘）。若前後兩輪對話間隔超過 30 分鐘，即使使用者回應簡短文字，系統亦強制將 `topic_relation` 判定為 `new_topic_session`，防止過期歷史干擾。

#### 【困難點 2】話題邊界與結束時機 (Topic Closure & Boundaries)
- **潛在問題**：何時標記話題已完成？若話題不閉合，歷史記憶會無限膨脹，或將過往的餐點誤認為當前餐點。
- **解決方案**：
  1. **三種話題結束機制 (Closure Triggers)**：
     - **目標完成**：飲食紀錄已產出草稿並獲確認，或飲食諮詢完成選擇（使用者：「那我就吃這個」），小芽給予結尾安撫後標記 `resolved`。
     - **新話題覆蓋**：使用者未回答舊話題，直接拋出全新事件時，舊話題自動凍結歸檔 (`archived`)。
     - **超時自然閉合**：閒置超過指定時間自動劃定話題結束。
  2. **輕量化對話狀態機 (`TopicState`)**：
     - 維護含有 `topic_id`, `status` ("in_progress" | "resolved"), `last_agent_hook` 的 Session 結構，讓 Stage 1 能以極低 Token 成本維護話題生命週期。

#### 【困難點 3】情緒標籤的過期污染與動態轉折 (Stale Emotion Leakage & Emotional Trajectory)
- **潛在問題**：若前一輪使用者極度罪惡或焦慮（如「暴飲暴食了」），到了下一輪使用者心情已轉好（如「明天要去跑步」），若小芽仍被舊情緒標籤綁架，會顯得過度同理或像機器覆讀機。
- **解決方案**：
  - **單輪即時評估 + 情緒轉折追蹤 (Emotion Trajectory Tracking)**：
  - Stage 1 Emotion 模組維持「單輪即時評估」主軸，同時輸出 `emotion_trend`（如 `guilt -> encouraged`）。
  - Stage 2 提示詞嚴格要求以「最新即時情緒」為準，並對正向情緒轉折給予讚賞與回應。

#### 【困難點 4】後端 Java API 查詢參數的上下文消歧義 (Disambiguation for Backend API)
- **潛在問題**：第一輪使用者提及「鹹酥雞」，第二輪說「那換成湯意麵呢？」。若直接拿第二輪字面傳給 Java `DietaryAgent` API，API 無法得知是「與鹹酥雞比較」還是「獨立查詢湯意麵」。
- **解決方案**：
  - Stage 1 `screen_user_request` 升級多輪上下文消歧義能力：自動識別 `current_meal_items` (湯意麵) 與 `referenced_meal_items` (鹹酥雞)，組合出明確的對比或查詢 Payload 傳遞給下游 Java API。

#### 【困難點 5】問句鉤子（Engaging Hook）迴圈與審問感 (Hook Overuse & Interrogation Avoidance)
- **潛在問題**：單輪 ESC 要求的「句尾拋出開放式問句」，若在多輪對話中每一輪都強制使用，使用者連答幾輪後會產生「被追問/被審問」的煩躁感。
- **解決方案**：
  - **依對話輪數動態調控句尾鉤子 (Dynamic Hook Strategy)**：
    - **第 1 輪 (新話題引導)**：拋出選擇題或開放式問句（探索與接球）。
    - **第 2 輪 (深化與延伸)**：給予同理與輕關懷，搭配隨性延伸問句。
    - **第 3 輪+ (話題收尾)**：轉換為溫暖祝福或肯定讚賞（溫馨結尾，不強制提問），自然引導話題閉合。

---
*本說明書更新於 2026 年 8 月 23 日，作為 Companion Agent v6.1 重構與多輪對話機制研發之標準指引。*


## 📌 七、 為了整體輸出品質進行之細微調整 (Fine-tuning & Optimization Enhancements)

本區塊記錄為了大幅提升 Companion Agent 回覆集中度、權威性與減少 Token 雜訊，針對 `companion-llm.js` 進行之專項細微調整與條列式變更說明。

### 1. 調整項目概覽與目標
- **痛點說明**：Stage 2 LLM 生成對話時，因傳入之 `dietaryAgentResponse` 包含過多重複的子欄位（如 `dish_advice` 陣列）與細節，導致注意力分散，未能以 Java 後端 Nutritionist Agent 產出的 `conclusion` 結論作為主骨幹。
- **重構目標**：
  1. 精簡 `minimizeDietaryResponse()` 函數：將 `conclusion` 置於 JSON 最頂層，移除重複干擾的 `dish_advice` 陣列，並保留完整的 `dish_nutrition` 餐點營養數據（包含 Calories, Protein, Sodium 等）。
  2. 升級 `REPLY_SYSTEM_PROMPT` 的 `Input Parameters Context` 與步驟 2：明確將 `conclusion` 標註為【最高權限核心依據】，強制對話重組以此為骨幹。
  3. 更新 Few-Shot 範例 D：展示如何平滑潤飾 `conclusion` 為小精靈口語。

### 2. 程式碼修改細節條列 (Detailed Code Modifications)

修改目標檔案：[`companion-llm.js`](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-llm.js)

#### 變更 1：`minimizeDietaryResponse()` 資料過濾函數重構
- **修改位置**：[`companion-llm.js`](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-llm.js#L493)
- **修改內容**：
  - 將 `conclusion` 置於回傳 JSON 物件最頂層 (`minimized.conclusion`)。
  - 移除 `dish_advice` 陣列 mapped 邏輯（避免與 `conclusion` 重疊干擾）。
  - 保留完整的 `dish_nutrition` 餐點營養數據（保留名稱、所有營養素項目如 Calories, Protein, Sodium、數值與單位）。

#### 變更 2：`REPLY_SYSTEM_PROMPT` 之 `Input Parameters Context` 權重升級
- **修改位置**：[`companion-llm.js`](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-llm.js#L418)
- **修改內容**：
  - 明確將 `dietaryAgentResponse.conclusion` 定義為 **【最高權限核心依據】**。

#### 變更 3：`REPLY_SYSTEM_PROMPT` 之【步驟 2】與 Few-Shot 範例 D 強化
- **修改位置**：[`companion-llm.js`](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-llm.js#L432)
- **修改內容**：
  - 【步驟 2】強制要求口語化潤飾時必須 100% 採納 `conclusion` 建議骨幹。
  - Few-Shot 範例 D 加入 `conclusion` 範例數據與期待輸出。

### 3. 對話擬真度與同理接話語法微調（基於語用學與人機互動理論）

- **痛點說明**：
  測試中發現 Stage 2 LLM 生成開頭時，常出現如 `「剛買好一份豬肉蛋餅當午餐，想確認營養夠不夠，這份心意很細心耶..」` 的句型。此類開頭帶有強烈的「鸚鵡式重述」與「機械生硬誇獎」，缺乏真實人類對話的自然感。
- **學術理論支持與病因分析**：
  1. **違反語用學合作原則（Grice's Cooperative Principle - Maxim of Quantity）**：
     AI 在回答前重新朗誦並摘要使用者的問句（Parrot Echoing），傳遞了冗餘重複的資訊，違反了對話的簡潔性原則（Maxim of Quantity），讓對話顯得像機械式客服確認流程。
  2. **社交距離與過度稱讚不適理論（Social Distance & Over-praising Discomfort in HCI）**：
     對於日常簡單的飲食選擇（如買蛋餅問營養），硬套 `「這很細心耶 / 這份心意...」` 等不符台灣繁體中文口語習慣的高度客套詞，引發「對話恐怖谷效應（Uncanny Valley of Conversational AI）」，讓使用者感受出人工營造的誇獎痕跡。
  3. **羅傑斯以人為中心之同理心理論（Person-Centered Empathy Standard）**：
     真正的同理建立在「情感與需求的自然共鳴」，而非結構化的句型填空（重述 $\to$ 硬套讚美標籤 $\to$ 給建議）。
- **優化目標與 Prompt 修改條列**：
  - **變更 A：簡化【步驟 1】過度微觀的條件，並融入多元情境接話策略**
    - 修改位置：[`companion-llm.js`](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-llm.js#L428)
    - 內容：移除原先對 `psychological_context` 分支（如 `work_overtime_stress` 等）的硬性條款，改為高層次的情感共鳴指導，並注入「多元情境接話策略」，以正面引導增強回應的自然度與豐富度。
  - **變更 B：更新 Few-Shot 範例 D 之開頭語氣**
    - 修改位置：[`companion-llm.js`](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-llm.js#L479)
    - 內容：修飾 Few-Shot 範例開頭，提供在地、多元且自然的人類口語接話範本，讓模型透過 In-Context Learning 自發模仿優質對話風格。

- **建議 Prompt 修改對比與建議範本 (Proposed Prompt Change)**：

  *原版【步驟 1】 Prompt：*
  ```markdown
  【步驟 1：同理與共鳴 (探索與安慰階段)】
  - 開頭第一句精準同理並重述 emotion.evidence 中的關鍵字與心情，絕不可出現冷漠拒絕或格式化警告。
  - 參考 emotion.psychological_context 與 emotion.primary_emotion：
    * 若為 work_overtime_stress 或 diet_relapse_guilt，首句必須給予安撫與包容，消除罪惡感。
    * 若為 weather_or_mood 或 other_general_chat，精準共鳴使用者描述的感受。
  ```

  *建議修改後之【步驟 1】 Prompt (簡化條件 + 多元接話策略)：*
  ```markdown
  【步驟 1：同理與共鳴 (情感與多元接話階段)】
  - 第一句請參考 emotion 資訊，精準共鳴使用者描述的感受、心情或當下情境。語氣保持親切包容，絕不可出現批判、冷漠拒絕或格式化警告。
  - 請根據語境靈活採用【多元情境接話策略】，避免套用僵硬公式或客套詞，讓回應更自然且多樣：
    1. **美食/生活情境共鳴**（例：*「午餐吃豬肉蛋餅很讚耶！」*、*「這天氣來碗熱湯最棒了！」*）
    2. **健康意圖肯定**（例：*「會注意到營養均衡很棒耶！」*）
    3. **直奔主題與親切回應**（例：*「豬肉蛋餅主要提供蛋白質與碳水...」*）
  ```





