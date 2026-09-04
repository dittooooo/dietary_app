# 優先清理：服務、核心與設定

行號以 2026-09-04 本次掃描為準。本文件把「需要處理」與「目前先不拆檔」分開，避免把設計建議誤當成現行錯誤。

## 待作清單

| 狀態 | 待作項目 | 優先度 | 實作難易度 |
| :--- | :--- | :--- | :--- |
| [ ] | 整理 `ApiClient` 的 HTTP、token refresh 與登入失效 UI 邊界 | 優先度中 | 難易度困難 |
| [ ] | 建立 `AuthService` 的 session、profile、頭像與回饋契約 | 優先度中 | 難易度困難 |
| [ ] | 整理 `DietService` 的飲食、營養、週報與 Companion 契約 | 優先度中 | 難易度困難 |
| [ ] | 確認多平台 API URL 與環境變數策略 | 優先度中 | 難易度中 |
| [ ] | 確認所有 profile 欄位都使用共用 mapping | 優先度中 | 難易度中 |

## 1. `api_client.dart` 同時負責 HTTP、token refresh 與全域登入 UI

- **檔案與行號**：`core/api_client.dart:12-352`。
- **原始碼片段**：`_sendWithRefresh()` 呼叫 `_refreshAccessToken()`；`_checkResponse()` 直接使用全域 `navigatorKey`、Dialog 與 `LoginPage`。
- **原因**：網路層與畫面導航耦合，測試 service 時必須依賴 Flutter navigator；refresh 失敗也容易和全域登出提示互相影響。
- **優先度**：優先度中
- **難易度**：難易度困難
- **目前證據**：同一類別包含多種 HTTP method、token 附加、refresh、登入失效 UI；raw response body logging 已改為只記錄狀態碼，不重複列為未完成。
- **驗證方式**：測試 2xx、401、403、refresh 成功／失敗、Companion endpoint 與無 UI context 情境。
- **完成條件**：client 回傳可測試的 session 結果；登入失效由上層決定 UI；所有呼叫端回歸通過。

## 2. `auth_service.dart` 集中登入、profile、頭像、回饋與快取

- **檔案與行號**：`services/auth_service.dart:9-534`。
- **原始碼片段**：`login()`、`getUserProfile()`、`updateProfile()`、`uploadAvatar()`、`submitProblemFeedback()` 與 `_cacheUserProfile()` 都位於同一 service。
- **原因**：帳號、個人資料、圖片與問題回饋的失敗契約與快取邊界不同，集中後容易在修改 session 時誤傷其他功能。
- **優先度**：優先度中
- **難易度**：難易度困難
- **目前證據**：方法數量與責任範圍可由類別直接確認；本輪不要求立即拆檔，先維持現狀並建立契約。
- **驗證方式**：測試登入／登出、頭像更新、profile 更新、回饋上傳與切換帳號。
- **完成條件**：各方法的 session、cache、錯誤與 response schema 有測試；是否拆分留待專門重構批次。

## 3. `diet_service.dart` 混合紀錄、營養、週報與 Companion API

- **檔案與行號**：`services/diet_service.dart:10-676`。
- **原始碼片段**：同一類別包含 `getMyDietRecords()`、`fetchDishNutrition()`、`createDietRecord()`、`askWeeklyAnalysis()` 與 `sendCompanionUserPrompt()`。
- **原因**：不同後端 endpoint、資料格式與錯誤處理集中；新增 Companion 欄位可能影響一般飲食紀錄。
- **優先度**：優先度中
- **難易度**：難易度困難
- **目前證據**：目前檔案約 676 行，包含多組 normalization 與 dynamic response；現有呼叫端仍多，不可直接拆除方法。
- **驗證方式**：逐一列出 endpoint 與呼叫端，測試新增／修改／刪除、營養查詢、週報與 Companion 草稿保存。
- **完成條件**：資料契約固定、錯誤類型可辨識；是否拆檔需在完整呼叫端盤點後決定。

## 4. `api_config.dart` 的多平台 URL 規則需集中說清楚

- **檔案與行號**：`config/api_config.dart:5-91`。
- **原始碼片段**：`baseUrl`、`serverBaseUrl`、`nutritionistBaseUrl`、`companionBaseUrl` 與 candidate fallback 同時處理多平台 URL。
- **原因**：localhost、Android emulator 位址、環境變數與多個 port 規則若由頁面自行拼接，容易在 Web／Android／桌面版出現連線錯誤。
- **優先度**：優先度中
- **難易度**：難易度中
- **目前證據**：目前已有集中 getter 與 `resolveServerUrl()`；後續應確認所有 endpoint 都透過此處，不要再把既有集中化誤判成未完成。
- **驗證方式**：在 Web、Android emulator 與桌面版逐一檢查主後端、營養服務與 Companion URL。
- **完成條件**：環境設定策略、fallback 順序與各 endpoint 來源有文件與測試。

## 5. `profile_value_mapper.dart` 維持單一 mapping 契約

- **檔案與行號**：`utils/profile_value_mapper.dart:1-186`。
- **原始碼片段**：`genderToApi()`、`petTypeToApi()`、`dietGoalToApi()`、`healthConditionsToApi()` 及對應 display 方法集中處理轉換。
- **原因**：若各頁自行硬編碼寵物、性別、疾病或飲食目標，會產生前端顯示值與 API enum 不一致；目前 mapping 不應直接移除。
- **優先度**：優先度中
- **難易度**：難易度中
- **目前證據**：這是目前有效的共用轉換工具；本輪沒有證據支持刪除，重點是檢查新頁面是否繞過它。
- **驗證方式**：以每個 display／API 值做雙向 mapping 測試，確認未知值 fallback 有明確規則。
- **完成條件**：所有 profile 相關頁面使用共用 mapper；未知值不會靜默造成錯誤資料。

## 交叉參照

完整密碼保存與敏感 log 另見 [優先清理_security_logging.md](優先清理_security_logging.md)；餐點搜尋與 Body Status 連線另見 [優先清理_network_data.md](優先清理_network_data.md)。
