# Dietary App 後端程式碼說明

這份文件的目的是幫你快速理解這個 Spring Boot 後端「整體在做什麼」、「為什麼這樣分層」、「每一層各自負責什麼」。

---

## 1. 這個專案在做什麼

這個後端是一個飲食管理系統，主要有兩大功能：

1. 使用者端功能
   - 註冊
   - 登入
   - 填寫 onboarding
   - 取得自己的個人資料

2. 管理者端功能
   - 管理使用者
   - 管理餐廳
   - 管理菜單
   - 管理飲食紀錄

系統使用：

- Spring Boot：建立 Web API
- Spring Security：處理登入與權限
- JWT：登入後用 token 驗證身分
- Spring Data JPA：操作資料庫
- SQL Server：儲存資料
- Lombok：減少 getter/setter/constructor 樣板碼

---

## 2. 為什麼要這樣分層

這個專案採用 Spring Boot 很常見的分層方式：

```text
controller -> service -> repository -> database
                |
               dto
                |
              entity
```

這樣分類的原因是：讓每一層只做自己該做的事。

### controller

負責接收 HTTP 請求與回傳 HTTP 回應。

例如：

- 接收前端送來的 JSON
- 呼叫 service
- 把結果回傳給前端

它不應該直接寫太多商業邏輯。

### service

負責真正的業務邏輯，也就是「系統怎麼運作」。

例如：

- 註冊時檢查 email 是否重複
- 密碼加密
- 建立 user 與 user profile
- 管理員新增使用者
- 角色字串正規化成 `ROLE_USER` / `ROLE_ADMIN`

### repository

負責跟資料庫溝通。

例如：

- `findByEmail`
- `findById`
- `save`
- `delete`
- 自訂搜尋 query

### entity

負責對應資料庫資料表。

例如：

- `User` 對應 `users`
- `UserProfile` 對應 `user_profile`
- `Restaurant` 對應 `restaurants`

### dto

負責 API 請求資料格式。

也就是前端送來的 JSON 先進 DTO，再交給 service。

這樣做的好處是：

- 不直接把前端資料綁死到資料表
- 可以做欄位驗證
- 未來調整資料表時，比較不會影響 API

### config

放系統設定，例如：

- Spring Security 設定
- JWT 驗證 filter
- 預設管理員初始化

### exception

集中處理錯誤回應，避免每個 controller 都自己重複寫錯誤格式。

---

## 3. 專案主要資料模型

### User

這張表主要處理登入相關資料：

- `email`
- `password`
- `role`
- `hasCompletedOnboarding`

`User` 的重點是：

- `password` 存的是加密後密碼，不是明文
- `role` 用來做權限控制
- `hasCompletedOnboarding` 用來判斷使用者是否填過個人資料

### UserProfile

這張表主要處理使用者的個人資訊：

- `nickname`
- `gender`
- `age`
- `height`
- `weight`
- `healthConditions`
- `dietGoal`
- `petType`
- `dietHistory`

系統把登入資料和個人資料拆開，是因為這兩種資料用途不同：

- `User` 偏登入與權限
- `UserProfile` 偏使用者內容資料

這樣拆開後，資料會比較清楚，也比較符合實務常見設計。

### Restaurant / MenuItem / DietRecord

這三張表就是管理者後台的主要資料：

- `Restaurant`：餐廳資料
- `MenuItem`：菜單資料
- `DietRecord`：飲食紀錄

---

## 4. 整個登入與權限流程怎麼跑

這是最重要的部分。

### 註冊流程

1. 前端呼叫 `/api/register`
2. `AuthController` 接到請求
3. `AuthService` 檢查 email 是否已存在
4. 使用 `BCryptPasswordEncoder` 加密密碼
5. 建立 `User`
6. 儲存到資料庫
7. 產生 JWT token
8. 回傳給前端

### 登入流程

1. 前端呼叫 `/api/login`
2. `AuthController` 收到 email/password
3. `AuthService` 用 email 查 `User`
4. 比對密碼是否正確
5. 正確就用 `JwtUtil` 產生 token
6. 回傳 token

### 帶 token 存取 API 的流程

1. 前端把 token 放進：

```text
Authorization: Bearer <token>
```

2. request 進來時先經過 `JwtAuthenticationFilter`
3. filter 會驗證 JWT
4. 解析出 email
5. 用 email 去資料庫查 `User`
6. 取得 `role`
7. 把登入者資訊與權限寫進 Spring Security
8. 再交給 `SecurityConfig` 判斷這個角色能不能用這個 API

### 角色判斷流程

目前角色有：

- `ROLE_USER`
- `ROLE_ADMIN`

在 `SecurityConfig` 中：

- `/api/register`、`/api/login`：不用登入
- `/api/user/**`：登入即可
- `/api/admin/**`：必須是 `ROLE_ADMIN`

這樣就能做到：

- 一般使用者不能進後台
- 管理者可以進後台

---

## 5. 每個資料夾在做什麼

### `src/main/java/com/tku/dietary_app`

#### `DietaryAppApplication.java`

專案啟動入口。

你可以把它理解成：

- Spring Boot 後端的 main function
- 啟動整個應用程式

#### `config`

放系統設定。

##### `SecurityConfig.java`

決定哪些 API 需要登入、哪些需要 admin 權限。

##### `JwtAuthenticationFilter.java`

每次 request 進來時先檢查 token，並把使用者角色放進 Spring Security。

##### `DefaultAdminInitializer.java`

系統啟動時自動建立或修正預設管理員：

- email 預設 `admin@gmail.com`
- password 預設 `Admin123`
- role 為 `ROLE_ADMIN`

#### `controller`

放 API 入口。

##### `AuthController.java`

負責：

- 註冊
- 登入

##### `UserProfileController.java`

負責：

- onboarding
- 取得目前登入者的 profile

##### `AdminController.java`

負責後台管理 API：

- users
- restaurants
- menus
- diet-records

#### `service`

放真正邏輯。

##### `AuthService.java`

負責：

- 註冊邏輯
- 登入邏輯
- 密碼比對
- token 產生

##### `JwtUtil.java`

負責：

- 產生 JWT
- 驗證 JWT
- 解析 JWT 中的 subject

##### `UserProfileService.java`

負責：

- 建立或更新使用者個人資料
- 查詢使用者個人資料

##### `AdminService.java`

負責：

- 管理者查詢使用者
- 建立使用者
- 修改使用者
- 刪除使用者
- 處理 `role` 與 `UserProfile` 的對應邏輯

##### `RestaurantService.java` / `MenuItemService.java` / `DietRecordService.java`

各自處理後台 CRUD 邏輯。

#### `repository`

放資料庫查詢介面。

這些介面大多繼承 `JpaRepository`，Spring 會幫你自動實作。

例如：

- `UserRepository`
- `UserProfileRepository`
- `RestaurantRepository`

#### `entity`

放資料表對應類別。

這些 class 主要負責：

- 對應資料庫欄位
- 定義欄位型別
- 定義資料表關係

#### `dto`

放前端 request body 對應格式。

例如：

- `RegisterRequest`
- `LoginRequest`
- `OnboardingRequest`
- `AdminUserRequest`

這樣 controller 可以直接收 JSON，並搭配驗證註解檢查欄位。

#### `exception`

##### `GlobalExceptionHandler.java`

集中處理例外，例如：

- validation error
- runtime error

這樣可以統一錯誤回傳格式。

---

## 6. 為什麼這樣寫比較好

### 好處 1：責任分清楚

如果全部邏輯都塞在 controller，檔案會很亂，之後很難維護。

現在這種分層的好處是：

- controller 看 API
- service 看邏輯
- repository 看查詢
- entity 看資料表

找問題比較快。

### 好處 2：比較容易改功能

例如未來你要把 `ROLE_USER` 改成更多角色：

- `ROLE_NUTRITIONIST`
- `ROLE_SUPER_ADMIN`

只要調整 service / security 邏輯，不用把所有 controller 全部重寫。

### 好處 3：比較接近實務專案

這種寫法是很多 Spring Boot 專案會使用的基本結構。

你現在先把這套想法搞懂，以後做：

- 電商
- 訂餐
- 會員系統
- 後台管理系統

都可以套用類似概念。

---

## 7. 目前這份程式碼還有什麼地方可以再改

### 1. 有些中文字串和註解有亂碼

這表示檔案編碼可能不一致。

建議統一：

- IDE 編碼設 UTF-8
- 檔案存檔也用 UTF-8

### 2. `JwtUtil` 與 `application.properties` 還有敏感資訊硬寫

像這種：

- JWT secret
- DB username
- DB password

建議改成環境變數或 profile 設定。

### 3. `/api/login` 回傳格式不一致

目前 register 回 JSON，但 login 回純字串 token。

建議之後統一成 JSON，比較方便前端處理。

### 4. Controller 有些地方自己 try/catch 太多

之後可以把更多錯誤交給 `GlobalExceptionHandler` 統一處理，controller 會更乾淨。

### 5. 測試還不夠多

目前建議補：

- 一般使用者打 admin API 應該 403
- 管理者打 admin API 應該 200
- 無 token 打保護 API 應該被擋

---

## 8. 你可以怎麼讀這份專案

如果你想快速理解，建議照這個順序看：

1. [DietaryAppApplication.java](/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/DietaryAppApplication.java)
2. [SecurityConfig.java](/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/config/SecurityConfig.java)
3. [JwtAuthenticationFilter.java](/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/config/JwtAuthenticationFilter.java)
4. [User.java](/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/entity/User.java)
5. [AuthController.java](/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/controller/AuthController.java)
6. [AuthService.java](/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/service/AuthService.java)
7. [UserProfileController.java](/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/controller/UserProfileController.java)
8. [UserProfileService.java](/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/service/UserProfileService.java)
9. [AdminController.java](/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/controller/AdminController.java)
10. [AdminService.java](/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/service/AdminService.java)

這樣讀，你會先懂：

- 專案怎麼啟動
- 權限怎麼管
- 登入怎麼跑
- 使用者資料怎麼建立
- 管理者 API 怎麼設計

---

## 9. 最後一句話版總結

這個後端的核心想法是：

- 用 `User` 管登入與角色
- 用 `UserProfile` 管個人資料
- 用 JWT 管登入狀態
- 用 Spring Security 管 API 權限
- 用 controller / service / repository 分層，讓每一層只做自己的工作

你如果把這個觀念吃下來，這份專案的骨架就差不多懂了。
---

## 2026-05-06 Diet Record Query Update

Admin diet record management was extended to support:

- all records
- all meals for a specific day
- one specific meal for a specific day
- all meals for a 7-day window

Relevant files:

- [AdminController.java](/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/controller/AdminController.java)
- [DietRecordService.java](/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/service/DietRecordService.java)
- [DietRecordRepository.java](/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/repository/DietRecordRepository.java)
- [DietRecord.java](/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/entity/DietRecord.java)
- [DietRecordRequest.java](/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/dto/DietRecordRequest.java)
- [MealType.java](/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/entity/MealType.java)

API shape:

```text
GET /api/admin/diet-records
GET /api/admin/diet-records?dishName=Chicken
GET /api/admin/diet-records?date=2026-05-06
GET /api/admin/diet-records?date=2026-05-06&mealType=BREAKFAST
GET /api/admin/diet-records?weekStart=2026-05-05
```

Field update:

- `DietRecord` now includes `mealType`
- accepted values: `BREAKFAST`, `LUNCH`, `DINNER`
- the backend also normalizes Chinese input such as `早餐`, `午餐`, `晚餐`

Filtering behavior:

- `date` filters records within that calendar day
- `weekStart` filters records in the next 7 days starting at `weekStart`
- `date` and `weekStart` are mutually exclusive
- records are sorted by `createdAt DESC, id DESC`
