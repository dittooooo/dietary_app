# MAF Workflow 導入與 Companion 職責調整規格

## 1. 文件目的

本文件定義本次導入 Microsoft Agent Framework（MAF）的最小改動範圍。目標是在不改變既有飲食紀錄、營養查詢與飲食建議邏輯的前提下，新增 MAF Workflow 作為入口流程的分流與編排機制。

本次只移動流程責任，不重新設計既有業務規則、API 契約或 Agent prompt。料理名稱擷取、份量解析、餐別解析與料理名稱標準化，必須沿用現有 Agent 使用的處理方法與 prompt。

## 2. 改動目標

- 新增 MAF Workflow，作為所有使用者訊息的統一入口。
- 由 MAF Workflow 判斷使用者問題屬於一般閒聊、飲食紀錄或飲食建議。
- 將 companion agent intake 與 translation 功能般至 workflow 處理。當問題屬於飲食紀錄或飲食建議時，由 Workflow 直接呼叫既有 OpenAI API 設定，執行一次 intake 與 translation
- 不新增除了 MAF work flow 以外任何新的 Agent。
- 將 CompanionAgent 的職責縮減為最終自然語言回覆生成。
- 保留 DietaryAgent 與 NutritionistAgent 的既有處理邏輯。
- Agent 與 Agent、Workflow 與遠端 Agent 之間仍一律透過既有 API 溝通。

## 3. 目標架構

```text
使用者 / 前端
      |
      v
MAF Workflow
  |- 分流：CHAT / RECORD / ADVICE
  |- intake + normalization：直接呼叫 OpenAI API 一次
  |- 暫停等待前端確認
  |- 狀態管理、錯誤處理、重試
      |
      +--> CompanionAgent API：只負責最終回覆生成
      +--> DietaryAgent API：既有飲食紀錄業務邏輯
      +--> NutritionistAgent API：既有營養資料與建議邏輯
      +--> 既有資料庫 / 外部服務
```

MAF Workflow 是流程編排層，不取代既有 Agent 服務，也不取代服務間的 API 傳輸層。

## 4. 職責範圍

### 4.1 MAF Workflow

本次新增或移入 MAF Workflow 的責任：

- 接收前端傳入的使用者訊息與必要的 conversation/session identifier。
- 判斷意圖：
  - `CHAT`：一般閒聊或一般對話。
  - `RECORD`：要求記錄飲食。
  - `ADVICE`：要求飲食建議。
- 對 `RECORD` 與 `ADVICE` 執行一次 OpenAI API 呼叫，沿用 CompanionAgent 目前的 intake 與 translation prompt 和處理方法。
- 擷取料理名稱。
- 擷取份量；未提供時沿用現有預設值一份。
- 擷取餐別；沿用目前早餐、午餐、晚餐、其他的判斷規則。
- 將店家或特殊料理名稱標準化；標準化規則與 prompt 必須沿用現有 CompanionAgent 行為。
- 將結果依照不同下游用途轉換為既有 API 所需的資料格式；前端 `meal_items`、DietaryAgent 的 `dish_info_list` 與飲食紀錄 API 的 `DietRecordRequest` 不視為同一種資料格式。
- 在飲食紀錄流程中，將待確認資料傳回前端。
- 等待前端回傳確認或修改結果。
- 管理流程狀態、錯誤處理、重試與必要的 checkpoint/resume。
- 根據流程結果呼叫 CompanionAgent 產生最後回覆。

### 4.2 CompanionAgent

本次調整後，CompanionAgent 只負責：

- 接收已完成處理的結果與回覆所需上下文。
- 將結果轉換成使用者可理解的自然語言。
- 依照目前 CompanionAgent 的回覆 prompt、語氣與格式產生最終回覆。

CompanionAgent 不再負責：

- 主要流程分流。
- 飲食紀錄或飲食建議流程控制。
- intake。
- 份量與餐別解析。
- 料理名稱 translation
- 決定是否需要等待使用者確認。

注意：本次不是重寫 CompanionAgent 的回覆邏輯。現有回覆 prompt 與生成行為應盡量原封不動保留，只移除已移交給 Workflow 的 intake/normalization 路徑。

### 4.3 DietaryAgent

保留現有實作與業務邏輯，不在本次修改：

- 飲食紀錄資料驗證。
- 營養資料取得或整合流程。
- 資料庫寫入邏輯。
- 既有 API endpoint、request schema 與 response schema，除非為接收 Workflow 已確認資料而有必要增加相容欄位。

### 4.4 NutritionistAgent

保留現有實作與業務邏輯，不在本次修改：

- 料理營養成分查詢。
- 營養建議產生。
- 既有 prompt、規則、資料來源與查詢流程。
- 既有 API endpoint、request schema 與 response schema。

## 5. 三種流程規格

### 5.1 一般閒聊：CHAT

```text
前端
  -> MAF Workflow
  -> CompanionAgent API
  -> MAF Workflow
  -> 前端
```

規則：

1. MAF Workflow 判定意圖為 `general_chat`。
2. 不執行 intake/translation OpenAI 呼叫。
3. 將原始使用者訊息與必要 conversation context 傳給 CompanionAgent。
4. CompanionAgent 產生回覆。
5. Workflow 將回覆傳回前端。

### 5.2 飲食紀錄：RECORD

```text
前端
  -> MAF Workflow：判斷 RECORD
  -> OpenAI API：既有 intake + translation prompt
  -> 前端：顯示待確認資料
  -> MAF Workflow：接收確認/修改
  -> DietaryAgent API
  -> NutritionistAgent API（依既有 DietaryAgent 流程）
  -> 資料庫（依既有 DietaryAgent 流程）
  -> CompanionAgent API
  -> 前端
```

規則：

1. Workflow 判定意圖為 `meal_record`。
2. Workflow 直接呼叫 OpenAI API 一次，完成目前 CompanionAgent 的 intake 與 normalization。
3. Workflow 將相容於目前前端的 `meal_items` 結構回傳前端供使用者確認。
4. 未確認前不得呼叫會寫入資料庫的流程。
5. 使用者確認或修改後，Workflow 將確認後資料透過 API 傳給 DietaryAgent。
6. DietaryAgent 後續呼叫 NutritionistAgent 並寫入資料庫的方式保持不變。
7. 完成後由 Workflow 呼叫 CompanionAgent 產生最終回覆。

### 5.3 飲食建議：ADVICE

```text
前端
  -> MAF Workflow：判斷 ADVICE
  -> OpenAI API：既有 intake + normalization prompt
  -> NutritionistAgent API
  -> CompanionAgent API
  -> 前端
```

規則：

1. Workflow 判定意圖為 `dish_advice`。
2. Workflow 直接呼叫 OpenAI API 一次，完成目前 CompanionAgent 的料理名稱擷取、份量解析與名稱標準化。
3. Workflow 將處理結果透過既有 API 傳給 NutritionistAgent。
4. NutritionistAgent 產生飲食建議的邏輯保持不變。
5. Workflow 將 NutritionistAgent 結果傳給 CompanionAgent。
6. CompanionAgent 只負責產生最終自然語言回覆。

## 6. OpenAI API 呼叫規格

### 6.1 呼叫位置

OpenAI API 呼叫由 MAF Workflow 的 intake/translation step 執行，不建立新的 Agent 服務。

```text
MAF Workflow
  -> OpenAI client
  -> OpenAI API
  -> 結構化 intake/translation result
```

API key 必須由後端環境變數或既有 secret 管理機制提供，不得由前端傳入或寫入程式碼。

### 6.2 Prompt 原則

- 直接沿用目前 CompanionAgent 的 intake/analysis prompt。
- 直接沿用目前 CompanionAgent 的 translation prompt。
- 若目前兩個 prompt 已在同一次呼叫中完成，則原封不動移至 Workflow。
- 若目前是同一個 prompt 中完成，維持同一個 prompt，避免改變模型行為。
- 不因導入 MAF 而新增新的判斷規則、料理分類規則或預設值。
- 只允許為了適應結構化輸出而增加 JSON schema 或輸出格式約束；欄位語意與判斷規則不得改變。

目前 Companion 的實際流程是先以 Responses API 執行意圖與 `meal_items` 分析，再以 translation prompt 執行料理名稱翻譯。因此本文件中的「一次執行 intake/translation」指 Workflow 的一次處理流程，不得在未明確驗證的情況下把兩個既有模型階段合併成單一 HTTP request；若合併，將可能改變既有 prompt、輸出與錯誤降級行為。

### 6.3 資料格式與轉換規格

本次不得將所有流程強制套用成同一個 JSON schema。目前系統有三種不同用途的資料格式，MAF Workflow 必須在流程邊界進行明確轉換。

#### 6.3.1 MAF Workflow / 前端飲食草稿格式

`RECORD` 流程的 OpenAI intake 結果，以及傳回前端供確認的資料，必須沿用目前 Companion 的 `screening` 結構，使用 `meal_items` 一維陣列：

```json
{
  "intent_category": "meal_record",
  "question_type": "not_applicable",
  "meal_items": [
    {
      "name": "水煮蛋",
      "quantity": 2,
      "unit": "顆",
      "meal_period": "早餐"
    }
  ],
  "query_date": null
}
```

欄位規則：

- `intent_category` 沿用目前值：`dish_advice`、`meal_record`、`general_chat`、`meal_query`。
- `meal_items` 必須是陣列，每筆包含 `name`、`quantity`、`unit`、`meal_period`。
- `quantity` 是 `meal_items` 項目內的份數；沒有提供時沿用目前預設值 `1`。
- `meal_period` 沿用目前中文餐期值：`早餐`、`中餐`、`晚餐`、`其他`。
- `query_date` 沿用目前 Companion 的日期欄位；沒有日期時為 `null`。
- 非 `dish_advice` 的 `question_type` 沿用現有規則使用 `not_applicable`。

前端確認流程目前是依照 `intent_category == "meal_record"` 且 `meal_items` 不為空來顯示確認介面，因此本次不新增 `needs_confirmation` 作為必要欄位。

#### 6.3.2 飲食建議用 DietaryAgent API 格式

`ADVICE` 流程在呼叫既有 DietaryAgent API 前，必須將 Workflow 的 intake 結果轉換為目前 API 接受的格式：

```json
{
  "question": "我晚餐吃牛肉麵，請給我建議",
  "question_type": "single_dish",
  "dish_info_list": [
    {
      "dish_name": "牛肉麵",
      "amount": 1
    }
  ]
}
```

必要規則：

- `dish_info_list` 必須是陣列，不是以料理名稱為 key 的物件。
- 每筆資料使用 `dish_name` 與 `amount`，不是 `name` 與 `quantity`。
- `question_type` 沿用目前值：`single_dish` 或 `dish_comparison`；沒有具體料理時沿用 `unknown` 並依既有流程處理。
- 使用者未提供份量時，`amount` 使用 `1`。
- 若目前 translation 將店家料理名稱轉成資料庫標準名稱，翻譯後名稱放在 `dish_info_list[].dish_name`。

為保持目前行為，原始名稱與 translation 後名稱的用途必須分開：

```text
meal_items[].name                  保留使用者原始料理名稱，供前端顯示
dish_info_list[].dish_name         使用 translation 後名稱，供 DietaryAgent 查詢
meal_items[].quantity              對應 dish_info_list[].amount
```

#### 6.3.3 飲食紀錄 API 格式

飲食紀錄確認後，若流程需要呼叫既有 `/api/diet-records`，必須使用既有 `DietRecordRequest` 格式，而不是直接將 6.3.1 的 intake JSON 傳入：

```json
{
  "dish_name": "水煮蛋",
  "amount": 2,
  "meal_type": "BREAKFAST",
  "record_date": "2026-09-05",
  "calories": 0,
  "protein": 0,
  "fat": 0,
  "carbohydrates": 0
}
```

欄位轉換規則：

```text
meal_items[].name          -> dish_name
meal_items[].quantity      -> amount
meal_items[].meal_period   -> meal_type
query_date                -> record_date
```

`meal_type` 是資料庫紀錄 API 的欄位，允許值依既有後端規則處理；它不應取代前端草稿格式中的 `meal_period`。營養欄位必須沿用現有 DietaryAgent/營養流程提供的結果，不能由 Workflow 任意估算或新增業務規則。

#### 6.3.4 不使用的欄位

以下欄位不是目前系統的既有共同契約，不應列為 MAF intake 的必要輸出：

- 頂層 `intent`。
- `dish_name_original`。
- `dish_name_normalized`。
- 頂層 `quantity`。
- `needs_confirmation`。
- `confidence`。

如果未來確實需要追蹤信心分數或確認狀態，應另行定義 Workflow 內部狀態欄位，不得假設前端或既有 Agent API 已能接受這些欄位。

## 7. API 邊界

本次保留以下通訊原則：

- MAF Workflow 與 CompanionAgent 使用 API。
- MAF Workflow 與 DietaryAgent 使用 API。
- MAF Workflow 與 NutritionistAgent 使用 API。
- DietaryAgent 與 NutritionistAgent 的既有 API 呼叫方式保持不變。
- 不因導入 MAF 而改用 in-process direct call。
- 不要求本次導入 A2A、MCP、message queue 或其他新通訊協定。
- API request/response 欄位以既有契約為主；如需調整，必須保持向後相容。
- Workflow 內部可以使用自己的狀態物件，但送出 API 前必須依 6.3 節轉換成既有契約。
- 飲食紀錄確認後，應呼叫目前實際承擔紀錄寫入的既有 API；若現行流程使用 `/api/diet-records`，不得改送 `/dietary-agent/ask`。

## 8. 狀態與確認流程

Workflow 至少需要區分以下狀態：

```text
RECEIVED
  -> ROUTED
  -> INTAKE_COMPLETED
  -> WAITING_CONFIRMATION       # 僅 RECORD
  -> CONFIRMED
  -> DOWNSTREAM_PROCESSING
  -> RESPONSE_GENERATING
  -> COMPLETED
```

錯誤狀態至少包括：

```text
INTAKE_FAILED
DOWNSTREAM_API_FAILED
CONFIRMATION_EXPIRED
RESPONSE_GENERATION_FAILED
```

重試規則：

- OpenAI 呼叫失敗時可重試，但必須限制次數。
- 遠端 API 暫時性錯誤時可重試，但必須避免資料庫重複寫入。
- DietaryAgent 的資料庫寫入必須具備 idempotency 或等效的重複請求保護。
- 使用者確認後恢復 Workflow 時，不應重新執行已成功完成的 intake step。

## 9. 明確不在本次範圍

- 不修改 DietaryAgent 的飲食紀錄業務邏輯。
- 不修改 NutritionistAgent 的營養查詢與建議邏輯。
- 不重新設計或改寫既有 Agent prompt。
- 不新增 IntakeAgent 或 NormalizationAgent。
- 不改變既有 API 服務部署方式。
- 不將 API 改成 A2A、MCP、gRPC 或 message queue。
- 不改變前端確認畫面的業務意義；只增加 Workflow 的暫停與恢復串接。
- 不新增資料庫表格或改變既有資料庫欄位，除非現有確認流程無法保存必要的 Workflow 狀態。
- 不把所有邏輯改成由 LLM 自由決策；分流與資料寫入仍需受 Workflow 與既有業務規則控制。

## 10. 驗收條件

### 功能驗收

- 一般閒聊只會進入 CompanionAgent 回覆流程，不會呼叫 intake/translation
- 飲食紀錄會呼叫一次 Workflow 內的 OpenAI intake/translation step。
- 飲食紀錄在使用者確認前不會寫入資料庫。
- 飲食紀錄確認後仍會依既有流程呼叫 DietaryAgent 與 NutritionistAgent。
- 飲食建議會呼叫一次 Workflow 內的 OpenAI intake/translation step。
- 飲食建議仍使用既有 NutritionistAgent 邏輯。
- CompanionAgent 只負責最終回覆生成。
- 三個 Agent 之間仍透過 API 溝通。

### 行為相容性

- 相同輸入在移轉前後，`intent_category`、`meal_items` 的料理名稱/份量/單位/餐期，以及送往下游 API 的 `dish_info_list` 結果應保持一致；若有差異，必須能追溯到模型版本、prompt 或輸出格式變更。
- 既有 DietaryAgent 與 NutritionistAgent 的 response 行為不應因 MAF 導入而改變。
- 既有 CompanionAgent 的最終回覆 prompt、語氣與格式應保持一致。

### 技術驗收

- API key 不出現在前端、版本控制或 log 中。
- OpenAI API、既有 Agent API 的錯誤可被 Workflow 捕捉並回傳一致的錯誤狀態。
- Workflow 可在等待確認後恢復執行。
- 重試不會造成重複飲食紀錄。
- 可透過 log 或 tracing 區分每次 Workflow run、OpenAI 呼叫與下游 API 呼叫。

## 11. 實作備註

MAF Workflow 可以使用圖形化 Workflow API 或 Python 的 Functional Workflow API 實作。若使用 Python Functional Workflow，intake/translation 應包成具備 step 邊界的函式，以便在確認等待或 checkpoint 恢復時避免重複呼叫模型。若使用 .NET，則以 WorkflowBuilder 與 typed executor 實作相同的流程邊界。

本次實作的核心不是重新建立 Agent，而是把目前 CompanionAgent 中已存在的兩段處理移到 Workflow 的模型呼叫 step，並保留既有 prompt、資料格式與下游 API 行為。
