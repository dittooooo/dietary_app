from __future__ import annotations
from typing import Any, Dict, List, Optional
import re
import numpy as np
import pandas as pd
from sentence_transformers import SentenceTransformer

ALIAS_MAP_DEFAULT = {
    "TAIWAN SEMICONDUCTOR MANUFACTURING": "TAIWAN SEMICONDUCTOR MANUFACTURING COMPANY LIMITED",
    "TAIWAN SEMICONDUCTOR MANUFACTURING COMPANY LIMITED": "TAIWAN SEMICONDUCTOR MANUFACTURING COMPANY LIMITED",
    "TAIWAN SEMICONDUCTOR MANUFACTURING COMPANY LIMITED (NYSE:TSM)": "TAIWAN SEMICONDUCTOR MANUFACTURING COMPANY LIMITED",
    "TAIWAN SEMICONDUCTOR MANUFACTURING ": "TAIWAN SEMICONDUCTOR MANUFACTURING COMPANY LIMITED",
    "TAIWAN SEMICONDUCTOR MANUFACTURING (NYSE:TSM)": "TAIWAN SEMICONDUCTOR MANUFACTURING COMPANY LIMITED",
    "TAIWAN SEMICONDUCTOR MANUFACTURING CO.": "TAIWAN SEMICONDUCTOR MANUFACTURING COMPANY LIMITED",
    "TSMC": "TAIWAN SEMICONDUCTOR MANUFACTURING COMPANY LIMITED",
    "TSM": "TAIWAN SEMICONDUCTOR MANUFACTURING COMPANY LIMITED",
}

# ===== 規則化與分桶 =====
_ABBR_STOPWORDS = {
    "CO", "CO.", "COMPANY", "CORP", "CORP.", "CORPORATION",
    "INC", "INC.", "INCORPORATED", "LTD", "LTD.", "LIMITED",
    "NV", "PLC", "LLC", "LLP", "SA", "AG", "BV", "KG"
}

def normalize_name(name: str) -> str:
    name = name.upper()
    name = re.sub(r"\(.*?\)","",name) # 去掉括號及內容
    name = re.sub(r"[^A-Z0-9 ]+", "", name) # 只留字母數字空格
    name = re.sub(r"\s+", " ", name).strip() # 去掉多餘空格
    # 去掉尾端公司型態字（CO, LTD, INC...）
    toks = [t for t in name.split() if t not in _ABBR_STOPWORDS]
    return " ".join(toks) if toks else name

def _normalize_alias_map(alias_map: Dict[str, str]) -> Dict[str, str]:
    out = {}
    for k,v in alias_map.items():
        out[normalize_name(k)] = normalize_name(v)
    return out

def alias_map_lookup(name: str, alias_map: Dict[str,str]) -> str:
    norm_name = normalize_name(name)
    return alias_map.get(norm_name, norm_name)

def signature_key(name: str) -> str:
    """
    粗分桶：移除常見停用詞、排序 token，降低彼此比對次數。
    相同 key 才進一步跑向量近鄰。
    """
    norm = normalize_name(name)
    toks = [t for t in norm.split() if t not in _ABBR_STOPWORDS]
    toks.sort()
    return " ".join(toks)


# ===== 並查集 =====
class DSU:
    def __init__(self, n:int):
        self.p = list(range(n))
        self.r = [0]*n
        
    def find(self, x:int)->int:
        while self.p[x]!=x:
            self.p[x] = self.p[self.p[x]]
            x = self.p[x]
        return x
        
    def union(self, a:int, b:int):
        ra, rb = self.find(a), self.find(b)
        if ra==rb: return
        if self.r[ra] < self.r[rb]:
            ra, rb = rb, ra
        self.p[rb] = ra
        if self.r[ra]==self.r[rb]:
            self.r[ra]+=1
        

# ===== 主函式（優化版）=====
def semantic_merge_nodes(
    df: pd.DataFrame,
    threshold: float = 0.80,
    embedding_model: str = "all-MiniLM-L6-v2",
    name_column: str = "title", 
    id_column: str = "id",
    alias_map: Optional[Dict[str,str]]=None,
    representative_id_map: Optional[Dict[str, Any]] = None,
    k: int=10,
    ef_search: int = 64,
    ef_construction: int = 200,
    verbose: bool = True,
    title_column_out: Optional[str] = None, 
    **kwargs: Any,
) -> pd.DataFrame:
    """
    以「分桶 + 近似最近鄰 + 並查集」降低時間複雜度的節點合併。
    - 先做 alias 與正規化，將明確別名直接對齊
    - 以 signature_key 分桶，只在小桶內做近鄰搜尋
    - 近鄰：優先使用 hnswlib（近似），找每個點的前 k 個近鄰；若無則退化
    - 使用並查集合併
    """
    try:
        print("[Step 0] 檢查欄位...")
        if name_column not in df.columns:
            raise ValueError(f"缺少欄位名稱 {name_column}")
        if id_column not in df.columns:
            raise ValueError(f"缺少 id 欄位 {id_column}")        
        
        # alias_map = (ALIAS_MAP_DEFAULT if alias_map is None else {**ALIAS_MAP_DEFAULT, **alias_map})
        # 準備 alias_map（含正規化 key）
        base = ALIAS_MAP_DEFAULT if alias_map is None else {**ALIAS_MAP_DEFAULT, **alias_map}
        alias_map = _normalize_alias_map(base)
        
        print("[Step 1] 準備名稱與ID...")
        names_raw: List[str] = df[name_column].fillna("").astype(str).tolist()
        ids: List[Any] = df[id_column].tolist()
        n = len(names_raw)
        
        if verbose:
            print(f"[semantic_merge_nodes] 節點數 : {n}, threshold={threshold}, k={k}")
            
        
        print("[Step 2] Alias + normalize 對齊...")
        names_norm = [alias_map_lookup(x, alias_map) for x in names_raw]
        
        # 先直接把「完全相同的正規化名稱」合併（O(N)）
        print("[Step 3] 精確匹配合併...")
        dsu = DSU(n)
        buckets_exact: Dict[str, List[int]] = {}
        for i,nm in enumerate(names_norm):
            buckets_exact.setdefault(nm, []).append(i)
        for idxs in buckets_exact.values():
            base = idxs[0]
            for j in idxs[1:]:
                if dsu.find(base) != dsu.find(j):
                    # print(f"[Exact Merge] '{names_raw[j]} (id={ids[j]}) -> '{names_raw[base]}' (id={ids[base]})")                    
                    dsu.union(base, j)
        
        
        print("[Step 4] Signature 分桶...")
        bucket_map: Dict[str, List[int]] = {}
        for i,nm in enumerate(names_norm):
            key = signature_key(nm)
            bucket_map.setdefault(key, []).append(i)
        
        # 計算 embeddings
        print("[Step 5] 載入模型...")
        model = SentenceTransformer(embedding_model)        
        emb = model.encode(names_norm, convert_to_tensor=True, normalize_embeddings=True)
        emb_np = emb.detach().cpu().numpy().astype("float32") # hnswlib 需要 float32
        
        
        print(f"[Step 8] 開始桶內相似度搜尋與合併...共{len(bucket_map)}個桶")
        for b_i, (key, idxs) in enumerate(bucket_map.items(), start=1):
            # print(f"處理桶 {b_i}/{len(bucket_map)}，key='{key}'，大小={len(idxs)}")
            
            if len(idxs) <= 1:
                continue
            
            sub_idx = np.array(idxs, dtype=np.int32)
            sub_vecs = emb_np[sub_idx]
            kk = max(2, min(k, len(sub_idx)))
            
            # 小桶直接 NumPy
            if len(sub_idx) < 5:
                sims = sub_vecs @ sub_vecs.T
                topk_idx = np.argpartition(-sims, kth=range(kk), axis=1)[:,:kk]
                for i_local in range (sims.shape[0]):
                    i_global = sub_idx[i_local]
                    for j_local in topk_idx[i_local]:
                        if j_local == i_local:
                            continue
                        j_global = sub_idx[j_local]
                        if float(sims[i_local, j_local]) >= threshold:
                            # print(
                            #     f"[Sim Merge Small] {names_raw[j_global]}' (id={ids[j_global]}) -> '{names_raw[i_global]}' (id={ids[i_global]}) "
                            #     f"(sim={float(sims[i_local, j_local]):.3f})")
                            dsu.union(i_global, j_global)
                continue
            
            # ====== 大桶：使用 sklearn.NearestNeighbors ======
            from sklearn.neighbors import NearestNeighbors

            nn = NearestNeighbors(
                n_neighbors=kk,
                metric="cosine",
                algorithm="auto", # 可選 'brute', 'ball_tree', 'kd_tree'
            )

            nn.fit(sub_vecs)
                
            dists, indices = nn.kneighbors(sub_vecs)
                
            for i_local, neighbors in enumerate(indices):
                i_global = sub_idx[i_local]
                for j_local, dist in zip(neighbors, dists[i_local]):
                    if j_local == i_local:
                        continue
                    j_global = sub_idx[j_local]
                    sim = 1.0 - float(dist)
                    if sim >= threshold:
                        # print(f"[Sim Merge Small] '{names_raw[j_global]}' (id={ids[j_global]}) -> {names_raw[j_global]} (id={ids[j_global]}) "
                        #       f"(sim={sim:.3f}")
                        dsu.union(i_global, j_global)
                            
        
        print("[Step 9] 生成輸出 DataFrame...")
        rep = [dsu.find(i) for i in range(n)] 
        
        # === 建立群組 canonical name（用於代表 ID 決策）===
        group_canonical: Dict[int, str] = {}
        for i in range(n):
            r = rep[i]
            if r not in group_canonical:
                group_canonical[r] = names_norm[r]
        
        
        id_map: Dict[Any, Any] = {ids[i]: ids[rep[i]] for i in range(n)}
        # 1) 若 representative_id_map 提供了 group canonical_name 的代表 ID，就用它
        # 2) 否則退回原本的 ids[rep[i]]（群組內第一筆的原 id）
        representative_id_map_norm = None
        if representative_id_map:
            representative_id_map_norm = {normalize_name(k): v for k,v in representative_id_map.items()}
        
        id_map: Dict[Any, Any] = {}
        for i in range(n):
            r = rep[i]
            canon = group_canonical[r]
            if representative_id_map_norm and canon in representative_id_map_norm:
                id_map[ids[i]] = representative_id_map_norm[canon]
            else:
                id_map[ids[i]] = ids[r]
                
        
        # 列出完整 id 對應（只列出有變化者）
        if verbose:
            for old_id, new_id in id_map.items():
                if old_id != new_id:
                    try:
                        idx_old = ids.index(old_id)
                        idx_new = ids.index(new_id)
                        print(f"'{names_raw[idx_old]}' (id={old_id}) -> '{names_raw[idx_new]}' (id={new_id})")
                    except Exception:
                        print(f"{old_id} -> {new_id}")
        
        # 回寫：新增 merge_id 與 canonical_name，並以代表 id 合併
        df_out = df.copy()
        # === CHG: 產出 canonical_name 與（可選）title 欄位 ===
        df_out["canonical_name"] = [alias_map_lookup(x, alias_map) for x in names_raw]
        if title_column_out:
            df_out[title_column_out] = df_out[name_column]
        
        # # === CHG: 覆寫 id 為代表 ID，然後以代表 ID 聚合去重 ===
        # df_out["merge_id"] = df_out[id_column].map(id_map)
        # df_out = df_out.drop(columns=[id_column]).rename(columns={"merge_id":id_column})
        
        # # 準備聚合規則：除了 id 欄位外，一律取第一筆（可依需求自訂）
        # # 先把舊 id 欄刪除，將 merge_id 轉回 id 欄
        # if id_column in df_out.columns and id_column != "merge_id":
        #     df_out = df_out.drop(columns=[id_column])
        # df_out = df_out.rename(columns={'merge_id': id_column})
        
        # # groupby 聚合：除了 id 以外都取「描述最長」那列（用 idxmax）
        # # 先找各 id 的代表列 index
        # idx = (
        #     df_out.groupby(id_column, as_index=False)["_desc_len"].idxmax()["_desc_len"]
        # )        
        # merged_df = df_out.loc[idx].drop(columns=["_desc_len"]).reset_index(drop=True)
        
        df_out["_desc_len"] = df_out["description"].fillna("").astype(str).str.len()
        
        df_out["merge_id"] = df_out[id_column].map(id_map)
        if id_column in df_out.columns:
            df_out = df_out.drop(columns=[id_column])
        df_out = df_out.rename(columns={"merge_id": id_column})
        
        idx = (
            df_out.groupby(id_column, as_index=False)["_desc_len"].idxmax()["_desc_len"]
        )
        
        merged_df = df_out.loc[idx].drop(columns=["_desc_len"]).reset_index(drop=True)
        
        if verbose:
            merged = sum(1 for i in range(n) if rep[i] != i)
            print(f"[semantic_merge_nodes] 合併節點數 : {merged} / {n}，輸出節點: {merged_df.shape[0]}")

        
        # 可選：把 id_map 存起來供後續 relationships 使用
        if "context" in kwargs and kwargs["context"]:
            try:
                setter = kwargs["context"].cache.set
                ret = setter("node_id_map", id_map)
                if hasattr(ret, "__await__"):
                    import asyncio
                    asyncio.get_event_loop().run_until_complete(ret)
                print(f"[semantic_merge_nodes] node_id_map saved, size={len(id_map)}")
            except Exception as e:
                 print(f"[semantic_merge_nodes] cache.set node_id_map failed: {e}")
        
        return merged_df
    
    except Exception as e:
        print("\n[semantic_merge_nodes] 發生錯誤！")
        print(f"錯誤訊息: {e}")
        print("詳細堆疊：")
        import traceback
        traceback.print_exc()
        raise