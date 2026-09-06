from __future__ import annotations

import re
import unicodedata
from collections import Counter
from typing import Any, Dict, List, Optional

from rank_bm25 import BM25Okapi

from .config import (
    DISH_BM25_TOP_K,
    DISH_MATCH_MIN_MARGIN,
    DISH_MATCH_THRESHOLD,
)


# 負責把使用者輸入的料理名稱，對齊 Neo4j 中最接近的 Dish 或 FoodItem。
class DishMatcher:
    # 建立配對器，並在 nutritionist agent 啟動時建立一次 BM25 index。
    def __init__(
        self,
        driver: Any,
        *,
        threshold: int = DISH_MATCH_THRESHOLD,
        bm25_top_k: int = DISH_BM25_TOP_K,
        min_margin: int = DISH_MATCH_MIN_MARGIN,
    ) -> None:
        self.driver = driver
        self.threshold = max(0, min(99, threshold))
        self.bm25_top_k = max(1, bm25_top_k)
        self.min_margin = max(0, min_margin)
        self._node_rows: List[Dict[str, Any]] = []
        self._exact_index: Dict[str, List[Dict[str, Any]]] = {}
        self._tokenized_names: List[List[str]] = []
        self._bm25: Optional[BM25Okapi] = None
        self.refresh_bm25_index()

    # 從目前 Neo4j 圖譜重新建立名稱語料庫與 BM25 index。
    # KG 更新後可呼叫此 method，不需要重建 DishMatcher 物件。
    def refresh_bm25_index(self) -> int:
        query = """
        MATCH (n)
        WHERE n:Dish OR n:FoodItem
        RETURN
          CASE WHEN n:Dish THEN "dish" ELSE "food_item" END AS match_type,
          n.name AS name,
          n.recipe_id AS recipe_id,
          n.food_id AS food_id
        ORDER BY match_type, name
        """
        with self.driver.session() as session:
            rows = [dict(row) for row in session.run(query)]

        self._node_rows = [
            row
            for row in rows
            if normalize_name(str(row.get("name") or ""))
        ]
        self._exact_index = {}
        self._tokenized_names = []

        for row in self._node_rows:
            normalized = normalize_name(str(row["name"]))
            self._exact_index.setdefault(normalized, []).append(row)
            self._tokenized_names.append(tokenize_name(normalized))

        self._bm25 = BM25Okapi(self._tokenized_names) if self._tokenized_names else None
        return len(self._node_rows)

    # 對每個候選料理執行 Exact -> BM25 -> bounded score，最後決定 match/no_match。
    def match_dishes(self, candidates: List[str]) -> List[Dict[str, Any]]:
        cleaned_candidates: List[str] = []
        seen: set[str] = set()
        for candidate in candidates:
            raw_candidate = str(candidate or "").strip()
            normalized_candidate = normalize_name(raw_candidate)
            if normalized_candidate and normalized_candidate not in seen:
                cleaned_candidates.append(raw_candidate)
                seen.add(normalized_candidate)

        if not cleaned_candidates:
            return []

        return [self._match_one(candidate) for candidate in cleaned_candidates]

    def _match_one(self, candidate: str) -> Dict[str, Any]:
        normalized_candidate = normalize_name(candidate)
        exact_rows = self._exact_index.get(normalized_candidate, [])
        if exact_rows:
            exact_row = self._select_exact_row(exact_rows)
            return self._build_match_result(
                candidate,
                exact_row,
                match_score=100,
                bm25_score=None,
                reason="exact normalized match",
                status="match",
            )

        if self._bm25 is None:
            return self._build_no_match_result(candidate, "BM25 index is empty")

        query_tokens = tokenize_name(normalized_candidate)
        if not query_tokens:
            return self._build_no_match_result(candidate, "empty query tokens")

        scores = self._bm25.get_scores(query_tokens)
        ranked_indexes = sorted(
            range(len(scores)),
            key=lambda index: (-float(scores[index]), str(self._node_rows[index].get("name") or "")),
        )
        ranked_candidates = [
            {
                "row": self._node_rows[index],
                "bm25_score": float(scores[index]),
                "tokens": self._tokenized_names[index],
            }
            for index in ranked_indexes
            if float(scores[index]) > 0
        ][: self.bm25_top_k]

        if not ranked_candidates:
            return self._build_no_match_result(candidate, "no positive BM25 result")

        for item in ranked_candidates:
            item["match_score"] = lexical_match_score(query_tokens, item["tokens"])

        ranked_candidates.sort(
            key=lambda item: (
                -int(item["match_score"]),
                -float(item["bm25_score"]),
                str(item["row"].get("name") or ""),
            )
        )
        best = ranked_candidates[0]
        second = ranked_candidates[1] if len(ranked_candidates) > 1 else None
        best_score = int(best["match_score"])

        if best_score < self.threshold:
            return self._build_no_match_result(
                candidate,
                f"BM25 lexical score {best_score} is below threshold {self.threshold}",
                bm25_score=float(best["bm25_score"]),
            )

        if second is not None:
            score_margin = best_score - int(second["match_score"])
            if score_margin < self.min_margin:
                return self._build_no_match_result(
                    candidate,
                    f"ambiguous BM25 candidates; score margin {score_margin} is below {self.min_margin}",
                    bm25_score=float(best["bm25_score"]),
                )

        return self._build_match_result(
            candidate,
            best["row"],
            match_score=best_score,
            bm25_score=float(best["bm25_score"]),
            reason="BM25 lexical match",
            status="match",
        )

    @staticmethod
    def _select_exact_row(rows: List[Dict[str, Any]]) -> Dict[str, Any]:
        # Dish 是料理查詢的主要節點；只有沒有 Dish exact match 時才使用 FoodItem。
        return next(
            (row for row in rows if row.get("match_type") == "dish"),
            rows[0],
        )

    @staticmethod
    def _build_match_result(
        candidate: str,
        row: Dict[str, Any],
        *,
        match_score: int,
        bm25_score: Optional[float],
        reason: str,
        status: str,
    ) -> Dict[str, Any]:
        match_type = row.get("match_type")
        is_dish = match_type == "dish"
        strategy = "dish_match" if is_dish else "fooditem_fallback"
        return {
            "input_name": candidate,
            "raw_input_name": candidate,
            "matched_query_name": row.get("name"),
            "matched_dish_name": row.get("name") if is_dish else None,
            "matched_food_id": row.get("food_id") if not is_dish else None,
            "matched_food_name": row.get("name") if not is_dish else None,
            "match_score": max(0, min(100, int(match_score))),
            "bm25_score": bm25_score,
            "match_status": status,
            "match_reason": reason,
            "retrieval_strategy": strategy,
        }

    @staticmethod
    def _build_no_match_result(
        candidate: str,
        reason: str,
        *,
        bm25_score: Optional[float] = None,
    ) -> Dict[str, Any]:
        # 保留 ingredient_fallback，讓既有 NutritionAgent 流程能安全處理 no_match。
        return {
            "input_name": candidate,
            "raw_input_name": candidate,
            "matched_query_name": candidate,
            "matched_dish_name": None,
            "matched_food_id": None,
            "matched_food_name": None,
            "match_score": 0,
            "bm25_score": bm25_score,
            "match_status": "no_match",
            "match_reason": reason,
            "retrieval_strategy": "ingredient_fallback",
        }


def normalize_name(value: str) -> str:
    # 只做通用 Unicode 與空白正規化，不加入料理別名或領域詞彙替換。
    normalized = unicodedata.normalize("NFKC", value or "")
    return re.sub(r"\s+", "", normalized).strip()


def tokenize_name(value: str) -> List[str]:
    # 中文料理名稱沒有空白斷詞時，使用二字字元 n-gram 保留關鍵字匹配能力。
    normalized = normalize_name(value)
    if not normalized:
        return []
    if len(normalized) == 1:
        return [normalized]
    return [normalized[index : index + 2] for index in range(len(normalized) - 1)]


def lexical_match_score(query_tokens: List[str], document_tokens: List[str]) -> int:
    """將非 exact 的 token overlap 轉成 0-99 分，100 只保留給 exact match。"""
    query_counts = Counter(query_tokens)
    document_counts = Counter(document_tokens)
    overlap = sum((query_counts & document_counts).values())
    if overlap == 0:
        return 0

    precision = overlap / sum(document_counts.values())
    recall = overlap / sum(query_counts.values())
    f1 = 2 * precision * recall / (precision + recall)
    return max(0, min(99, round(f1 * 99)))
