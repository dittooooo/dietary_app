# Dietary App Postman 測試流程

本文件說明如何用新版 Postman collection 測試目前後端 API，內容以 2026-08-06 現況為準。

## 1. 檔案位置

Postman collection 檔案位於：

```text
postman/DietaryApp.postman_collection.json
```

## 2. 匯入方式

1. 開啟 Postman
2. 選擇 Import
3. 匯入 `postman/DietaryApp.postman_collection.json`

## 3. 需要的 Collection Variables

新版 collection 已內建以下變數：

- `baseUrl`
- `accessToken`
- `refreshToken`
- `adminAccessToken`
- `adminRefreshToken`
- `dietRecordId`
- `userId`

建議一開始先把：

- `baseUrl` 設成 `http://localhost:8080`

其餘 token 與 id 變數可讓測試腳本自動寫入。

## 4. 建議測試順序

### 4.1 一般使用者流程

1. `Auth / Register`
2. `User / Complete Onboarding`
3. `User / Get Profile`
4. `User / Add My Diet Record`
5. `User / Get My Diet Records`
6. `Diet Records / List Records`
7. `Diet Records / Update Record`
8. `Body Status / Get Body Status`
9. `Body Status / Settle Daily Scores`
10. `Dietary Agent / Ask`
11. `Auth / Refresh`
12. `Auth / Logout`

### 4.2 管理員流程

1. 先用管理員帳號執行 `Auth / Admin Login`
2. 再測：
   - `Admin / List Users`
   - `Admin / Get User`
   - `Admin / List Diet Records`
   - `Admin / Create User`
   - `Admin / Update User`

## 5. 新版 token 行為

目前後端不是回傳單一 `token`，而是：

- `accessToken`
- `refreshToken`
- `accessTokenExpiresInSeconds`
- `refreshTokenExpiresInSeconds`

collection 內的 Auth request 測試腳本會自動：

- 儲存 `accessToken`
- 儲存 `refreshToken`

管理員登入則會自動：

- 儲存 `adminAccessToken`
- 儲存 `adminRefreshToken`

## 6. 重要 request 說明

### 6.1 Register

Path：

```text
POST {{baseUrl}}/api/register
```

Body 範例：

```json
{
  "email": "user001@example.com",
  "password": "User123"
}
```

成功後腳本會自動把 token 存回 collection variables。

### 6.2 Login

Path：

```text
POST {{baseUrl}}/api/login
```

成功後會更新：

- `accessToken`
- `refreshToken`

### 6.3 Refresh

Path：

```text
POST {{baseUrl}}/api/refresh
```

Body：

```json
{
  "refreshToken": "{{refreshToken}}"
}
```

成功後會用新 token 覆蓋舊 token。

### 6.4 Logout

Path：

```text
POST {{baseUrl}}/api/logout
```

Header：

```text
Authorization: Bearer {{accessToken}}
```

執行成功後，建議手動清掉 token 變數，或重新登入取得新 token。

### 6.5 Complete Onboarding

Path：

```text
POST {{baseUrl}}/api/user/onboarding
```

需要：

- `Authorization: Bearer {{accessToken}}`

### 6.6 Add My Diet Record

Path：

```text
POST {{baseUrl}}/api/user/diet-records
```

成功後，collection 會自動保存 `dietRecordId`，方便後續更新與刪除。

### 6.7 Upload Diet Photo

Path：

```text
POST {{baseUrl}}/api/diet-records/{{dietRecordId}}/photo
```

Body 類型：

- `form-data`
- key：`file`
- type：`File`

## 7. 常見驗證重點

### 7.1 驗證 access token 是否正常工作

做法：

1. 登入取得 `accessToken`
2. 呼叫 `/api/user/profile`
3. 若回傳 200，代表 Bearer token 生效

### 7.2 驗證 refresh token 流程

做法：

1. 登入
2. 使用 collection 中保存的 `refreshToken`
3. 呼叫 `/api/refresh`
4. 確認新的 `accessToken` 與 `refreshToken` 有被更新

### 7.3 驗證 onboarding 狀態

做法：

1. 註冊新帳號
2. 檢查回傳 `needsOnboarding`
3. 執行 onboarding
4. 再查 `/api/user/profile`

### 7.4 驗證 admin 權限

做法：

1. 使用一般使用者 token 呼叫 `/api/admin/users`
2. 應得到 403
3. 使用管理員 token 重試
4. 應得到 200

## 8. 常見錯誤排查

### 8.1 401 Unauthorized

通常原因：

- 沒帶 `Authorization`
- `accessToken` 過期
- token 不正確

處理方式：

- 先跑 `Auth / Refresh`
- 若 refresh 也失敗，重新登入

### 8.2 403 Forbidden

通常原因：

- 用一般使用者 token 呼叫 admin API

### 8.3 400 Bad Request

通常原因：

- request body 欄位缺漏
- enum 值不合法
- password 或 email 格式不符

### 8.4 409 Conflict

通常原因：

- email 已存在

## 9. 建議測試資料

一般使用者：

```text
email: user001@example.com
password: User123
```

管理員：

```text
email: admin@example.com
password: Admin123
```

若你的本地資料庫資料不同，請改成實際可登入的帳號。

## 10. 搭配文件

建議一起看：

- `docs/FRONTEND_BACKEND_INTEGRATION_ZH.md`
- `docs/CODEBASE_GUIDE_ZH.md`
- `docs/BACKEND_REVIEW_2026-08-06.md`
