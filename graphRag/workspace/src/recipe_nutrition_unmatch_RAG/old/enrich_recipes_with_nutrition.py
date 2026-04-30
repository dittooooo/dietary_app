#!/usr/bin/env python3
"""
Build a lightweight RAG index from nutrition_data.json, then enrich recipes.json
by writing matched nutrition records back into each ingredient as "營養成份".
"""

from __future__ import annotations

import argparse
import json
import math
import re
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Iterable, List, Sequence, Tuple


def normalize_text(text: str) -> str:
    text = (text or "").strip().lower()
    text = re.sub(r"[\s\u3000]+", "", text)
    return text


def split_aliases(text: str) -> List[str]:
    if not text:
        return []
    parts = re.split(r"[，,、/／;；|｜]+", text)
    return [p.strip() for p in parts if p and p.strip()]


def char_ngrams(text: str, n: int) -> Iterable[str]:
    if len(text) < n:
        if text:
            yield text
        return
    for i in range(len(text) - n + 1):
        yield text[i : i + n]


def to_features(query: str) -> Counter:
    """
    Feature design:
    - full-word token (strong)
    - char bigram/trigram (fuzzy)
    """
    q = normalize_text(query)
    tf = Counter()
    if not q:
        return tf

    tf[f"w:{q}"] += 4.0
    for bg in char_ngrams(q, 2):
        tf[f"c2:{bg}"] += 1.0
    for tg in char_ngrams(q, 3):
        tf[f"c3:{tg}"] += 1.2
    return tf


@dataclass
class NutritionDoc:
    doc_id: int
    name: str
    aliases: List[str]
    record: Dict
    exact_keys: List[str]


class SimpleRAG:
    def __init__(self, docs: Sequence[NutritionDoc]):
        self.docs = list(docs)
        self.n_docs = len(self.docs)
        self.idf: Dict[str, float] = {}
        self.postings: Dict[str, List[Tuple[int, float]]] = defaultdict(list)
        self.exact_lookup: Dict[str, List[int]] = defaultdict(list)
        self._build()

    @staticmethod
    def _doc_text(doc: NutritionDoc) -> str:
        base = [doc.name, *doc.aliases]
        return " ".join([b for b in base if b])

    def _build(self) -> None:
        df = Counter()
        doc_term_tfs: List[Counter] = []

        for doc in self.docs:
            tf = to_features(self._doc_text(doc))
            if not tf:
                tf = Counter({"__empty__": 1.0})
            doc_term_tfs.append(tf)
            for t in tf.keys():
                df[t] += 1
            for ek in doc.exact_keys:
                self.exact_lookup[ek].append(doc.doc_id)

        for term, dfi in df.items():
            self.idf[term] = math.log((self.n_docs + 1) / (dfi + 1)) + 1.0

        for doc_id, tf in enumerate(doc_term_tfs):
            weighted = {}
            norm_sq = 0.0
            for term, freq in tf.items():
                w = (1.0 + math.log(freq)) * self.idf.get(term, 1.0)
                weighted[term] = w
                norm_sq += w * w
            norm = math.sqrt(norm_sq) if norm_sq > 0 else 1.0
            for term, w in weighted.items():
                self.postings[term].append((doc_id, w / norm))

    def search(self, query: str, top_k: int = 3) -> List[Tuple[NutritionDoc, float]]:
        q_tf = to_features(query)
        if not q_tf:
            return []

        weighted_q = {}
        norm_sq = 0.0
        for term, freq in q_tf.items():
            idf = self.idf.get(term)
            if idf is None:
                continue
            w = (1.0 + math.log(freq)) * idf
            weighted_q[term] = w
            norm_sq += w * w

        if not weighted_q:
            return []

        q_norm = math.sqrt(norm_sq)
        q_vec = {t: w / q_norm for t, w in weighted_q.items()}

        scores = defaultdict(float)
        for term, q_w in q_vec.items():
            for doc_id, d_w in self.postings.get(term, []):
                scores[doc_id] += q_w * d_w

        qn = normalize_text(query)
        for doc_id in self.exact_lookup.get(qn, []):
            scores[doc_id] += 1.0

        # Containment boost: useful for cases like "雞蛋" vs "雞蛋(白殼)"
        for doc_id in list(scores.keys()):
            doc = self.docs[doc_id]
            candidate_keys = [normalize_text(doc.name), *(normalize_text(a) for a in doc.aliases)]
            candidate_keys = [ck for ck in candidate_keys if ck]
            for ck in candidate_keys:
                if not ck:
                    continue
                if qn and qn in ck:
                    scores[doc_id] += 0.35 * (len(qn) / max(len(ck), 1))
                    break

        ranked = sorted(scores.items(), key=lambda x: x[1], reverse=True)[:top_k]
        return [(self.docs[doc_id], score) for doc_id, score in ranked]

    def save_index(self, path: Path) -> None:
        payload = {
            "meta": {
                "kind": "simple_rag_index",
                "created_at_utc": datetime.now(timezone.utc).isoformat(),
                "documents": self.n_docs,
            },
            "documents": [
                {
                    "doc_id": d.doc_id,
                    "name": d.name,
                    "aliases": d.aliases,
                    "exact_keys": d.exact_keys,
                    "整合編號": d.record.get("整合編號"),
                }
                for d in self.docs
            ],
        }
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def detect_fields(sample_record: Dict) -> Tuple[str, str]:
    name_key = "樣品名稱" if "樣品名稱" in sample_record else ""
    alias_key = "俗名" if "俗名" in sample_record else ""

    if not name_key:
        for k in sample_record.keys():
            if "名稱" in k:
                name_key = k
                break
    if not alias_key:
        for k in sample_record.keys():
            if "俗名" in k or "別名" in k:
                alias_key = k
                break
    if not name_key:
        raise ValueError("找不到 nutrition_data.json 的名稱欄位（例如：樣品名稱）")
    return name_key, alias_key


def build_docs(nutrition_records: Sequence[Dict]) -> List[NutritionDoc]:
    if not nutrition_records:
        return []

    name_key, alias_key = detect_fields(nutrition_records[0])
    docs: List[NutritionDoc] = []

    for i, rec in enumerate(nutrition_records):
        name = str(rec.get(name_key, "")).strip()
        alias_raw = str(rec.get(alias_key, "")).strip() if alias_key else ""
        aliases = split_aliases(alias_raw)

        exact_set = {normalize_text(name)} if name else set()
        exact_set.update(normalize_text(a) for a in aliases if a)
        exact_keys = sorted(k for k in exact_set if k)

        docs.append(
            NutritionDoc(
                doc_id=i,
                name=name,
                aliases=aliases,
                record=rec,
                exact_keys=exact_keys,
            )
        )
    return docs


def nutrient_payload_from_record(rec: Dict) -> Dict:
    base_skip = {"內容物描述"}
    nutrients = {}
    for k, v in rec.items():
        if k in base_skip:
            continue
        if v is None:
            continue
        nutrients[k] = v
    return nutrients


def enrich_recipes(
    recipes: List[Dict],
    rag: SimpleRAG,
    min_score: float = 0.6,
    top_k: int = 2,
) -> Tuple[List[Dict], Dict]:
    total_ings = 0
    matched = 0

    for recipe in recipes:
        ingredients = recipe.get("ingredients", [])
        for ing in ingredients:
            total_ings += 1
            query_name = (ing.get("name") or ing.get("name_raw") or "").strip()
            if not query_name:
                ing["營養成份"] = None
                continue

            results = rag.search(query_name, top_k=top_k)
            if not results:
                ing["營養成份"] = None
                continue

            best_doc, score = results[0]
            second_score = results[1][1] if len(results) > 1 else 0.0
            if score < min_score:
                ing["營養成份"] = None
                continue
            if second_score > 0 and score / second_score < 1.12 and score < 0.9:
                # ambiguous top-1 result
                ing["營養成份"] = None
                continue

            matched += 1
            ing["營養成份"] = {
                "查詢食材": query_name,
                "對應樣品名稱": best_doc.name,
                "相似度": round(float(score), 4),
                "資料": nutrient_payload_from_record(best_doc.record),
            }

    stats = {
        "ingredients_total": total_ings,
        "ingredients_matched": matched,
        "match_rate": round(matched / total_ings, 4) if total_ings else 0.0,
        "min_score": min_score,
    }
    return recipes, stats


def load_json(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def save_json(path: Path, obj: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build RAG index from nutrition_data.json and enrich recipes.json with nutrition data."
    )
    parser.add_argument(
        "--recipes",
        default="workspace/src/test4/data/input/recipes.json",
        help="recipes.json path",
    )
    parser.add_argument(
        "--nutrition",
        default="workspace/src/test4/data/input/nutrition_data.json",
        help="nutrition_data.json path",
    )
    parser.add_argument(
        "--index-out",
        default="workspace/src/test4/data/output/nutrition_rag_index.json",
        help="output path for saved RAG KB metadata",
    )
    parser.add_argument(
        "--output",
        default="workspace/src/test4/data/output/recipes_with_nutrition.json",
        help="output path for enriched recipes",
    )
    parser.add_argument(
        "--stats-out",
        default="workspace/src/test4/data/output/enrich_stats.json",
        help="output path for summary stats",
    )
    parser.add_argument(
        "--min-score",
        type=float,
        default=0.6,
        help="minimum cosine similarity score to accept a match",
    )
    args = parser.parse_args()

    recipes_path = Path(args.recipes)
    nutrition_path = Path(args.nutrition)
    index_path = Path(args.index_out)
    output_path = Path(args.output)
    stats_path = Path(args.stats_out)

    recipes = load_json(recipes_path)
    nutrition_records = load_json(nutrition_path)
    if not isinstance(recipes, list):
        raise ValueError("recipes.json 必須是 list")
    if not isinstance(nutrition_records, list):
        raise ValueError("nutrition_data.json 必須是 list")

    docs = build_docs(nutrition_records)
    rag = SimpleRAG(docs)
    rag.save_index(index_path)

    enriched, stats = enrich_recipes(recipes, rag, min_score=args.min_score, top_k=1)
    save_json(output_path, enriched)
    save_json(stats_path, stats)

    print(f"[OK] Nutrition docs: {len(docs)}")
    print(f"[OK] RAG KB saved: {index_path}")
    print(f"[OK] Enriched recipes saved: {output_path}")
    print(f"[OK] Stats saved: {stats_path}")
    print(f"[STATS] matched {stats['ingredients_matched']}/{stats['ingredients_total']} ({stats['match_rate']:.2%})")


if __name__ == "__main__":
    main()
