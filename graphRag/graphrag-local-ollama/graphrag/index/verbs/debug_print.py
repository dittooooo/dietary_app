from typing import Any
import pandas as pd
from datashaper import TableContainer, verb


def _to_df(x: Any) -> pd.DataFrame:
    if isinstance(x, pd.DataFrame):
        return x
    if hasattr(x, "get_input"):
        tc = x.get_input()
        if hasattr(tc, "table") and isinstance(tc.table, pd.DataFrame):
            return tc.table
        if isinstance(tc, pd.DataFrame):
            return tc
    for attr in ("table", "value", "data", "df"):
        if hasattr(x, attr):
            v = getattr(x, attr)
            if isinstance(v, pd.DataFrame):
                return v
    if isinstance(x, dict):
        for k in ("table", "value", "data", "df"):
            v = x.get(k)
            if isinstance(v, pd.DataFrame):
                return v
    raise TypeError("debug_print: cannot resolve input as DataFrame")
  
def debug_print_verb(
    input: Any = None,
    table: Any = None,
    msg: str = "",
    head: int = 5,
    count: int = 0,
    show_rows: bool = False, **kwargs
):
    df = _to_df(table if table is not None else input)
    print("\n[DEBUG_PRINT] debug_print_verb :",msg)
    print("[DEBUG_PRINT] debug_print_verb columns :",list(df.columns))
    print("=== start of rows ===")
    print(df.head(count).to_string())
    print("=== end of rows ==="+"\n")
    # if show_rows:
    #     print(df.head(head).to_string(index=False))
    return TableContainer(table=df)