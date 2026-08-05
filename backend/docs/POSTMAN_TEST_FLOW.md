# Dietary App Postman 測試流程

Base URL:

```text
http://localhost:8080
```

Postman 建議先建立 Environment：

| 變數 | 初始值 |
|---|---|
| `baseUrl` | `http://localhost:8080` |
| `userToken` | 空 |
| `adminToken` | 空 |
| `createdUserProfileId` | 空 |
| `restaurantId` | 空 |
| `menuId` | 空 |
| `dietRecordId` | 空 |

所有需要登入的 API 都要加 Header：

```text
Authorization: Bearer <token>
Content-Type: application/json
```

## 1. 一般使用者註冊

Method:

```text
POST {{baseUrl}}/api/register
```

Body:

```json
{
  "email": "user001@gmail.com",
  "password": "User123"
}
```

正確回傳:

```text
HTTP 200 OK
```

```json
{
  "success": true,
  "message": "...",
  "token": "<JWT_TOKEN>",
  "needsOnboarding": true
}
```

前端判斷：

| 欄位 | 用途 |
|---|---|
| `success === true` | 註冊成功 |
| `token` | 存到 localStorage 或狀態管理 |
| `needsOnboarding === true` | 導向 onboarding 頁 |

錯誤範例：

```text
HTTP 400 Bad Request
```

```json
{
  "success": false,
  "message": "..."
}
```

密碼規則目前是 6-18 字，且至少包含小寫英文、大寫英文、數字。

## 2. 一般使用者登入

Method:

```text
POST {{baseUrl}}/api/login
```

Body:

```json
{
  "email": "user001@gmail.com",
  "password": "User123"
}
```

正確回傳:

```text
HTTP 200 OK
```

```text
<JWT_TOKEN>
```

注意：目前 login API 回傳的是純 token 字串，不是 JSON。前端要直接把 response body 當 token 存起來。

## 3. 一般使用者完成 Onboarding

Method:

```text
POST {{baseUrl}}/api/user/onboarding
```

Headers:

```text
Authorization: Bearer {{userToken}}
Content-Type: application/json
```

Body:

```json
{
  "nickname": "測試使用者",
  "gender": "female",
  "age": 22,
  "height": 165.5,
  "weight": 55.2,
  "healthConditions": ["none"],
  "dietGoal": "weight_control",
  "petType": "cat"
}
```

正確回傳:

```text
HTTP 200 OK
```

```json
{
  "success": true,
  "message": "Onboarding ...",
  "data": {
    "id": 1,
    "nickname": "測試使用者",
    "gender": "female",
    "age": 22,
    "height": 165.5,
    "weight": 55.2,
    "healthConditions": "none",
    "dietGoal": "weight_control",
    "petType": "cat",
    "createdAt": "...",
    "updatedAt": "..."
  }
}
```

前端判斷：

| 欄位 | 用途 |
|---|---|
| `success === true` | onboarding 完成 |
| `data` | 使用者個人資料 |

## 4. 一般使用者取得個人資料

Method:

```text
GET {{baseUrl}}/api/user/profile
```

Headers:

```text
Authorization: Bearer {{userToken}}
```

正確回傳:

```text
HTTP 200 OK
```

```json
{
  "success": true,
  "data": {
    "id": 1,
    "nickname": "測試使用者",
    "gender": "female",
    "age": 22,
    "height": 165.5,
    "weight": 55.2,
    "healthConditions": "none",
    "dietGoal": "weight_control",
    "petType": "cat"
  }
}
```

尚未 onboarding:

```text
HTTP 404 Not Found
```

```json
{
  "success": false,
  "message": "..."
}
```

## 5. 一般使用者測試 Admin 權限

Method:

```text
GET {{baseUrl}}/api/admin/users
```

Headers:

```text
Authorization: Bearer {{userToken}}
```

正確結果：

```text
HTTP 403 Forbidden
```

這代表一般使用者不能使用後台 API，角色權限有生效。

## 6. 管理者登入

預設管理者帳號：

```text
email: admin@gmail.com
password: Admin123
role: ROLE_ADMIN
```

Method:

```text
POST {{baseUrl}}/api/login
```

Body:

```json
{
  "email": "admin@gmail.com",
  "password": "Admin123"
}
```

正確回傳:

```text
HTTP 200 OK
```

```text
<JWT_TOKEN>
```

把這個 token 存成 `adminToken`。

## 6-1. 登入失敗測試

Method:

```text
POST {{baseUrl}}/api/login
```

Body:

```json
{
  "email": "admin@gmail.com",
  "password": "WrongPassword123"
}
```

正確回傳:

```text
HTTP 401 Unauthorized
```

```json
{
  "error": "帳號或密碼錯誤"
}
```

前端判斷：

| 情境 | HTTP 狀態 | 處理方式 |
|---|---:|---|
| 密碼錯誤 | 401 | 顯示登入失敗訊息，不要當成成功登入 |
| 帳號不存在 | 401 | 顯示登入失敗訊息 |

## 7. 管理者查詢使用者

Method:

```text
GET {{baseUrl}}/api/admin/users
```

Headers:

```text
Authorization: Bearer {{adminToken}}
```

正確回傳:

```text
HTTP 200 OK
```

```json
[
  {
    "id": 1,
    "nickname": "測試使用者",
    "gender": "female",
    "age": 22,
    "height": 165.5,
    "weight": 55.2,
    "healthConditions": "none",
    "dietGoal": "weight_control",
    "petType": "cat"
  }
]
```

搜尋使用者：

```text
GET {{baseUrl}}/api/admin/users?keyword=user001
```

## 8. 管理者新增使用者

Method:

```text
POST {{baseUrl}}/api/admin/users
```

Headers:

```text
Authorization: Bearer {{adminToken}}
Content-Type: application/json
```

Body:

```json
{
  "email": "created-by-admin@gmail.com",
  "password": "Adminuser123",
  "role": "ROLE_USER",
  "name": "後台新增使用者",
  "gender": "male",
  "age": 30,
  "height": 175.0,
  "weight": 70.0,
  "specialDisease": "none",
  "dietGoal": "maintain",
  "dietaryHistory": "normal",
  "petType": "dog"
}
```

正確回傳:

```text
HTTP 200 OK
```

```json
{
  "id": 2,
  "nickname": "後台新增使用者",
  "gender": "male",
  "age": 30,
  "height": 175.0,
  "weight": 70.0,
  "healthConditions": "none",
  "dietHistory": "normal",
  "dietGoal": "maintain",
  "petType": "dog"
}
```

如果要新增管理者，把 `role` 改成：

```json
{
  "role": "ROLE_ADMIN"
}
```

程式也接受 `ADMIN`，會自動轉成 `ROLE_ADMIN`。

## 9. 管理者修改使用者

Method:

```text
PUT {{baseUrl}}/api/admin/users/{{createdUserProfileId}}
```

Body:

```json
{
  "email": "created-by-admin@gmail.com",
  "password": "",
  "role": "ROLE_USER",
  "name": "後台修改使用者",
  "gender": "male",
  "age": 31,
  "height": 176.0,
  "weight": 71.0,
  "specialDisease": "none",
  "dietGoal": "muscle_gain",
  "dietaryHistory": "high_protein",
  "petType": "dog"
}
```

正確回傳:

```text
HTTP 200 OK
```

回傳更新後的 user profile JSON。

## 10. 管理者管理餐廳

新增餐廳:

```text
POST {{baseUrl}}/api/admin/restaurants
```

```json
{
  "name": "健康餐盒",
  "address": "台北市測試路 1 號",
  "phone": "02-12345678",
  "menu": "雞胸餐, 鮭魚餐",
  "review": "低油低鹽",
  "stars": 5,
  "latitude": 25.033,
  "longitude": 121.5654,
  "healthLevel": "A"
}
```

正確回傳:

```text
HTTP 200 OK
```

回傳 restaurant JSON，包含 `id`。

查詢餐廳:

```text
GET {{baseUrl}}/api/admin/restaurants
GET {{baseUrl}}/api/admin/restaurants?name=健康
```

修改餐廳:

```text
PUT {{baseUrl}}/api/admin/restaurants/{{restaurantId}}
```

刪除餐廳:

```text
DELETE {{baseUrl}}/api/admin/restaurants/{{restaurantId}}
```

正確回傳:

```text
HTTP 200 OK
```

```text
刪除成功訊息字串
```

## 11. 管理者管理菜單

新增菜單:

```text
POST {{baseUrl}}/api/admin/menus
```

```json
{
  "restaurantName": "健康餐盒",
  "dishName": "舒肥雞胸餐",
  "ingredients": "雞胸肉, 花椰菜, 糙米",
  "nutrition": "protein:35g, carb:45g, fat:10g",
  "recommendLevel": "high"
}
```

正確回傳:

```text
HTTP 200 OK
```

回傳 menu item JSON，包含 `id`。

查詢菜單:

```text
GET {{baseUrl}}/api/admin/menus
GET {{baseUrl}}/api/admin/menus?dishName=雞胸
```

修改菜單:

```text
PUT {{baseUrl}}/api/admin/menus/{{menuId}}
```

刪除菜單:

```text
DELETE {{baseUrl}}/api/admin/menus/{{menuId}}
```

正確回傳:

```text
HTTP 200 OK
```

```text
刪除成功訊息字串
```

## 12. 管理者管理飲食紀錄

新增飲食紀錄:

```text
POST {{baseUrl}}/api/admin/diet-records
```

```json
{
  "dishName": "舒肥雞胸餐",
  "nutrition": "protein:35g, carb:45g, fat:10g",
  "cumulativeNutrition": "protein:80g, carb:120g, fat:30g",
  "healthLevel": "A"
}
```

正確回傳:

```text
HTTP 200 OK
```

回傳 diet record JSON，包含 `id`。

查詢飲食紀錄:

```text
GET {{baseUrl}}/api/admin/diet-records
GET {{baseUrl}}/api/admin/diet-records?dishName=雞胸
```

修改飲食紀錄:

```text
PUT {{baseUrl}}/api/admin/diet-records/{{dietRecordId}}
```

刪除飲食紀錄:

```text
DELETE {{baseUrl}}/api/admin/diet-records/{{dietRecordId}}
```

正確回傳:

```text
HTTP 200 OK
```

```text
刪除成功訊息字串
```

## 13. 管理者刪除使用者

Method:

```text
DELETE {{baseUrl}}/api/admin/users/{{createdUserProfileId}}
```

Headers:

```text
Authorization: Bearer {{adminToken}}
```

正確回傳:

```text
HTTP 200 OK
```

```text
刪除成功訊息字串
```

注意：

- 這裡刪的是 `UserProfile` 的 id，不是 `User` 的 id。
- 建議先用 `Create User By Admin` 建一筆測試資料，再刪除。

## 前端狀態判斷整理

| 情境 | HTTP 狀態 | 前端建議 |
|---|---:|---|
| 註冊成功 | 200 | 存 token，導向 onboarding |
| 登入成功 | 200 | response body 是 token 字串 |
| validation 錯誤 | 400 | 顯示欄位錯誤或 message |
| 沒帶 token | 401 或 403 | 導向登入 |
| token 無效 | 401 | 清掉 token，導向登入 |
| 一般使用者打 admin API | 403 | 顯示無權限 |
| 查不到 profile | 404 | 導向 onboarding |
| server error | 500 | 顯示系統錯誤 |

## 建議測試順序

1. 啟動 Spring Boot 後端。
2. 匯入 `postman/DietaryApp.postman_collection.json`。
3. 建立 Postman Environment，設定 `baseUrl=http://localhost:8080`。
4. 跑「一般使用者註冊」，確認存到 `userToken`。
5. 跑「一般使用者完成 Onboarding」。
6. 跑「一般使用者取得個人資料」。
7. 跑「一般使用者測試 Admin 權限」，應該得到 403。
8. 跑「管理者登入」，確認存到 `adminToken`。
9. 跑所有 `/api/admin/**` API，應該得到 200。
---

## 2026-05-06 Admin Diet Record 更新

`/api/admin/diet-records` 現在支援管理者依日期與餐別查詢飲食紀錄。

支援的查詢方式：

```text
GET {{baseUrl}}/api/admin/diet-records
GET {{baseUrl}}/api/admin/diet-records?dishName=Chicken
GET {{baseUrl}}/api/admin/diet-records?date=2026-05-06
GET {{baseUrl}}/api/admin/diet-records?date=2026-05-06&mealType=BREAKFAST
GET {{baseUrl}}/api/admin/diet-records?weekStart=2026-05-05
```

查詢規則：

- `date` format: `yyyy-MM-dd`
- `weekStart` format: `yyyy-MM-dd`
- `mealType` supports `BREAKFAST`, `LUNCH`, `DINNER`
- `date` and `weekStart` cannot be used together
- `date` 格式：`yyyy-MM-dd`
- `weekStart` 格式：`yyyy-MM-dd`
- `mealType` 支援 `BREAKFAST`、`LUNCH`、`DINNER`
- `date` 與 `weekStart` 不能同時使用

新增／修改飲食紀錄的 request body 現在也支援 `mealType`：

```json
{
  "dishName": "Sous Vide Chicken Box",
  "nutrition": "protein:35g, carb:45g, fat:10g",
  "cumulativeNutrition": "protein:80g, carb:120g, fat:30g",
  "healthLevel": "A",
  "mealType": "BREAKFAST"
}
```

