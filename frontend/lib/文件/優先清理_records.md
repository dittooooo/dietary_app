# 優先清理：飲食紀錄

行號以 2026-09-04 本次掃描為準。以下只列目前有實際使用或有明確刪除證據的項目。

## 待作清單

| 狀態 | 待作項目 | 優先度 | 實作難易度 |
| :--- | :--- | :--- | :--- |
| [ ] | 確認 `camera_record_page.dart` 無入口後刪除或封存 | 優先度中 | 難易度簡單 |
| [ ] | 整理 `simple_camera_page.dart` 的寵物與圖片邏輯 | 優先度中 | 難易度中 |
| [ ] | 保留 `ElfFeedingPage`，整理動畫與飲食寫入責任 | 優先度中 | 難易度困難 |
| [ ] | 整理手動紀錄頁的模型、Dialog、搜尋與儲存流程 | 優先度中 | 難易度困難 |
| [ ] | 統一日誌、飲食紀錄與報告頁的資料載入與日期契約 | 優先度中 | 難易度困難 |

## 1. `camera_record_page.dart` 是未接入且含模擬 AI 的刪除候選

- **檔案與行號**：`views/records/camera_record_page.dart:10-579`；模擬資料約在 `37-50`，未使用 helper 在 `157`、`200`、`241`、`342`、`470`、`577`。
- **原始碼片段**：`final List<Map<String, dynamic>> _detectedItems = [...]`；多個方法標註 `ignore: unused_element`；辨識流程以 `Timer(const Duration(milliseconds: 300), ...)` 模擬完成。
- **原因**：全專案引用搜尋找不到 `CameraRecordPage` 或 `camera_record_page.dart` 的外部入口；頁面仍保留模擬辨識、精靈 UI 與未使用編輯 helper，維護成本高且容易被誤當成正式 AI 功能。
- **優先度**：優先度中
- **難易度**：難易度簡單
- **目前證據**：目前唯一的頁面內引用是它自己的 import／類別；手動紀錄流程實際使用的是 `SimpleCameraPage`。
- **驗證方式**：搜尋路由、Navigator、deep link、測試入口與平台設定；完成後以手動紀錄、拍照、返回與冷啟動做 smoke test。
- **完成條件**：產品確認不需要此頁後刪除或封存整個檔案，並移除只服務它的 import；若仍要保留，必須補正式 API 與入口，不可繼續以模擬 AI 當正式功能。

## 2. `simple_camera_page.dart` 仍在使用，但含重複精靈／圖片邏輯

- **檔案與行號**：`views/records/simple_camera_page.dart:8-315`；呼叫端 `manual_record_page.dart:773`。
- **原始碼片段**：`_loadPetData()`、`_getPetImagePath()`、`_getElfMood()` 與 `_buildElfOverlay()` 同時處理相機與精靈 UI。
- **原因**：相機拍攝、寵物狀態、圖片路徑與飲食記錄入口耦合；若寵物圖片規則改變，需同時檢查多個頁面。
- **優先度**：優先度中
- **難易度**：難易度中
- **目前證據**：`ManualRecordPage` 明確導航到 `SimpleCameraPage`，不可直接刪除；它不是孤立頁面。
- **驗證方式**：從手動紀錄進入相機、拍照、取消、確認與返回，並測試不同帳號的寵物／頭像資料。
- **完成條件**：保留相機頁可用性，將圖片與寵物狀態改由共用來源提供，避免頁面自行硬編碼。

## 3. `elf_feeding_page.dart` 仍被多處呼叫，不可直接刪除

- **檔案與行號**：`views/records/elf_feeding_page.dart:11-203`；呼叫端為 `home_view.dart:1767、1843`、`manual_record_page.dart:1088`，另有相機頁入口 `527`。
- **原始碼片段**：`class ElfFeedingPage ...` 同時包含餵食動畫、寵物載入、飲食項目與返回日誌。
- **原因**：它目前有多個有效入口；直接刪除會造成編譯錯誤或破壞手動紀錄流程。適合記錄重新命名、動畫與寫入責任分離方案，不適合列為立即刪除。
- **優先度**：優先度中
- **難易度**：難易度困難
- **目前證據**：全專案搜尋確認有多處 `ElfFeedingPage(...)` 建立式呼叫。
- **驗證方式**：先盤點所有入口及 `items`、`imagePath`、`recordDate` 契約，再測試動畫完成、返回與紀錄持久化。
- **完成條件**：名稱與責任符合實際功能；動畫只負責呈現，飲食紀錄寫入由明確 service／流程負責。

## 4. 手動紀錄頁責任過度集中

- **檔案與行號**：`views/records/manual_record_page.dart:15-1600`。
- **原始碼片段**：同一檔案包含 `_SelectedFood`、營養編輯 Dialog、餐點搜尋、圖片選擇、日期、`DietService` 寫入與主要 UI。
- **原因**：新增欄位或修改儲存契約時，會同時影響 Dialog、搜尋結果與 API payload；目前公開建構子只保留 `initialDate`，舊 `selectedImage`、`imageBytes` 參數不應再列為現行問題。
- **優先度**：優先度中
- **難易度**：難易度困難
- **目前證據**：檔案約 1,500 行且有多個資料類別與流程方法；`DishSearchService` 由此頁實際建立。
- **驗證方式**：測試自訂餐點、搜尋餐點、選取／編輯、圖片、日期與寫入失敗重試。
- **完成條件**：資料模型、Dialog、搜尋狀態與儲存流程有清楚邊界；不改變既有建構子契約。

## 5. 日誌、飲食紀錄頁與報告頁重複載入與資料處理

- **檔案與行號**：`diary_page.dart:169-214`、`dietary_record_page.dart:94-109`、`report_page.dart:121-267`。
- **原始碼片段**：三頁各自呼叫 `DietService().getMyDietRecords()`，並各自做日期篩選、營養解析、圖片／UI 狀態處理。
- **原因**：相同 response 欄位與日期規則分散，容易造成某頁顯示的餐期、數值或頭像與另一頁不同。
- **優先度**：優先度中
- **難易度**：難易度困難
- **目前證據**：三個正式頁面各有獨立載入與解析方法；不是未使用頁面。
- **驗證方式**：同一帳號、同一天、同一筆紀錄在三頁比對；測試新增／編輯／刪除後返回與跨頁更新。
- **完成條件**：共用資料轉換與日期契約；頁面只負責呈現與互動。完整紀錄 log 另見 [優先清理_security_logging.md](優先清理_security_logging.md)。
