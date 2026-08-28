# Companion Agent Version 7.0 前端託管與無狀態後端技術規格說明書 (adjust_v7_conversation.md)

本說明書根據團隊組長導向之架構決策，採用 **「方案 A：前端 `temp_story` 託管與完全無狀態後端 (Stateless Backend Architecture)」** 進行技術規格定義、API 請求合約設計、風險診斷與 ASCII 流程圖規劃。

---

## 📌 零、 架構核心理念：前端歷史託管 vs. 完全無狀態後端

經過團隊會議討論，決定採納維護成本最低、開發速度最快、極簡高效的 **「前端 `temp_story` 歷史託管機制」**：

| 比較維度 | 前端歷史對話託管 (Frontend `temp_story`) | 後端 API 服務 (Stateless Companion Agent) |
| :--- | :--- | :--- |
| **角色與職責** | **【保管與維護對話歷史】**<br/>前端利用 `localStorage` 存放當前對話最近 3 則訊息（名為 `temp_story`）。 | **【純粹無狀態計算器】**<br/>後端不需要開設任何 `sessions` 或 `messages` 資料庫表格，也不需要維護任何 `session_id` 狀態。 |
| **話題歸零機制** | **【前端自主重置】**<br/>使用者按下「🌱 開啟新話題」或超過 24 小時未發言，**前端直接清空 `temp_story = []`**，無需發送 API 告訴後端。 | **【無感無狀態處理】**<br/>後端接到請求時，直接拿 Request 傳來的 `temp_story` 丟給 OpenAI 推理，算完即回傳。 |
| **主要架構成效** | 1. 介面保持單一主視窗極簡體驗。<br/>2. 主導權完全在前端，話題切換零延遲。 | 1. **後端開發負擔降至 0**，無需寫 SQL 讀寫與維護 DB。<br/>2. 完全消去 Session 閉合、死鎖與超時計算的複雜邏輯。 |

---

## 📌 一、 專案目的與核心運作規則 (Purpose & Core Rules)

### 1. 專案目的
採用 **「無狀態 API + 前端 `temp_story` 託管」** 機制。後端成為極輕量的無狀態 AI 計算微服務，對話歷史由前端於本地區塊 (local_storage) 自行維護。

### 2. 核心運作規則
1. **單一主聊天視窗 (Single Active Chat Window)**：
   - 介面維持極簡清爽，使用者永遠在同一個主畫面中與米粒互動。
2. **前端「🌱 開啟新話題」機制**：
   - 聊天視窗角落提供 **`🌱 開啟新話題`** 按鈕。點擊後前端直接執行 `localStorage.removeItem('temp_story')` 將對話歷史與 UI 畫面歸零重新開始。
3. **前端 24 小時閒置自動清空 (24h Idle Timeout)**：
   - 前端每次成功發言時自動更新時間戳 `localStorage.setItem('last_update_time', Date.now())`。
   - 當使用者開啟或回到頁面時，前端計算 `(Date.now() - last_update_time) >= 24h`。若超過 24 小時，前端自動將主視窗對話 UI 與本地 `temp_story` **連同畫面一併清空**，恢復乾淨初始狀態。
4. **AI 推理記憶與長度限制 (Last 3 Messages)**：
   - 前端傳給後端的 `temp_story` **嚴格限制最多維持最近 3 則訊息**（超過 3 則的舊對話由前端自動 `shift()` 切掉），確保控制 Token 費用並防止注意力污染。


---

## 📌 二、 API 請求與回應合約設計 (Stateless API Contract)

因為後端沒有資料庫，每次發問時，前端會將當前使用者輸入 (`user_prompt`) 與本地的近 3 則歷史 (`temp_story`) 一併打包傳給後端：

### 1. 請求 (POST /companion/ask)

```json
{
  "user_prompt": "那如果換成炸雞腿呢？",
  "temp_story": [
    {
      "role": "user",
      "content": "水煮雞胸肉便當熱量多少？"
    },
    {
      "role": "assistant",
      "content": "水煮雞胸肉便當大約 450 大卡喔！"
    }
  ]
}
```

### 2. 回應 (JSON Response)

```json
{
  "success": true,
  "companion_reply": "炸雞腿便當大約 750 大卡，比水煮雞胸肉多出約 300 大卡喔！晚餐想配什麼蔬菜嗎？🌱",
  "intent_category": "nutrition_query",
  "meal_items": ["炸雞腿便當"]
}
```

---

## 📌 三、 系統架構與 ASCII 流程圖 (Architecture & ASCII Flowcharts)

```text
+------------------+         +--------------------+         +---------------------+         +----------------------+
|  前端 APP / Web  |         | Node.js Express    |         | OpenAI API          |         | Java Dietary Agent   |
| (localStorage)   |         | (companion-agent)  |         | (Stage 1 & Stage 3) |         | (營養計算服務)        |
+------------------+         +--------------------+         +---------------------+         +----------------------+
         |                             |                              |                             |
  1. 點擊「🌱 開啟新話題」             |                              |                             |
     (temp_story = [])                 |                              |                             |
  --------------------                 |                              |                             |
         |                             |                              |                             |
  2. POST /companion/ask               |                              |                             |
     (user_prompt + temp_story近3則)   |                              |                             |
  ------------------------------------>|                              |                             |
         |                             |                              |                             |
         |                             | 3. 呼叫 Stage 1 意圖/情緒診斷 (帶入 userPrompt + temp_story) |
         |                             |----------------------------------------------------------->|
         |                             |<-----------------------------------------------------------|
         |                             |    (取得 screening, emotion, dish_info_list)             |
         |                             |                              |                             |
         |                             | 4. (條件式) 呼叫 Java 營養計算                             |
         |                             |----------------------------------------------------------->|
         |                             |<-----------------------------------------------------------|
         |                             |    (取得 dietaryAgentResponse 營養建議)                    |
         |                             |                              |                             |
         |                             | 5. 呼叫 Stage 3 生成小芽對話 (帶入 userPrompt + temp_story + 營養數據)
         |                             |----------------------------------------------------------->|
         |                             |<-----------------------------------------------------------|
         |                             |    (取得 companion_reply 溫暖文字)                         |
         |                             |                              |                             |
  6. 回傳 JSON 結果                    |                              |                             |
     (companion_reply, intent)         |                              |                             |
  <------------------------------------|                              |                             |
         |                             |                              |                             |
  7. 前端將本次發問與小芽回應           |                              |                             |
     Append 寫入 temp_story            |                              |                             |
     (並保持 temp_story 最多 3 則)      |                              |                             |
  -----------------------------        |                              |                             |
```

---

## 📌 四、 根據討論經驗之「潛在風險診斷與前端防護」 (Risks & Safeguards)

採用前端 `temp_story` 託管與無狀態後端方案，依然能完善處理先前討論的 4 大關鍵問題：

### 1. 省略句與餐點比較的指涉模糊 (Ellipsis Disambiguation)
- **解決方案**：
  後端收到 `temp_story` 後，在 Step 3 呼叫 Stage 1 時，直接將 `temp_story` 當作背景上下文餵給 Stage 1 診斷器，並搭配 Response Schema Prompt 加強提示，即可 100% 精準識別代名詞與省略餐點。

### 2. 午夜跨日與體驗中斷 (Midnight Boundary Edge Case)
- **解決方案**：
  因為後端完全無狀態，午夜 00:00 發送請求**絕對不會被後端擋下或拋錯**。使用者在 23:59 聊到 00:01 體驗極度流暢。

### 3. Prompt 注意力污染與 Token 控管
- **解決方案**：
  前端在向 `temp_story` Append 新訊息時，執行防護邏輯：`if (temp_story.length > 3) temp_story.shift();`，永遠將傳給後端的歷史控制在 3 則以內。

### 4. 歷史訊息的 Role 格式與防污染清洗 (Role & Sanitization)
- **解決方案**：
  前端傳送前或後端接收後，僅保留 `role === 'user'` 與 `role === 'assistant'` 的物件，且對 `content` 做 `substring(0, 300)` 截斷，防範超長食譜文章與 Prompt 注入攻擊。

---

## 📌 五、 未來升級 TopicState (v7.0) 的銜接路徑

未來若要升級至全功能動態 `TopicState`：
- 前端僅需在 `temp_story` 中隨帶一個輕量的 `topic_state` 物件傳給後端。
- 後端無需改動 DB 架構，即可平滑升級支援主題追蹤！

---
*本規格說明書最後更新於 2026 年 8 月 27 日，專為 Companion Agent Version 7.0 前端託管與無狀態後端機制研發使用。*
