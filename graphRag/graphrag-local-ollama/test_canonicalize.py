#!/usr/bin/env python3
import pandas as pd
from graphrag.index.verbs.canonicalize import canonicalize_entities_verb
from datashaper import TableContainer

# === 測試資料 ===
# 模擬 DataFrame 內的 'entities' 欄位
# 每一列是一個 list[dict]，dict 內有 'name'
data = [
    [{"name": "TSMC"}, {"name": "TSM"}],
    [{"name": "Taiwan Semiconductor Manufacturing"}, {"name": "APPLE"}],
    [{"name": "NVIDIA"}, {"name": "NVDA"}],
    [{"name": "Morgan Stanley"}, {"name": "MS"}],
    [{"name": "The Motley Fool"}, {"name": "Stock Advisor"}],
]

df = pd.DataFrame({"entities": data})

print("=== Input DataFrame ===")
print(df)

# === 執行 canonicalize_entities_verb ===
print("\n=== Running canonicalize_entities_verb ===")
result = canonicalize_entities_verb(table=df, verbose=True)

print("\n=== Output DataFrame ===")
print(result.table)
