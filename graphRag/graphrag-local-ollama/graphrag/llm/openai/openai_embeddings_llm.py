# openai_embeddings_llm.py

from typing_extensions import Unpack
from graphrag.llm.base import BaseLLM
from graphrag.llm.types import (
    EmbeddingInput,
    EmbeddingOutput,
    LLMInput,
)
from .openai_configuration import OpenAIConfiguration
from .types import OpenAIClientTypes
import ollama

# ✅ 新增 OpenAI 官方 SDK
from openai import AsyncOpenAI


class OpenAIEmbeddingsLLM(BaseLLM[EmbeddingInput, EmbeddingOutput]):
    _client: OpenAIClientTypes
    _configuration: OpenAIConfiguration

    def __init__(self, client: OpenAIClientTypes, configuration: OpenAIConfiguration):
        self._client = client
        self._configuration = configuration
                

        # ✅ 如果要直連 OpenAI，初始化 client
        if True: # getattr(configuration, "use_openai_sdk", False):
            self._sdk_client = AsyncOpenAI(
                api_key=configuration.api_key,
                base_url=getattr(configuration, "api_base", "https://api.openai.com/v1"),
            )
        else:
            self._sdk_client = None

    async def _execute_llm(
        self, input: EmbeddingInput, **kwargs: Unpack[LLMInput]
    ) -> EmbeddingOutput | None:
        args = {
            "model": self._configuration.model,
            **(kwargs.get("model_parameters") or {}),
        }
        embedding_list = []

        # ✅ 判斷是否用 OpenAI SDK
        use_sdk = True # getattr(self._configuration, "use_openai_sdk", False)

        if use_sdk:
            client = AsyncOpenAI(
                api_key=self._configuration.api_key,
                base_url=getattr(self._configuration, "api_base", "https://api.openai.com/v1"),
            )

        for inp in input:
            if use_sdk:
                resp = await client.embeddings.create(
                    model=self._configuration.model,
                    input=inp,
                )
                embedding = resp.data[0].embedding
            else:
                embedding = ollama.embeddings(
                    model=self._configuration.model,
                    prompt=inp
                )["embedding"]

            embedding_list.append(embedding)

        return embedding_list
