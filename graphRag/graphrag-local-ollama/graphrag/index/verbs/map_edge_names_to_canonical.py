# graphrag/index/verbs/map_edge_names_to_canonical.py
from __future__ import annotations
import os
from typing import Any, Optional
import pandas as pd

try:
    import pyarrow  # noqa: F401
    _HAS_PARQUET = True
except Exception:
    _HAS_PARQUET = False


def _read_nodes(path: str) -> pd.DataFrame:
    if not path or not os.path.exists(path):
        raise FileNotFoundError(f"nodes_path 不存在：{path}")
    try:
        return pd.read_parquet(path)
    except Exception as e:
        raise RuntimeError(f"讀取 nodes 失敗：{e}") from e


def _to_dataframe(obj: Any) -> Optional[pd.DataFrame]:
    if obj is None:
        return None
    if isinstance(obj, pd.DataFrame):
        return obj
    # VerbInput 相容：盡量取出 DataFrame
    if hasattr(obj, "get_input"):
        try:
            df = obj.get_input()
            if isinstance(df, pd.DataFrame):
                return df
        except Exception:
            pass
    # 其他型別不強轉，回 None
    return None


def _pick_edges(kwargs: dict, args: tuple) -> pd.DataFrame:
    # 可能位置：source（多輸入）、input（單輸入）、args[0]
    for key in ("source", "input"):
        df = _to_dataframe(kwargs.get(key))
        if df is not None:
            return df
    if args:
        df = _to_dataframe(args[0])
        if df is not None:
            return df
    raise ValueError("map_edge_names_to_canonical: 無法取得 edges（未提供 source/input）")


def _pick_nodes(kwargs: dict, node_lookup_key: str, node_replace_key: str) -> Optional[pd.DataFrame]:
    # 直接拿 nodes（多輸入常見）
    df = _to_dataframe(kwargs.get("nodes"))
    if df is not None:
        return df

    # 有些版本會把多個 DF 當成獨立 kwargs 傳入；做啟發式掃描：
    for v in kwargs.values():
        df = _to_dataframe(v)
        if df is not None and {node_lookup_key, node_replace_key}.issubset(set(df.columns)):
            return df
    return None


def run(*args, **kwargs) -> pd.DataFrame:
    """
    兼容各種 datashaper 傳參方式：
      - 單輸入：input=DataFrame / VerbInput
      - 多輸入：source=<edges>, nodes=<nodes>
      - 其他 kwargs 可能混入奇怪鍵（如 __annotations__），一律忽略
    """
    source_col: str = kwargs.get("source_col", "source")
    target_col: str = kwargs.get("target_col", "target")
    node_lookup_key: str = kwargs.get("node_lookup_key", "title")
    node_replace_key: str = kwargs.get("node_replace_key", "canonical_name")

    # 1) 取得 edges
    edges_df = _pick_edges(kwargs, args)

    # 2) 取得 nodes（優先記憶體）
    nodes_df = _pick_nodes(kwargs, node_lookup_key, node_replace_key)
    if nodes_df is None:
        nodes_path = kwargs.get("nodes_path")
        if not nodes_path:
            raise ValueError("map_edge_names_to_canonical: 必須提供 `nodes` 或 `nodes_path` 其一")
        if not _HAS_PARQUET:
            raise RuntimeError("未安裝 parquet 引擎(pyarrow/fastparquet)，且未提供 nodes DataFrame")
        nodes_df = _read_nodes(nodes_path)

    # 3) 檢查必要欄位
    for col in (source_col, target_col):
        if col not in edges_df.columns:
            raise KeyError(f"edges 缺少欄位：{col}")
    if node_lookup_key not in nodes_df.columns:
        raise KeyError(f"nodes 缺少欄位：{node_lookup_key}")
    if node_replace_key not in nodes_df.columns:
        raise KeyError(f"nodes 缺少欄位：{node_replace_key}")

    # 4) 建 lookup 並替換
    tmp = nodes_df[[node_lookup_key, node_replace_key]].dropna(subset=[node_lookup_key]).drop_duplicates(subset=[node_lookup_key], keep="first")
    lookup = pd.Series(tmp[node_replace_key].values, index=tmp[node_lookup_key].values)

    result = edges_df.copy()
    result[source_col] = result[source_col].map(lambda v: lookup.get(v, v))
    result[target_col] = result[target_col].map(lambda v: lookup.get(v, v))
    return result
