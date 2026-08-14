# Dietary App 後端程式碼導覽

本文件說明目前 `backend` 專案的主要結構、核心流程與重要檔案位置，內容以 2026-08-06 現況為準。

## 1. 專案定位

這是一個使用 Spring Boot 開發的後端 API，主要提供：

- 使用者註冊、登入、refresh token、登出
- 使用者 onboarding 與個人資料
- 飲食紀錄建立、查詢、修改、刪除與照片上傳
- 身體狀態計算與每日結算
- AI 飲食助理相關 API
- 管理員使用者管理與飲食紀錄管理

目前 token 設計採用：

- 短效 `access token`
- 長效 `refresh token`
- App 端自行保存 token，不使用 HttpOnly cookie

## 2. 專案目錄

主要程式碼在：

```text
src/main/java/com/tku/dietary_app
```

目前主要目錄如下：

```text
config/
controller/
dto/
entity/
exception/
repository/
service/
DietaryAppApplication.java
```

## 3. 分層架構

整體流程大致如下：

```text
Controller
  -> Service
    -> Repository
      -> Database
```

搭配：

- `dto`：request / response 結構
- `entity`：資料表對應物件
- `config`：安全、JWT、CORS、外部 API client 等設定
- `exception`：自訂例外與全域錯誤處理

## 4. 各層職責

### 4.1 Controller

位置：

```text
src/main/java/com/tku/dietary_app/controller
```

用途：

- 接收 HTTP request
- 驗證登入狀態或使用 Spring Security 身分
- 呼叫 service
- 回傳 `AuthResponse` 或 `ApiResponse<T>`

目前主要 controller：

- `AuthController`
- `UserProfileController`
- `DietRecordController`
- `BodyStatusController`
- `DietaryAgentController`
- `AdminController`

### 4.2 Service

位置：

```text
src/main/java/com/tku/dietary_app/service
```

用途：

- 放商業邏輯
- 處理 token 發行與 refresh token 驗證
- 管理 onboarding / profile / body metrics
- 管理飲食紀錄與圖片儲存
- 呼叫外部 dietary partner API
- 處理管理員相關功能

目前比較重要的 service 包含：

- `AuthService`
- `UserProfileService`
- `DietRecordService`
- `BodyStatusService`
- `BodyMetricsService`
- `DietaryAgentService`
- `AdminService`

### 4.3 Repository

位置：

```text
src/main/java/com/tku/dietary_app/repository
```

用途：

- 負責資料查詢與持久化
- 透過 Spring Data JPA 操作資料庫

常見用途例如：

- 依 email 查詢使用者
- 查詢使用者 profile
- 查詢特定日期或週期的飲食紀錄

### 4.4 DTO

位置：

```text
src/main/java/com/tku/dietary_app/dto
```

用途：

- 定義 API 請求格式
- 定義 API 回傳格式
- 避免 controller 直接暴露 entity

目前重要 DTO：

- `AuthResponse`
- `ApiResponse`
- `RegisterRequest`
- `LoginRequest`
- `RefreshTokenRequest`
- `OnboardingRequest`
- `UserProfileResponse`
- `DietRecordRequest`
- `DietRecordResponse`
- `BodyStatusResponse`
- `SettlementResponse`
- `DietaryAskRequest`
- `DietaryDishNutritionRequest`
- `AdminUserRequest`

### 4.5 Entity

位置：

```text
src/main/java/com/tku/dietary_app/entity
```

目前已保留的核心 entity：

- `User`
- `UserProfile`
- `DietRecord`
- `MealType`

目前 `Restaurant` 與 `MenuItem` 已移除，不應再作為現行架構的一部分理解。

## 5. 驗證與授權

### 5.1 Security 設定

主要設定檔：

```text
src/main/java/com/tku/dietary_app/config/SecurityConfig.java
```

目前重點：

- 使用 stateless session
- 關閉 CSRF
- 啟用 CORS
- 由 `JwtAuthenticationFilter` 驗證 Bearer token

公開路徑：

- `/api/register`
- `/api/login`
- `/api/refresh`
- `/avatars/**`

需要登入的主要路徑：

- `/api/user/**`
- `/api/diet-records/**`
- `/api/body-status/**`
- `/dietary-agent/**`

管理員限定：

- `/api/admin/**`

### 5.2 Auth API 回傳格式

Auth 相關 API 是特例，不走 `ApiResponse<T>`，而是直接回傳 `AuthResponse`：

- `POST /api/register`
- `POST /api/login`
- `POST /api/refresh`

欄位包含：

- `success`
- `message`
- `tokenType`
- `accessToken`
- `refreshToken`
- `accessTokenExpiresInSeconds`
- `refreshTokenExpiresInSeconds`
- `needsOnboarding`

其他大部分 API 則使用：

```json
{
  "success": true,
  "message": "optional",
  "data": {}
}
```

## 6. 核心功能模組

### 6.1 認證模組

入口：

- `AuthController`
- `AuthService`
- `JwtUtil`
- `JwtAuthenticationFilter`

負責：

- 註冊
- 登入
- access token 發行
- refresh token 發行與更新
- 登出時使 refresh token 失效

### 6.2 使用者資料與 Onboarding

入口：

- `UserProfileController`
- `UserProfileService`

負責：

- 完成 onboarding
- 取得目前使用者 profile
- 維護 BMR / TDEE / 建議熱量等資料

### 6.3 飲食紀錄

入口：

- `DietRecordController`
- `DietRecordService`

負責：

- 新增飲食紀錄
- 查詢自己的飲食紀錄
- 更新與刪除紀錄
- 上傳餐點照片

`mealType` 目前允許：

- `BREAKFAST`
- `LUNCH`
- `DINNER`

### 6.4 身體狀態

入口：

- `BodyStatusController`
- `BodyStatusService`
- `BodyMetricsService`

負責：

- 取得身體狀態
- 每日結算分數
- 重新計算身體指標

主要回傳型別：

- `BodyStatusResponse`
- `SettlementResponse`

### 6.5 AI 飲食助理

入口：

- `DietaryAgentController`
- `DietaryAgentService`

負責：

- 問答型飲食建議
- 菜色營養查詢
- 呼叫外部 dietary partner API

相關 DTO：

- `DietaryAskRequest`
- `DietaryDishNutritionRequest`
- `DietaryAgentPayload`

### 6.6 管理員功能

入口：

- `AdminController`
- `AdminService`

負責：

- 查詢使用者
- 建立與更新使用者
- 刪除使用者
- 管理全站飲食紀錄

## 7. 設定檔與資源

位置：

```text
src/main/resources
```

重要檔案：

- `application.properties`
- `application-local.properties`
- `db/`：Flyway migration

目前設定重點包含：

- JWT secret 與有效時間
- 資料庫連線
- 外部 dietary partner API base URL 與 path
- 外部 API timeout 設定
- 啟動時是否建立預設管理員帳號

## 8. 資料庫 migration

目前專案已採用 Flyway。

位置：

```text
src/main/resources/db
```

用途：

- 管理 schema 變更
- 避免啟動流程直接自動寫入非必要資料
- 讓不同環境資料庫結構一致

## 9. 測試

測試位置：

```text
src/test/java/com/tku/dietary_app
```

目前已有的重點測試：

- `AuthControllerTest`
- `ApiSecurityAndExceptionTest`
- `AuthServiceTest`
- `AdminServiceTest`
- `DietRecordServiceTest`
- `BodyStatusServiceTest`
- `BodyMetricsServiceTest`
- `JwtUtilTest`

這些測試大致覆蓋：

- auth 流程
- security 與例外處理
- admin 高風險流程
- JWT 時效與驗證
- body metrics 計算

## 10. 前端串接時要注意的事

- Auth API 與一般 API 的回傳格式不同
- App 端需自行保存 `accessToken` 與 `refreshToken`
- refresh token 需要在 access token 過期後主動呼叫 `/api/refresh`
- 圖片欄位如 `avatarUrl`、`photoUrl` 若為相對路徑，前端要自己補 host
- `message` 欄位不是所有成功 API 都一定有
- 錯誤回傳格式可能依例外類型不同，前端應優先看 HTTP status

## 11. 文件建議閱讀順序

若是第一次接手這個後端，建議閱讀順序：

1. `config/SecurityConfig.java`
2. `controller/AuthController.java`
3. `service/AuthService.java`
4. `controller/UserProfileController.java`
5. `controller/DietRecordController.java`
6. `controller/BodyStatusController.java`
7. `controller/DietaryAgentController.java`
8. `controller/AdminController.java`
9. `dto/` 內 request / response 類別
10. `src/main/resources/application.properties`

## 12. 相關文件

目前建議搭配閱讀：

- `docs/FRONTEND_BACKEND_INTEGRATION_ZH.md`
- `docs/POSTMAN_TEST_FLOW.md`
- `postman/DietaryApp.postman_collection.json`
- `docs/BACKEND_REVIEW_2026-08-06.md`
