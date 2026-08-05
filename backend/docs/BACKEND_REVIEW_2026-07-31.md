# 後端檢查報告

檢查日期: 2026-07-31  
專案: `dietary_app/backend`

## 先說結論

目前後端可以編譯、測試也能跑過，但整體狀態比較像「開發可用、上線風險偏高」。

這次檢查中，優先度最高的是:

1. 敏感設定仍保留預設值，包含資料庫密碼與 JWT secret。
2. 安全路由與實際 controller 路徑不一致，`/dietary-agent/**` 沒有被清楚納入 security 規則。
3. 飲食紀錄更新與檔案上傳缺少驗證，容易造成資料被清空或非預期檔案上傳。
4. 錯誤處理與測試覆蓋率不足，很多執行時問題不容易被提早發現。

## 主要 Findings

### P1 敏感設定使用可預測預設值，不適合任何共用或正式環境

- 位置: [application.properties](/abs/path/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/resources/application.properties:6)
- 相關行:
  - `spring.datasource.password=${DB_PASSWORD:1234}`
  - `jwt.secret=${JWT_SECRET:DietaryAppSecretKeyForJWTAuthentication123456}`

風險:

- 如果 `.env` 沒有正確載入，系統會直接用弱密碼與固定 JWT secret 啟動。
- 固定 secret 代表任何拿到字串的人都能自行簽 JWT。
- 這類設定很容易在 demo、測試機或新同事環境中被直接沿用到外部可連線環境。

建議修正:

- 移除預設密碼與 JWT secret，改成啟動時必填。
- 至少在非 `local/dev` profile 下，缺少這些值就應直接 fail fast。
- 補上不同環境的設定分層，例如 `application-local.properties`、`application-prod.properties`。

### P1 Security 規則與實際 API 路徑不一致，容易造成權限行為跟預期不同

- 位置:
  - [SecurityConfig.java](/abs/path/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/config/SecurityConfig.java:49)
  - [DietaryAgentController.java](/abs/path/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/controller/DietaryAgentController.java:15)

現況:

- `SecurityConfig` 只明確處理 `/api/dietary/**`，但 controller 實際路徑是 `/dietary-agent/**`。
- `anyRequest().authenticated()` 會讓 `/dietary-agent/dish-nutrition` 也需要登入，但這不是設定檔中清楚表達出來的規則。
- 之後如果團隊以為 `/api/dietary/**` 才是正式入口，很容易改錯地方。

風險:

- 權限政策與實作脫節，未來擴充時容易出現漏保護或誤封鎖。
- 前後端對 API path 的理解可能不一致，造成整合錯誤。

建議修正:

- 統一路徑命名，建議全部改到 `/api/dietary/**` 或在 security 中明確加入 `/dietary-agent/**`。
- 對公開與需驗證的 dietary endpoint 分開定義，不要依賴 `anyRequest()` 隱性接住。

### P1 飲食照片與頭像上傳缺少檔案型別/內容驗證

- 位置:
  - [DietRecordService.java](/abs/path/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/service/DietRecordService.java:131)
  - [AvatarController.java](/abs/path/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/controller/AvatarController.java:52)

現況:

- 檔案副檔名完全取自 `getOriginalFilename()`。
- 直接 `Files.copy(...)` 寫入 uploads。
- 沒有驗證 MIME type、實際內容、允許副檔名白名單，也沒有防止超大量重複上傳的清理策略。

風險:

- 可上傳偽裝圖片的惡意檔案。
- 若靜態檔案設定或代理層配置不當，可能衍生檔案暴露風險。
- 未來若支援更多格式，沒有集中驗證邏輯會越來越難控管。

建議修正:

- 僅允許明確白名單，例如 `.jpg/.jpeg/.png/.webp`。
- 驗證 `contentType` 與實際檔案內容。
- 針對大小、檔名、覆蓋策略與舊檔刪除補上規則。

### P1 RuntimeException 一律映射成 500，會把授權或查無資料誤判成伺服器錯誤

- 位置:
  - [GlobalExceptionHandler.java](/abs/path/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/exception/GlobalExceptionHandler.java:45)
  - [DietRecordService.java](/abs/path/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/service/DietRecordService.java:112)

現況:

- `RuntimeException` 直接回 `500 INTERNAL_SERVER_ERROR`。
- service 層很多「找不到資料」與「沒有權限」都仍然用 `RuntimeException`。

風險:

- 前端無法正確區分 401/403/404/409。
- 監控會把正常業務錯誤誤算成系統故障。
- 除錯與 API 契約都會變得混亂。

建議修正:

- 建立自訂例外，例如 `ResourceNotFoundException`、`ForbiddenOperationException`、`ConflictException`。
- 在 `@RestControllerAdvice` 中分別映射為 404、403、409。

### P2 飲食紀錄更新會直接覆蓋營養欄位，容易把既有資料清成 `null`

- 位置: [DietRecordService.java](/abs/path/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/service/DietRecordService.java:91)

現況:

- `create()` 會先打 partner API 補齊營養資料。
- 但 `updateByAdmin()` 與 `update()` 直接 `setCalories/setProtein/setFat/setCarbohydrates` 使用 request 值。
- 若前端只想改描述或餐別，未傳入營養欄位時，原資料就會被蓋成 `null`。

風險:

- 資料完整性下降。
- 前端做 partial update 時很容易踩雷。

建議修正:

- 明確區分 `PUT` 全量更新與 `PATCH` 部分更新。
- 若保留現有設計，至少在 `null` 時保留舊值。
- 若 `dishName` 被修改，重新觸發營養估算或明確要求前端一併送值。

### P2 `UserProfileController` 直接回 entity，且 onboarding/profile 的錯誤處理重複而分散

- 位置:
  - [UserProfileController.java](/abs/path/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/controller/UserProfileController.java:61)
  - [UserProfileService.java](/abs/path/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/service/UserProfileService.java:20)

現況:

- controller 中大量手動抓 `SecurityContextHolder`、手動組 401/500 response。
- `completeOnboarding()` 和 `getUserProfile()` 都各自 `try/catch Exception`。
- 回傳內容直接帶 `UserProfile` entity。

風險:

- controller 邏輯重複，之後每個 endpoint 都可能各自長出不同錯誤格式。
- entity 一旦新增敏感欄位、關聯或 lazy 載入需求，回傳風險會增加。

建議修正:

- 把「取得目前登入使用者」抽成共用元件或使用 `@AuthenticationPrincipal`。
- 由全域 exception handler 統一處理錯誤，不要 controller 自己吞 `Exception`。
- 對外回傳 DTO，而不是直接回 entity。

### P2 多個管理端 CRUD 沒有 `@Valid` 與欄位約束，容易把不完整資料寫進 DB

- 位置:
  - [AdminController.java](/abs/path/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/controller/AdminController.java:45)
  - [DietRecordRequest.java](/abs/path/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/dto/DietRecordRequest.java:6)
  - [AdminUserRequest.java](/abs/path/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/dto/AdminUserRequest.java:6)
  - [RestaurantRequest.java](/abs/path/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/dto/RestaurantRequest.java:6)
  - [MenuItemRequest.java](/abs/path/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/dto/MenuItemRequest.java:6)

現況:

- 多數 admin CRUD 的 `@RequestBody` 都沒有 `@Valid`。
- 這幾個 DTO 幾乎沒有欄位驗證。
- DB 層雖然有 `nullable = false`，但錯誤會延後到 persistence 階段才爆。

風險:

- 錯誤訊息不好懂。
- API 契約不明確。
- 前端很容易送出半套資料才在 DB transaction 階段失敗。

建議修正:

- 在 controller 入口補 `@Valid`。
- 為 DTO 加上 `@NotBlank`、`@NotNull`、範圍驗證與 enum 驗證。

### P2 `application.properties` 仍保留開發導向設定，正式環境噪音與風險偏高

- 位置: [application.properties](/abs/path/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/resources/application.properties:9)

現況:

- `spring.jpa.hibernate.ddl-auto=update`
- `spring.jpa.show-sql=true`
- 顯式指定 `hibernate.dialect`

風險:

- `ddl-auto=update` 在正式環境可能造成不可控 schema 變更。
- `show-sql=true` 會增加 log 噪音，還可能把敏感查詢內容寫進 log。
- 測試輸出已出現 Hibernate 對 dialect 的 deprecation warning。

建議修正:

- 正式環境改用 migration 工具，例如 Flyway 或 Liquibase。
- 預設關閉 `show-sql`，需要時只在 local profile 打開。
- 移除多餘的 dialect 設定。

### P3 測試覆蓋率非常低，目前幾乎無法防回歸

- 位置: [DietaryAppApplicationTests.java](/abs/path/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/test/java/com/tku/dietary_app/DietaryAppApplicationTests.java:7)

現況:

- 目前只有一個 `contextLoads()`。
- 沒有 controller、service、security、repository 的行為測試。

風險:

- 權限、驗證、partner API fallback、檔案上傳等高風險邏輯都沒有保護網。
- 未來重構很難判斷是否破壞既有功能。

建議修正:

- 優先補以下測試:
  - auth/register/login 成功與失敗案例
  - admin route 的角色授權
  - diet record create/update 對營養欄位的處理
  - 上傳 API 的檔案格式限制
  - global exception handler 的 status code 映射

## 其他觀察

### `UserProfileService` 會把 `healthConditions` 存成逗號字串

- 位置: [UserProfileService.java](/abs/path/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/service/UserProfileService.java:38)

這不一定是 bug，但代表:

- 未來若要查詢單一疾病、做統計或避免值內本身含逗號，會比較難處理。
- 可以考慮改為獨立表、JSON column，或至少統一定義 enum/value list。

### `AvatarController` 混用 `userId` 與 `profileId` 查詢

- 位置: [AvatarController.java](/abs/path/C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/controller/AvatarController.java:48)

這段程式容忍 `findByUserId(userId)` 找不到時再回退 `findById(userId)`，表示 API 參數語意本身不夠乾淨。長期來看建議固定只接受一種 id。

## 建議修正順序

1. 先修安全與設定:
   - JWT secret / DB password / route policy / upload 驗證
2. 再修資料正確性:
   - diet record update 行為 / exception 類型 / DTO validation
3. 最後補可維護性:
   - DTO 回傳模型 / migration / 測試覆蓋 / controller 簡化

## 本次驗證

- 已執行 `./mvnw.cmd test`
- 結果: `BUILD SUCCESS`
- 但測試內容只有 Spring context 啟動，不能代表主要功能已被充分驗證
