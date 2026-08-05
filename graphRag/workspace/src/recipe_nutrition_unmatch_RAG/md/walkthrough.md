# RAG System 實作完成

我已經根據您的需求完成了 **食譜與營養成份配對的 RAG 系統** 的建置。

## 變更摘要

1. **環境設定檔 (`.env`)**
   - 建立了 `.env` 檔案以方便您設定金鑰。目前已預設為使用 **OpenAI** (`gpt-4o-mini`) 與 `sentence-transformers` 的多語言模型。
   - 若未來想切換回 Ollama，只需註解 OpenAI 設定並將 Ollama 相關的設定取消註解即可。

2. **向量資料庫建置 (`1_build_vector_db.py`)**
   - 讀取了有兩千多筆的 `2_nutrition_data_categorized_...json` 檔案。
   - 將每一筆營養成份格式化為 `[分類] [樣品名稱]，俗名：[俗名]`。
   - 利用 `sentence-transformers` 將文字轉換為向量，並儲存在本地的 `chroma_db` 資料夾中。這個過程只需執行一次，之後查詢就會非常快。

3. **RAG 比對主程式 (`2_rag_matcher.py`)**
   - 讀取 `recipes.json`。
   - 實作了 **快取 (Cache)** 機制 (`data/output/cache.json`)，避免對同樣的「洋蔥」重複呼叫 LLM 浪費 Token 與時間。
   - **檢索 (Retrieve)**：利用 ChromaDB 取回前 5 名最相似的營養品候選。
   - **生成 (Generate)**：要求 OpenAI 嚴格從這 5 個選項中挑選一個「一字不漏」回傳，找不到則回傳 `None`。關閉了 Randomness (`temperature=0.0`) 確保輸出穩定。
   - 使用 `tqdm` 監控執行進度。
   - **新增功能**：您可以透過修改程式內的 `START_IDX` 與 `END_IDX` 變數來決定要處理的食譜範圍（例如只跑前 10 個食譜進行測試）。
   - 結果將會動態輸出成 `recipes_rag_enriched_{timestamp}_idx{start}_to{end}.json`。

> [!IMPORTANT]  
> **下一步行動（需要您的操作）**
> 1. 請打開 `workspace/src/recipe_nutrition_unmatch_RAG/.env` 檔案，將 `OPENAI_API_KEY` 換成您真實的 API 金鑰。
> 2. 請先執行 `python 1_build_vector_db.py` 建立向量資料庫（第一次執行會花幾分鐘下載語言模型）。
> 3. 建立完成後，即可執行 `python 2_rag_matcher.py` 開始食譜比對。

若有任何使用上的問題或需要微調 Prompt 的地方，歡迎隨時跟我說！
