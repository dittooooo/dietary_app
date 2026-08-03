import json
import os
from typing import Dict, List
from dotenv import load_dotenv
import chromadb
from sentence_transformers import SentenceTransformer
from tqdm import tqdm

load_dotenv()

NUTRITION_DATA_PATH = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_RAG\data\input\2_nutrition_data_categorized_20260422_170816.json"
CHROMA_DB_DIR = os.getenv("CHROMA_DB_DIR", "chroma_db")
EMBEDDING_MODEL_NAME = os.getenv("EMBEDDING_MODEL_NAME", "paraphrase-multilingual-MiniLM-L12-v2")
COLLECTION_NAME = "nutrition_collection"

def load_categorized_data(filepath: str) -> List[Dict]:
    with open(filepath, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    # Extract records from categorized structure
    records = []
    if isinstance(data, dict):
        for category, items in data.items():
            for item in items:
                records.append(item)
    elif isinstance(data, list):
        records = data
    return records

def format_nutrition_text(record: Dict) -> str:
    category = record.get("食品分類", "未知分類")
    name = record.get("樣品名稱", "")
    aliases = record.get("俗名", "")
    
    text = f"{category} {name}"
    if aliases:
        text += f"，俗名：{aliases}"
    return text

def main():
    print("🚀 啟動 RAG 向量資料庫建置程式...")
    
    # 1. 載入資料
    print(f"📂 正在載入資料：{NUTRITION_DATA_PATH}")
    if not os.path.exists(NUTRITION_DATA_PATH):
        print(f"❌ 找不到資料檔: {NUTRITION_DATA_PATH}")
        return

    records = load_categorized_data(NUTRITION_DATA_PATH)
    print(f"✅ 成功載入 {len(records)} 筆營養成份資料")

    # 2. 準備文件與 Metadata
    documents = []
    metadatas = []
    ids = []
    
    for idx, record in enumerate(records):
        doc_text = format_nutrition_text(record)
        documents.append(doc_text)
        
        # 提取需要保留的 meta 資訊
        meta = {
            "整合編號": str(record.get("整合編號", "")),
            "食品分類": str(record.get("食品分類", "")),
            "樣品名稱": str(record.get("樣品名稱", "")),
            "俗名": str(record.get("俗名", ""))
        }
        # ChromaDB metadata value cannot be None or complex dict, must be str, int, float, bool
        metadatas.append(meta)
        ids.append(f"doc_{idx}")

    # 3. 初始化 Embedding 模型
    print(f"🧠 載入 Embedding 模型 ({EMBEDDING_MODEL_NAME})... 這可能需要一點時間下載")
    embedder = SentenceTransformer(EMBEDDING_MODEL_NAME)

    # 4. 初始化 ChromaDB
    print(f"💾 建立或連接本地端 ChromaDB ({CHROMA_DB_DIR})...")
    # 確保資料夾存在
    os.makedirs(CHROMA_DB_DIR, exist_ok=True)
    
    chroma_client = chromadb.PersistentClient(path=CHROMA_DB_DIR)
    
    # 如果已存在則先刪除再重建，確保資料是最新的
    try:
        chroma_client.delete_collection(name=COLLECTION_NAME)
        print(f"🗑️ 已刪除舊的 Collection: {COLLECTION_NAME}")
    except ValueError:
        pass # collection doesn't exist
        
    collection = chroma_client.create_collection(
        name=COLLECTION_NAME,
        metadata={"hnsw:space": "cosine"} # 使用餘弦相似度
    )

    # 5. 批次處理並存入向量資料庫 (避免一次丟太多導致記憶體問題)
    batch_size = 200
    print("⏳ 開始將文本轉換為向量並存入 ChromaDB...")
    
    for i in tqdm(range(0, len(documents), batch_size), desc="處理批次"):
        batch_docs = documents[i:i+batch_size]
        batch_metas = metadatas[i:i+batch_size]
        batch_ids = ids[i:i+batch_size]
        
        # 使用 SentenceTransformer 生成 embeddings
        embeddings = embedder.encode(batch_docs, show_progress_bar=False)
        
        collection.add(
            embeddings=embeddings.tolist(),
            documents=batch_docs,
            metadatas=batch_metas,
            ids=batch_ids
        )

    print("\n🎉 向量資料庫建置完成！可以開始進行 RAG 查詢了。")

if __name__ == "__main__":
    main()
