
from datashaper import TableContainer, VerbInput, VerbCallbacks, verb
import pandas as pd

def _to_df(x):
    if x is None:
        return pd.DataFrame()
    if isinstance(x, pd.DataFrame):
        return x
    # TableContainer
    if hasattr(x, "table") and isinstance(x.table, pd.DataFrame):
        return x.table
    return pd.DataFrame()

@verb(name="check_dangling_ids")
def check_dangling_ids_verb(
    input: VerbInput,
    callbacks: VerbCallbacks,
    **kwargs,
) -> TableContainer:
    # 優先取命名輸入
    try:
        edges_in = input.get_input("edges")
    except Exception:
        edges_in = input.get_input()  # 退回 primary input
    try:
        nodes_in = input.get_input("nodes")
    except Exception:
        nodes_in = None

    edges = _to_df(edges_in)
    nodes = _to_df(nodes_in)

    if edges.empty:
        raise TypeError("edges 必須是 DataFrame 或 TableContainer")

    # 沒有 nodes 就不過濾，直接回傳
    if nodes.empty or "id" not in nodes.columns:
        return TableContainer(table=edges)

    valid_ids = set(nodes["id"].astype(str))
    if "source" in edges.columns and "target" in edges.columns:
        src = edges["source"].astype(str)
        tgt = edges["target"].astype(str)
        mask = src.isin(valid_ids) & tgt.isin(valid_ids)
        dropped = (~mask).sum()
        if dropped:
            print(f"[check_dangling_ids] removed {dropped} dangling edges")
        edges = edges.loc[mask].copy()

    return TableContainer(table=edges)
