# graphrag/index/verbs/graph/add_relation_type.py
# Copyright (c) 2024
# Licensed under the MIT License

"""
Datashaper custom verb: 確保 edges DataFrame 裡一定有 relation_type 欄位
- 如果已存在，就補齊 NaN → "RELATED"
- 如果不存在，就新增並全部填入 "RELATED"
"""

import pandas as pd
import traceback
from typing import Any
from datashaper import TableContainer, verb


def _to_dataframe(x: Any) -> pd.DataFrame:
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
    if isinstance(x, dict):
        for k in ("table", "value", "data", "df"):
            v = x.get(k)
            if isinstance(v, pd.DataFrame):
                return v

    raise TypeError("add_relation_type: cannot resolve input as DataFrame")


def add_relation_type_verb(
    input: Any = None,
    table: Any = None,
    column: str = "relation_type",
    default_value: str = "RELATED",
    **kwargs,
) -> TableContainer:
    """
    Datashaper verb: 確保 DataFrame 內有 relation_type 欄位
    - 如果沒有就新增，值為 default_value (RELATED)
    - 如果已有就補齊 NaN → default_value
    """
    try:
        container = table if table is not None else input
        if container is None:
            raise TypeError("add_relation_type expects 'table' or 'input' argument")

        df = _to_dataframe(container)

        if column not in df.columns:
            df[column] = default_value
        else:
            df[column] = df[column].fillna(default_value)

        return TableContainer(table=df)

    except Exception as e:
        print("\n[add_relation_type] 發生錯誤！")
        print(f"錯誤訊息: {e}")
        print("詳細堆疊 : ")
        traceback.print_exc()
        raise
