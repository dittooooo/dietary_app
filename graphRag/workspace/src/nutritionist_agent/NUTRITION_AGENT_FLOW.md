# Nutrition Agent：飲食建議流程

## /ask 的決策順序

1. 驗證呼叫端的料理與份量，不再從 question 抽取料理。
2. 只要 health_condition.has_chronic_disease=true，依 chronic_diseases 主動查詢 Neo4j；不以問題是否提到疾病作為條件。
3. 料理匹配後以固定、唯讀的 Neo4j template 查詢取得營養明細。
4. 按 dish_info_list.amount 加總營養，依三大營養素重新計算熱量。
5. 共用 evidence_builder 整理疾病規則、參考食譜營養來源、候選相對比較、diet_goal 與最近七日紀錄。
6. AnswerGenerator 依證據產生建議，驗證結構、所有候選料理涵蓋、證據 ID、推薦一致性與安全表述。
7. 不合格時只修正一次；再次失敗回 503，不把錯誤文字包裝成正常建議。

/dish-nutrition 共用匹配、固定查詢與計算流程，但不呼叫模型。

## 檔案職責

| 檔案 | 職責 |
| --- | --- |
| app.py / models.py | HTTP、資料驗證與相容的回應格式 |
| agent.py | 協調流程；共用 _lookup；重複料理合併份量；執行固定營養查詢 |
| dish_matcher.py | 現有料理／FoodItem／食材匹配 |
| template_cypher.py | 依已匹配料理與份量建立固定、唯讀的營養查詢 |
| cypher_guard.py / retriever.py | 唯讀查詢、必要欄位、參數傳遞與 Neo4j 型別轉換 |
| disease_rules.py | 獨立主動檢索、規則單位／基準判斷、資料不足狀態 |
| nutrition_calculator.py | 營養加總與熱量重算 |
| evidence_builder.py | 可追溯事實、近期資料、保守排序與具體營養來源 |
| answer_generator.py | 將事實表達為建議、共用輸出驗證、一次修正 |

## 疾病檢索

單次參數化查詢取回所有已提供疾病的 Disease → HAS_DIET_RULE → Nutrition 關係，使用 properties(r) 保留現有規則屬性。超過安全上限會明確失敗，不靜默截斷成完整證據。

狀態包括 rules_found、disease_not_found、no_rules、missing_disease_name。勾選慢性病但沒有名稱時不能辨識特定疾病，會請使用者補充；不從問題臆測診斷。資料庫連線失敗不等同「沒有規則」。

疾病關係不再 join 進營養明細，避免多條規則／多疾病讓同一營養列重複加總。營養查詢保留舊 disease_* 空欄位，維持既有 row contract。

營養查詢不由模型生成，因此不需要 LangChain fallback 或第二次 template 核對；資料仍會經過唯讀查詢、必要欄位與營養計算驗證。

## 規則適用範圍

- food_level_rule_json 的 per_100g 與 criteria_json 的每日／能量百分比門檻分開處理。
- 僅支援明確單一營養素、單一條件、可換算單位的食材門檻。
- potential_conflict / support_signal 只表示參考食材觸發規則，不是整道料理的疾病合格判定。
- not_triggered 不等於安全；insufficient 不等於零。
- 添加糖不以總糖代替，GI 不由碳水推算；脂肪比例、分期、用藥等資料不全時不強行計算。
- 高鉀與 adjust_by_stage 的條件需要個別醫療背景，阻止自動選出唯一最佳料理。
- 圖譜規則未在本次做外部醫學來源查證；不可把 Neo4j 查到的文字描述成已查證臨床指南。

## 目標與近期紀錄

diet_goal 的已知方向只用於候選間比較，不推算個人每日需求；疾病方向衝突時不能讓目標覆蓋疾病限制。沒有可支持唯一推薦的資料時，提供條件式點餐建議，不強制排名。

紀錄以服務日期為基準，保留當日與前六日；未來、舊紀錄、無效或缺日期另計，不稱為近期習慣。文字線索的近期加權只排列提醒，不當作實測攝取量或臨床判定。歷史 nutrition 的份量基準未定義，因此不擅自乘 amount 或宣稱整週營養達標。

參考食譜主來源與相對方向以定性方式送給結論模型：例如「參考食譜的醬油膏是鈉來源，點餐可確認調味能否分開」。不宣稱店家確實使用此配方，也不保證修改後達標。

## 輸出與可靠性界線

對外仍為 question、question_type、dish_nutrition、dish_advice、conclusion。營養 API 保留數值；建議文字避免精確營養／份量數字。evidence_ids 為內部驗證資料，整合測試報告會保存 evidence 供檢查。

程式可驗證必要欄位、證據存在與基本衝突，無法僅憑 ID 與文字檢查保證任意模型輸出的所有語意都正確。新增規則需補充單位、適用基準、來源與測試；正式健康用途仍需專業審核。

## 設定與驗證

唯一檔案設定來源是 dietary_app/.env，既有程序環境變數優先；不讀 workspace 或 nutritionist_agent 內的 .env。修改設定後重啟程序。

在 graphRag/workspace 執行：

```powershell
.\.venv\Scripts\python.exe -X utf8 -m unittest discover -s src/nutritionist_agent/test_area -p "test_*.py" -v
.\.venv\Scripts\python.exe -X utf8 -m src.nutritionist_agent.test_area.run_advice_smoke --live --repeat 2 --label manual
```

--live 會呼叫真實模型並可能產生費用。測試會保存完整 request/response、證據、模型名稱與耗時；營養結果由同一份固定 template 查詢產生。

test_data 下提供可貼到 Swagger 的 JSON；靜態日期久了需更新，整合測試腳本自動使用昨天的日期。v1 保留為歷史格式，不是目前推薦範本。
