# Companion Agent 第六次版本架構調整討論與規劃 (adjust_v6.md)

本文件專為團隊內部與隊長討論 **Companion Agent Version 6 流程重構** 所設計。詳細記載現有架構 (v5)、隊長初版提案與團隊最終共識定案 v6 架構的三種 OpenAI API 呼叫對比，並剖析潛在隱患與具體改進建議。

---

## 📌 一、 三種 OpenAI API 呼叫架構全方位對比 (Architectural Comparison)

### 📊 三種架構之 OpenAI 呼叫對照表 (Side-by-Side Comparison Table)

| 架構方案 | 呼叫次序 | 呼叫名稱/函數 | 核心目的 | 傳入 Input | 核心 Output (產出物) |
| :--- | :---: | :--- | :--- | :--- | :--- |
| **方案一：現有 v5 架構**<br/>*(單次併行抽取流)* | 第 1 次 | `runLLMAnalysis` | 意圖分類 + 食物/份數抽取 + 情緒診斷 | `user_prompt` + 當前時間 | `screening` JSON + `emotion` JSON |
| | 第 2 次 | `translateDishes` | 華麗餐點標準化翻譯（條件觸發） | 花俏餐點名稱陣列 | 標準品名字典 `translatedDishInfoList` |
| | *(轉接)* | *(Java Dietary Agent)* | 專業熱量與三大營養素計算 | `question`, `question_type`, `dish_info_list` | 專業營養 JSON `dietaryAgentResponse` |
| | 第 3 次 | `runLLMReply` | 小精靈陪伴對話生成與重組 | Prompt + 數據 + `emotion` | 對話文字 `companion_reply` (string) |
| --- | --- | --- | --- | --- | --- |
| **方案二：隊長初版提案**<br/>*(任務拆分 + 早退)* | 第 1 次 | *(預檢與生成器)* | 意圖/情緒診斷 + **Persona 早期回覆 (`early_reply`)** | `user_prompt` + 角色設定 | 分類 JSON + 對話 `early_reply` (文字) |
| | *(過濾)* | *(早期回傳)* | 若 `should_handle === false` **直接回傳 `early_reply`** | `early_reply` | 直接結束請求，跳過後續 API |
| | 第 2 次 | *(餐點與翻譯器)* | 食物名稱/份數/餐期抽取 + 餐點翻譯 | `user_prompt` + 翻譯規範 | `meal_records` + `dish_info_list` |
| | *(轉接)* | *(Java Dietary Agent)* | 專業熱量與三大營養素計算 | `question`, `question_type`, `dish_info_list` | 專業營養 JSON `dietaryAgentResponse` |
| | 第 3 次 | `runLLMReply` | 小精靈陪伴對話生成與重組 | Prompt + 數據 + 抽取結果 | 對話文字 `companion_reply` (string) |
| --- | --- | --- | --- | --- | --- |
| **方案三：修改版本 v6 架構**<br/>*(抽取整合與靈活分流流)* | 第 1 次 | `runLLMAnalysis` | **意圖/情緒診斷 + 食物/份數/餐期抽取**<br/>(純 JSON，不生成對話文字、無 Persona) | `user_prompt` + 當前時間 | `screening` JSON (含 `dish_info_list`) + `emotion` JSON |
| | *(分流 A)* | *(閒聊/非飲食)* | 跳過 Java 與翻譯，直奔第 3 次 API 生成導回對話 | `userPrompt` + Persona | 小精靈親切導回對話 `companion_reply` |
| | *(分流 B)* | *(飲食紀錄)* | 跳過 Java 後端，**立刻回傳 `meal_records` 彈出草稿視窗** | `meal_records` | 彈跳視窗草稿 JSON (+ 小精靈讚賞語) |
| | *(分流 C)* 第 2 次| `translateDishes` | **(飲食諮詢)** 華麗餐點標準化翻譯（條件觸發） | 花俏餐點名稱陣列 | 標準品名字典 `translatedDishInfoList` |
| | *(轉接)* | *(Java Dietary Agent)* | 專業熱量與三大營養素計算 | `question`, `question_type`, `dish_info_list` | 專業營養 JSON `dietaryAgentResponse` |
| | 第 3 次 | `runLLMReply` | **小精靈本尊對話生成器 (100% 集中 Persona 靈魂)** | Prompt + 數據 + Persona | 最終一致對話 `companion_reply` (string) |

---

### 🔍 方案詳細說明 (Detailed Scheme Description)

#### 方案一：現有專案架構 (Current Version 5 - 併行抽取流)
* **第 1 次 API（意圖分類 + 食物抽取 + 情緒診斷）**
  * **呼叫目的**：一次性完成「要不要處理 (`should_handle`)」、「意圖分類 (`intent_category`)」、「餐點與餐期抽取 (`meal_records`)」與「情緒診斷 (`analyze_emotion`)」。
  * **傳入 Input**：`user_prompt` + 24小時制系統時間。
  * **產出 Output**：`screening` JSON (含 `dish_info_list: { "炸雞": 2 }`) + `emotion` JSON (含 `needs_empathy: true`)。
* **第 2 次 API（華麗餐點標準化翻譯 - 條件觸發）**
  * **呼叫目的**：將花俏商品名（如「起司瀑布牛肉堡」）翻譯為資料庫標準名（如「牛肉漢堡」），提升 Java 後端命中率。
  * **傳入 Input**：花俏餐點陣列 `["起司瀑布牛肉堡"]`。
  * **產出 Output**：翻譯後標準字典 `translatedDishInfoList: { "牛肉漢堡": 1 }`。
* **(中間轉接：呼叫 Java Dietary Agent 進行熱量與營養計算)**
* **第 3 次 API（陪伴對話生成與重組）**
  * **呼叫目的**：作為小精靈發聲，結合情緒需求與 Java 營養數據，生成 50 大卡區間化與附帶免責聲明的親切對話。
  * **傳入 Input**：`userPrompt` + `screening` + `emotion` + 簡化營養數據 + `dietaryAgentError`。
  * **產出 Output**：對話文字字串 `companion_reply` (string)。

---

#### 方案二：隊長初版提案 (Team Lead's Proposal - 任務拆分與早期回覆)
* **第 1 次 API（預檢過濾 + 角色對話生成）**
  * **呼叫目的**：判定 `should_handle`、`intent_category`、`analyze_emotion`，並在第一階段寫入角色設定 (Persona)，直接生成 `early_reply` 內容。
  * **傳入 Input**：`user_prompt` + 角色設定 Persona。
  * **產出 Output**：`should_handle` + `intent_category` + `emotion` + 自然語言 `early_reply` (string)。
* **(條件過濾：若 `should_handle === false`，直接回傳 `early_reply` 並結束請求)**
* **第 2 次 API（餐點抽取 + 餐點翻譯）**
  * **呼叫目的**：當 `should_handle === true` 時，專門抽取食物名稱、份數、單位、餐期，並進行品名翻譯。
  * **傳入 Input**：`user_prompt` + 翻譯規範。
  * **產出 Output**：`dish_info_list` (字典結構) + `meal_records` (陣列)。
* **(中間轉接：呼叫 Java Dietary Agent 進行熱量與營養計算)**
* **第 3 次 API（陪伴對話生成與重組）**
  * **呼叫目的**：結合 Java 數據與情緒，生成最終建議對話。
  * **傳入 Input**：`userPrompt` + 抽取結果 + Java 數據。
  * **產出 Output**：對話文字字串 `companion_reply` (string)。

---

#### 方案三：團隊共識定案 v6 架構 (Team Final Consensus Version 6 - 抽取整合與靈活分流)
* **第 1 次 API（意圖分類 + 食物/餐期抽取 + 情緒診斷）**
  * **呼叫目的**：一次性完成「要不要處理 (`should_handle`)」、「意圖分類 (`intent_category`)」、「餐點與餐期抽取 (`meal_records`)」與「情緒診斷 (`analyze_emotion`)」。
  * **特點**：純結構化 JSON 輸出，**絕不生成任何自然語言對話 (`early_reply`)，亦不載入角色設定 (Persona)**。
  * **傳入 Input**：`user_prompt` + 24小時制系統時間。
  * **產出 Output**：`screening` JSON (含 `dish_info_list: { "炸雞": 2 }`) + `emotion` JSON (含 `needs_empathy: true`)。
* **(靈活分流與過濾機制)**：
  * **分流 A (非飲食閒聊 `should_handle === false`)**：跳過 Java 後端與微型翻譯，直奔第 3 次 API，由小精靈生成親切同理與導回對話。
  * **分流 B (飲食紀錄 `intent_category === "meal_record"`)**：跳過 Java 後端，直接拿第 1 次 API 抽好的 `meal_records` **立刻回傳前端彈出確認草稿彈跳視窗** ✨！
  * **分流 C (飲食諮詢 `intent_category === "dish_advice"`)**：走第 2 次微型翻譯 (條件觸發) $\to$ 呼叫 Java Dietary Agent 算熱量 $\to$ 第 3 次 API 生成最終建議。
* **第 2 次 API（華麗餐點標準化翻譯 - 條件觸發）**
  * **呼叫目的**：當 `dish_info_list` 包含花俏商品名（如「起司瀑布牛肉堡」）時，進行微型翻譯為標準名（如「牛肉漢堡」）。
  * **傳入 Input**：花俏餐點陣列 `["起司瀑布牛肉堡"]`。
  * **產出 Output**：翻譯後標準字典 `translatedDishInfoList: { "牛肉漢堡": 1 }`。
* **(中間轉接：呼叫 Java Dietary Agent 進行熱量與營養計算)**
* **第 3 次 API（小精靈本尊對話生成器 - 100% 集中 Persona 靈魂）**
  * **呼叫目的**：小精靈唯一的發聲管道！統一處理「非飲食親切拒絕引導」、「飲食紀錄確認讚賞」與「正常熱量與營養建議」。
  * **傳入 Input**：`userPrompt` + `screening` + `emotion` + Java 數據 + 小精靈完整 Persona 設定。
  * **產出 Output**：最終顯示給使用者的對話文字 `companion_reply` (string)。

---

## 🎯 二、 團隊共識定案 v6 架構的 4 大核心優勢 (Core Advantages)

1. **完美滿足 Flutter 前端彈跳視窗 (Popup UX)**：
   * 當 `intent_category === "meal_record"` 時，在**第 1 次 API 完成的瞬間**，後端就已經拿到完整的 `meal_records`（食物、數量、單位、餐期），可以立刻傳回前端觸發草稿彈跳視窗，體驗極速！

2. **第 1 次 API 依然保持 100% 高穩定度**：
   * 因為第 1 次 API **完全不生成自然語言對話 (`early_reply`)**、也不混入 Persona，它依然是個「純粹的冷靜 JSON 產出器」，絕不會有 `JSON.parse` 崩潰或胡編熱量數字的問題。

3. **小精靈角色口吻 100% 統一**：
   * 第 3 次 API 依然是小精靈唯一的發聲管道，不論是閒聊導回還是飲食建議，講話語意與敬語風格絕對不會割裂。

4. **API 通訊次數最優化 (Zero Waste)**：
   * 閒聊/非飲食：**只需 2 次 API**（第 1 次預檢 $\to$ 跳過 Java $\to$ 第 3 次小精靈親切導回）。
   * 飲食紀錄：**只需 1~2 次 API**（第 1 次預檢取得草稿 $\to$ 立刻彈出視窗）。
   * 飲食諮詢：**固定 2~3 次 API**（第 1 次預檢與抽取 $\to$ 翻譯與 Call Java $\to$ 第 3 次小精靈建議）。

---

## 💡 三、 架構優化對比與對齊 Check-list

### 💬 團隊架構決策矩陣

| 討論議題 | 隊長初版構想 | 團隊共識定案 v6 架構 | 最終決策目標 |
| :--- | :--- | :--- | :--- |
| **Persona 放置點** | 第 1 次 與 第 3 次 皆放置 | **100% 集中在第 3 次 API** | 確保小精靈人格 100% 統一，避免維護雙重 Prompt |
| **非飲食過濾語氣** | 由第 1 次生成 `early_reply` | 由第 3 次小精靈統一對話 | 避免 `early_reply` 與 `companion_reply` 語氣撕裂與 JSON 崩潰 |
| **食物與餐期抽取** | 移至第 2 次 API 抽取 | **留在第 1 次 API 一併抽取** | **確保飲食紀錄 (`meal_record`) 能即時觸發前端草稿彈跳視窗** |
| **餐點翻譯 (Translation)** | 併在第 2 次抽取中處理 | **條件式獨立微型翻譯外掛** | 確保食物數量與餐期抽取 100% 精準，不被翻譯干擾 |
| **紀錄 (`meal_record`)** | 抽完食物後處理 | 本地傳回草稿 / 第 3 次小精靈讚賞 | 兼顧前端草稿視窗即時性與對話活潑度 |

---

### 💬 4 大待實作改進重點 Check-list

1. **第 1 次 API Prompt 淨化**：
   * 確定移除 `early_reply` 欄位與 Persona 描述，讓 `ANALYSIS_SYSTEM_PROMPT` 成為純 JSON 產出器。
2. **三路分流 (Flow Routing) 邏輯**：
   * 在 [`companion-agent-services.js`](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-agent-services.js) 中，依據 `should_handle` 與 `intent_category` 進行「閒聊導回 / 紀錄彈窗 / 諮詢計算」三路分流。
3. **無食物防呆機制**：
   * 當 `intent_category === "dish_advice"` 且抽不出食物 (`dish_info_list` 為空) 時，跳過 Java 後端，直接帶空資料進入第 3 次 API 由小精靈溫馨追問。
4. **小精靈 Persona 100% 集中注入**：
   * 在 `REPLY_SYSTEM_PROMPT` (第 3 次 API) 注入完整的性格檔（小芽、台灣口吻、顏文字、關懷風格）。
