# 後端檢查報告 - 2026-08-06

## 檢查範圍

這份報告是依照目前 `backend` 專案最新狀態重新整理，目的不是回顧舊問題，而是反映「現在還有哪些地方值得繼續修」。

本次檢查基準：

- 已改為短效 `access token` + `refresh token`
- `Restaurant` / `MenuItem` 相關程式已移除
- 已導入 Flyway migration
- 管理員建立 / 更新使用者的 email 正規化與重複檢查已補上
- 預設啟動時不再自動建立 admin 帳號
- 目前 `.\mvnw.cmd test` 可通過

## 目前整體狀態

- 編譯與測試狀態：`PASS`
- 目前最大風險：仍有少數檔案疑似保留舊編碼內容，導致部分快速檢查時會看到亂碼
- 目前最大技術債：上游 dietary partner API 雖然已有 timeout，但還沒有更完整的韌性保護
- 目前最大可維護性問題：少部分 API 契約與錯誤處理仍可再統一

## 已完成項目

以下問題目前已視為處理完成，或至少已完成第一階段修補：

- `P1` 資料庫 migration 缺失
  - 已導入 Flyway
  - 已新增核心 schema migration
- 管理端 email 正規化與重複檢查
  - `AdminService` 已做 `trim().toLowerCase()`
  - 建立 / 更新時已檢查 email 是否重複
- 啟動時自動寫入 admin 資料
  - `DefaultAdminInitializer` 已改成需要明確開啟設定才會啟用
- 大部分明顯亂碼訊息
  - `src` 內主要 controller / dto / service 已清過一輪
- 多數常用成功回應格式
  - 多個 controller 已改用 `ApiResponse`

## 目前仍建議處理的問題

### P2

#### 1. dietary partner API 只有 timeout，還沒有 retry / circuit breaker / fallback

嚴重度：中

目前狀態：

- [RestTemplateConfig.java](C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/config/RestTemplateConfig.java) 已有 connect / read timeout
- [DietaryAgentService.java](C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/service/DietaryAgentService.java) 已把上游例外包成 `UpstreamServiceException`

還缺少的部分：

- 沒有 retry 策略
- 沒有 circuit breaker
- 沒有 fallback
- 沒有限流或 bulkhead 類保護

影響：

- 上游若持續不穩，雖然不會無限卡住，但使用者仍會直接收到失敗
- 系統對上游異常的恢復能力還不夠好

建議修正：

- 若這個上游是核心依賴，下一步可導入 `resilience4j`
- 至少補：
  - timeout
  - retry
  - circuit breaker
  - 明確 fallback 策略

#### 2. Auth API 的回傳格式仍是特例，與其他 controller 沒完全統一

嚴重度：中

目前狀態：

- 多數一般業務 API 已改成 `ApiResponse`
- 但 [AuthController.java](C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/controller/AuthController.java) 仍直接回 `AuthResponse`
- `logout` 目前回 `Map<String, Object>`

影響：

- 前端整合 auth 與非 auth API 時，仍要保留不同解析邏輯
- 若之後再擴充 auth flow，容易繼續分岔

建議修正：

- 選一個方向固定下來：
  - 保持 auth 為特例，但明確文件化
  - 或把 `logout` 至少也包成和其他 API 一致的 response envelope

#### 3. 仍缺少幾個高風險流程的專門測試

嚴重度：中

目前已有：

- controller 測試
- diet record / body metrics / body status / admin service 測試

目前較值得補的：

- `AuthService.refresh()` 的 rotation、過期 token、錯誤 token 類型
- `JwtUtil` 的 access / refresh token 驗證
- `DietaryAgentService` 的 response parsing edge cases
- `AvatarController` / `ImageStorageService` 更細的檔案驗證案例

影響：

- 現在基礎測試是綠的，但 auth 與上游整合的核心安全流程還不夠有保護

建議修正：

- 先補 service 層測試，再視需要補整合測試

### P3

#### 4. 少數檔案可能仍保留編碼不一致問題

嚴重度：低

目前狀態：

- `src` 底下大多數明顯亂碼已清除
- 但重新檢視時，像 [AuthController.java](C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/controller/AuthController.java) 與 [DietaryAgentService.java](C:/Users/Cyborg%2015/Desktop/dietary_app/backend/src/main/java/com/tku/dietary_app/service/DietaryAgentService.java) 在某些讀取情境下仍會顯示疑似舊編碼內容

影響：

- 有機會造成維護時閱讀困難
- 若未來用不同編輯器或工具鏈開啟，可能再次出現文字毀損

建議修正：

- 確認所有 `.java` / `.properties` 都是 UTF-8
- 對仍可疑的檔案做一次明確重存
- 若團隊有 IDE 設定，統一專案編碼

#### 5. response envelope 雖然已大致統一，但仍有局部例外

嚴重度：低

目前狀態：

- `AdminController`、`DietRecordController`、`AvatarController`、`DietaryAgentController`、`UserProfileController`、`BodyStatusController` 已大多使用 `ApiResponse`
- `AuthController` 仍保留特例

建議修正：

- 若決定維持特例，就把這件事寫進 API 規格
- 若不想保留特例，則把 auth 類端點也納入相同 response 規格

#### 6. 有些錯誤分類還可以再更精準

嚴重度：低

目前狀態：

- `GlobalExceptionHandler` 已能處理多數自訂例外
- 但部分情況仍可能用 `IllegalStateException` 或較泛化的 `IllegalArgumentException`

影響：

- API 使用者雖然能拿到錯誤，但有些錯誤語意仍可更清楚

建議修正：

- 對較常見的失敗類型再明確拆分類別
- 例如：
  - 設定缺失
  - 上傳失敗
  - 上游格式錯誤
  - 業務規則衝突

## 建議修正順序

1. 補強 dietary partner API 韌性保護
2. 補 `AuthService.refresh()` / `JwtUtil` 等高風險測試
3. 決定 auth API 是否維持 response 特例
4. 再做一次可疑檔案的 UTF-8 編碼確認
5. 視需要把例外分類再細化

## 補充結論

目前後端比最初版本穩定很多，原本高風險的 migration、admin email、啟動自動寫入等問題都已處理到可接受狀態。

如果現在要繼續往下修，我會優先處理：

1. `DietaryAgentService` 的韌性保護
2. auth / jwt 相關測試覆蓋

這兩項對實際上線穩定性和後續維護價值最高。
