# Nutritionist Agent Railway + Neo4j Aura Deployment Plan

## Summary

把目前本機架構改成：

`GitHub monorepo -> Railway Docker service -> FastAPI -> Neo4j Aura -> OpenAI API`

目前 repo 觀察到實際 FastAPI 入口是 `graphRag/workspace/src/nutrition_agent_v2/app.py`，Docker 啟動在 `graphRag/docker/docker-compose.yml`，目前依賴 `host.docker.internal` 連本機 Neo4j。部署時要移除本機依賴、改用 Railway Environment Variables、Neo4j Aura `neo4j+s://...` 連線、並讓容器用 Railway 提供的 `$PORT` 啟動。

重要提醒：`graphRag/workspace/.env` 目前含有 OpenAI API key 與 Neo4j 密碼，這些已經進入工作區檔案，應立刻輪換 OpenAI key，並確保 `.env` 不進 Git。

參考官方文件：Railway Dockerfile 會從 source root 找 `Dockerfile`，可用 `RAILWAY_DOCKERFILE_PATH` 指定路徑；Railway monorepo 可設定 service Root Directory；Neo4j Aura 支援匯入既有資料庫。  
Sources: Railway Dockerfiles https://docs.railway.com/builds/dockerfiles, Railway Monorepo https://docs.railway.com/deployments/monorepo, Neo4j Aura import https://neo4j.com/docs/aura/classic/auradb/importing/import-database/

## Key Changes

- FastAPI 設定
  - 保留 `config.py` 用 `os.getenv()` 讀取設定，但部署環境必須完全依賴 Railway Variables，不依賴 `.env`。
  - 建議新增啟動檢查：production 若缺 `OPENAI_API_KEY`、`NEO4J_URI`、`NEO4J_USER`、`NEO4J_PASSWORD` 就 fail fast。
  - `NEO4J_URI` 從 `bolt://host.docker.internal:7687` 改為 Aura 提供的 `neo4j+s://xxxx.databases.neo4j.io`。
  - `OPENAI_API_BASE` 通常保留預設 `https://api.openai.com/v1`，不必在 Railway 設，除非用 proxy。

- Docker / Railway
  - 不使用 `docker-compose.yml` 部署到 Railway；Compose 只保留本機開發用。
  - 建議新增一個 production Dockerfile，例如 `graphRag/docker/Dockerfile.railway`，或調整現有 Dockerfile：
    - COPY 必要的 `workspace/src` 與 `graphrag-local-ollama`。
    - install `graphRag/workspace/src/nutrition_agent_v2/requirements.txt`。
    - `CMD ["sh", "-c", "uvicorn src.nutrition_agent_v2.app:app --host 0.0.0.0 --port ${PORT:-8000}"]`
  - Railway service 設定：
    - Root Directory 建議設 `/graphRag`，因為 Dockerfile 目前 build context 需要 `workspace` 和 `graphrag-local-ollama`。
    - 若 Dockerfile 不在 Root Directory 根部，設定 `RAILWAY_DOCKERFILE_PATH=/docker/Dockerfile.railway`。
    - Watch Paths 設 `/graphRag/**`，避免前端或 Java backend 改動觸發 agent 重部署。

- 本機架構保留與調整
  - 可保留：FastAPI app、Neo4j Python driver、LangChain、OpenAI SDK、`/ask`、`/health`。
  - 本機限定需移除於 production：`host.docker.internal`、`localhost` Neo4j、Docker volume mount、`env_file: ../workspace/.env`、compose command 裡每次啟動才 pip install。
  - 建議重構：把部署用 Dockerfile 與本機 compose 分開，避免 Railway 容器啟動時才安裝依賴。

## Neo4j Aura Migration

- 建立 AuraDB
  - 到 Neo4j Aura 建立 AuraDB instance。
  - 選 Free 或最低成本方案，region 優先選離 Railway region 近的位置。
  - 記下：
    - Connection URI: `neo4j+s://...databases.neo4j.io`
    - Username: 通常 `neo4j`
    - Password: Aura 建立時下載或重設的密碼

- 匯出/匯入建議
  - 首選：Neo4j 官方 dump / Aura import 或 Migration Tool。
    - 最適合完整搬遷整個 Neo4j Desktop DB，包含 nodes、relationships、properties、indexes、constraints。
  - 備選：`apoc.export.cypher.all`。
    - 適合小資料集、需要可讀 Cypher 檔、或 dump 版本不相容時。
    - 缺點是 APOC 設定與大量資料匯入較麻煩。
  - 不建議首選：手寫 CSV export/import。
    - 容易漏 relationship properties、indexes、constraints，除非資料模型很小且可重建。

- 實作流程
  - 在 Neo4j Desktop 停止寫入，確認 DB 名稱與 Neo4j 版本。
  - 用 Desktop 或 `neo4j-admin database dump neo4j --to-path=...` 產生 dump。
  - 依 Aura Console 的 Import / Upload 指引匯入 dump；若 Aura Free 對 dump 有限制，改用官方 Migration Tool 或 APOC Cypher export。
  - 匯入後用 Neo4j Browser 驗證：
    - `MATCH (n) RETURN count(n)`
    - `MATCH ()-[r]->() RETURN count(r)`
    - `CALL db.labels()`
    - `CALL db.relationshipTypes()`
    - 抽查核心查詢：Dish -> Ingredient -> FoodItem -> Nutrition -> Disease diet rule。
  - 本機與 Aura count 相同後，再把 Railway `NEO4J_URI` 指向 Aura。

## Railway Deployment Steps

- GitHub
  - 確認 repo 已 push 到 GitHub。
  - `.gitignore` 加上：
    - `graphRag/workspace/.env`
    - `**/__pycache__/`
    - 測試輸出、大型 cache、Neo4j dump 檔
  - 輪換已暴露的 OpenAI key，不要再使用目前 `.env` 裡的 key。

- Railway Project
  - Railway Dashboard -> New Project -> Deploy from GitHub repo。
  - 選專題 repo。
  - 建立 service 後到 Settings：
    - Root Directory: `/graphRag`
    - Dockerfile path variable: `RAILWAY_DOCKERFILE_PATH=/docker/Dockerfile.railway`
    - Healthcheck path: `/health`
    - Watch Paths: `/graphRag/**`

- Environment Variables
  - `OPENAI_API_KEY=sk-...`
  - `OPENAI_MODEL=gpt-4.1-nano`
  - `NEO4J_URI=neo4j+s://xxxx.databases.neo4j.io`
  - `NEO4J_USER=neo4j`
  - `NEO4J_PASSWORD=...`
  - `NUTRITION_AGENT_TOP_N_ROWS=80`
  - `NUTRITION_AGENT_DISH_MATCH_THRESHOLD=60`
  - `NUTRITION_AGENT_GRAPH_QUERY_LIMIT=1000`
  - 不需要設定 `PORT`，Railway 會提供；程式只要讀 `${PORT:-8000}`。

- Deploy / Domain / HTTPS
  - 觸發 Deploy，觀察 Build Logs 是否成功安裝依賴。
  - 觀察 Deploy Logs 是否顯示 uvicorn listening on `0.0.0.0:$PORT`。
  - 到 Networking / Public Networking 產生 Railway domain。
  - Railway domain 預設提供 HTTPS。
  - 若要自訂網域，再於 Domains 加入 custom domain 並依 Railway 指示設定 DNS。

## Test Plan

- Health
  - Browser: `https://<railway-domain>/health`
  - curl:
    ```bash
    curl https://<railway-domain>/health
    ```
  - 預期：`{"status":"ok","service":"nutrition_agent"}`

- Swagger
  - 開啟 `https://<railway-domain>/docs`
  - 確認 `/ask` schema 正常顯示。

- Neo4j Aura connectivity
  - 用一個最小 `/ask` request 測核心菜色或疾病查詢。
  - 若失敗，從 Railway logs 判斷：
    - DNS/TLS/Authentication error：Aura URI 或密碼錯。
    - Cypher no result：資料未完整匯入或 label/schema 不一致。
    - Timeout：查詢太大，調整 query limit 或索引。

- OpenAI connectivity
  - `/ask` 應能產生 `dish_advice` 與 `conclusion`。
  - 若 Railway 回 503 且 detail 提到 OpenAI key，檢查 `OPENAI_API_KEY` 是否存在、是否已輪換、是否有額度。
  - 用 Postman 建立 Team collection，包含：
    - `GET /health`
    - `POST /ask` single dish
    - `POST /ask` chronic disease case
    - `POST /ask` comparison case

## Phased Deployment Plan

- Phase 1: Security and repo cleanup
  - 目標：移除 secret 風險，準備可部署 repo。
  - 修改：`.gitignore`、移除 tracked `.env`、輪換 OpenAI API key。
  - 驗證：GitHub repo 不含 secret；本機用環境變數仍可啟動。

- Phase 2: Production Docker setup
  - 目標：讓 Railway 可穩定 build/run FastAPI。
  - 修改：新增 production Dockerfile，啟動命令改用 `${PORT:-8000}`，不依賴 compose volume。
  - 驗證：本機 `docker build` 成功；`docker run -e ... -p 8000:8000` 後 `/health` 正常。

- Phase 3: Neo4j Aura migration
  - 目標：把 Neo4j Desktop DB 完整搬到雲端。
  - 修改：不改程式，先做資料遷移。
  - 驗證：Aura 節點數、關係數、labels、relationship types、核心查詢結果與本機一致。

- Phase 4: Railway service deployment
  - 目標：GitHub push 後 Railway 自動部署 agent。
  - 修改：Railway 設 Root Directory、Dockerfile path、Variables、Healthcheck、Domain。
  - 驗證：Build/Deploy logs 成功，`/health` 透過 HTTPS 正常。

- Phase 5: End-to-end API validation
  - 目標：確認 FastAPI + Aura + OpenAI 全鏈路可用。
  - 修改：必要時調整 env、query limit、CORS 或 timeout。
  - 驗證：Postman/curl/Swagger 可完成 `/ask`，Railway logs 無未處理例外。

- Phase 6: Team handoff and low-cost operations
  - 目標：讓組員不需本機環境即可使用。
  - 產出：README 部署章節、API base URL、Postman collection、環境變數清單但不含值、常見錯誤排查。
  - 維運：OpenAI 設 usage limit，Aura 選免費/低成本方案，Railway 監控 usage，定期匯出 Aura backup 或保留 dump。

## Assumptions

- 主要部署目標是 `graphRag/workspace/src/nutrition_agent_v2/app.py`。
- Railway 只部署 Nutritionist Agent，不部署 Java `backend`、Flutter `frontend`、資料建置腳本。
- Neo4j Aura 使用官方 AuraDB，不在 Railway 自架 Neo4j，因為 Aura 更省維運、TLS/backup/管理較簡單。
- `/health` 目前只檢查 API process；若要更 production-ready，後續可新增 `/ready` 檢查 Neo4j driver 與 OpenAI key 設定。
