# import pandas as pd
# import traceback
# from typing import Any
# from datashaper import TableContainer
# import ollama

# # 簡單快取，避免重複查詢
# _alias_cache = {}


# def _is_same_entity_ollama(a: str, b: str, model: str = "llama3") -> bool:
#     """
#     使用本地 Ollama 判斷兩個 entity 是否為同一個。
#     """
#     key = tuple(sorted([a, b]))
#     if key in _alias_cache:
#         return _alias_cache[key]

#     prompt = f"""
#     Compare the following two entity mentions.
#     Return "YES" if they refer to the same real-world entity, otherwise "NO".

#     Mention A: "{a}"
#     Mention B: "{b}"
#     """

#     try:
#         response = ollama.chat(
#             model=model,
#             messages=[{"role": "user", "content": prompt}],
#         )
#         answer = response["message"]["content"].strip().upper()
#         result = "YES" in answer
#         _alias_cache[key] = result
#         return result
#     except Exception as e:
#         print(f"[canonicalize_entities_verb] Ollama request failed: {e}")
#         return False


# def _to_dataframe(x: Any) -> pd.DataFrame:
#     # 1) 已是 DataFrame
#     if isinstance(x, pd.DataFrame):
#         return x

#     # 2) Datashaper VerbInput: 先取 TableContainer
#     if hasattr(x, "get_input"):
#         tc = x.get_input()
#         if hasattr(tc, "table") and isinstance(tc.table, pd.DataFrame):
#             return tc.table
#         if isinstance(tc, pd.DataFrame):
#             return tc

#     # 3) 容器常見欄位
#     for attr in ("table", "value", "data", "df"):
#         if hasattr(x, attr):
#             v = getattr(x, attr)
#             if isinstance(v, pd.DataFrame):
#                 return v

#     # 4) dict 形式
#     if isinstance(x, dict):
#         for k in ("table", "value", "data", "df"):
#             v = x.get(k)
#             if isinstance(v, pd.DataFrame):
#                 return v

#     raise TypeError(
#         "semantic_merge_nodes_verb: cannot resolve input as DataFrame")


# def canonicalize_entities_verb(
#     input: Any = None,
#     table: Any = None,
#     name_column: str = "name",
#     name_field: str = "name",   # dict 裡的 key
#     model: str = "llama3.1:8b", # Ollama 模型名稱
#     verbose: bool = True,
#     **kwargs,
# ):
#     """
#     Datashaper verb: 使用 Ollama 將不同 alias canonicalize 成同一個實體名稱
#     適用於 entity_extract 的輸出：DataFrame 裡有一個 'entities' 欄位
#     該欄位每列是一個 list[dict]，每個 dict 有 'name' 等欄位
#     """
#     try:
#         # 兼容 Datashaper 的不同輸入格式
#         container = table if table is not None else input
#         if container is None:
#             raise TypeError("canonicalize_entities_verb expects 'table' or 'input' argument")

#         df = _to_dataframe(container)

#         canonical_names = []

#         def canonicalize(x: str) -> str:
#             x = str(x).strip().strip('"')
#             for canon in canonical_names:
#                 if _is_same_entity_ollama(x, canon, model=model):
#                     if verbose:
#                         print(f"[canonicalize_entities_verb] '{x}' → '{canon}'")
#                     return canon
#             canonical_names.append(x)
#             return x

#         def canonicalize_entity_list(entity_list):
#             """處理每一列的 entities (list of dicts)"""
#             if not isinstance(entity_list, list):
#                 return entity_list
#             for e in entity_list:
#                 if isinstance(e, dict) and name_field in e:
#                     e[name_field] = canonicalize(e[name_field])
#             return entity_list

#         # ✅ 改為處理整個 'entities' 欄位
#         if "entities" not in df.columns:
#             raise KeyError("'entities' column not found in DataFrame")
#         df["entities"] = df["entities"].map(canonicalize_entity_list)

#         return TableContainer(table=df)

#     except Exception as e:
#         print("\n[canonicalize_entities_verb] 發生錯誤！")
#         print(f"錯誤訊息:{e}")
#         print("詳細堆疊 : ")
#         traceback.print_exc()
#         raise

# ============================================================================================================================================
# python graphrag-local-ollama\test_canonicalize.py
import pandas as pd
import traceback
from typing import Any, Dict
from datashaper import TableContainer
import ollama
import json


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

    raise TypeError(
        "canonicalize_entities_verb: cannot resolve input as DataFrame")


def canonicalize_entities_verb(
    input: Any = None,
    table: Any = None,
    name_field: str = "name",   # dict 裡的 key
    model: str = "llama3.1:8b",  # Ollama 模型名稱
    batch_size: int = 80,
    verbose: bool = True,
    **kwargs,
):
    """
    Datashaper verb: 使用 Ollama 進行全域實體 canonicalize
    - 一次收集所有實體名稱
    - 交給 LLM 輸出 alias → canonical 對照表
    - 再套回 DataFrame
    """
    print(" === canonicalizing ===")
    try:
        # 兼容 Datashaper 的不同輸入格式
        container = table if table is not None else input
        if container is None:
            raise TypeError(
                "canonicalize_entities_verb expects 'table' or 'input' argument")

        df = _to_dataframe(container)

        if "entities" not in df.columns:
            raise KeyError("'entities' column not found in DataFrame")

        # === 1) 收集所有 unique entity names ===
        all_names = []
        for entity_list in df["entities"].dropna():
            if isinstance(entity_list, list):
                for e in entity_list:
                    if isinstance(e, dict) and name_field in e:
                        all_names.append(str(e[name_field]).strip().strip('"'))

        unique_names = sorted(set(all_names))

        # === 2) 分批送進 LLM，得到 alias→canonical 對照表 ===
        mappings: Dict[str, str] = {}
        for i in range(0, len(unique_names), batch_size):
            batch = unique_names[i:i+batch_size]

            prompt = f"""
            你是一個知識圖譜清理助手。
            請將下列實體名稱，根據同義詞 / 別名 / 公司全名 / 縮寫，合併成統一的 canonical form。

            請務必只輸出 **純 JSON**，不要使用 Markdown 語法，不要在 JSON 外加任何文字。
            JSON 的結構必須是：
            {{
                "原始名稱1": "canonical 名稱1",
                "原始名稱2": "canonical 名稱2",
                ...
                "原始名稱n": "canonical 名稱n",
                "_comment": {{
                    "原始名稱1": "清理過程的細節說明",
                    "原始名稱2": "清理過程的細節說明"
                }}
            }}

            實體名稱清單：
            {json.dumps(batch, ensure_ascii=False, indent=2)}
            """

            response = ollama.chat(
                model=model,
                messages=[{"role": "user", "content": prompt}],
                options={"temperature": 0}  # 讓輸出更穩定、避免隨機性
            )
            # print('=== response["message"]["content"] ===')
            # print(response["message"]["content"])
            try:
                batch_map = json.loads(response["message"]["content"])
                # 取出 _comment
                if "_comment" in batch_map:
                    comments = batch_map["_comment"]
                    print("\n=== Canonicalization Comments ===")
                    for k, v in comments.items():
                        print(f"[{k}] {v}")
                    # 移除 _comment，不進入後續流程
                    batch_map.pop("_comment", None)

                mappings.update(batch_map)
                
            except Exception as e:
                if verbose:
                    print("⚠️ LLM response parse error:", e)
                    print("Raw response:", response)

        # === 3) 替換 DataFrame 裡的 entities ===
        def apply_mapping(entity_list):
            if not isinstance(entity_list, list):
                return entity_list
            for e in entity_list:
                if isinstance(e, dict) and name_field in e:
                    orig = str(e[name_field]).strip().strip('"')
                    e[name_field] = mappings.get(orig, orig)
            return entity_list

        df["entities"] = df["entities"].map(apply_mapping)

        # === 4) 輸出結果到 cmd ===
        if verbose:
            print("\n=== Canonicalization Results ===")
            for src, tgt in sorted(mappings.items()):
                print(f"[canonicalize_entities_verb] '{src}' → '{tgt}'")

            # 額外檢查：同一 canonical 有多個 alias
            rev_map: Dict[str, list] = {}
            for src, tgt in mappings.items():
                rev_map.setdefault(tgt, []).append(src)

            print("\n=== Grouped by Canonical ===")
            for canonical, aliases in rev_map.items():
                if len(aliases) > 1:
                    print(f"{canonical}: {aliases}")

        return TableContainer(table=df)

    except Exception as e:
        print("\n[canonicalize_entities_verb] 發生錯誤！")
        print(f"錯誤訊息:{e}")
        print("詳細堆疊 : ")
        traceback.print_exc()
        raise
