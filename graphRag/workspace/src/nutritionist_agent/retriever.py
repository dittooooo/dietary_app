from __future__ import annotations

from typing import Any, Dict, List

from neo4j import GraphDatabase
from neo4j.graph import Node, Path as Neo4jPath, Relationship

from .cypher_guard import validate_read_only_cypher


# 封裝 Neo4j driver，負責執行受安全檢查保護的查詢並整理回傳值。
class GraphRetriever:
    # 建立 Neo4j driver，供整個 NutritionAgent 重複使用。
    def __init__(self, uri: str, user: str, password: str) -> None:
        self.driver = GraphDatabase.driver(uri, auth=(user, password))

    # 關閉 Neo4j driver 連線。
    def close(self) -> None:
        self.driver.close()

    # 執行 read-only Cypher，並把 Neo4j 型別轉成一般 Python dict/list。
    def retrieve(self, cypher: str) -> List[Dict[str, Any]]:
        validate_read_only_cypher(cypher)
        with self.driver.session() as session:
            result = session.run(cypher)
            return [{key: self.to_plain_value(value) for key, value in record.data().items()} for record in result]

    # 遞迴轉換 Neo4j Node、Relationship、Path，讓結果可 JSON 序列化。
    @classmethod
    def to_plain_value(cls, value: Any) -> Any:
        if isinstance(value, Node):
            return {"labels": sorted(value.labels), "properties": dict(value.items())}
        if isinstance(value, Relationship):
            return {"type": value.type, "properties": dict(value.items())}
        if isinstance(value, Neo4jPath):
            return {
                "nodes": [cls.to_plain_value(node) for node in value.nodes],
                "relationships": [cls.to_plain_value(rel) for rel in value.relationships],
            }
        if isinstance(value, list):
            return [cls.to_plain_value(item) for item in value]
        if isinstance(value, dict):
            return {key: cls.to_plain_value(item) for key, item in value.items()}
        return value

