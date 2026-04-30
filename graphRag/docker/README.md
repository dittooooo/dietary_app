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