from __future__ import annotations

import re


WRITE_KEYWORDS = re.compile(
    r"\b(CREATE|MERGE|SET|DELETE|DETACH|REMOVE|DROP|LOAD\s+CSV|CALL|APOC|"
    r"CREATE\s+INDEX|CREATE\s+CONSTRAINT|ALTER|GRANT|DENY|REVOKE|START|INSERT|FINISH)\b",
    re.IGNORECASE,
)


def validate_read_only_cypher(cypher: str) -> None:
    if not cypher.strip():
        raise ValueError("Cypher is empty.")
    if ";" in cypher.strip().rstrip(";"):
        raise ValueError("Cypher contains multiple statements.")
    if WRITE_KEYWORDS.search(cypher):
        raise ValueError(f"Cypher is not read-only:\n{cypher}")
    if not re.match(r"^\s*(MATCH|OPTIONAL\s+MATCH|UNWIND)\b", cypher, re.IGNORECASE):
        raise ValueError("Cypher must start with MATCH, OPTIONAL MATCH, or UNWIND.")
    if not re.search(r"\bRETURN\b", cypher, re.IGNORECASE):
        raise ValueError("Cypher must contain RETURN.")
    if not re.search(r"\bLIMIT\b", cypher, re.IGNORECASE):
        raise ValueError("Cypher must contain LIMIT.")
