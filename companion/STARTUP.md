# Companion 啟動說明

## 1. 安裝依賴

在 `companion_js` 目錄執行：

```powershell
cd C:\Users\Cyborg 15\Desktop\dietary_app\companion\companion_js
npm install
```

## 2. 建立 `.env`

請在下列任一位置建立 `.env`，程式會依序尋找：

1. `C:\Users\Cyborg 15\Desktop\dietary_app\.env`
2. `C:\Users\Cyborg 15\Desktop\dietary_app\companion\.env`
3. `C:\Users\Cyborg 15\Desktop\dietary_app\companion\companion_js\.env`

可直接複製 `C:\Users\Cyborg 15\Desktop\dietary_app\companion\.env.example` 內容，並填入實際值：

```env
OPENAI_API_KEY=replace-with-your-openai-api-key
OPENAI_MODEL=gpt-4o-mini
DIETARY_AGENT_API_URL=http://localhost:8080
COMPANION_API_PORT=3000
```

## 3. 啟動 Java Dietary Agent

請確認 Java/Spring Boot 服務已啟動，且 V2 路徑可用：

```text
POST {DIETARY_AGENT_API_URL}/api/dietary/ask-weekly-analysis
```

如果 Java 端有驗證，請擇一處理：

- 測試階段先放行該路徑
- 呼叫 Companion API 時帶上有效的 `Authorization: Bearer <token>`

## 4. 啟動 Companion API

在 `companion_js` 目錄執行：

```powershell
npm start
```

成功時會看到類似：

```text
Companion Agent API listening on port 3000
```

## 5. 驗證是否啟動成功

先測健康檢查：

```powershell
curl http://localhost:3000/health
```

預期回傳：

```json
{"status":"ok"}
```

再測主要 API：

```powershell
$body = @{ user_prompt = "我今天中午吃炸雞，晚上還能吃拉麵嗎？" } | ConvertTo-Json -Compress
Invoke-RestMethod -Uri "http://localhost:3000/companion/ask" -Method Post -Body $body -ContentType "application/json; charset=utf-8"
```

## 6. 仍需你手動完成的部分

- 填入真實的 `OPENAI_API_KEY`
- 確認 `DIETARY_AGENT_API_URL` 指向你們實際的 Java 服務
- 若 Java 端有驗證，提供有效 token 或請隊友先放行測試路徑
