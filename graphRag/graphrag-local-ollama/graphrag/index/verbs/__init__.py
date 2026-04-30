# Copyright (c) 2024 Microsoft Corporation.
# Licensed under the MIT License

"""A module containing get_default_verbs method definition."""

from .covariates import extract_covariates
from .entities import entity_extract, summarize_descriptions
from .genid import genid
from .graph import (
    cluster_graph,
    create_community_reports,
    create_graph,
    embed_graph,
    layout_graph,
    merge_graphs,
    unpack_graph,
)
from .overrides import aggregate, concat, merge
# 
from .snapshot import snapshot
from .snapshot_rows import snapshot_rows
from .spread_json import spread_json
from .text import chunk, text_embed, text_split, text_translate
from .unzip import unzip
from .zip import zip_verb

from .semantic_merge_nodes import semantic_merge_nodes_verb
from .remap_edge_ids import run as remap_edge_ids_verb
from .check_dangling_ids import check_dangling_ids_verb
from .canonicalize import canonicalize_entities_verb
from .add_relation_type import add_relation_type_verb
from .map_edge_names_to_canonical import run as map_edge_names_to_canonical_verb


from .debug_print import debug_print_verb

__all__ = [
    "aggregate",
    "chunk",
    "cluster_graph",
    "concat",
    "create_community_reports",
    "create_graph",
    "embed_graph",
    "entity_extract",
    "extract_covariates",
    "genid",
    "layout_graph",
    "merge",
    "merge_graphs",
    "snapshot",
    "snapshot_rows",
    "spread_json",
    "summarize_descriptions",
    "text_embed",
    "text_split",
    "text_translate",
    "unpack_graph",
    "unzip",
    "zip_verb",
    # "remap_edge_ids_verb",
    # "check_dangling_ids_verb",
    # "canonicalize",
]

"""
key (字串)：在 workflow YAML 或 Python pipeline 裡你要用的 verb 名稱
value (函式)：實際執行的 function
"""

def get_default_verbs():
    return {
        "semantic_merge_nodes":semantic_merge_nodes_verb,
        "semantic_merge_nodes_verb": semantic_merge_nodes_verb,
        "remap_edge_ids": remap_edge_ids_verb,
        "check_dangling_ids":check_dangling_ids_verb,
        "canonicalize":canonicalize_entities_verb, # 可以被註解掉
        "add_relation_type":add_relation_type_verb,
        "map_edge_names_to_canonical":map_edge_names_to_canonical_verb,
        "debug_print":debug_print_verb,            
    }
