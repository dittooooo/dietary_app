# Companion Agent Version 7.0 前端託管與無狀態後端實作規劃說明書 (adjust_v7_conversation_imple_v2.md)

本說明書參考 [`adjust_v7_conversation.md`](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/doc/adjust_v7_conversation.md)，詳細規格化 **Companion Agent (米粒)** 採用 **「前端 `temp_story` 託管與完全無狀態後端 (Stateless Backend Architecture)」** 方案下的變更原因、前後端影響檔案清單，以及各檔案之詳細程式碼變更內容與邊界防護邏輯。

---

## 📌 一、 為甚麼要做變更？ (Background & Motivation)

### 1. 舊架構痛點與 Session 資料庫託管之維護成本
在之前的討論與實作規劃中，曾考慮過後端維護 `companion_sessions` 與 `companion_messages` 資料庫表格的模式（Session-based Architecture）。然而，經過團隊評估，後端託管歷史會帶來以下挑戰：
* **資料庫負擔與開發維護成本高**：後端需要寫 SQL 進行 Session 建立、讀取歷史、更新最後發言時間以及判斷 24h 閉合 (Status 'closed')，大幅增加複雜度。
* **死鎖與狀態同步問題**：多裝置或網路波動時，前端 UI 狀態與後端資料庫 Session 狀態容易出現同步延遲或不一致。
* **話題轉折與重置負擔**：當使用者欲切換主題時，前端必須發送 HTTP 請求通知後端「強制結案舊 Session 並開啟新 Session」，增加了多餘的 API round-trip 延遲與連線失敗風險。

### 2. Version 7.0 核心設計理念與「前端託管 + 無狀態後端」優勢
經過團隊會議決議，全面採納維護成本最低、開發速度最快、極簡高效的 **「前端 `temp_story` 託管與完全無狀態後端 (Stateless Backend Architecture)」**：

1. **完全無狀態後端 (Stateless Companion Microservice)**：
   * **後端資料庫負擔降至 0**：後端不用開設 `companion_sessions` 或 `companion_messages` 資料庫表格，也不維護任何 `session_id`。後端僅作為純粹的 AI 推理計算器。
   * **API 回應速度最大化**：消去所有 Session 查詢與 DB 鎖定開銷，收到請求即進行 LLM 推理並即時回傳。
2. **單一主聊天視窗與前端 `temp_story` 託管**：
   * 使用者永遠在同一個主視窗與米粒互動，介面保持極簡清爽。
   * 前端使用 `localStorage` 自行託管當前話題的最近 3 則訊息（稱為 `temp_story`）。
3. **前端自主「🌱 開啟新話題」零延遲重置**：
   * 聊天視窗角落提供 **`🌱 開啟新話題`** 按鈕。點擊後前端直接執行 `localStorage.removeItem('temp_story')` 並清空 UI 畫面，**無需發送 API 告知後端**，達成 0ms 極速話題重置。
4. **前端 24 小時閒置自動清空 (24h Idle Timeout)**：
   * 前端紀錄 `last_update_time` 時間戳記。當使用者開啟或回到頁面時，若 `(Date.now() - last_update_time) >= 24h`，前端自動清空 `temp_story` 與 UI 畫面，恢復乾淨初始狀態。
5. **AI 推理記憶與 Token 控管 (Last 3 Messages Window)**：
   * 前端傳給後端的 `temp_story` **嚴格限制最多維持最近 3 則訊息**（超過 3 則的舊對話由前端自動 `shift()` 剔除），精準控制 Token 費用並防止注意力污染。

---

## 📌 二、 分別變更 前、後端那些檔案 (Affected Files Matrix)

### 檔案變更總覽表

在 Version 7.0 無狀態架構下，**後端完全不需要資料庫層 (`db_concerned`)**，所有對話歷史維護、閒置檢查與主題重置均由前端獨立完成。

| 端的分類 | 檔案路徑 / 名稱 | 變更類型 | 核心職責與變更目的 |
| :--- | :--- | :--- | :--- |
| **後端** | [`companion_js/companion-agent.js`](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-agent.js) | **[MODIFY]** | 控制器層。調整 `POST /companion/ask` 接收並過濾/清洗 `temp_story`；移除 Session DB 與 Reset 相關路由，確保 100% 無狀態。 |
| **後端** | [`companion_js/companion-agent-services.js`](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-agent-services.js) | **[MODIFY]** | 業務協調層。更新 `runOpenAIFlow` 與 `getCompanionReply` 函數簽名，傳遞 `tempStory` 上下文至 LLM 模組。 |
| **後端** | [`companion_js/companion-llm.js`](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-llm.js) | **[MODIFY]** | LLM 處理層。將 `tempStory` 注入 Stage 1 (意圖與情緒診斷) 與 Stage 3 (小芽對話生成)，解決代名詞與省略句指涉問題。 |
| **前端** | `src/stores/chatStore.js` (或相應 Store) | **[NEW / MODIFY]** | 維護 `temp_story` 本地快取、`last_update_time` 24h 閒置自動清空、點擊「🌱 開啟新話題」清空邏輯與最多 3 則佇列滑動。 |
| **前端** | `src/services/companionApi.js` | **[NEW / MODIFY]** | API 連線封裝。將 `user_prompt` 與本地 `temp_story` 打包發送至 `POST /companion/ask`；刪除舊有的 Session Reset API 呼叫。 |
| **前端** | `src/components/NewTopicButton.vue` | **[NEW / MODIFY]** | 提供 **`🌱 開啟新話題`** 按鈕 UI，綁定點擊事件觸發純前端重置 `chatStore.startNewTopic()`。 |
| **前端** | `src/views/ChatView.vue` | **[MODIFY]** | 單一主對話框介面。掛載時觸發 24h 閒置檢測，呈現目前對話內容與 Loading 狀態。 |

---

## 📌 三、 詳細說明個別檔案的詳細變更內容 (Detailed File Changes)

### 1. 後端檔案詳細變更說明 (Backend Express & LLM Services)

#### (1) [`companion_js/companion-agent.js`](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-agent.js) **[MODIFY]**
* **主要變更**：
  1. 修改 `handleCompanionAsk(req, res)` 處理邏輯，從 `req.body` 解析 `temp_story` 陣列。
  2. **安全性與清洗機制 (Sanitization)**：
     * 過濾非 `role === 'user'` 或 `role === 'assistant'` 的項目。
     * 強制限制最多保留最近 3 筆 (`temp_story.slice(-3)`)。
     * 對每筆內容執行最長 300 字截斷 (`content.substring(0, 300)`)，防止長文章輸入導致 Prompt 注入與 Token 暴增。
  3. 將清洗後的 `temp_story` 傳遞給 `runOpenAIFlow` 與 `getCompanionReply`。
  4. 移除所有與 DB / Session 相關的路由（無 `/companion/session/reset`），維持微服務完全無狀態。

* **關鍵程式碼範例**：
  ```javascript
  /**
   * 處理陪伴精靈對話請求的主路由邏輯 (Stateless Node)
   */
  async function handleCompanionAsk(req, res) {
    const user_prompt = typeof req.body.user_prompt === "string" ? req.body.user_prompt.trim() : "";
    if (!user_prompt) {
      return res.status(400).json({
        success: false,
        error_code: "BAD_REQUEST",
        error_message: "The 'user_prompt' field is required and must be a non-empty string."
      });
    }

    // 1. 安全解析與清洗前端傳入的 temp_story 歷史紀錄
    let rawTempStory = Array.isArray(req.body.temp_story) ? req.body.temp_story : [];
    const sanitizedTempStory = rawTempStory
      .filter(item => item && (item.role === 'user' || item.role === 'assistant') && typeof item.content === 'string')
      .map(item => ({
        role: item.role,
        content: item.content.trim().substring(0, 300) // 限制每筆最大 300 字
      }))
      .slice(-3); // 保留最多最近 3 則

    console.log(`[Companion Agent] 📥 收到提問: "${user_prompt}" | 帶入歷史筆數: ${sanitizedTempStory.length}`);

    // 2. 執行第一階段 LLM 分析，代入 temp_story
    let openAiResult;
    try {
      openAiResult = await runOpenAIFlow(user_prompt, sanitizedTempStory);
    } catch (error) {
      return res.status(502).json({ success: false, error_message: error.message });
    }

    // 3. (條件式) 呼叫 Java 營養計算助理 ...
    // [中略 API 轉發邏輯] ...

    // 4. 執行第三階段回覆生成，代入 temp_story
    const companionReply = await getCompanionReply({
      userPrompt: user_prompt,
      screening: openAiResult.screening,
      emotion: openAiResult.emotion,
      dietaryAgentResponse,
      dietaryAgentRequest: openAiResult.dietary_agent_request,
      dietaryAgentError,
      tempStory: sanitizedTempStory // 注入歷史上下文
    });

    return res.json({
      success: true,
      companion_reply: companionReply,
      intent_category: openAiResult.screening.intent_category || "general_chat",
      meal_items: openAiResult.screening.meal_items || []
    });
  }
  ```

---

#### (2) [`companion_js/companion-agent-services.js`](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-agent-services.js) **[MODIFY]**
* **主要變更**：
  1. 更新 `runOpenAIFlow(userPrompt, tempStory)` 簽名，接收 `tempStory` 並向下透傳至 `companion-llm.js` 的 LLM 分析模組。
  2. 更新 `getCompanionReply({ ..., tempStory })` 參數結構，將對話歷史上下文傳給 Stage 3 回覆生成器。

* **關鍵程式碼範例**：
  ```javascript
  // 1. 調整 runOpenAIFlow
  async function runOpenAIFlow(userPrompt, tempStory = []) {
    // 將 tempStory 傳給 LLM 意圖分析階段
    const result = await runLLMAnalysis(userPrompt, tempStory);
    const { screening, emotion } = result;

    // [簡化略：分流處理與 Java 飲食助理 Payload 組裝] ...

    return {
      screening,
      emotion,
      dietary_agent_request: dietaryAgentRequest
    };
  }

  // 2. 調整 getCompanionReply
  async function getCompanionReply({
    screening,
    emotion,
    dietaryAgentResponse,
    userPrompt,
    dietaryAgentError,
    tempStory = []
  }) {
    // 飲食紀錄分流快捷處理 ...

    let finalReply = "";
    try {
      finalReply = await runLLMReply({
        userPrompt,
        screening,
        emotion,
        dietaryAgentResponse,
        dietaryAgentError,
        tempStory // 帶入 Stage 3
      });
    } catch (error) {
      console.error("LLM Generation Failed:", error);
      finalReply = "AI 功能目前發生異常，請稍後再試。";
    }

    return finalReply;
  }
  ```

---

#### (3) [`companion_js/companion-llm.js`](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-llm.js) **[MODIFY]**
* **主要變更**：
  1. **Stage 1 省略句解讀 (Ellipsis Disambiguation)**：
     * 在 Stage 1 OpenAI 請求的 System / Messages 中，將 `tempStory` 作為前置對話 context 餵給模型。
     * 當使用者問「那如果換成炸雞腿呢？」，Stage 1 能根據 Context （上一筆「水煮雞胸肉便當熱量多少？」）正確將食物提取為「炸雞腿便當」並分析為餐點比較或替換問題。
  2. **Stage 3 陪伴對話生成 (Contextual Companion Response)**：
     * 將 `tempStory` 轉換為 Prompt 對話歷史格式，併入 Stage 3 的生成 Prompt 中，使米粒能流暢接續上一輪話題，語氣更加溫暖貼心。

* **關鍵程式碼範例**：
  ```javascript
  // 1. Stage 1 注入 tempStory
  async function runOpenAIFlow(userPrompt, tempStory = []) {
    const apiKey = getApiKey();
    const model = getModel();

    // 格式化對話歷史供 Prompt 使用
    const historyText = tempStory.length > 0
      ? tempStory.map(m => `${m.role === 'user' ? '使用者' : '米粒'}: ${m.content}`).join('\n')
      : "無歷史對話";

    const promptMessages = [
      {
        role: "system",
        content: `你是一個專業的飲食輔助診斷器。\n當前最近對話歷史如下：\n${historyText}\n\n請根據歷史上下文與使用者最新的提問，精準識別食物名稱（含隱含代名詞與省略餐點）、意圖類別與情緒狀態。`
      },
      {
        role: "user",
        content: userPrompt
      }
    ];

    // 發送給 OpenAI API 解析 JSON ...
  }

  // 2. Stage 3 注入 tempStory
  async function generateCompanionReply({ userPrompt, screening, emotion, dietaryAgentResponse, dietaryAgentError, tempStory = [] }) {
    // 建立小芽 Stage 3 Persona Prompt ...
    const formattedHistory = tempStory.map(m => ({
      role: m.role === 'user' ? 'user' : 'assistant',
      content: m.content
    }));

    const messages = [
      { role: "system", content: "你是「米粒 (Mili)」，一位溫暖親切的飲食陪伴精靈..." },
      ...formattedHistory, // 帶入近 3 則歷史
      { role: "user", content: `使用者最新問題：${userPrompt}\n飲食分析結果：${JSON.stringify(dietaryAgentResponse)}` }
    ];

    // 呼叫 OpenAI Chat Completion 產生親切對話 ...
  }
  ```

---

### 2. 前端檔案詳細變更說明 (Vue Frontend / Store / Services)

#### (1) `src/stores/chatStore.js` **[NEW / MODIFY]**
* **主要變更**：
  1. 託管本地對話歷史 `temp_story` (Array of `{ role, content }`) 與 UI 顯示訊息列表 `messages`。
  2. 託管 `last_update_time` (時間戳記)，於每次成功發言與收到對話時更新，並持久化於 `localStorage`。
  3. 提供 `checkAndApply24hIdleTimeout()`：頁面初始化或重新可見時觸發，判斷 `Date.now() - last_update_time >= 24 * 60 * 60 * 1000`。若超時，直接執行 `resetChat()`。
  4. 提供 `startNewTopic()`：使用者點擊「🌱 開啟新話題」時觸發，執行 `resetChat()`（`temp_story = []`，UI 清空），不發送 API。
  5. 提供 `sendMessage(prompt)`：
     - 將使用者問題寫入 UI 並推入 `temp_story`。
     - 若 `temp_story.length > 3`，執行 `temp_story.shift()` maintain 滑動視窗。
     - 呼叫 API 取得小芽回覆後，將小芽回覆推入 `temp_story`（同樣維持 max 3 筆）。

* **關鍵程式碼範例**：
  ```javascript
  import { defineStore } from 'pinia';
  import { askCompanionApi } from '@/services/companionApi';

  const TEMP_STORY_KEY = 'temp_story';
  const LAST_UPDATE_KEY = 'last_update_time';
  const IDLE_24H_MS = 24 * 60 * 60 * 1000;

  export const useChatStore = defineStore('chat', {
    state: () => ({
      messages: [], // 用於 UI 畫面渲染
      temp_story: JSON.parse(localStorage.getItem(TEMP_STORY_KEY) || '[]'),
      last_update_time: Number(localStorage.getItem(LAST_UPDATE_KEY) || 0),
      isLoading: false
    }),

    actions: {
      // 1. 24h 閒置檢測
      checkAndApply24hIdleTimeout() {
        const now = Date.now();
        if (this.last_update_time > 0 && (now - this.last_update_time) >= IDLE_24H_MS) {
          console.log('⏱️ 超過 24 小時未互動，自動清空對話與歷史');
          this.resetChat();
        }
      },

      // 2. 點擊「🌱 開啟新話題」或 24h 清空
      resetChat() {
        this.messages = [];
        this.temp_story = [];
        this.last_update_time = Date.now();
        localStorage.removeItem(TEMP_STORY_KEY);
        localStorage.setItem(LAST_UPDATE_KEY, this.last_update_time);
      },

      // 3. Append 歷史並維持最多 3 筆 (Slide Window)
      appendTempStory(role, content) {
        this.temp_story.push({ role, content });
        if (this.temp_story.length > 3) {
          this.temp_story.shift(); // 剔除最舊的訊息
        }
        this.last_update_time = Date.now();
        localStorage.setItem(TEMP_STORY_KEY, JSON.stringify(this.temp_story));
        localStorage.setItem(LAST_UPDATE_KEY, this.last_update_time);
      },

      // 4. 發送對話
      async sendMessage(userPrompt) {
        if (!userPrompt.trim()) return;

        // 寫入前端 UI
        this.messages.push({ role: 'user', content: userPrompt });

        // 打包當前 temp_story 副本發送給後端 (在 append 本次提問之前或之後皆可，合約規範帶入歷史)
        const payloadHistory = [...this.temp_story];

        // 將本次使用者輸入放入 temp_story
        this.appendTempStory('user', userPrompt);

        this.isLoading = true;
        try {
          const res = await askCompanionApi({
            user_prompt: userPrompt,
            temp_story: payloadHistory
          });

          if (res.success && res.companion_reply) {
            // 寫入 UI 與 temp_story
            this.messages.push({ role: 'assistant', content: res.companion_reply });
            this.appendTempStory('assistant', res.companion_reply);
          }
        } catch (error) {
          this.messages.push({ role: 'system', content: '小芽暫時無法回應，請稍後再試。' });
        } finally {
          this.isLoading = false;
        }
      }
    }
  });
  ```

---

#### (2) `src/services/companionApi.js` **[MODIFY]**
* **主要變更**：
  1. 封裝 `askCompanionApi({ user_prompt, temp_story })`。
  2. 發送 `POST /companion/ask` 時，同時將 `user_prompt` 與 `temp_story` 作為 JSON Payload 傳送。
  3. 刪除所有與 `POST /companion/session/reset` 相關的廢棄 API 呼叫。

* **關鍵程式碼範例**：
  ```javascript
  import axios from 'axios';

  const apiClient = axios.create({
    baseURL: process.env.VUE_APP_COMPANION_API_URL || 'http://localhost:3000',
    headers: { 'Content-Type': 'application/json' }
  });

  /**
   * 發送對話請求給無狀態 Companion Agent API
   * @param {Object} data - { user_prompt: string, temp_story: Array }
   */
  export async function askCompanionApi(data) {
    const response = await apiClient.post('/companion/ask', {
      user_prompt: data.user_prompt,
      temp_story: data.temp_story || []
    });
    return response.data;
  }
  ```

---

#### (3) `src/components/NewTopicButton.vue` **[NEW / MODIFY]**
* **主要變更**：
  1. 在聊天 UI 角落提供 **`🌱 開啟新話題`** 按鈕。
  2. 點擊時彈出確認提示（或直接重置），觸發 `chatStore.resetChat()`。
  3. 達成前端 0 延遲歸零對話畫面與 `temp_story`。

* **關鍵程式碼範例**：
  ```vue
  <template>
    <button class="new-topic-btn" @click="handleNewTopic">
      🌱 開啟新話題
    </button>
  </template>

  <script setup>
  import { useChatStore } from '@/stores/chatStore';

  const chatStore = useChatStore();

  function handleNewTopic() {
    // 點擊後純前端清空，無需呼叫後端 API
    chatStore.resetChat();
  }
  </script>

  <style scoped>
  .new-topic-btn {
    background-color: #e8f5e9;
    color: #2e7d32;
    border: 1px solid #a5d6a7;
    padding: 6px 12px;
    border-radius: 16px;
    cursor: pointer;
    font-weight: 500;
    transition: all 0.2s ease;
  }
  .new-topic-btn:hover {
    background-color: #c8e6c9;
  }
  </style>
  ```

---

#### (4) `src/views/ChatView.vue` **[MODIFY]**
* **主要變更**：
  1. 在組件 `onMounted` 生命週期以及視窗 `visibilitychange`（使用者重返頁面）時，自動呼叫 `chatStore.checkAndApply24hIdleTimeout()`。
  2. 綁定 `chatStore.messages` 渲染單一對話框歷史。
  3. 整合 `NewTopicButton` 按鈕元件與發送輸入框。

* **關鍵程式碼範例**：
  ```vue
  <template>
    <div class="chat-container">
      <header class="chat-header">
        <h2>陪伴精靈 米粒</h2>
        <NewTopicButton />
      </header>

      <main class="chat-messages">
        <div v-for="(msg, index) in chatStore.messages" :key="index" :class="['message', msg.role]">
          <div class="bubble">{{ msg.content }}</div>
        </div>
        <div v-if="chatStore.isLoading" class="loading-bubble">米粒思考中...🌱</div>
      </main>

      <footer class="chat-input-area">
        <input
          v-model="inputText"
          @keyup.enter="handleSend"
          placeholder="跟米粒聊聊今天的飲食吧..."
        />
        <button @click="handleSend" :disabled="chatStore.isLoading">發送</button>
      </footer>
    </div>
  </template>

  <script setup>
  import { ref, onMounted, onUnmounted } from 'vue';
  import { useChatStore } from '@/stores/chatStore';
  import NewTopicButton from '@/components/NewTopicButton.vue';

  const chatStore = useChatStore();
  const inputText = ref('');

  function handleVisibilityChange() {
    if (document.visibilityState === 'visible') {
      chatStore.checkAndApply24hIdleTimeout();
    }
  }

  onMounted(() => {
    // 檢查是否超過 24h 閒置
    chatStore.checkAndApply24hIdleTimeout();
    document.addEventListener('visibilitychange', handleVisibilityChange);
  });

  onUnmounted(() => {
    document.removeEventListener('visibilitychange', handleVisibilityChange);
  });

  async function handleSend() {
    if (!inputText.value.trim() || chatStore.isLoading) return;
    const text = inputText.value;
    inputText.value = '';
    await chatStore.sendMessage(text);
  }
  </script>
  ```

---

## 📌 四、 總結與架構優勢比較

採用 **Version 7.0 前端 `temp_story` 託管與完全無狀態後端** 架構後：
1. **後端極致輕量化**：完全免除資料庫連線、SQL 表格設計與鎖定問題，服務具備水平擴充 (Scale-out) 的極佳彈性。
2. **前後端權責分離明確**：歷史紀錄由 UI 前端自主管理，後端純粹進行大語言模型推理與營養微服務串接。
3. **使用者體驗極佳**：話題重置與 24h 自動清空達到零延遲，對話視窗永遠保持清爽簡潔。

---
*本規格說明書最後更新於 2026 年 8 月 27 日，專為 Companion Agent Version 7.0 前端託管與無狀態後端技術實作使用。*
