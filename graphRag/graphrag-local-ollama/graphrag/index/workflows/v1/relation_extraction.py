# graphrag/index/workflows/v1/relation_extraction.py
# Copyright (c) 2024
# Licensed under the MIT License

"""
Workflow for extracting typed relationships using relation_extraction_v3.txt
Now includes relation_type in GraphML edges so it won't be lost in final parquet.
"""

from datashaper import AsyncType
from graphrag.index.config import PipelineWorkflowConfig, PipelineWorkflowStep


workflow_name = "relation_extraction"


def build_steps(config: PipelineWorkflowConfig) -> list[PipelineWorkflowStep]:
    """
    Create the base table for extracted relationships.

    ## Dependencies
    * `workflow:create_base_text_units`
    """
    relation_extraction_config = config.get("relation_extract", {})
    graphml_snapshot_enabled = config.get("graphml_snapshot", False) or False

    # 自訂 edge 格式化，把 relation_type 一起寫進 graphml
    # 注意：這段依賴 entity_extract verb 支援 edge_transform
    def _edge_transform(rel: dict, chunk_id: str) -> dict:
        return {
            "description": rel.get("description", ""),
            "weight": rel.get("confidence", 1.0),
            "relation_type": rel.get("relation_type", "RELATED"),  # ✅ 新增
            "source_id": chunk_id,
        }

    return [
        {
            "verb": "entity_extract",
            "args": {
                **relation_extraction_config,
                "prompt": "prompts/relation_extraction_v3.txt",
                "column": relation_extraction_config.get("text_column", "chunk"),
                "id_column": relation_extraction_config.get("id_column", "chunk_id"),
                "async_mode": relation_extraction_config.get(
                    "async_mode", AsyncType.AsyncIO
                ),
                "strategy": relation_extraction_config.get("strategy", {}),
                "to": "relationships",
                "graph_to": "entity_graph",
                # ✅ 將 relation_type 傳遞到 edge
                "edge_transform": _edge_transform,
            },
            "input": {"source": "workflow:create_base_text_units"},
        },
        {
            "verb": "snapshot_rows",
            "enabled": graphml_snapshot_enabled,
            "args": {
                "base_name": "raw_extracted_relationships",
                "column": "entity_graph",
                "formats": [{"format": "text", "extension": "graphml"}],
            },
        },
    ]
