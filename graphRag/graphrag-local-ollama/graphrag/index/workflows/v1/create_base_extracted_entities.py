# Copyright (c) 2024 Microsoft Corporation.
# Licensed under the MIT License

"""A module containing build_steps method definition."""

from datashaper import AsyncType

from graphrag.index.config import PipelineWorkflowConfig, PipelineWorkflowStep

workflow_name = "create_base_extracted_entities"


def build_steps(
    config: PipelineWorkflowConfig,
) -> list[PipelineWorkflowStep]:
    """
    Create the base table for extracted entities.

    ## Dependencies
    * `workflow:create_base_text_units`
    """
    entity_extraction_config = (
        config.get("entity_extract", {})
        or config.get("entity_extraction", {})
    )
    # print("[DEBUG] entity_extraction_config:", entity_extraction_config)
    graphml_snapshot_enabled = config.get("graphml_snapshot", False) or False
    raw_entity_snapshot_enabled = config.get(
        "raw_entity_snapshot", False) or False

    return [
        {
            "verb": "entity_extract",
            "args": {
                "strategy": entity_extraction_config.get("strategy", "openai"),  # 👈 預設值
                **entity_extraction_config,
                "column": entity_extraction_config.get("text_column", "chunk"),
                "id_column": entity_extraction_config.get("id_column", "chunk_id"),
                "async_mode": entity_extraction_config.get(
                    "async_mode", AsyncType.AsyncIO
                ),
                "to": "entities",
                "graph_to": "entity_graph",
            },
            "input": {"source": "workflow:create_base_text_units"},
        },
        {
            "verb": "snapshot",
            "enabled": raw_entity_snapshot_enabled,
            "args": {
                "name": "raw_extracted_entities",
                "formats": ["json"],
            },
        },
        # 🔎 在這裡插 debug_print，看 entity_extract 後的 DataFrame 有哪些欄位
        # {
        #     "verb": "debug_print",
        #     "args": {
        #         "msg": " => create_base_extracted_entities : After entity_extract",
        #         "head": 10,
        #         "show_rows": True
        #     },
        # },
        
        # 新增 canonicalization 步驟
        # {
        #     "verb": "canonicalize",
        #     "args": {
        #         "name_field": "name",   # dict 裡的 key（通常是 "name"）
        #         "model": "llama3.1:8b",
        #         "verbose": True,
        #     },
        # },
        
        # {
        #     "verb": "unpack_entities",
        #     "args": {
        #         "column": "entities",    # 來源欄位
        #         "to": "unpacked_entities"
        #     },
        # },
        # {
        #     "verb": "debug_print",
        #     "args": {
        #         "message": "=> Entities after canonicalization (flattened)",
        #         "max_rows": 20,
        #         "columns": ["name", "canonical_name"],   # 👈 這裡就能抓到
        #     },
        #     "input": {"source": "unpacked_entities"},
        # },
        {
            "verb": "merge_graphs",
            "args": {
                "column": "entity_graph",
                "to": "entity_graph",
                **config.get(
                    "graph_merge_operations",
                    {
                        "nodes": {
                            "source_id": {
                                "operation": "concat",
                                "delimiter": ", ",
                                "distinct": True,
                            },
                            "description": ({
                                "operation": "concat",
                                "separator": "\n",
                                "distinct": False,
                            }),
                        },
                        "edges": {
                            "source_id": {
                                "operation": "concat",
                                "delimiter": ", ",
                                "distinct": True,
                            },
                            "description": ({
                                "operation": "concat",
                                "separator": "\n",
                                "distinct": False,
                            }),
                            "weight": "sum",
                        },
                    },
                ),
            },
        },
        {
            "verb": "snapshot_rows",
            "enabled": graphml_snapshot_enabled,
            "args": {
                "base_name": "merged_graph",
                "column": "entity_graph",
                "formats": [{"format": "text", "extension": "graphml"}],
            },
        },
    ]
