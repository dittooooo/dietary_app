# README 0725

## 目錄

- [1. 這次實際做了什麼](#1-這次實際做了什麼)
- [2. 這次有動到或新增的檔案](#2-這次有動到或新增的檔案)
- [3. Companion 端修改內容](#3-companion-端修改內容)
- [4. 後端端點路徑確認](#4-後端端點路徑確認)
- [5. Backend 端處理內容](#5-backend-端處理內容)
- [6. 啟動方式](#6-啟動方式)
- [7. 測試方式](#7-測試方式)
- [8. 帶 token 的完整測試模板](#8-帶-token-的完整測試模板)
- [9. 如何判斷是否成功](#9-如何判斷是否成功)

## 1. 這次實際做了什麼

這次主要是把 `companion` 這條線接到 `backend`，並把本地測試流程跑通。

我實際做的事情有：

1. 調整 Companion 的 `.env` 讀取方式，讓它可以優先讀專案最外層的 `.env`。
2. 確認 Companion 呼叫 Java backend 的端點路徑。
3. 把 backend 新版本內容拉下來，讓本地後端不是舊版。
4. 實際測試 `Companion API -> Java backend -> 回傳結果 -> companion_reply` 這條流程。
5. 最後使用 token 的方式完成測試，不是用 `permitAll()`。

---

## 2. 這次有動到或新增的檔案

這裡只列這次真的有新增或修改的檔案。

### Companion 端

- `companion/companion_js/companion-agent.js`
  - 修改 `.env` 讀取邏輯。

- `companion/companion_js/companion-agent-services.js`
  - 確認 Companion 呼叫 Java backend 的 API 路徑。

- `companion/readme0725.md`
  - 這份工作紀錄。

- `companion/doc/codex_companion_test_2026-07-25.md`
  - 這次測試過程留下的測試說明。

- `companion/doc/codex_companion_test_results.json`
  - 這次測試結果 JSON。

### Backend 端

- backend 整包有重新拉新版本，目的是補齊新版 controller、service、dto、repository、security 相關內容。

---

## 3. Companion 端修改內容

### 3-1. `.env` 讀取方式

這次有調整 `companion-agent.js`，讓 Companion 會依序找下面三個位置的 `.env`：

1. `dietary_app/.env`
2. `dietary_app/companion/.env`
3. `dietary_app/companion/companion_js/.env`

因為你們後來決定只保留一份 `.env`，放在專案最外層，所以現在實際上 Companion 會優先讀：

- `C:\Users\Cyborg 15\Desktop\dietary_app\.env`

這樣就能符合「只保留一份 `.env`」的規則。

### 3-2. Companion fallback 行為

Companion 本來就有 fallback。

也就是說，當 Java backend 沒開、403、500，甚至 partner API 有問題時，Companion 還是可以先回一段 `companion_reply`。

所以之前你看到：

- `fetch failed`
- `Dietary Agent error 403`
- `Dietary Agent error 500`

但 `companion_reply` 還是有內容，這是正常的，因為 Companion 沒有直接整個中斷。

---

## 4. 後端端點路徑確認

這次確認過，Java backend 正確路徑是：

```text
${baseUrl}/dietary-agent/ask
```

也就是說 Companion 目前這段是正確的：

```js
const response = await fetch(`${baseUrl}/dietary-agent/ask`, {
```

這裡要特別註記：

- 這次不是把它改成別的
- 而是確認目前使用的 `${baseUrl}/dietary-agent/ask` 才是正確路徑

---

## 5. Backend 端處理內容

### 5-1. 把 backend 新版本拉下來

有先發現本機 backend 太舊，所以後來有把 backend 的新內容拉下來。

目的很簡單：

- 避免本地後端還停在舊版
- 讓 security、controller、service、dto、repository 與現在測試流程一致

### 5-2. 最後採用 token 測試

一開始測試過程有碰到：

- `403`
- `使用者不存在`

最後決定不走 `permitAll()` 的方向，而是改用正常登入流程測試，也就是：

1. 先 login
2. 拿 token
3. 打 `/companion/ask` 時帶上 `Authorization: Bearer <token>`
4. Companion 再把 token 轉傳給 Java backend

所以最後正式採用的做法是：

- 用 token 測試
- 不是靠 `permitAll()` 放行

---

## 6. 啟動方式

### 6-1. 安裝 Companion 依賴

在 `companion_js` 目錄執行：

```powershell
cd C:\Users\Cyborg 15\Desktop\dietary_app\companion\companion_js
npm install
```

### 6-2. 準備 `.env`

目前 Companion 會優先讀最外層 `.env`，所以請確認這份檔案存在：

```text
C:\Users\Cyborg 15\Desktop\dietary_app\.env
```

至少要有這些欄位：

```env
OPENAI_API_KEY=replace-with-your-openai-api-key
OPENAI_MODEL=gpt-4o-mini
DIETARY_AGENT_API_URL=http://localhost:8080
COMPANION_API_PORT=3000
```

### 6-3. 啟動 Java backend

請先確定 Java backend 已經成功啟動。

### 6-4. 啟動 Companion API

在 `companion_js` 目錄執行：

```powershell
npm start
```

成功時會看到類似：

```text
Companion Agent API listening on port 3000
```

---

## 7. 測試方式

### 7-1. 先測 Companion 是否有活著

```powershell
curl.exe http://localhost:3000/health
```

預期回傳：

```json
{"status":"ok"}
```

### 7-2. 直接測 Companion API

```powershell
$body = @{
  user_prompt = "我今天中午吃炸雞，晚上還能吃拉麵嗎？"
} | ConvertTo-Json -Compress

Invoke-RestMethod -Uri "http://localhost:3000/companion/ask" `
  -Method Post `
  -Body $body `
  -ContentType "application/json; charset=utf-8"
```

如果後端沒開、沒權限、或使用者不存在，通常 `companion_reply` 還是會出來，但 `dietary_agent_error` 會有錯誤訊息。

---

## 8. 帶 token 的完整測試模板

如果要用正常登入流程測試，建議直接用下面這組。

### 8-1. 先登入 backend 拿 token

```powershell
$loginBody = @{
  email = "test@gmail.com"
  password = "Test123"
} | ConvertTo-Json -Compress

$loginRes = Invoke-RestMethod -Uri "http://localhost:8080/api/login" `
  -Method Post `
  -Body $loginBody `
  -ContentType "application/json; charset=utf-8"

$loginRes | ConvertTo-Json -Depth 5
```

如果回傳欄位是：

```json
{ "token": "eyJ..." }
```

就接著取 token：

```powershell
$token = $loginRes.token
```

### 8-2. 帶 token 打 Companion API

```powershell
$headers = @{
  Authorization = "Bearer $token"
}

$body = @{
  user_prompt = "我今天中午吃炸雞，晚上還能吃拉麵嗎？"
} | ConvertTo-Json -Compress

$response = Invoke-RestMethod -Uri "http://localhost:3000/companion/ask" `
  -Method Post `
  -Headers $headers `
  -Body $body `
  -ContentType "application/json; charset=utf-8"

$response | ConvertTo-Json -Depth 10
```

### 8-3. 展開看 Java backend 回傳內容

```powershell
$response.dietary_agent_response | ConvertTo-Json -Depth 10
```

### 8-4. 只看 `dish_nutrition`

```powershell
$response.dietary_agent_response.dish_nutrition | ConvertTo-Json -Depth 10
```

### 8-5. 只看 `dish_advice`

```powershell
$response.dietary_agent_response.dish_advice | ConvertTo-Json -Depth 10
```

---

## 9. 如何判斷是否成功

### 9-1. 成功的狀態

至少要看到：

- `success : true`
- `dietary_agent_response` 有內容
- `dietary_agent_error` 是空的
- `companion_reply` 有完整自然語言回覆

### 9-2. 常見錯誤代表什麼

#### `Missing OPENAI_API_KEY`

代表最外層 `.env` 沒讀到，或 `OPENAI_API_KEY` 沒填好。

#### `fetch failed`

代表 Companion 連不到 Java backend。

常見原因：

- backend 沒啟動
- 端口不是 `8080`
- `DIETARY_AGENT_API_URL` 寫錯

#### `Dietary Agent error 403`

代表 Java backend 有開，但沒有通過權限驗證。

#### `Dietary Agent error 500: 使用者不存在`

代表請求雖然進到 API，但 controller 內部還是拿不到有效登入者資料。

