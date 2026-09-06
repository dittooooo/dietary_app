# Docker startup

Use `start-all.ps1` from the repository root to validate and start the four backend services:

```text
SQL Server and Neo4j (manual) -> Nutritionist Agent (8000) -> Spring Boot backend (8080) -> Companion Agent (3000) -> MAF Workflow (3001)
```

The script starts Nutritionist Agent, Spring Boot backend, Companion Agent, and MAF Workflow as Docker services. SQL Server and Neo4j must already be running locally. Docker Desktop with Linux containers is required.

## Start the system

After filling in `.env`, run this command from the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\start-all.ps1
```

The services are available at:

```text
Nutritionist Agent  http://127.0.0.1:8000
Spring Boot backend http://127.0.0.1:8080
Companion Agent     http://127.0.0.1:3000
MAF conversation    http://127.0.0.1:3001
```

The Nutritionist Agent API uses the `/nutritionist-agent` prefix, for example:

```text
GET http://127.0.0.1:8000/nutritionist-agent/health
GET http://127.0.0.1:8000/nutritionist-agent/dishes/search?q=便
```

The backend containers connect to local SQL Server database `dietaryApp` at port 1433 and local Neo4j Bolt at port 7687 through `host.docker.internal`. Override these defaults with `BACKEND_DB_URL` and `NEO4J_AGENT_URI` in `.env` when needed. Only uploads are managed by this Compose project.

## Required configuration

Copy `.env.example` to `.env` and fill in the required values, including:

```env
DB_PASSWORD=...
JWT_SECRET=...
OPENAI_API_KEY=...
NEO4J_URI=...
NEO4J_USER=neo4j
NEO4J_PASSWORD=...
```

`DB_PASSWORD` and `DB_USERNAME` are used by Spring Boot to connect to the manually started SQL Server. `NEO4J_URI`, `NEO4J_USER`, and `NEO4J_PASSWORD` are used by the Nutritionist Agent. Inside Docker, the default Neo4j address is `bolt://host.docker.internal:7687`.

## Inspect and stop services

```powershell
docker compose ps
docker compose logs --tail 100
docker compose down
```

The `down` command stops the four backend containers. The manually managed database data is not affected.

## Validate without starting services

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\start-all.ps1 -ValidateOnly
```

Validation checks `.env`, required settings, Docker, and the Compose configuration without starting services.
