from __future__ import annotations

from typing import Any

from fastapi import FastAPI, Header
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field

from .clients import OpenAIServiceError, WorkflowServices, sanitize_temp_story
from .config import Settings
from .workflow import ConversationServices, create_conversation_workflow


class ConversationRequest(BaseModel):
    model_config = ConfigDict(extra="ignore")

    user_prompt: Any = None
    temp_story: list[dict[str, Any]] = Field(default_factory=list)


def create_app(services: ConversationServices | None = None) -> FastAPI:
    app = FastAPI(title="MAF Conversation Workflow", version="1.0.0")
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.state.services = services

    @app.get("/health")
    async def health() -> dict[str, str]:
        return {"status": "ok"}

    @app.post("/maf/ask", response_model=None)
    async def maf_ask(
        request: ConversationRequest,
        authorization: str | None = Header(default=None),
    ) -> Any:
        user_prompt = request.user_prompt.strip() if isinstance(request.user_prompt, str) else ""
        if not user_prompt:
            return JSONResponse(
                status_code=400,
                content={
                    "success": False,
                    "error_code": "BAD_REQUEST",
                    "error_message": "The 'user_prompt' field is required and must be a non-empty string.",
                },
            )

        current_services = app.state.services
        if current_services is None:
            try:
                current_services = WorkflowServices(Settings.from_env())
                app.state.services = current_services
            except Exception as error:
                return JSONResponse(
                    status_code=500,
                    content={
                        "success": False,
                        "error_code": "INTERNAL_SERVER_ERROR",
                        "error_message": "An unexpected error occurred on the server.",
                    },
                )

        workflow = create_conversation_workflow(current_services)
        try:
            result = await workflow.run(
                {
                    "user_prompt": user_prompt,
                    "temp_story": sanitize_temp_story(request.temp_story),
                    "authorization": authorization,
                }
            )
            outputs = result.get_outputs()
            if not outputs:
                raise RuntimeError("MAF workflow completed without an output.")
            return outputs[0]
        except OpenAIServiceError as error:
            return JSONResponse(
                status_code=502,
                content={
                    "success": False,
                    "error_code": "OPENAI_SERVICE_ERROR",
                    "error_message": "Failed to communicate with OpenAI API. Please try again later.",
                    "debug_message": str(error),
                },
            )
        except Exception as error:
            return JSONResponse(
                status_code=500,
                content={
                    "success": False,
                    "error_code": "INTERNAL_SERVER_ERROR",
                    "error_message": "An unexpected error occurred on the server.",
                },
            )

    return app


app = create_app()
