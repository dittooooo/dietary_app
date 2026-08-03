# 營養管線穩定性修復計畫 (Nutrition Pipeline Reliability Fix Plan)

為了確保每一筆食譜都能精準對應，我們將放棄多執行緒並行，改採更穩健的 **循序處理 (Sequential Processing)** 模式。這能完全避免執行緒間的競爭衝突，並讓 OpenAI 的頻率限制管理更為可控。

## 用戶審閱需求 (User Review Required)

> [!IMPORTANT]
> 1. **循序執行**：改為一次處理一筆食材。雖然總執行時間會比並行模式長，但能保證資料的 100% 完整與準確。
> 2. **每筆存檔**：維持處理完一筆食材就立即寫入快取與日誌，確保即便中斷也能隨時從最後一筆恢復。
> 3. **清理受損數據**：我會先刪除舊的受損快取檔案，讓系統重新對可能失敗過的項目進行正確的 DB 匹配。

## 建議變更 (Proposed Changes)

---
### 1. 強化 API 呼叫的容錯能力 (Retry & Error Raising)

#### [MODIFY] [query_nutrition_V5.py](file:///c:/Users/PARALELL/Desktop/code4/workspace/src/recipe_nutrition_unmatch/tools/query_nutrition_V5.py)
#### [MODIFY] [online_nutrition_search.py](file:///c:/Users/PARALELL/Desktop/code4/workspace/src/recipe_nutrition_unmatch/tools/online_nutrition_search.py)
#### [MODIFY] [amount_estimator.py](file:///c:/Users/PARALELL/Desktop/code4/workspace/src/recipe_nutrition_unmatch/tools/amount_estimator.py)
- **Tenacity 重試**：為所有 OpenAI API 呼叫加上 `tenacity.retry`。針對 `RateLimitError` 進行指數退避等待。
- **嚴格異發**：修改內部的 `try...except`。如果遇到 API 通訊或頻率限制錯誤，**必須向上拋出異常**，嚴禁回傳 `None` 或信心度 `0`。只有在 API 成功回應且「確認資料庫無此食材」時才允許回傳 `None`。

---
### 2. 重構管線為單執行緒模式

#### [MODIFY] [compute_nutrition_pipeline.py](file:///c:/Users/PARALELL/Desktop/code4/workspace/src/recipe_nutrition_unmatch/compute_nutrition_pipeline.py)
- **取消 ThreadPool**：移除 `concurrent.futures` 邏輯，改用單純的 `for` 迴圈處理 `tasks`。
- **快取邏輯修正**：
  - 只有在 `process_item` 成功完成（無異常）時才將結果寫入 `self.cache`。
  - 維持一筆存檔一次的頻率，確保斷點續傳。
- **日誌增強**：在日誌中記錄具體的 OpenAI 錯誤訊息（若發生），方便除錯。

---
### 3. 恢復與執行

#### [EXECUTE] 初始化
- 刪除或更名現有的 `pipeline_v4_cache.json` 以排除先前並行時可能產生的壞損快取。
- 重新啟動 `compute_nutrition_pipeline.py`。

## 驗證計畫 (Verification Plan)

### 手動驗證
- 觀察 `r481065` (鮮蝦冬粉煲) 的處理過程，確認其「蝦子」、「高麗菜」是否能正確從 DB 撈取資料（不應觸發聯網搜尋）。
- 確認程式在遇到網路斷開或頻率限制時會自動等待重試，而不是直接跳過。

### 品質查核
- 比對新的 `recipes_per_serving_v4.json`，確保沒有因為技術錯誤導致的 `null` 欄位。
