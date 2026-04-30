可以。先把最小可行架構收斂成 **6 個模組** 就夠了。

## 1. `config`

負責集中管理設定值。

內容包含：

* Google Places API key
  * AIzaSyDKTEWKeg9m-IuGYW6_hyT85I9FnlCVUy8
* 搜尋中心座標（淡江大學）
* 搜尋半徑
* 輸出資料夾路徑
* OCR 參數
* 菜單圖評分門檻

目的很單純：避免 API key、路徑、閾值散落在各檔案裡。

---

## 2. `restaurant_finder`

負責找「淡江大學附近的餐廳」。

輸入：

* 中心點座標
* 半徑
* 關鍵字或類型

輸出：

* 餐廳清單

  * `restaurant_name`
  * `place_id`
  * `address`
  * `lat`
  * `lng`
  * `google_maps_url` 或可追蹤來源

這一層只做「找店」，不要混進圖片或 OCR 邏輯。

---

## 3. `image_collector`

負責替每家餐廳蒐集候選圖片。

輸入：

* 單一餐廳資訊

輸出：

* 候選圖片清單

  * `image_url`
  * `local_path`
  * `source`
  * `restaurant_name`

這一層只做「收集可能的圖片」，不要判斷哪張是菜單。

---

## 4. `menu_image_ranker`

負責從候選圖片中，挑出最像菜單的一張。

輸入：

* 某家餐廳的候選圖片列表

輸出：

* 最佳圖片
* 每張圖的分數
* 是否通過最低門檻

評分依據可以先用最小版 heuristic：

* OCR 後文字量是否夠多
* 是否有數字、價格符號、`元`、`$`
* 是否出現菜名常見詞，如 `飯`、`麵`、`湯`、`套餐`、`飲料`
* 排版是否像多行列表

這一層的重點是：
**先選圖，再正式 OCR。**

---

## 5. `ocr_engine`

負責把選中的菜單圖轉成文字。

輸入：

* 單張最佳菜單圖

輸出：

* `ocr_text`
* `confidence`
* 可選的區塊化 OCR 結果

可再拆成兩步：

* `preprocess_image`：灰階、二值化、去噪、裁切
* `run_ocr`：PaddleOCR 辨識

這樣日後比較好調整品質。

---

## 6. `pipeline_runner`

這是主流程控制器，也是整個 MVP 的核心。

流程：

```text
找餐廳
→ 逐家收集圖片
→ 挑最佳菜單圖
→ OCR
→ 組裝結果
→ 輸出 JSON
```

輸出建議格式：

```json
{
  "restaurant_name": "...",
  "place_id": "...",
  "address": "...",
  "best_menu_image": "...",
  "menu_score": 0.87,
  "ocr_text": "...",
  "status": "ok"
}
```

如果失敗也要保留狀態，例如：

* `no_image_found`
* `no_menu_like_image`
* `ocr_failed`

---

# 最小可行的資料流

你下一輪寫程式時，建議就照這條線：

```text
config
  ↓
restaurant_finder
  ↓
image_collector
  ↓
menu_image_ranker
  ↓
ocr_engine
  ↓
pipeline_runner
```

---

# 額外但先不用做的模組

這些之後再加，不要進 MVP：

* `logger`：正式記錄執行過程
* `cache`：避免重複抓同一餐廳或圖片
* `database`：把結果存 DB
* `menu_parser`：把 OCR 文字再拆成菜名與價格
* `kg_exporter`：匯出給 Neo4j / GraphRAG

---

# 你現在最適合的檔案切法

可以先切成這樣：

```text
project/
├─ config.py
├─ restaurant_finder.py
├─ image_collector.py
├─ menu_image_ranker.py
├─ ocr_engine.py
├─ pipeline_runner.py
└─ output/
```

這樣已經很夠做第一版。

下一個對話就可以直接進到「這 6 個模組的完整 Python 程式碼」。
