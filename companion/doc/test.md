# Path: c:\Users\User\Documents\Github_Repo\dietary_app\companion\doc\test.md
# Description: Guide and instructions for testing Companion Agent API endpoints

# Companion Agent 測試與驗證指南

本文件引導您如何啟動服務，並使用命令列工具進行 API 測試，以驗證意圖分析、情緒同理、料理抽取以及與 Dietary Agent 的串接。

---

## 1. 測試前置作業

在進行測試之前，請確保您的本機環境已完成以下步驟：

1. **安裝相依套件**：
   打開終端機（PowerShell 或 CMD），定位到專案目錄並執行：
   ```bash
   # npm: Node Package Manager (Node 套件管理器)
   # install: 依據 package.json 檔案中的設定，自動下載並安裝本專案所需的所有第三方套件 (如 express, cors, dotenv)
   npm install
   ```
2. **設定環境變數**：
   確認您的 `c:\Users\User\Documents\Github_Repo\dietary_app\companion\companion_js\.env` 檔案內已經設定好正確的 `OPENAI_API_KEY`。
3. **啟動 Companion Agent 伺服器**：
   在終端機中執行：
   ```bash
   # start: 執行 package.json 中 "scripts" 設定的 "start" 腳本，即在背景執行 "node companion-agent.js" 來啟動伺服器
   npm start
   ```
   * 看到主畫面上顯示 `Companion Agent API listening on port 3000` 即代表伺服器啟動成功。
   * **注意**：測試時請保持此終端機視窗開啟，不要關閉。

---

## 2. 關於本地測試的常見問題

### 2.1 測試時我必須同時開啟同學的 Dietary Agent 嗎？
* **不需要強求**：因為我們的 Companion Agent 具備「連線容錯 (Try-Catch)」機制。
* 如果您只開了您的 Companion Agent，沒開同學的服務：
  * API 依然可以正常運作。它會完成 OpenAI 的語意分析、情緒分析與料理抽取。
  * 回傳的 JSON 當中，`success` 會是 `true`，而 `dietary_agent_error` 會記錄連線失敗訊息，`companion_reply` 則會提供保底的引導回覆。
  * 這讓您可以**獨立測試自己的程式碼**。
* 如果同學的服務也開了，且您在 `.env` 中設定了她的 `DIETARY_AGENT_API_URL`：
  * 系統便會完整連通，您的對話中會包含她所產出的專業飲食建議！

---

## 3. 三大測試情境（條列式指引）

您可以使用 `curl` 指令在**另一個新的終端機視窗**進行測試。 

### 🛠️ 情境一：一般飲食問題且帶有焦慮情緒 (同理心 + 料理抽取測試)
此情境用來驗證模型是否能正確分析「焦慮情緒」並「擷取兩個料理（炸雞、拉麵）」，且組裝三元素 Payload。

* **輸入 (Request JSON)**
  ```json
  {
    "message": "我今天中午吃炸雞了，晚上還能吃拉麵嗎？我有點焦慮。",
    "user_profile": {
      "height_cm": 165,
      "weight_kg": 60,
      "gender": "female",
      "age": 21
    }
  }
  ```

* **測試指令 (curl)**
  ```bash
  # curl: 命令列傳輸工具，用來發送 HTTP 請求
  # -X POST: 指定使用 HTTP POST 方法來提交資料
  # http://localhost:3000/companion/ask: 您本機啟動的 Companion Agent API 接口網址
  # -H "Content-Type: application/json": 設定 Headers，告訴伺服器我們寄過去的資料格式是 JSON
  # -d "{\"message\"...}": 帶有反斜線轉義的雙引號字串，為我們要發送的 JSON 數據主體 (Payload)
  curl -X POST http://localhost:3000/companion/ask \
  -H "Content-Type: application/json" \
  -d "{\"message\":\"我今天中午吃炸雞了，晚上還能吃拉麵嗎？我有點焦慮。\",\"user_profile\":{\"height_cm\":165,\"weight_kg\":60,\"gender\":\"female\",\"age\":21}}"
  ```

* **預期輸出結果 (Response JSON)**
  ```json
  {
    "success": true,
    "llm_fallback_used": false,
    "screening": {
      "should_handle": true,
      "intent_category": "dish_advice",
      "question_type": "single_dish",
      "requires_more_context": false,
      "missing_information": [],
      "confidence": 0.95,
      "dishes": ["炸雞", "拉麵"]
    },
    "emotion": {
      "primary_emotion": "anxiety",
      "valence": "negative",
      "urgency": "medium",
      "needs_empathy": true,
      "companion_tone": "calm",
      "evidence": ["焦慮"]
    },
    "dietary_agent_request": {
      "question": "我今天中午吃炸雞了，晚上還能吃拉麵嗎？我有點焦慮。",
      "question_type": "single_dish",
      "dish_names": ["炸雞", "拉麵"]
    },
    "dietary_agent_response": null,
    "dietary_agent_error": "fetch failed",
    "companion_reply": "我有注意到你現在有點在意這次的選擇，先不用太緊張喔。❤️\n已成功記錄您的問題，正在為您尋求最佳飲食建議。"
  }
  ```

---

### 🛠️ 情境二：料理比較問題 (問題分類與雙實體測試)
此情境用來驗證模型是否能將問題歸類為比較型 (`dish_comparison`)，並擷取多個料理。

* **輸入 (Request JSON)**
  ```json
  {
    "message": "牛肉麵跟水餃哪一個熱量比較高？",
    "user_profile": {
      "height_cm": 165,
      "weight_kg": 55
    }
  }
  ```

* **測試指令 (curl)**
  ```bash
  # curl: 發送 HTTP 請求
  # -X POST: 使用 POST 方法
  # -H: 指定傳送的格式為 JSON 格式
  # -d: 夾帶要比較的內容「牛肉麵跟水餃」，以及使用者的基本身高體重
  curl -X POST http://localhost:3000/companion/ask \
  -H "Content-Type: application/json" \
  -d "{\"message\":\"牛肉麵跟水餃哪一個熱量比較高？\",\"user_profile\":{\"height_cm\":165,\"weight_kg\":55}}"
  ```

* **預期輸出結果 (Response JSON)**
  ```json
  {
    "success": true,
    "llm_fallback_used": false,
    "screening": {
      "should_handle": true,
      "intent_category": "dish_advice",
      "question_type": "dish_comparison",
      "requires_more_context": false,
      "missing_information": [],
      "confidence": 0.98,
      "dishes": ["牛肉麵", "水餃"]
    },
    "emotion": {
      "primary_emotion": "curious",
      "valence": "neutral",
      "urgency": "low",
      "needs_empathy": false,
      "companion_tone": "neutral",
      "evidence": []
    },
    "dietary_agent_request": {
      "question": "牛肉麵跟水餃哪一個熱量比較高？",
      "question_type": "dish_comparison",
      "dish_names": ["牛肉麵", "水餃"]
    },
    "dietary_agent_response": null,
    "dietary_agent_error": "fetch failed",
    "companion_reply": "我先幫您整理這次的飲食建議：\n已成功記錄您的問題，正在為您尋求最佳飲食建議。"
  }
  ```

---

### 🛠️ 情境三：醫療敏感詞過濾 (Pre-check 安全攔截測試)
此情境驗證本地防線是否發揮作用：偵測到醫療詞時，強制攔截並不呼叫後端。

* **輸入 (Request JSON)**
  ```json
  {
    "message": "這個降血糖藥我應該怎麼服用？請幫我診斷。"
  }
  ```

* **測試指令 (curl)**
  ```bash
  # curl: 發送 HTTP 請求
  # -X POST: 使用 POST 方法
  # -H: 指定 JSON 傳送格式
  # -d: 夾帶包含「降血糖藥」、「診斷」等醫療字詞的敏感問句
  curl -X POST http://localhost:3000/companion/ask \
  -H "Content-Type: application/json" \
  -d "{\"message\":\"這個降血糖藥我應該怎麼服用？請幫我診斷。\"}"
  ```

* **預期輸出結果 (Response JSON)**
  ```json
  {
    "success": true,
    "llm_fallback_used": false,
    "screening": {
      "should_handle": false,
      "intent_category": "medical_out_of_scope",
      "question_type": "unknown",
      "requires_more_context": false,
      "missing_information": [],
      "confidence": 0.8,
      "dishes": []
    },
    "emotion": {
      "primary_emotion": "neutral",
      "valence": "neutral",
      "urgency": "medium",
      "needs_empathy": false,
      "companion_tone": "neutral",
      "evidence": []
    },
    "dietary_agent_request": null,
    "dietary_agent_response": null,
    "dietary_agent_error": null,
    "companion_reply": "這類問題比較接近醫療診斷或治療判斷，我目前不能直接替代專業醫療建議。建議您諮詢醫生或合格的醫療專家喔。"
  }
  ```

---

## 4. Windows PowerShell 專用指令

若您使用的是 Windows 的 PowerShell，因為雙引號解析問題，使用傳統的 `curl` 指令可能會發生格式錯誤。請改用以下 **PowerShell 專用指令** 進行測試：

### PowerShell 測試指令 - 情境一：一般飲食問題且帶有焦慮情緒
```powershell
# 1. 建立一個包含請求參數 (message 與 user_profile) 的雜湊表 (Hashtable)
$body = @{
    message = "我今天中午吃炸雞了，晚上還能吃拉麵嗎？我有點焦慮。"
    user_profile = @{
        height_cm = 165
        weight_kg = 60
        gender = "female"
        age = 21
    }
} | ConvertTo-Json -Depth 4 -Compress # 2. 將這個雜湊表物件序列化轉換成壓縮後的 JSON 字串

# 3. 將 JSON 字串轉成 UTF-8 位元組陣列，防止中文字在 PowerShell 中傳輸時變成問號亂碼
$bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)

# 4. 使用 PowerShell 內建的 Invoke-RestMethod 工具發送 POST 請求
# -Uri: 後端 API 網址
# -Method: 指定發送的方法為 Post
# -Body: 帶入轉好 UTF-8 的位元組資料
# -ContentType: 指定傳送的格式為 JSON 且強制宣告 UTF-8 編碼
Invoke-RestMethod -Uri "http://localhost:3000/companion/ask" -Method Post -Body $bodyBytes -ContentType "application/json; charset=utf-8"
```

### PowerShell 測試指令 - 情境二：料理比較問題
```powershell
# 1. 建立一個包含請求參數 (message 與 user_profile) 的雜湊表 (Hashtable)
$body = @{
    message = "牛肉麵跟水餃哪一個熱量比較高？"
    user_profile = @{
        height_cm = 165
        weight_kg = 55
    }
} | ConvertTo-Json -Depth 4 -Compress

# 2. 將 JSON 字串轉成 UTF-8 位元組陣列，防止中文字在 PowerShell 中傳輸時變成問號亂碼
$bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)

# 3. 使用 PowerShell 內建的 Invoke-RestMethod 工具發送 POST 請求
Invoke-RestMethod -Uri "http://localhost:3000/companion/ask" -Method Post -Body $bodyBytes -ContentType "application/json; charset=utf-8"
```

### PowerShell 測試指令 - 情境三：醫療敏感詞過濾
```powershell
# 1. 建立一個包含請求參數 (message) 的雜湊表 (Hashtable)
$body = @{
    message = "這個降血糖藥我應該怎麼服用？請幫我診斷。"
} | ConvertTo-Json -Depth 4 -Compress

# 2. 將 JSON 字串轉成 UTF-8 位元組陣列，防止中文字在 PowerShell 中傳輸時變成問號亂碼
$bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)

# 3. 使用 PowerShell 內建的 Invoke-RestMethod 工具發送 POST 請求
Invoke-RestMethod -Uri "http://localhost:3000/companion/ask" -Method Post -Body $bodyBytes -ContentType "application/json; charset=utf-8"
```

如果您不想在命令列打字，推薦使用圖形化介面工具如 **Postman** 或是 VS Code 的 **Thunder Client** 擴充套件，將 URL 設為 `POST http://localhost:3000/companion/ask`，並把 `Request JSON` 貼進 Body 內發送即可！

---

## 5. 與 Dietary Agent (Java / Spring Boot) 連線測試準備

根據您同學提供的 Controller 程式碼，對方的服務是基於 **Java / Spring Boot** 且整合了 **Spring Security 認證機制**。要順利進行兩者連線測試，請進行以下準備：

### 5.1 檢查並設定對接網址
1. **詢問同學的服務網址**：確認她的專案啟動在本地的哪一個埠口（例如 `http://localhost:8080`）。
2. **更新環境設定**：打開您的 **[.env](file:///c:/Users/User/Documents/Github_Repo/dietary_app/companion/companion_js/.env)**，將 `DIETARY_AGENT_API_URL` 設定為她的網址。例如：
   ```env
   DIETARY_AGENT_API_URL=http://localhost:8080
   ```

### 5.2 關鍵安全認證處理 (Spring Security)
您同學的程式碼中有一行關鍵邏輯：
```java
String email = SecurityContextHolder.getContext().getAuthentication().getPrincipal().toString();
```
### TODO: Token:前端連上後端登入成功後，後端所發回的 Token。因為目前驗證為兩台後端伺服器對接，沒有跑手機 App 登入流程，所以目前沒有這條手環（Token）。
這代表該 API 受到**身分認證保護**。如果我們直接送出請求，對方伺服器會因為沒有 Token 而回傳 **401 Unauthorized (未授權)**，或者因為找不到 anonymousUser 而噴出 `使用者不存在` 錯誤。

**解決對策（二選一）**：
* **對策 A（推薦測試方法）**：請同學在她的 Spring Security 設定檔（通常是 `SecurityConfig.java`）中，暫時將 `/api/dietary/ask-weekly-analysis` 路徑設定為免驗證放行（`permitAll()`），方便你們在本地開發階段進行無驗證對接測試。
### TODO: 將 /api/dietary/** 的 Security 規則暫時改成 permitAll()，這樣 our app (frontend) 才能不需要 Token 就能順利串接，之後前後端正式連線，必須要改回來。
### 已更動後端 securityconfig.java :                        
#### 開發階段暫時放行，方便本地無驗證對接測試。
####  .requestMatchers("/api/dietary/ask-weekly-analysis").permitAll()
####  .requestMatchers("/api/dietary/**").authenticated()

* **對策 B（正式對接方法）**：如果必須認證，您需要向同學索取一個有效的**測試 Token (如 JWT Token)**，並在 `Companion/companion-agent-services.js` 的 `callDietaryAgent` 函數中的 `headers` 加上該 Token（例如：`"Authorization": "Bearer <同學給的Token>"`）。

### 5.3 確認測試資料庫中存在使用者資料
### TODO:更動DietaryAgentController
同學的程式碼會執行：
```java
userRepository.findByEmail(email).orElseThrow(() -> new RuntimeException("使用者不存在"));
```
在測試時，請確保她本地端的資料庫（Database）中已經**存在一筆該 Email 的 User 資料**，否則 API 會丟出「使用者不存在」的 RuntimeException。

### 5.4 雙端成功連線時的輸入與輸出範例

當您與您同學的 Java Dietary Agent 伺服器成功連通時，整個傳輸鏈路中的 JSON 格式如下：

#### 1. 前端對您發送的請求 (Request to Companion Agent)
```json
{
  "message": "我今天中午吃炸雞了，晚上還能吃拉麵嗎？我有點焦慮。",
  "user_profile": {
    "height_cm": 165,
    "weight_kg": 60,
    "gender": "female",
    "age": 21
  }
}
```

#### 2. 您轉傳給同學後端的封裝三元素 (Payload to Java Dietary Agent)
這是發送到 `POST http://localhost:8080/api/dietary/ask-weekly-analysis` 的資料結構：
```json
{
  "question": "我今天中午吃炸雞了，晚上還能吃拉麵嗎？我有點焦慮。",
  "question_type": "single_dish",
  "dish_names": ["炸雞", "拉麵"]
}
```

#### 3. 同學後端回傳給您的資料 (Response from Java Dietary Agent)
這是同學的 API 所回覆的 JSON 範例：
```json
{
  "reply_text": "中午吃了炸雞（高油脂、高熱量），晚上如果再吃拉麵，一日熱量與鈉含量極易超標。建議晚上改為清淡飲食；若一定要吃拉麵，建議選擇鹽味或醬油清湯底，不要喝湯，並加點一份蔬菜以補充足夠膳食纖維喔！",
  "conclusion": "建議晚上改為清淡飲食，拉麵需限制湯頭與鈉攝取"
}
```

#### 4. 您整合後回傳給前端 App 的完整結果 (Final Response to Flutter)
這是您的 Companion Agent 融合情緒安撫前綴後，最終回傳給手機 App 的完整 JSON 物件：
```json
{
  "success": true,
  "llm_fallback_used": false,
  "screening": {
    "should_handle": true,
    "intent_category": "dish_advice",
    "question_type": "single_dish",
    "requires_more_context": false,
    "missing_information": [],
    "confidence": 0.95,
    "dish_names": ["炸雞", "拉麵"]
  },
  "emotion": {
    "primary_emotion": "anxiety",
    "valence": "negative",
    "urgency": "medium",
    "needs_empathy": true,
    "companion_tone": "calm",
    "evidence": ["焦慮"]
  },
  "dietary_agent_request": {
    "question": "我今天中午吃炸雞了，晚上還能吃拉麵嗎？我有點焦慮。",
    "question_type": "single_dish",
    "dish_names": ["炸雞", "拉麵"]
  },
  "dietary_agent_response": {
    "reply_text": "中午吃了炸雞（高油脂、高熱量），晚上如果再吃拉麵，一日熱量與鈉含量極易超標。建議晚上改為清淡飲食；若一定要吃拉麵，建議選擇鹽味或醬油清湯底，不要喝湯，並加點一份蔬菜以補充足夠膳食纖維喔！",
    "conclusion": "建議晚上改為清淡飲食，拉麵需限制湯頭與鈉攝取"
  },
  "dietary_agent_error": null,
  "companion_reply": "我有注意到你現在有點在意這次的選擇，先不用太緊張喔。❤️\n中午吃了炸雞（高油脂、高熱量），晚上如果再吃拉麵，一日熱量與鈉含量極易超標。建議晚上改為清淡飲食；若一定要吃拉麵，建議選擇鹽味或醬油清湯底，不要喝湯，並加點一份蔬菜以補充足夠膳食纖維喔！"
}
```

### 5.5 判別成功連上 Dietary Agent 的關鍵欄位

當您在終端機或 Postman 收到回覆時，可以透過以下關鍵欄位快速判定連線是否成功：

1. **`dietary_agent_error`**：應顯示 **`null`**（這代表我們沒有再遇到連線失敗 `fetch failed`，成功打到對方後台！）。
2. **`dietary_agent_response`**：這欄應該**運作正常且不再是空值**，而是會顯示同學後端 Java 專案回傳給您的 JSON 建議內容。
3. **`companion_reply`**：這段回覆會自動將您的同理心安撫前綴（如：`我有注意到你現在有點在意這次的選擇，先不用太緊張喔。❤️\n`），與同學的 API 回傳建議進行完美融合。

---

### 5.6 使用 Postman 進行三個情境之步驟指引

您可以使用 **Postman** 圖形化介面工具，來替代 `curl` 指令進行 API 測試。以下為完整的 Postman 操作與設定指引：

#### 步驟 1：建立 HTTP 請求
1. 開啟 Postman，點擊左上角的 **「+」** 或 **「New」** 按鈕新建一個請求（Request）。
2. 將 HTTP 方法（Method）下拉選單切換為 **`POST`**。
3. 在網址輸入框中填入 Companion Agent API 本地端網址：
   ```text
   http://localhost:3000/companion/ask
   ```

#### 步驟 2：設定 Headers (要求標頭)
1. 切換至 **Headers** 頁籤。
2. 預設情況下，Postman 會自動生成部分 Headers。請確保（或手動新增）以下 key-value 對：
   * **Key**: `Content-Type`
   * **Value**: `application/json`

#### 步驟 3：設定 Body (請求本體)
1. 切換至 **Body** 頁籤。
2. 選擇下方單選按鈕中的 **`raw`**。
3. 在右側的格式下拉選單（原本可能是 `Text`）切換為 **`JSON`**。
4. 依據您想測試的情境，將下列對應的 JSON Payload 貼入 Body 輸入框中，並點擊 **「Send」** 按鈕發送請求：

---

##### 🧪 情境一：一般飲食問題且帶有焦慮情緒 (同理心 + 料理抽取測試)
* **貼入 Body 的 JSON 內容**：
  ```json
  {
    "message": "我今天中午吃炸雞了，晚上還能吃拉麵嗎？我有點焦慮。",
    "user_profile": {
      "height_cm": 165,
      "weight_kg": 60,
      "gender": "female",
      "age": 21
    }
  }
  ```
* **驗證重點**：
  1. 回傳狀態碼應為 `200 OK`。
  2. `screening.dishes` 應包含 `["炸雞", "拉麵"]`。
  3. `emotion.primary_emotion` 應判定為 `anxiety`。
  4. `companion_reply` 開頭有同理心的安撫語（如：`我有注意到你現在有點在意這次的選擇，先不用太緊張喔。❤️`）。

##### 🧪 情境二：料理比較問題 (問題分類與雙實體測試)
* **貼入 Body 的 JSON 內容**：
  ```json
  {
    "message": "牛肉麵跟水餃哪一個熱量比較高？",
    "user_profile": {
      "height_cm": 165,
      "weight_kg": 55
    }
  }
  ```
* **驗證重點**：
  1. 回傳狀態碼應為 `200 OK`。
  2. `screening.question_type` 應為 `dish_comparison`。
  3. `screening.dishes` 應正確擷取 `["牛肉麵", "水餃"]`。

##### 🧪 情境三：醫療敏感詞過濾 (Pre-check 安全攔截測試)
* **貼入 Body 的 JSON 內容**：
  ```json
  {
    "message": "這個降血糖藥我應該怎麼服用？請幫我診斷。"
  }
  ```
* **驗證重點**：
  1. 回傳狀態碼應為 `200 OK`。
  2. `screening.should_handle` 應為 `false`。
  3. `screening.intent_category` 應為 `medical_out_of_scope`。
  4. `companion_reply` 應傳回警示語（如：`這類問題比較接近醫療診斷...`）。

---

#### 💡 連線 Dietary Agent (Java/Spring Boot) 聯調測試的補充設定

如果您正在進行 **5.2 對策 B**（需要帶上 Bearer Token 進行身份驗證對接）：
1. **如果您要利用 Postman 直接測試同學的 Java Dietary Agent API (`POST http://localhost:8080/api/dietary/ask-weekly-analysis`)**：
   * 在該請求的 **Authorization** 頁籤中，將 **Type** 選擇為 **`Bearer Token`**。
   * 在右側的 **Token** 輸入框中貼上同學提供給您的有效測試用 JWT Token。
2. **如果是透過 Companion Agent 轉傳**：
   * 請確認您已依照 5.2 對策 B，在您的 Node.js 程式碼中將 Token 寫入 Header，再直接用上述步驟 1~3 的設定測試 Companion Agent 即可。

