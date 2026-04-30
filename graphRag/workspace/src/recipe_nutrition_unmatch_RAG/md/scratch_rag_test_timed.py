import time
start_time = time.time()

print(f"[{time.time()-start_time:.2f}s] Importing libraries...")
import chromadb
from sentence_transformers import SentenceTransformer
import os
import json

CHROMA_DB_DIR = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_RAG\chroma_db"
EMBEDDING_MODEL_NAME = "paraphrase-multilingual-MiniLM-L12-v2"
COLLECTION_NAME = "nutrition_collection"

print(f"[{time.time()-start_time:.2f}s] Loading embedding model...")
embedder = SentenceTransformer(EMBEDDING_MODEL_NAME)

print(f"[{time.time()-start_time:.2f}s] Loading chromadb...")
client = chromadb.PersistentClient(path=CHROMA_DB_DIR)
collection = client.get_collection(name=COLLECTION_NAME)

queries = ["披薩起士絲", "蕃茄糊", "蒜蓉", "牛奶", "雞蛋", "泡打粉", "高筋麵粉"]
k = 15

results_dict = {}

print(f"[{time.time()-start_time:.2f}s] Starting queries...")
for query in queries:
    loop_start = time.time()
    print(f"  [{time.time()-start_time:.2f}s] Processing query: {query}")
    query_embedding = embedder.encode([query]).tolist()
    print(f"    [{time.time()-start_time:.2f}s] Encoded (took {time.time()-loop_start:.2f}s)")
    
    query_start = time.time()
    results = collection.query(
        query_embeddings=query_embedding,
        n_results=k
    )
    print(f"    [{time.time()-start_time:.2f}s] Queried ChromaDB (took {time.time()-query_start:.2f}s)")
    
    candidates = []
    if results and results["documents"] and results["documents"][0]:
        for i in range(len(results["documents"][0])):
            candidates.append({
                "text": results["documents"][0][i],
                "name": results["metadatas"][0][i].get("樣品名稱", ""),
                "distance": results["distances"][0][i]
            })
    results_dict[query] = candidates

output_path = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_RAG\data\output\scratch_rag_test_timed.json"
with open(output_path, "w", encoding="utf-8") as f:
    json.dump(results_dict, f, ensure_ascii=False, indent=2)

print(f"[{time.time()-start_time:.2f}s] Done! Output saved to {output_path}")
