# 前端串接後端說明

本文件整理目前 `dietary_app` 後端提供給前端 App 使用的主要 API、驗證流程、回傳格式與串接注意事項。

## 1. 基本資訊

- API Base URL：請以前後端實際部署環境為準，例如 `http://localhost:8080`
- Content-Type：大多數 API 使用 `application/json`
- 驗證方式：`Bearer Token`
- Token 設計：`短效 access token + refresh token`
- App 端建議：
  - `accessToken` 放在記憶體或安全儲存區
  - `refreshToken` 放在平台安全儲存區，例如 iOS Keychain / Android Keystore
  - 不建議把 refresh token 放在一般可讀的本機儲存

## 2. 驗證與登入流程

### 2.1 註冊

- Method：`POST`
- Path：`/api/register`
- 是否需要登入：否

Request:

```json
{
  "email": "user@example.com",
  "password": "Abc123"
}
```

Response:

```json
{
  "success": true,
  "message": "註冊成功",
  "tokenType": "Bearer",
  "accessToken": "eyJ...",
  "refreshToken": "eyJ...",
  "accessTokenExpiresInSeconds": 3600,
  "refreshTokenExpiresInSeconds": 2592000,
  "needsOnboarding": true
}
```

### 2.2 登入

- Method：`POST`
- Path：`/api/login`
- 是否需要登入：否

Request:

```json
{
  "email": "user@example.com",
  "password": "Abc123"
}
```

Response 格式與註冊相同：

```json
{
  "success": true,
  "message": "登入成功",
  "tokenType": "Bearer",
  "accessToken": "eyJ...",
  "refreshToken": "eyJ...",
  "accessTokenExpiresInSeconds": 3600,
  "refreshTokenExpiresInSeconds": 2592000,
  "needsOnboarding": false
}
```

### 2.3 更新 token

- Method：`POST`
- Path：`/api/refresh`
- 是否需要登入：否

Request:

```json
{
  "refreshToken": "eyJ..."
}
```

Response 格式與登入相同，前端應直接用新回傳的 `accessToken` 與 `refreshToken` 覆蓋舊值。

### 2.4 登出

- Method：`POST`
- Path：`/api/logout`
- 是否需要登入：是

Request Header:

```http
Authorization: Bearer <accessToken>
```

Response:

```json
{
  "success": true,
  "message": "登出成功",
  "data": null
}
```

前端收到成功後，應主動清掉本機的 `accessToken` 與 `refreshToken`。

## 3. 前端建議的 token 處理方式

建議流程如下：

1. App 啟動時先讀取本機保存的 token。
2. 若 `accessToken` 還有效，直接帶入後續 API。
3. 若 API 回傳 `401`，使用 `refreshToken` 呼叫 `/api/refresh`。
4. refresh 成功後，更新本機 token，並重送原本失敗的 request。
5. 若 refresh 也失敗，代表登入狀態失效，導回登入頁。

建議前端做一層 API client / interceptor，集中處理：

- 自動補上 `Authorization` header
- 遇到 `401` 自動 refresh
- refresh 失敗時統一登出

## 4. 通用 request header

一般 JSON API：

```http
Content-Type: application/json
Authorization: Bearer <accessToken>
```

上傳圖片 API：

```http
Content-Type: multipart/form-data
Authorization: Bearer <accessToken>
```

## 5. 回傳格式規則

### 5.1 Auth API 是特例

以下三支 API 直接回傳 `AuthResponse`：

- `/api/register`
- `/api/login`
- `/api/refresh`

格式不是 `ApiResponse<T>`，而是：

```json
{
  "success": true,
  "message": "xxx",
  "tokenType": "Bearer",
  "accessToken": "xxx",
  "refreshToken": "xxx",
  "accessTokenExpiresInSeconds": 3600,
  "refreshTokenExpiresInSeconds": 2592000,
  "needsOnboarding": true
}
```

### 5.2 其他大部分 API 使用 `ApiResponse<T>`

格式如下：

```json
{
  "success": true,
  "message": "可有可無",
  "data": {}
}
```

有些 API 不一定會帶 `message`，前端不要把 `message` 視為必填欄位。

### 5.3 錯誤回傳

目前錯誤回傳不完全等同成功格式，前端建議至少處理：

- `401`：未登入、token 過期、token 無效
- `403`：權限不足
- `404`：資料不存在
- `409`：重複資料，例如 email 已存在
- `400`：欄位驗證失敗

欄位驗證失敗時，後端可能回傳欄位對應訊息 map，前端建議以 HTTP status 為主要判斷依據，不要只靠固定 JSON 結構。

## 6. 使用者主要 API

## 6.1 完成 onboarding

- Method：`POST`
- Path：`/api/user/onboarding`
- 是否需要登入：是

Request:

```json
{
  "nickname": "Milo",
  "gender": "MALE",
  "age": 25,
  "height": 170,
  "weight": 65,
  "healthConditions": [
    "DIABETES"
  ],
  "dietGoal": "LOSE_WEIGHT",
  "petType": "DOG"
}
```

Response:

```json
{
  "success": true,
  "message": "Onboarding 完成",
  "data": {
    "id": 1,
    "userId": 1,
    "email": "user@example.com",
    "hasCompletedOnboarding": true,
    "nickname": "Milo",
    "gender": "MALE",
    "age": 25,
    "height": 170.0,
    "weight": 65.0,
    "healthConditions": [
      "DIABETES"
    ],
    "dietGoal": "LOSE_WEIGHT",
    "petType": "DOG",
    "avatarUrl": null,
    "bmr": 1500.0,
    "tdee": 2100.0,
    "recommendedCalories": 1800.0,
    "bodyScore": 60,
    "muscleScore": 55,
    "bodyType": "BALANCED",
    "lastSettleDate": null,
    "createdAt": "2026-08-06T10:00:00",
    "updatedAt": "2026-08-06T10:00:00"
  }
}
```

### 6.2 取得自己的 profile

- Method：`GET`
- Path：`/api/user/profile`
- 是否需要登入：是

回傳 `data` 結構與 onboarding 完成後相同，都是 `UserProfileResponse`。

### 6.3 取得自己的飲食紀錄

- Method：`GET`
- Path：`/api/user/diet-records`
- 是否需要登入：是

Response:

```json
{
  "success": true,
  "data": [
    {
      "id": 10,
      "dishName": "雞胸肉沙拉",
      "description": "午餐",
      "mealType": "LUNCH",
      "photoUrl": "/avatars/example.jpg",
      "date": "2026-08-06",
      "createdAt": "2026-08-06T12:30:00",
      "nutrition": {
        "calories": "350.0 kcal",
        "protein": "30.0 g",
        "fat": "8.0 g",
        "carbohydrates": "25.0 g"
      }
    }
  ]
}
```

### 6.4 新增自己的飲食紀錄

- Method：`POST`
- Path：`/api/user/diet-records`
- 是否需要登入：是

Request:

```json
{
  "dishName": "雞胸肉沙拉",
  "calories": 350,
  "protein": 30,
  "fat": 8,
  "carbohydrates": 25,
  "date": "2026-08-06",
  "description": "午餐",
  "mealType": "LUNCH"
}
```

`mealType` 目前可用值：

- `BREAKFAST`
- `LUNCH`
- `DINNER`

## 7. 飲食紀錄 API

這組 API 與 `/api/user/diet-records` 功能接近，但路徑較通用，前端可依畫面需求擇一使用。

### 7.1 取得飲食紀錄列表

- Method：`GET`
- Path：`/api/diet-records`

### 7.2 新增飲食紀錄

- Method：`POST`
- Path：`/api/diet-records`

Request body 結構與上面相同。

### 7.3 更新飲食紀錄

- Method：`PUT`
- Path：`/api/diet-records/{id}`

### 7.4 刪除飲食紀錄

- Method：`DELETE`
- Path：`/api/diet-records/{id}`

Response:

```json
{
  "success": true,
  "message": "刪除成功",
  "data": null
}
```

### 7.5 上傳飲食照片

- Method：`POST`
- Path：`/api/diet-records/{id}/photo`
- Content-Type：`multipart/form-data`

Form Data:

- key：`file`
- value：圖片檔案

Response:

```json
{
  "success": true,
  "message": "圖片上傳成功",
  "data": "/uploads/diet-records/xxx.jpg"
}
```

## 8. 身體狀態 API

### 8.1 取得目前身體狀態

- Method：`GET`
- Path：`/api/body-status`

Response `data` 為 `BodyStatusResponse`：

```json
{
  "success": true,
  "data": {
    "bodyScore": 60,
    "muscleScore": 55,
    "bodyType": "BALANCED",
    "bmr": 1500.0,
    "tdee": 2100.0,
    "recommendedCalories": 1800.0,
    "recommendedProtein": 90.0,
    "lastSettleDate": "2026-08-06"
  }
}
```

### 8.2 每日結算

- Method：`POST`
- Path：`/api/body-status/settle`

Response `data` 為 `SettlementResponse`，包含：

- `settled`
- `lastSettleDate`
- `bodyScore`
- `muscleScore`
- `bodyType`
- `oldBodyType`
- `newBodyType`
- `bodyTypeChanged`
- `bodyScoreChange`
- `muscleScoreChange`
- `recommendedCalories`
- `totalCalories`
- `recommendedProtein`
- `totalProtein`
- `results`

### 8.3 重新計算身體指標

- Method：`POST`
- Path：`/api/body-status/recalculate`

回傳 `data` 也是身體狀態相關資料，前端可直接重刷 profile / body status 畫面。

## 9. AI 飲食助理 API

### 9.1 詢問飲食助理

- Method：`POST`
- Path：`/dietary-agent/ask`
- 是否需要登入：是

Request:

```json
{
  "question": "我今天晚餐這樣吃可以嗎？",
  "question_type": "diet_advice",
  "dish_names": [
    "雞胸肉",
    "白飯"
  ],
  "user_profile": {
    "height_cm": 170,
    "weight_kg": 65,
    "gender": "MALE",
    "age": 25
  },
  "health_condition": {
    "has_chronic_disease": true,
    "chronic_diseases": [
      "DIABETES"
    ]
  },
  "weekly_diet_records": [
    {
      "date": "2026-08-06",
      "meal": "DINNER",
      "dish_name": "雞胸肉",
      "note": "少油"
    }
  ]
}
```

Response 會包在 `ApiResponse.data` 中，實際內容由 dietary partner 回傳結果決定，前端建議先以動態物件處理，不要把欄位寫死得太早。

### 9.2 查詢菜色營養

- Method：`POST`
- Path：`/dietary-agent/dish-nutrition`

Request:

```json
{
  "dish_name": "雞胸肉便當"
}
```

Response 同樣包在 `ApiResponse.data` 中，欄位內容依外部 dietary partner 回傳為準。

## 10. 頭像與靜態資源

目前 `/avatars/**` 為公開路徑，不需要 token。

如果後端回傳的 `avatarUrl` 或 `photoUrl` 是相對路徑，前端應自行補上 API host：

```text
完整圖片網址 = {BASE_URL} + {avatarUrl 或 photoUrl}
```

## 11. 管理員 API

若前端有管理後台，可再串以下路徑：

- `GET /api/admin/users`
- `GET /api/admin/users/{id}`
- `POST /api/admin/users`
- `PUT /api/admin/users/{id}`
- `DELETE /api/admin/users/{id}`
- `GET /api/admin/diet-records`
- `POST /api/admin/diet-records`
- `PUT /api/admin/diet-records/{id}`
- `DELETE /api/admin/diet-records/{id}`
- `POST /api/admin/diet-records/{id}/photo`

這些 API 需要 `ROLE_ADMIN` 權限，App 一般使用者端通常不會用到。

## 12. 前端實作建議摘要

- 把 Auth API 與一般 API 的 response parser 分開處理。
- 所有需要登入的 API 都統一走同一個 API client。
- 用 interceptor 自動補 `Authorization`。
- 用單一 refresh 流程避免多個 request 同時刷新 token。
- 看到 `needsOnboarding = true` 時，登入後直接導向 onboarding 畫面。
- 上傳圖片時使用 `multipart/form-data`，不要手動把檔案轉成 JSON。
- 對錯誤處理優先看 HTTP status，其次才看 response body。
