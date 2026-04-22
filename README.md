# Dietary App - Backend
## 專案架構
```
src/main/java/com/tku/dietary_app
├── config # Security 設定
├── controller # API 控制層
├── dto # 資料傳輸物件
├── entity # 資料庫實體
├── repository # 資料庫存取層
├── service # 商業邏輯層
└── exception # 全域錯誤處理
```
---
## 使用者註冊 API
(可用postman測試)

**POST** `/api/register`

### Request Body
```json
{
  "email": "test@gmail.com",
  "password": "123456"
}
```
功能說明
- 檢查 Email 是否重複
- 使用 BCrypt 加密密碼
- 寫入資料庫
- 自動產生 created_at

## 使用者登入 API

**POST** `/api/login`

### Request Body
```json
{
"email": "test@gmail.com",
"password": "123456"
}
```
功能說明
- 查詢資料庫是否有該 email
- 比對加密密碼
- 成功 → 回傳登入成功
- 失敗 → 回傳錯誤訊息
---
## 密碼加密機制

### 使用：
```
BCryptPasswordEncoder
```
資料庫儲存為加密後字串，不保存明文密碼

---
## 全域錯誤處理

### 使用：
```
@RestControllerAdvice
```
統一錯誤回傳格式

---
## Security 設定

### 目前開發階段設定為：
```
permitAll()
```
所有 API 允許存取（之後會改為 JWT 驗證）。

### 資料庫設定的帳號密碼
詳細內容看 application.properties
```
spring.datasource.username=sa
spring.datasource.password=TkuProject
```