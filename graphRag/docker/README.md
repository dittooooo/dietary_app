在 Windows `cmd` 用這樣啟動就可以：

```cmd
cd /d C:\Users\PARALELL\Desktop\code4\docker
docker compose up -d
```

第一次或你改過 Dockerfile 後，用：

```cmd
docker compose up -d --build
```

進容器：

```cmd
docker compose exec graphrag-dev bash
```

這是正常的，因為你現在在「容器內」，容器裡沒有 Docker CLI。
請先退出容器回到你電腦終端機再執行：

```bash
exit
cd /d C:\Users\PARALELL\Desktop\code4\docker
docker compose stop
```

`docker compose ...` 指令都要在主機（Windows cmd/PowerShell）執行，不是在 `root@...:/app/workspace#` 裡執行。

## 啟動 FastAPI

現在 Docker 預設會啟動新版 `nutrition_agent_v2` FastAPI：

```powershell
cd C:\_AlwaysUndone\dietary_app\graphRag\docker
docker compose up -d
```

這個 compose command 會在容器啟動時先安裝 `workspace/src/nutrition_agent_v2/requirements.txt`，再啟動 API。若你真的改了 Dockerfile 才需要加 `--build`。

啟動後測試：

```powershell
curl http://127.0.0.1:8000/health
```

Swagger 文件：

```text
http://127.0.0.1:8000/docs
```

GraphRAG 問答入口：

```text
POST http://127.0.0.1:8000/ask
```

如果 Neo4j 跑在主機上，容器內預設會用：

```text
bolt://host.docker.internal:7687
```

如需改連線，設定 `NEO4J_URI`、`NEO4J_USER`、`NEO4J_PASSWORD` 後重新 `docker compose up -d`。
