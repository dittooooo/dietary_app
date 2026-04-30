# from __future__ import annotations
# import pandas as pd
# from typing import Any, Dict
# from datashaper import TableContainer

# def _to_df(x):
#     # 1) None
#     if x is None:
#         return pd.DataFrame()

#     # 2) 直接是 DataFrame
#     if isinstance(x, pd.DataFrame):
#         return x

#     # 3) Datashaper VerbInput：有 get_input()
#     if hasattr(x, "get_input"):
#         try:
#             tc = x.get_input()
#             # 修正 typo: tablem -> table
#             if hasattr(tc, "table") and isinstance(tc.table, pd.DataFrame):
#                 return tc.table
#         except Exception:
#             pass

#     # 4) TableContainer：有 .table
#     if hasattr(x, "table") and isinstance(x.table, pd.DataFrame):
#         return x.table

#     # 5) dict 形式（保險）
#     if isinstance(x, dict):
#         for k in ("table", "value", "data", "df", "source", "edges", "input"):
#             v = x.get(k)
#             if isinstance(v, pd.DataFrame):
#                 return v
#             if hasattr(v, "table") and isinstance(v.table, pd.DataFrame):
#                 return v.table

#     return pd.DataFrame()

# def _first_non_empty_df(*candidates: Any):
#     for c in candidates:
#         try:
#             df = _to_df(c)
#             if isinstance(df, pd.DataFrame) and not df.empty:
#                 return df
#         except Exception:
#             continue
#     return pd.DataFrame()

# def run(
#     input: Any = None,
#     table: Any = None,
#     data: Any = None,
#     args: Dict[str, Any] | None = None,
#     context: Any | None = None,
#     **kwargs: Any,
# ) -> TableContainer:
#     """
#     Remap edge endpoint IDs using context.cache['node_id_map'].
#     - 支援兩種欄位命名：
#       - 新版/常見：'source', 'target'
#       - 舊版/變體：'source_id', 'target_id'
#     - 也會在重寫後做去重（完全相同的邊與主要欄位相同時）。
#     """
#     df_candidate = _first_non_empty_df(
#         table,
#         input,
#         data,
#         args,
#         kwargs,
#         {"table":table},
#         {"input":input},
#         {"edges": kwargs.get("edges") if isinstance(kwargs, dict) else None},
#     )

#     if isinstance (df_candidate, pd.DataFrame):
#         df = df_candidate.copy()
#     else:
#         df = pd.DataFrame()


#     if df.empty and kwargs:
#        for _, v in kwargs.items():
#             cand = _to_df(v)
#             if isinstance (cand, pd.DataFrame) and not cand.empty:
#                 df = cand.copy()
#                 break

#     if df.empty:
#         print("[remap_edge_ids] empty input")
#         return TableContainer(table=df)

#     # 讀 id_map（修正：非 awaitable 也要賦值）
#     id_map: Dict[str, str] = {}
#     if context is not None and hasattr(context, "cache"):
#         try:
#             maybe = context.cache.get("node_id_map", {})
#             if hasattr(maybe, "__await__"):
#                 import asyncio
#                 id_map = asyncio.get_event_loop().run_until_complete(maybe) or {}
#             else:
#                 id_map = maybe or {}
#         except Exception:
#             id_map = {}

#     # 判斷端點欄位名稱
#     if {"source", "target"}.issubset(df.columns):
#         src_col, tgt_col = "source", "target"
#     elif {"source_id", "target_id"}.issubset(df.columns):
#         src_col, tgt_col = "source_id", "target_id"
#     else:
#         print(f"[remap_edge_ids] no endpoint columnsno endpoint columns in columns={list(df.column)}, [passthrough]")
#         return TableContainer(table=df)

#     # 有映射就套映射
#     if id_map:
#         df[src_col] = df[src_col].map(id_map).fillna(df[src_col])
#         df[tgt_col] = df[tgt_col].map(id_map).fillna(df[tgt_col])

#     # 不論是否有映射，都保證輸出標準欄位
#     df["source"] = df[src_col]
#     df["target"] = df[tgt_col]

#     # 去重（用標準欄位）
#     key_cols = [c for c in ["source", "target", "description", "human_readable_id"] if c in df.columns]
#     if key_cols:
#         df = df.drop_duplicates(subset=key_cols)
#     else:
#         df = df.drop_duplicates()

#     print(f"[remap_edge_ids] rows={len(df)}; id_map={'yes' if id_map else 'no'}; src_col={src_col}, tgt_col={tgt_col}")
#     print("[remap_edge_ids] preview columns :",df.columns.tolist())

#     return TableContainer(table=df)


from datashaper import TableContainer, VerbInput, VerbCallbacks, verb
import pandas as pd
import numpy as np

@verb(name="remap_edge_ids")
def run(
    input: VerbInput,
    callbacks: VerbCallbacks,
    args=None,
    context=None,
    **kwargs,
) -> TableContainer:
    # 取 edges / nodes（若只有單一輸入，也能 fallback）
    try:
        edges = input.get_input("source").copy()
    except Exception:
        edges = input.get_input().copy()
    try:
        nodes = input.get_input("nodes").copy()
    except Exception:
        nodes = pd.DataFrame()

    print(f"[remap_edge_ids] incoming rows={len(edges)} cols={list(edges.columns)}; nodes_rows={len(nodes)}")

    if edges.empty or not {"source","target"}.issubset(edges.columns):
        print("[remap_edge_ids] missing edges or endpoint columns; passthrough")
        return TableContainer(table=edges)

    # 1) 用 nodes 把名稱 -> id（title / canonical_name / label -> id）
    title_to_id = {}
    if not nodes.empty and "id" in nodes.columns:
        for key in ("title", "canonical_name", "label"):
            if key in nodes.columns:
                title_to_id.update(pd.Series(nodes["id"].values, index=nodes[key]).to_dict())
    if title_to_id:
        edges["source"] = edges["source"].map(title_to_id).fillna(edges["source"])
        edges["target"] = edges["target"].map(title_to_id).fillna(edges["target"])
        print("[remap_edge_ids] name→id mapped via nodes")

    # 2) 套用 node_id_map（舊 id -> canonical id）
    id_map = {}
    if context is not None and hasattr(context, "cache"):
        try:
            maybe = context.cache.get("node_id_map")  # 只能給 1 個參數
        except TypeError:
            try:
                maybe = context.cache["node_id_map"]
            except Exception:
                maybe = None
        except Exception:
            maybe = None
        # 可能是 awaitable
        try:
            if hasattr(maybe, "__await__"):
                import asyncio
                maybe = asyncio.get_event_loop().run_until_complete(maybe)
        except Exception:
            pass
        if isinstance(maybe, dict):
            id_map = maybe

    if id_map:
        edges["source"] = edges["source"].map(id_map).fillna(edges["source"])
        edges["target"] = edges["target"].map(id_map).fillna(edges["target"])
        print(f"[remap_edge_ids] applied node_id_map size={len(id_map)}")

    # 3) **補上 text_unit_ids**：由 source_id 轉成 list
    if "text_unit_ids" not in edges.columns:
        if "source_id" in edges.columns:
            def to_list(v):
                if pd.isna(v):
                    return []
                if isinstance(v, list):
                    return v
                if isinstance(v, str):
                    # 可能是單一 id 或 逗號分隔
                    parts = [s.strip() for s in v.split(",") if s.strip()]
                    return parts if parts else [v]
                return [v]
            edges["text_unit_ids"] = edges["source_id"].apply(to_list)
        else:
            edges["text_unit_ids"] = [[] for _ in range(len(edges))]
        print("[remap_edge_ids] created text_unit_ids from source_id")

    # 4) 去重（可選）
    key_cols = [c for c in ["source","target","description","human_readable_id"] if c in edges.columns]
    edges = edges.drop_duplicates(subset=key_cols) if key_cols else edges.drop_duplicates()

    print(f"[remap_edge_ids] done rows={len(edges)}; cols={list(edges.columns)}")
    
    def normalize_list(val):
        if val is None or (isinstance(val, float) and pd.isna(val)):
            return []
        if isinstance(val, list):
            return [str(x) for x in val]
        if isinstance(val, (np.ndarray, pd.Series, tuple, set)):
            return [str(x) for x in list(val)]
        if isinstance(val, str):
            return [s.strip() for s in val.split(",") if s.strip()]
        return [str(val)]

    if "text_unit_ids" in edges.columns:
        edges["text_unit_ids"] = edges["text_unit_ids"].apply(normalize_list)
    
    return TableContainer(table=edges)

