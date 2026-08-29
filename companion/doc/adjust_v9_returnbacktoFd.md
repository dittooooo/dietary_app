# Companion Agent Version 9.0 歷史飲食紀錄查詢與前端卡片觸發規格說明書 (adjust_v9_returnbacktoFd.md)

本說明書為 **Companion Agent (米粒)** 升級至 **Version 9.0** 之前端觸發 MVP 規格說明書。本版本採用與 `meal_record` 相同之**「後端解析意圖/日期，前端接手觸發 UI 卡片 (Decoupled Frontend-Driven Pattern)」**設計哲學，確保 Companion Agent 架構輕量、低延遲，並提供最佳的使用者介面體驗。

---

## 📌 一、 升級背景與核心設計哲學 (Design Philosophy)

在 Companion Agent 現有架構中，飲食紀錄功能 (`meal_record`) 採用了非常成功的解耦模式：
* **Companion Agent (Node.js)** 專注做 **自然語言處理**（解析出食物草稿 `meal_items`），不直接寫入資料庫。
* **前端 (App/Web)** 接收到 `meal_items` 草稿後，彈出確認 UI 卡片，由前端向 Java 後端發送存檔請求。

Version 9.0 的 **歷史飲食紀錄查詢 (`meal_query`)** 延續此一優良模式：
1. 使用者提問（例：「我 6/19 吃了什麼？」或「我昨天晚餐吃什麼？」）。
2. Companion Agent 專注解析出**目標日期 `query_date`**（如 `2026-06-19`），並回傳給前端。
3. 前端接收到 `query_date` 後，發送 API 請求向 Java 後端獲取該日飲食資料，並在對話介面中**直接彈出/渲染原生的飲食紀錄卡片**。
4. **無需中間確認**：查詢為讀取操作 (Read)，不破壞資料庫，問完直接彈出卡片給予使用者最順暢的即時體驗。

---

## 📌 二、 Version 9.0 MVP 核心規格細節 (MVP Specifications)

### 1. 規格一：Stage 1 意圖與單一日期解析 (`query_date`)

* **意圖分類新增**：`meal_query`
* **基準時間注入**：後端發送 Stage 1 LLM 請求時，自動帶入伺服器當前日期（如：`Current Date: 2026-08-29`），以便 LLM 推算「昨天」、「前天」等相對詞彙。
* **解析欄位**：僅需單一日期欄位 `query_date`（標準 ISO 格式 `YYYY-MM-DD`）。

#### Stage 1 LLM 輸出範例：
```json
{
  "should_handle": true,
  "intent_category": "meal_query",
  "query_date": "2026-06-19",
  "confidence": 0.95
}
```

---

### 2. 規格二：Companion Agent 秒回與 API 回應合約 (Response Contract)

Companion Agent 接收到 Stage 1 解析結果後，跳過複雜的後端 DB 查詢與 Stage 3 冗長 Prompt，直接回傳帶有 `query_date` 的標準 JSON 給前端：

#### HTTP POST `/companion/ask` 回應範例：
```json
{
  "success": true,
  "companion_reply": "幫你找到 6/19 號的飲食紀錄囉！請看下方卡片✨",
  "intent_category": "meal_query",
  "query_date": "2026-06-19",
  "meal_items": [],
  "dietary_agent_error": null
}
```

---

### 3. 規格三：前端原生卡片觸發流程 (Frontend Workflow)

1. **收到 Companion 回應**：前端檢查 `intent_category === "meal_query"` 且 `query_date` 有值。
2. **渲染對話泡泡**：呈現米粒的親切回覆訊息（`companion_reply`）。
3. **打 Java API 渲染卡片**：前端持 `query_date` 自動發送 HTTP 請求（如 `GET /api/diet-records?date=2026-06-19`）獲取紀錄，並渲染包含早餐、午餐、晚餐、點心分頁的原生 UI 卡片。

---

## 📌 三、 邊界情境 (Edge Cases) 處置規則

| 邊界情境 | 使用者輸入範例 | Companion 處理邏輯 | 前端 UI 處理 |
| :--- | :--- | :--- | :--- |
| **一般日期查詢** | 「我 6/19 號吃了什麼？」 | 解析 `query_date: "2026-06-19"` | 打 API 撈取 6/19 資料並顯示卡片 |
| **相對時間查詢** | 「我昨天吃了什麼？」 | 解析 `query_date: "2026-08-28"` (以 Server 日期推算) | 打 API 撈取昨天資料並顯示卡片 |
| **未來日期查詢** | 「我明天吃了什麼？」 | LLM 解析出 `query_date > today` 時，米粒親切提醒：「未來的餐點本精靈還無法預知捏～😉」 | `query_date: null`，前端僅顯示對話泡泡，不觸發卡片 |
| **無日期資訊** | 「看我以前吃什麼」 | LLM 判定 `query_date: null`，米粒詢問：「你想看哪一天的飲食紀錄呢？」 | 前端僅顯示對話泡泡，引導使用者提供日期 |

---

## 📌 四、 程式碼變更指引 (Code Modification Steps)

### 1. [`companion_js/companion-llm.js`](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-llm.js) **[MODIFY]**
* 更新 `ANALYSIS_SYSTEM_PROMPT`：加入 `meal_query` 分類與 `query_date` 提取說明。
* 在 Tool Specification (Function Calling) 的 `screen_user_request` 欄位中新增 `query_date` (string)。
* `sanitizeScreening` 函數補上 `query_date` 的防呆預設值 (`null`)。

### 2. [`companion_js/companion-agent-services.js`](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-agent-services.js) **[MODIFY]**
* 在 `runOpenAIFlow` 分流中，若 `intent_category === "meal_query"`，直接回傳不需呼叫 Java 諮詢 API。
* 在 `getCompanionReply` 中，針對 `meal_query` 加上秒回罐頭/簡短溫暖對話：如「幫你找到 X月X號 的飲食紀錄囉！請看下方卡片✨」。

### 3. [`companion_js/companion-agent.js`](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-agent.js) **[MODIFY]**
* 回傳 JSON 加上 `query_date: openAiResult.screening.query_date || null` 欄位。

---

## 📌 五、 方案優勢對比總結

| 維度 | 後端抓取全包方案 | 本 MVP 方案（前端觸發卡片） ⭐ |
| :--- | :--- | :--- |
| **架構一致性** | 與 `meal_record` 模式不同 | **與 `meal_record` 100% 一致** |
| **UI/UX 呈現** | 純文字聊天泡泡（排版受限） | **原生 UI 卡片/畫布（分頁清晰好看）** |
| **Companion Agent 複雜度** | 高（需串 DB API + LLM 二次重組） | **極低（只需 Stage 1 時間解析）** |
| **回應速度 (Latency)** | 較慢 (2-4 秒) | **極快 (< 1 秒)** |

---
*文件建立時間：2026 年 8 月 29 日 | Companion Agent Version 9.0 (returnbacktoFd) 規格說明書*
