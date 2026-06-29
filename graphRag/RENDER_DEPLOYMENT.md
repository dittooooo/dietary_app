# Render Deployment Guide

This service deploys the Nutrition Agent FastAPI app to Render and connects it to Neo4j Aura.

## Target Architecture

```text
GitHub -> Render Web Service -> Docker -> FastAPI -> Neo4j Aura -> OpenAI API
```

FastAPI entrypoint:

```text
workspace/src/nutrition_agent_v2/app.py
```

Uvicorn import path:

```text
src.nutrition_agent_v2.app:app
```

## Render Service Settings

Create a Render Web Service from the GitHub repository:

```text
Service Type: Web Service
Runtime: Docker
Root Directory: graphRag
Dockerfile Path: docker/Dockerfile.production
Health Check Path: /health
```

Render provides `PORT` automatically. Do not hard-code the port. The Dockerfile already starts FastAPI with:

```bash
uvicorn src.nutrition_agent_v2.app:app --host 0.0.0.0 --port ${PORT:-8000}
```

## Environment Variables

Set these in Render Environment. Do not commit real values into Git.

```text
APP_ENV=production
OPENAI_API_KEY=sk-...
OPENAI_MODEL=gpt-4.1-nano
NEO4J_URI=neo4j+s://xxxxx.databases.neo4j.io
NEO4J_USER=neo4j
NEO4J_PASSWORD=...
NUTRITION_AGENT_TOP_N_ROWS=80
NUTRITION_AGENT_DISH_MATCH_THRESHOLD=60
NUTRITION_AGENT_GRAPH_QUERY_LIMIT=1000
```

`APP_ENV=production` is recommended on Render so the app fails fast if required secrets are missing.

## Neo4j Aura Check

After importing the local database into Aura, verify counts in Aura Browser:

```cypher
MATCH (n) RETURN count(n) AS nodes;
```

```cypher
MATCH ()-[r]->() RETURN count(r) AS relationships;
```

Expected current counts:

```text
nodes: 7687
relationships: 232173
```

## Test URLs

Replace `<render-domain>` with the Render public domain.

Health:

```bash
curl https://<render-domain>/health
```

Readiness, including Neo4j Aura connectivity:

```bash
curl https://<render-domain>/ready
```

Swagger UI:

```text
https://<render-domain>/docs
```

Ask endpoint:

```text
POST https://<render-domain>/ask
```

## Free Plan Notes

Render Free Web Services can spin down after inactivity. For team development, ask teammates to call `/health` first and wait for the service to wake up before testing `/ask`.

Set client timeouts to at least 60 seconds during development because the first request after spin-down may be slow.

## Local Development

The existing `docker/docker-compose.yml` remains for local development. It may use local `.env`, volume mounts, and `host.docker.internal`.

Production deployment uses `docker/Dockerfile.production` and Render Environment Variables instead. The production image only copies the `nutrition_agent_v2` API package, not the full local GraphRAG workspace.
