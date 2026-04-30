from typing import Any
from datashaper import TableContainer
import pandas as pd
from graphrag.index.graph.merge.semantic_merge_nodes import semantic_merge_nodes
import traceback


def _to_dataframe(x:Any) -> pd.DataFrame:
    # 1) 已是 DataFrame
    if isinstance(x, pd.DataFrame):
        return x
    
    # 2) Datashaper VerbInput: 先取 TableContainer
    if hasattr(x, "get_input"):
        tc = x.get_input()
        if hasattr(tc, "table") and isinstance(tc.table, pd.DataFrame):
            return tc.table
        if isinstance(tc, pd.DataFrame):
            return tc
            
    # 3) 容器常見欄位
    for attr in ("table", "value", "data", "df"):
        if hasattr(x, attr):
            v = getattr(x, attr)
            if isinstance(v, pd.DataFrame):
                return v
    
    # 4) dict 形式
    if isinstance(x,dict):
        for k in ("table", "value", "data", "df"):
            v = x.get(k)
            if isinstance(v, pd.DataFrame):
                return v
            
    raise TypeError("semantic_merge_nodes_verb: cannot resolve input as DataFrame")



def semantic_merge_nodes_verb(    
    input: Any = None,
    table: Any = None,
    context: Any = None,
    threshold: float = 0.80,
    embedding_model: str = "all-MiniLM-L6-v2",
    name_column: str = "title",
    id_column: str = "id",
    alias_map: dict = None,
    representative_id_map: dict = None,
    verbose: bool = True,
    title_column_out: str = "title",
    **kwargs
):
    """Datashaper verb: 語意合併節點"""
    try:
        # 兼容不同鍵名
        container = table if table is not None else input
        if container is None:
            raise TypeError("semantic_merge_nodes_verb expects 'table' or 'input' argument")
        
        df = _to_dataframe(container)
        
        if context is not None:
            kwargs["context"] = context # 傳給內部以便寫 node_id_map
        
        merge_df = semantic_merge_nodes(
            df,
            threshold=threshold,
            embedding_model=embedding_model,
            name_column=name_column,
            id_column=id_column,
            alias_map=alias_map,
            representative_id_map=representative_id_map,
            verbose=verbose,
            title_column_out=title_column_out,
            **kwargs
        )
        
        return TableContainer(table=merge_df)
    except Exception as e:
        print("\n[semantic_merge_nodes_verb] 發生錯誤！")
        print(f"錯誤訊息:{e}")
        print("詳細堆疊 : ")
        traceback.print_exc()
        raise