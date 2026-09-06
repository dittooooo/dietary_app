# Dietary App repository context

This file defines the repository scope and current runtime architecture for documentation and code-indexing tools such as DeepWiki. It is not the end-user README.

## Current implementation path

The currently implemented application is composed of four independently started services:

| Component | Active location | Runtime | Default port | Responsibility |
| --- | --- | --- | --- | --- |
| Flutter client | `frontend/` | Flutter / Dart | Platform-dependent | User interface, authentication state, chat UI, meal-record confirmation, and calls to backend services |
| Companion Agent | `companion/companion_js/` | Node.js / Express | 3000 | Current chat entry point, OpenAI intent and emotion analysis, dish-name translation for advice, Dietary Agent orchestration, and final conversational reply |
| Dietary backend | `backend/` | Java 21 / Spring Boot | 8080 | JWT authentication, user and diet-record persistence, Dietary Agent API, and forwarding requests to the Nutritionist Agent |
| Nutritionist Agent | `graphRag/workspace/src/nutritionist_agent/` | Python 3.12 / FastAPI | 8000 | Neo4j/GraphRAG nutrition retrieval, deterministic nutrition calculation, disease-rule evidence, and OpenAI-supported nutrition advice |

Current request flow:

```text
Flutter
  -> Companion Agent POST /companion/ask
      -> OpenAI Responses API (intent, meal items, emotion)
      -> optional dish translation through OpenAI
      -> Spring Boot POST /dietary-agent/ask for advice
          -> Nutritionist Agent POST /nutritionist-agent/ask
      -> OpenAI final companion reply

Flutter meal-record confirmation
  -> Spring Boot POST /api/diet-records
      -> Nutritionist Agent POST /nutritionist-agent/dish-nutrition
      -> database write
```

The three similarly named services are distinct:

- Companion Agent is the conversational service on port 3000.
- Dietary Agent is implemented inside the Spring Boot backend on port 8080.
- Nutritionist Agent is the Python GraphRAG service on port 8000.

## Planned MAF architecture

`MAF/MAF_WORKFLOW_CHANGE_SPEC 1.md` is an approved change specification, not current runtime behavior. The `MAF/` directory does not yet contain a Microsoft Agent Framework implementation.

The planned change moves routing, intake, translation, confirmation state, retries, and orchestration from the Companion Agent into a new MAF Workflow. Until that implementation is completed and verified, documentation must label MAF content as planned architecture.

## Active and reference-only directories

Use these directories as primary sources when documenting the running application:

- `frontend/lib/`
- `backend/src/main/`
- `companion/companion_js/`, excluding `node_modules/`
- `graphRag/workspace/src/nutritionist_agent/`
- `backend/src/main/resources/db/migration/`

The following local-only material is intentionally excluded from Git so repository-indexing tools do not treat it as application source:

- `companion/doc/`, except its scope README: design history and prior implementation notes
- `dietary-advice/`: earlier standalone dietary-advice experiments
- `backend/docs/`, `backend/postman/`, and `backend/sql/`: superseded reviews, generated API collections, and pre-Flyway SQL
- `frontend/lib/文件/` and `frontend/spec.txt`: cleanup notes and an older product specification
- `graphRag/workspace/data/`: local corpora, reference documents, generated snapshots, and import datasets
- `graphRag/workspace/src/kg_builder/data/`: duplicated legacy/import datasets
- `graphRag/output/` and analysis notebooks: generated investigation output
- directories named `old`, `output`, or `result`, and versioned experiment folders such as `V1`, `V2`, and `test2`; the active `nutritionist_agent/test_area/` test suite is an explicit exception
- `blender/` and `blender_extracted/`: 3D authoring source assets, not runtime application code

The `frontend/third_party/model_viewer_plus/` directory is intentionally tracked because `frontend/pubspec.yaml` declares it as a path dependency required to build the application. Treat it as vendored dependency code, not Dietary App domain logic.

Runtime images and `.glb` models under `frontend/assets/` are also intentionally tracked because Flutter packages them as application assets. They are not architecture source and should not be described as services or modules.

Do not infer current behavior from generated JSON, screenshots, platform icons, archived plans, or binary assets when an active source file provides the same information.

## Sources of truth

When sources disagree, use this order:

1. Active runtime source code and API DTOs/models.
2. Database migrations and runtime configuration templates.
3. Component README files next to active code.
4. `MAF/MAF_WORKFLOW_CHANGE_SPEC 1.md` for planned MAF behavior only.
5. Historical notes and experiment folders.

Never copy credentials or local machine paths into generated documentation. Document environment-variable names and placeholders only.
