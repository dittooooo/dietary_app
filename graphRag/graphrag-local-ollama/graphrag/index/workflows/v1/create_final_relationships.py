# Copyright (c) 2024 Microsoft Corporation.
# Licensed under the MIT License

"""A module containing build_steps method definition."""

from graphrag.index.config import PipelineWorkflowConfig, PipelineWorkflowStep

workflow_name = "create_final_relationships"


def build_steps(
    config: PipelineWorkflowConfig,
) -> list[PipelineWorkflowStep]:
    """
    Create the final relationships table.

    ## Dependencies
    * `workflow:create_base_entity_graph`
    * `workflow:create_final_nodes`
    """
    base_text_embed = config.get("text_embed", {})
    relationship_description_embed_config = config.get(
        "relationship_description_embed", base_text_embed
    )
    skip_description_embedding = config.get(
        "skip_description_embedding", False)

    return [
        # 1) 從 base graph 取出 edges
        {
            "id": "edges_unpacked",
            "verb": "unpack_graph",
            "args": {"column": "clustered_graph", "type": "edges"},
            "input": {"source": "workflow:create_base_entity_graph"},
        },
        {
            "id": "debug_edges_unpacked",
            "verb": "snapshot_rows",
            "args": {
                "column": "source_id",
                "base_name": "debug_edges_unpacked",
                "formats": ["csv"]
            },
            "input": "edges_unpacked"
        },
        # 3) 只取 level = 0
        {
            "id": "edges_level0",
            "verb": "filter",
            "args": {"column": "level", "criteria": [{"type": "value", "operator": "equals", "value": 0}]},
            "input": "edges_unpacked",
        },
        {
            "id": "debug_edges_level0",
            "verb": "snapshot_rows",
            "args": {
                "column": "source_id",
                "base_name": "debug_edges_level0",
                "formats": ["csv"]
            },
            "input": "edges_level0"
        },
        # 4) （可選）描述向量，不影響鏈路
        {
            "id": "edges_level0_emb",
            "verb": "text_embed",
            "enabled": not skip_description_embedding,
            "args": {
                "embedding_name": "relationship_description",
                "column": "description",
                "to": "description_embedding",
                **relationship_description_embed_config,
            },
            "input": "edges_level0",
        },
        # 5) 移除暫存欄位（直接吃 edges_level0，避免 embedding 關掉時鏈路斷）
        {
            "id": "pruned_edges",
            "verb": "drop",
            "args": {"columns": ["level"]},
            "input": "edges_level0",
        },
        # 7) 最終節點（level=0）
        {
            "id": "filtered_nodes",
            "verb": "filter",
            "args": {"column": "level", "criteria": [{"type": "value", "operator": "equals", "value": 0}]},
            "input": "workflow:create_final_nodes",
        },

        # 6) 用 nodes 對應，把 source/target 名稱 → id（再 canonical）
        {
            "id": "remapped_edges",
            "verb": "remap_edge_ids",
            "input": {"source": "pruned_edges", "nodes": "filtered_nodes"},
        },

        # 8) rank
        {
            "id": "ranked_edges",
            "verb": "compute_edge_combined_degree",
            "args": {"to": "rank"},
            "input": {"source": "remapped_edges", "nodes": "filtered_nodes"},
        },
        # 9) convert（只保留 human_readable_id 轉字串）
        {
            "id": "converted_human_id",
            "verb": "convert",
            "args": {"column": "human_readable_id", "type": "string", "to": "human_readable_id"},
            "input": "ranked_edges",
        },
        # 10) 檢查 dangling：把同一張表同時當 primary input 與命名輸入傳進去
        {
            "id": "edges_checked",
            "verb": "check_dangling_ids",
            "args": {},
            "input": {
                "source": "converted_human_id",   # primary input
                "edges":  "converted_human_id",   # 命名輸入：edges
                "nodes":  "filtered_nodes"        # 命名輸入：nodes
            },
        },
    ]
