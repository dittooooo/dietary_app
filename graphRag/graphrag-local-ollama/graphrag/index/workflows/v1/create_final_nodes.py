# Copyright (c) 2024 Microsoft Corporation.
# Licensed under the MIT License

"""A module containing build_steps method definition."""

from graphrag.index.config import PipelineWorkflowConfig, PipelineWorkflowStep

workflow_name = "create_final_nodes"


def build_steps(
    config: PipelineWorkflowConfig,
) -> list[PipelineWorkflowStep]:
    """
    Create the base table for the document graph.

    ## Dependencies
    * `workflow:create_base_entity_graph`
    """
    
    snapshot_top_level_nodes = config.get("snapshot_top_level_nodes", False)
    layout_graph_enabled = config.get("layout_graph_enabled", True)
    _compute_top_level_node_positions = [
        {
            "verb": "unpack_graph",
            "args": {"column": "positioned_graph", "type": "nodes"},
            "input": {"source": "laid_out_entity_graph"},
        },
        {
            "verb": "filter",
            "args": {
                "column": "level",
                "criteria": [
                    {
                        "type": "value",
                        "operator": "equals",
                        "value": config.get("level_for_node_positions", 0),
                    }
                ],
            },
        },
        {
            "verb": "select",
            "args": {"columns": ["id", "x", "y"]},
        },
        {
            "verb": "snapshot",
            "enabled": snapshot_top_level_nodes,
            "args": {
                "name": "top_level_nodes",
                "formats": ["json"],
            },
        },
        {
            "id": "_compute_top_level_node_positions",
            "verb": "rename",
            "args": {
                "columns": {
                    "id": "top_level_node_id",
                }
            },
        },
        {
            "verb": "convert",
            "args": {
                "column": "top_level_node_id",
                "to": "top_level_node_id",
                "type": "string",
            },
        },
    ]
    
    layout_graph_config = config.get( 
        "layout_graph",
        {
            "strategy": {
                "type": "umap" if layout_graph_enabled else "zero",
            },
        },
    )
    
    # =====================================================================================================
    # 使用指令版需要註解掉
    # layout_graph_config = config.get("layout_graph", {})
    # strategy_cfg = layout_graph_config.get("strategy", {})
    # embeddings_config = strategy_cfg.get("embeddings")
    # print("="*120)
    # print("[DEBUG] build_steps(create_final_nodes) -> embeddings config:", embeddings_config)
    # print("="*120)
    # =====================================================================================================
    
    return [
        {
            "id": "laid_out_entity_graph",
            "verb": "layout_graph",
            "args": {
                "embeddings_column": "embeddings",
                "graph_column": "clustered_graph",
                "to": "node_positions",
                "graph_to": "positioned_graph",
                **layout_graph_config,
            },
            "input": {"source": "workflow:create_base_entity_graph"},
        },
        {
            "verb": "unpack_graph",
            "args": {"column": "positioned_graph", "type": "nodes"},
        },
        {
            "id": "nodes_without_positions",
            "verb": "drop",
            "args": {"columns": ["x", "y"]},
        },
        *_compute_top_level_node_positions,
        {
            "verb": "join",
            "args": {
                "on": ["id", "top_level_node_id"],
            },
            "input": {
                "source": "nodes_without_positions",
                "others": ["_compute_top_level_node_positions"],
            },
        },
        {
            "verb": "rename",
            "args": {"columns": {"label": "title", "cluster": "community"}},
        },
        # {
        #     # datashaper.errors.WorkflowVerbNotFoundError: Workflow verb not found: semantic_merge_nodes_verb
        #     # 要放 graphrag-local-ollama\graphrag\index\verbs\__init__.py => get_default_verbs()裡面的key而不是value
        #     "verb": "semantic_merge_nodes",
        #     "args": {
        #         "threshold": 0.80,
        #         "embedding_model": "all-MiniLM-L6-v2",
        #         "name_column": "title",
        #         "id_column": "id",
        #         "verbose": True
        #     },
        # },
    ]
