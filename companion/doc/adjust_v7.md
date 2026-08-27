# Companion Agent v7 調整與前端對接規格說明書 (adjust_v7.md)

本文件詳細列出 Companion Agent 升級至 v7 所需進行的修改條目，供團隊逐項確認後進行程式碼實作。

---

## 📌 一、 變更目標與背景 (Goals & Overview)

1. **Companion Agent 人設與名稱更新**：
   - 將飲食陪伴小精靈名稱統一由「小芽」修改為 **「米粒」**，包含 Prompt 角色宣告、能力邊界說明與 Few-Shot 對話範例。
2. **前後端草稿數據轉化與對接 (依據 [`frontend_adjust.md`](file:///c:/Users/User/Documents/Github_Repo/dietary_app/frontend_adjust.md))**：
   - Companion Agent (v6/v7) 後端回傳之結構化飲食草稿 Key 為 **`meal_items`**（一維平坦陣列 `[{ name, quantity, unit, meal_period }]`）。
   - Flutter 前端現行彈窗 UI 預期讀取按餐期分組之巢狀陣列 Key 為 **`meal_records`** (`[{ meal_period, meal_items }]`)。
   - 由前端 `DietService` 在接收層自動完成 Group By 轉化與向下相容，確保草稿彈窗 (`_showMealRecordDraftDialog`) 能順利觸發。

---

## 📌 二、 條列式修改清單 (Itemized Modifications for Review)

### 🔹 項目一：Companion Agent 後端人設與名稱變更 (LLM System Prompt)

- **目標檔案**：[`companion/companion_js/companion-llm.js`](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/companion-llm.js)
- **變更說明**：將 `REPLY_SYSTEM_PROMPT` 中所有稱呼與範例統一由「小芽」改為「米粒」。

| 條目編號 | 修改區域 / 行數 (約) | 現行內容 | 預計修改為 |
| :--- | :--- | :--- | :--- |
| **1.1** | Role & System Objective (L389) | `名字叫「小芽」（或「本精靈」）` | `名字叫「米粒」（或「本精靈」）` |
| **1.2** | Persona Scope (L396-398) | `小芽的唯一定位...` / `要求小芽處理...` | `米粒的唯一定位...` / `要求米粒處理...` |
| **1.3** | 軟化包裝原則 (L437) | `軟化為「小芽替你擔心」` | `軟化為「米粒替你擔心」` |
| **1.4** | Out-of-Scope 範例 (L456) | `想問小芽能不能...` / `小芽是專門...` | `想問米粒能不能...` / `米粒是專門...` |
| **1.5** | 情境 C 範例 (L468-470) | `userPrompt: "小芽，我這樣吃..."` / `有小芽陪伴你呢！小芽超級樂意...` | `userPrompt: "米粒，我這樣吃..."` / `有米粒陪伴你呢！米粒超級樂意...` |
| **1.6** | 情境 D 範例 (L482) | `小芽建議可以優先選...` | `米粒建議可以優先選...` |

---

### 🔹 項目二：Flutter 前端 Service 數據解析與結構轉化

- **目標檔案**：[`frontend/lib/services/diet_service.dart`](file:///c:/Users/User/Documents/Github_Repo/dietary_app/frontend/lib/services/diet_service.dart)
- **變更說明**：在 `sendCompanionUserPrompt` 方法中接收 `data['meal_items']` 一維陣列，並在 Service 層自動轉化為 UI 彈窗可用的 `meal_records` 分組巢狀陣列。

| 條目編號 | 變更區域 / 方法 | 具體修改內容 |
| :--- | :--- | :--- |
| **2.1** | `sendCompanionUserPrompt` (L560-569) | 提取後端回傳之 `data['meal_items']` 一維平坦陣列 (`List<dynamic>`)。 |
| **2.2** | Group By 轉化邏輯 | 遍歷 `meal_items`，依據 `meal_period`（如「早餐」、「午餐」等）進行 Group By 整理，生成相容現行 UI 的 `meal_records` 兩層巢狀 List。 |
| **2.3** | 回傳 Map 結構擴充 | 在回傳 Map 中同時包含 `meal_items` (原始一維陣列) 與 `meal_records` (轉化後分組陣列)，確保向上向下完整相容。 |

#### 💡 轉化前後 JSON 結構對照範例：

```json
// 後端 Companion Agent 回傳之 1D 一維平坦陣列 (meal_items)
{
  "success": true,
  "companion_reply": "太棒了！米粒已經為你整理好餐點草稿囉！✨",
  "intent_category": "meal_record",
  "meal_items": [
    { "name": "水煮蛋", "quantity": 2, "unit": "顆", "meal_period": "早餐" },
    { "name": "牛肉麵", "quantity": 1, "unit": "碗", "meal_period": "午餐" }
  ]
}

// 前端 DietService 轉化後供 UI 彈窗使用的相容 Map (meal_records)
{
  "success": true,
  "companion_reply": "太棒了！米粒已經為你整理好餐點草稿囉！✨",
  "intent_category": "meal_record",
  "meal_items": [ ... ],
  "meal_records": [
    {
      "meal_period": "早餐",
      "meal_items": [ { "name": "水煮蛋", "quantity": 2, "unit": "顆" } ]
    },
    {
      "meal_period": "午餐",
      "meal_items": [ { "name": "牛肉麵", "quantity": 1, "unit": "碗" } ]
    }
  ]
}
```

---

### 🔹 項目三：Flutter 前端 View 觸發驗證

- **目標檔案**：[`frontend/lib/views/home/home_view.dart`](file:///c:/Users/User/Documents/Github_Repo/dietary_app/frontend/lib/views/home/home_view.dart)
- **變更說明**：確認 `_handleMessage` 接收到 `res['meal_records']` 轉化後的非空 List 且意圖為 `meal_record` 時，順利自動彈出草稿視窗 `_showMealRecordDraftDialog`。

| 條目編號 | 變更區域 / 方法 | 具體確認內容 |
| :--- | :--- | :--- |
| **3.1** | `_handleMessage` (L654-658) | 確認 `intent == 'meal_record' && mealRecords.isNotEmpty` 條件判斷能順利觸發草稿彈窗。 |

---

## 📌 三、 驗證與測試計畫 (Verification & Checklist)

1. **陪伴名稱測試**：
   - 在陪伴對話中發送：「你是誰？」或「可以幫我寫 code 嗎？」。
   - 驗證 Companion Agent 回應自稱名稱為 **米粒**。
2. **飲食紀錄草稿彈窗測試**：
   - 在陪伴對話中發送：「`我早餐吃了 2 顆水煮蛋，午餐吃了 1 碗牛肉麵`」。
   - 驗證陪伴氣泡回應後，畫面自動跳出草稿彈窗。
   - 驗證草稿彈窗中正確將食物依 **「早餐」** (水煮蛋 2 顆) 與 **「午餐」** (牛肉麵 1 碗) 分卡片展示。
3. **儲存測試**：
   - 在草稿彈窗點擊「確認儲存」，驗證飲食紀錄成功儲存至後端資料庫。
