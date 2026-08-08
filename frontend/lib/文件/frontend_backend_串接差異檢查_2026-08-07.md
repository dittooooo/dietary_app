# Frontend / Backend 串接差異檢查

日期：2026-08-07

這份文件只整理目前 `frontend` 與 `backend` 實際程式碼之間的串接差異，目標是回答：

- 前端現在若要正式接上後端，還需要改哪些地方
- 哪些地方是「一定要先改」，不然會直接串不起來
- 哪些地方是「可以先跑，但資料會錯或流程不完整」

---

## 1. 結論先看

目前前端與後端**不是完全不能連**，但有幾個核心落差會讓登入後流程不完整，甚至某些功能直接打錯 API：

### 一定要先改的項目

1. **Auth token 儲存格式不對**
   - backend 登入 / 註冊回傳的是 `AuthResponse`
   - frontend 目前還在用舊邏輯，把整包 response 當成單一 `token` 存
   - 影響：
     - `jwt_token` 可能根本沒存到正確 access token
     - refresh token 流程完全沒接
     - `needsOnboarding` 也沒正確接上

2. **AI 飲食問答 API 路徑打錯**
   - frontend 打的是 `/dietary/ask-weekly-analysis`
   - backend 實際是 `/dietary-agent/ask`
   - 這一塊目前會直接打不到

3. **管理端 service 還保留已被 backend 移除的 restaurants / menus API**
   - frontend 還在打：
     - `/api/admin/restaurants/**`
     - `/api/admin/menus/**`
   - backend 目前 controller 已沒有這兩組 API
   - 這些頁面若進去操作，會直接失敗

4. **個人資料 / onboarding 的欄位值格式還沒完全對齊**
   - frontend 目前把 `dietGoal` 送成逗號字串
   - backend 現在的 `OnboardingRequest` / `UserProfileResponse` 風格是單一值欄位
   - `petType` 前端目前也還是 UI 自定字串，不一定等於 backend 預期值

5. **刪除帳號 API 前端有呼叫，但 backend 目前沒有對應 endpoint**
   - frontend 打 `/api/user/account`
   - backend 沒有這支 controller

---

## 2. 前端目前已可對上的部分

以下功能大方向是對得上的，只是還有格式或解析細節要補：

- `POST /api/login`
- `POST /api/register`
- `POST /api/user/onboarding`
- `GET /api/user/profile`
- `GET /api/diet-records`
- `POST /api/diet-records`
- `PUT /api/diet-records/{id}`
- `DELETE /api/diet-records/{id}`
- `POST /api/diet-records/{id}/photo`
- `GET /api/body-status`
- `POST /api/body-status/settle`
- `POST /api/user/avatar`
- `GET /api/admin/users`
- `GET /api/admin/users/{id}`
- `POST /api/admin/users`
- `PUT /api/admin/users/{id}`
- `DELETE /api/admin/users/{id}`
- `GET /api/admin/diet-records`
- `POST /api/admin/diet-records`
- `PUT /api/admin/diet-records/{id}`
- `DELETE /api/admin/diet-records/{id}`

---

## 3. 必改清單

### 3.1 AuthService 需要改成吃 `AuthResponse`

參考：

- frontend: `frontend/lib/services/auth_service.dart`
- backend: `backend/src/main/java/com/tku/dietary_app/dto/AuthResponse.java`
- backend: `backend/src/main/java/com/tku/dietary_app/controller/AuthController.java`

目前問題：

- frontend `login()` 仍然假設成功後可能拿到「純 token 字串」或舊格式資料
- frontend `register()` 還在讀 `data['token']`
- backend 現在回傳欄位是：
  - `accessToken`
  - `refreshToken`
  - `tokenType`
  - `needsOnboarding`
  - `accessTokenExpiresInSeconds`
  - `refreshTokenExpiresInSeconds`

前端應改：

- `jwt_token` 改存 `accessToken`
- 另外新增儲存 `refresh_token`
- 成功登入 / 註冊後直接讀 `needsOnboarding`
- 如果 `needsOnboarding == true`，導去 onboarding
- 如果 `needsOnboarding == false`，直接進主頁
- 後續所有 Bearer Token 都應該用 `accessToken`

補充：

- backend 已有 `/api/refresh` 與 `/api/logout`
- frontend 目前完全沒接 refresh 流程

---

### 3.2 ApiClient 需要補 token refresh / 統一 response parsing

參考：

- frontend: `frontend/lib/core/api_client.dart`
- backend: `backend/src/main/java/com/tku/dietary_app/dto/ApiResponse.java`
- backend: `backend/src/main/java/com/tku/dietary_app/controller/AuthController.java`

目前問題：

- `ApiClient` 現在只會在 `401/403` 時跳 dialog
- 不會自動 refresh token
- 不會重送原 request
- 不同 service 還在各自手動解析 `response.body`

前端應改：

- 在 `ApiClient` 統一處理：
  - 自動附加 access token
  - 收到 `401` 時呼叫 `/api/refresh`
  - refresh 成功後重送原 request
  - refresh 失敗才導回登入
- 統一解析 backend 的 `ApiResponse<T>`
  - 一般 API：`{ success, message, data }`
  - auth API：`AuthResponse`

---

### 3.3 AI 小精靈 API 路徑與 request body 要重接

參考：

- frontend: `frontend/lib/services/diet_service.dart`
- backend: `backend/src/main/java/com/tku/dietary_app/controller/DietaryAgentController.java`

目前問題：

- frontend 呼叫：`/dietary/ask-weekly-analysis`
- backend 實際 endpoint：
  - `POST /dietary-agent/ask`
  - `POST /dietary-agent/dish-nutrition`

前端應改：

- 把 `askWeeklyAnalysis()` 改打 `/dietary-agent/ask`
- request body 也要對照 `DietaryAskRequest`
- 如果首頁聊天要問單一食物營養，應考慮改接 `/dietary-agent/dish-nutrition`

---

### 3.4 AdminService 要移除或關閉 restaurants / menus 功能

參考：

- frontend: `frontend/lib/services/admin_service.dart`
- backend: `backend/src/main/java/com/tku/dietary_app/controller/AdminController.java`

目前問題：

- frontend 仍保留：
  - `listRestaurants / createRestaurant / updateRestaurant / deleteRestaurant`
  - `listMenuItems / createMenuItem / updateMenuItem / deleteMenuItem`
- backend 已經沒有對應 controller / dto / entity / repository

前端應改：

- 先把這兩塊 UI 隱藏或標記為未開放
- 或直接移除 service 與頁面入口

否則：

- 使用者一點就會打到不存在的 API

---

### 3.5 刪除帳號按鈕目前是假的

參考：

- frontend: `frontend/lib/views/auth/edit_profile_page.dart`
- backend: controller 內未找到 `/api/user/account`

目前問題：

- frontend 會打 `DELETE /api/user/account`
- backend 目前沒有這支 API

前端應改：

- 先隱藏該按鈕
- 或保留 UI，但標示「尚未開放」

---

## 4. 資料格式需要修正的地方

### 4.1 onboarding / edit profile 的 `dietGoal` 不建議再送逗號字串

參考：

- frontend: `frontend/lib/views/auth/initial_info_page.dart`
- frontend: `frontend/lib/views/auth/edit_profile_page.dart`
- backend: `backend/src/main/java/com/tku/dietary_app/dto/OnboardingRequest.java`

目前問題：

- frontend 送：
  - `dietGoal: _goals.join(', ')`
- 但 backend 現在的欄位是單一 `String dietGoal`

風險：

- 如果前端允許多選，backend 最後只會收到一個拼接字串
- 後續推薦、展示、統計都會變得不好處理

建議：

- 前端改成單選目標
- 直接送 backend 規格值

---

### 4.2 `petType` 現在看起來還沒對齊 backend enum / 規格值

參考：

- frontend: `frontend/lib/views/auth/initial_info_page.dart`
- frontend: `frontend/lib/views/auth/edit_profile_page.dart`
- backend: `backend/docs/FRONTEND_BACKEND_INTEGRATION_ZH.md`

目前問題：

- frontend 還在用 UI 自定字串
- backend 文件示例比較像固定值，例如 `DOG`

建議：

- 前端 UI 可以顯示中文
- 但送 API 時要轉成 backend 規格值，例如：
  - `DOG`
  - 其他若未實作就不要先送

---

### 4.3 `healthConditions` 雖然型別對得上，但值域最好也做 mapping

參考：

- frontend: `frontend/lib/views/auth/initial_info_page.dart`
- backend: `backend/src/main/java/com/tku/dietary_app/dto/OnboardingRequest.java`

目前狀況：

- frontend 已經送 `List<String>`
- backend 也收 `List<String>`

但建議：

- 前端不要直接送顯示文案
- 應送固定代碼，例如：
  - `DIABETES`
  - `HYPERTENSION`
  - `NONE`

---

### 4.4 Android base URL 目前高機率有問題

參考：

- frontend: `frontend/lib/config/api_config.dart`

目前問題：

- Android 寫的是 `http://127.0.0.1:8080/api`
- 如果是 Android emulator，通常應該是 `10.0.2.2`
- 除非你真的有做 `adb reverse tcp:8080 tcp:8080`

建議：

- 開發環境至少區分：
  - Android emulator
  - Web
  - Desktop
- 或改成可從 `--dart-define` / env 設定 base URL

---

## 5. 飲食紀錄功能的注意點

### 5.1 DietService 主路徑基本正確，但回傳資料解析仍偏舊

參考：

- frontend: `frontend/lib/services/diet_service.dart`
- backend: `backend/src/main/java/com/tku/dietary_app/controller/DietRecordController.java`
- backend: `backend/src/main/java/com/tku/dietary_app/dto/DietRecordResponse.java`

目前狀況：

- API 路徑用 `/diet-records` 是對的
- backend 也確實回傳 `ApiResponse.success(data)`

但前端仍要注意：

- create / update 成功後，真正資料在 `response.body.data`
- 不應假設回來的是裸資料物件

---

### 5.2 `date` / `mealDate` 欄位名稱曾有歷史差異，前端建議統一

參考：

- frontend: `frontend/lib/services/diet_service.dart`
- frontend: `frontend/lib/views/records/diary_page.dart`
- backend: `backend/src/main/java/com/tku/dietary_app/dto/DietRecordRequest.java`
- backend: `backend/src/main/java/com/tku/dietary_app/dto/DietRecordResponse.java`

目前狀況：

- frontend create / update 時送的是 `mealDate`
- backend request DTO 欄位叫 `date`
- 但 diary 頁面目前也在兼容 `mealDate`
- backend response DTO 回傳欄位其實是 `date`

建議：

- 前端統一改成以 `date` 為主
- 顯示層如果要兼容舊資料，可短期保留 fallback

這一項未必會立刻壞，但屬於高風險不一致點。

---

### 5.3 飲食頁目前對 `nutrition` 的處理可用，但有點混合舊新格式

參考：

- frontend: `frontend/lib/views/records/diary_page.dart`
- backend: `backend/src/main/java/com/tku/dietary_app/dto/DietRecordResponse.java`

目前狀況：

- backend 回傳 `nutrition` 物件
- frontend 已經有處理 `Map` 與 `String` 兩種情況

建議：

- 最後收斂成只吃 backend 現行 `nutrition` object
- 不再依賴字串 regex 解析營養資訊

---

## 6. 管理端還要補的地方

### 6.1 Admin API response 解析要改成吃 `ApiResponse.data`

參考：

- frontend: `frontend/lib/services/admin_service.dart`
- backend: `backend/src/main/java/com/tku/dietary_app/controller/AdminController.java`

目前問題：

- frontend 多處仍在假設 `response.body` 可能直接是 list 或物件
- backend 實際大多包在 `ApiResponse.data`

建議：

- `listUsers()`
- `getUserDetail()`
- `createUser()`
- `updateUser()`
- `listDietRecords()`
- `createDietRecord()`
- `updateDietRecord()`

以上都應統一先拆 `data`

---

### 6.2 管理員上傳頭像目前前端還沒接 `/api/admin/users/{userId}/avatar`

參考：

- backend: `backend/src/main/java/com/tku/dietary_app/controller/AvatarController.java`

目前狀況：

- backend 已支援 admin 幫指定 user 上傳頭像
- frontend 目前只接了自己的 `/api/user/avatar`

如果管理端有這需求：

- 可補一個 admin avatar upload service

---

## 7. 建議前端實作順序

建議照這個順序改，風險最低：

1. 先修 `AuthService` 與 `ApiClient`
2. 再修 onboarding / profile 欄位 mapping
3. 再修 AI 問答 endpoint
4. 再清掉 admin 的 restaurants / menus 舊功能
5. 最後再整理 diary / nutrition / date 欄位一致性

---

## 8. 最小可上線條件

如果目標只是讓一般使用者主流程先能跑，前端至少要完成以下 6 件事：

1. 正確儲存 `accessToken` / `refreshToken`
2. 依 `needsOnboarding` 導頁
3. onboarding 的 `dietGoal` / `petType` / `healthConditions` 做正規 mapping
4. 個人資料讀寫都統一吃 `ApiResponse.data`
5. AI 問答改打 `/dietary-agent/ask`
6. 隱藏「刪除帳號」、「restaurants」、「menus」這些 backend 尚未提供的功能

---

## 9. 總結

目前最需要修的不是畫面，而是 **API contract 對齊**：

- Auth response 格式
- refresh token 流程
- AI endpoint
- onboarding 欄位值 mapping
- admin 舊 API 清理

只要先把上面幾項修掉，前端就能和現在這版 backend 進入可測狀態；否則會出現「表面有連到、實際流程斷在中途」的情況。
