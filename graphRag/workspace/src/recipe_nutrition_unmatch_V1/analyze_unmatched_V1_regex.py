#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
analyze_unmatched.py

用途：
1. 讀取 recipes.json 與 nutrition_data.json
2. 用 baseline matcher 先做一輪食材名稱比對
3. 將 unmatched 食材做統計分析
4. 輸出多份 CSV 報表，協助後續建立 normalization / matcher 規則

輸入：
- recipes.json
- nutrition_data.json

輸出（預設在 ./output_unmatched_analysis/）：
- match_results.csv
- unmatched_unique.csv
- unmatched_token_stats.csv
- unmatched_prefix_stats.csv
- unmatched_suffix_stats.csv
- unmatched_candidates.csv

執行範例：
python analyze_unmatched.py \
    --recipes recipes.json \
    --nutrition nutrition_data.json \
    --output-dir output_unmatched_analysis

設計原則：
- 先分析，不急著硬配
- 保留 explainability
- 方便後續接到 V5.2 / V5.3 / V5.4 matcher pipeline

python analyze_unmatched.py --recipes workspace/src/recipe_nutrition_unmatch/data/input/recipes.json  --nutrition workspace/src/recipe_nutrition_unmatch/data/input/nutrition_data.json --output-dir workspace/src/recipe_nutrition_unmatch/data/output
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple


# =========================
# 資料結構
# =========================

@dataclass
class RecipeIngredient:
    recipe_id: str
    recipe_name: str
    ingredient_name_raw: str
    ingredient_name: str
    amount_raw: Optional[str]
    amount_value: Optional[float]
    amount_unit: Optional[str]
    amount_note: Optional[str]


@dataclass
class NutritionItem:
    food_id: str
    food_category: Optional[str]
    sample_name: str
    aliases: List[str]
    description: str
    raw: dict


@dataclass
class MatchResult:
    recipe_id: str
    recipe_name: str
    ingredient_name_raw: str
    ingredient_name: str
    normalized_name: str
    match_status: str                 # matched / unmatched
    match_method: str                 # exact_sample / exact_alias / normalized_sample / normalized_alias / none
    matched_food_id: Optional[str]
    matched_sample_name: Optional[str]
    matched_alias: Optional[str]
    confidence: float


@dataclass
class CandidateRow:
    recipe_id: str
    recipe_name: str
    ingredient_name_raw: str
    ingredient_name: str
    normalized_name: str
    candidate_rank: int
    candidate_food_id: str
    candidate_sample_name: str
    candidate_alias_hit: str
    candidate_score: float
    score_detail: str


# =========================
# 基本工具
# =========================

def load_json(path: Path):
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def safe_str(value) -> str:
    if value is None:
        return ""
    return str(value).strip()


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def write_csv(path: Path, rows: Iterable[dict], fieldnames: List[str]) -> None:
    with path.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


# =========================
# 字串正規化
# =========================

FULLWIDTH_MAP = str.maketrans({
    "（": "(",
    "）": ")",
    "，": ",",
    "：": ":",
    "；": ";",
    "　": " ",
    "／": "/",
    "～": "~",
    "–": "-",
    "—": "-",
})

BRAND_PREFIXES = [
    "全聯", "好市多", "costco", "家樂福", "大潤發", "頂好", "全家", "7-11", "統一", "義美", "金蘭"
]

NOISE_PATTERNS = [
    r"^\s+|\s+$",
    r"\(.*?\)",
    r"（.*?）",
]

# 高價值同義／回歸基底名稱
SYNONYM_MAP = {
    "蕃茄": "番茄",
    "蒜蓉": "蒜頭",
    "蒜末": "蒜頭",
    "蒜": "蒜頭",
    "大蒜": "蒜頭",
    "蔥花": "青蔥",
    "洋蔥丁": "洋蔥",
    "薑片": "薑",
    "老薑": "薑",
    "黑胡椒": "黑胡椒粉",
    "白胡椒": "白胡椒粉",
    "味增": "味噌",
    "味增醬": "味噌",
    "味噌醬": "味噌",
    "開水": "水",
    "清水": "水",
    "米酒水": "米酒",
    "食用油": "油",
    "植物油": "油",
    "水煮蛋": "雞蛋",
    "雞小腿": "雞腿",
    "鱸魚片": "鱸魚",
    "豬後腿肉塊": "豬後腿肉",
    "融化無鹽奶油": "無鹽奶油",
    "熟麵粉": "麵粉",
    "關廟麵條": "關廟麵",
    "玉米罐頭": "玉米",
    "冷凍薯餅": "薯餅",
    "紫色洋蔥": "洋蔥",
}

# 若名稱開頭有品牌詞，嘗試去除
BRAND_PREFIX_PATTERN = re.compile(r"^(全聯|好市多|costco|家樂福|大潤發|頂好|全家|7-11|統一|義美|金蘭)[^\u4e00-\u9fffA-Za-z0-9]*")


def basic_normalize(text: str) -> str:
    s = safe_str(text).translate(FULLWIDTH_MAP).lower()
    for p in NOISE_PATTERNS:
        s = re.sub(p, "", s)
    s = re.sub(r"\s+", "", s)
    return s


def strip_brand_prefix(text: str) -> str:
    s = text
    for prefix in BRAND_PREFIXES:
        if s.startswith(prefix) and len(s) > len(prefix):
            return s[len(prefix):]
    s2 = BRAND_PREFIX_PATTERN.sub("", s)
    return s2 if s2 else s


def strip_common_suffixes(text: str) -> str:
    """
    輕量規則，避免過度 aggressive。
    不直接亂砍核心詞，只處理高頻噪音。
    """
    s = text

    replacements = [
        ("粒", ""),
        ("丁", ""),
    ]

    for old, new in replacements:
        if s.endswith(old) and len(s) > len(old) + 1:
            s = s[:-len(old)] + new

    return s


def normalize_food_name(text: str) -> str:
    """
    分成多步做，保持可解釋性
    """
    s = safe_str(text)
    s = s.translate(FULLWIDTH_MAP)
    s = re.sub(r"\(.*?\)|（.*?）", "", s)
    s = s.strip()

    s = strip_brand_prefix(s)

    # 同義詞先做一次
    if s in SYNONYM_MAP:
        s = SYNONYM_MAP[s]

    s = strip_common_suffixes(s)

    # 再做一次同義詞映射
    if s in SYNONYM_MAP:
        s = SYNONYM_MAP[s]

    s = re.sub(r"\s+", "", s)
    return s


# =========================
# Token / 前後綴切分
# =========================

def generate_char_tokens(text: str, min_n: int = 1, max_n: int = 2) -> List[str]:
    """
    中文沒有空格，這裡用字元 n-gram 當作簡化 token。
    """
    s = safe_str(text)
    tokens = []
    for n in range(min_n, max_n + 1):
        for i in range(len(s) - n + 1):
            tokens.append(s[i:i+n])
    return tokens


def prefix_of(text: str, n: int = 2) -> str:
    s = safe_str(text)
    return s[:n] if len(s) >= n else s


def suffix_of(text: str, n: int = 2) -> str:
    s = safe_str(text)
    return s[-n:] if len(s) >= n else s


# =========================
# 相似度
# =========================

def char_bigram_set(text: str) -> set:
    s = safe_str(text)
    if not s:
        return set()
    if len(s) == 1:
        return {s}
    return {s[i:i+2] for i in range(len(s) - 1)}


def jaccard_similarity(a: str, b: str) -> float:
    sa = char_bigram_set(a)
    sb = char_bigram_set(b)
    if not sa and not sb:
        return 1.0
    if not sa or not sb:
        return 0.0
    inter = len(sa & sb)
    union = len(sa | sb)
    return inter / union if union else 0.0


def overlap_score(a: str, b: str) -> float:
    """
    字元集合 overlap，輔助 score。
    """
    sa = set(a)
    sb = set(b)
    if not sa or not sb:
        return 0.0
    inter = len(sa & sb)
    return inter / max(len(sa), len(sb))


# =========================
# Nutrition 索引
# =========================

def parse_aliases(alias_text: str) -> List[str]:
    raw = safe_str(alias_text)
    if not raw:
        return []
    parts = re.split(r"[;,，、/]+", raw)
    aliases = [p.strip() for p in parts if p.strip()]
    return aliases


def build_nutrition_items(nutrition_json: list) -> List[NutritionItem]:
    items: List[NutritionItem] = []
    for row in nutrition_json:
        food_id = safe_str(row.get("整合編號"))
        category = safe_str(row.get("食品分類"))
        sample_name = safe_str(row.get("樣品名稱"))
        aliases = parse_aliases(row.get("俗名"))
        desc = safe_str(row.get("內容物描述"))

        if not sample_name:
            continue

        items.append(
            NutritionItem(
                food_id=food_id,
                food_category=category,
                sample_name=sample_name,
                aliases=aliases,
                description=desc,
                raw=row,
            )
        )
    return items


class NutritionIndex:
    def __init__(self, items: List[NutritionItem]):
        self.items = items

        self.by_sample_exact: Dict[str, List[NutritionItem]] = defaultdict(list)
        self.by_alias_exact: Dict[str, List[Tuple[NutritionItem, str]]] = defaultdict(list)
        self.by_sample_normalized: Dict[str, List[NutritionItem]] = defaultdict(list)
        self.by_alias_normalized: Dict[str, List[Tuple[NutritionItem, str]]] = defaultdict(list)

        for item in items:
            sample = item.sample_name
            self.by_sample_exact[sample].append(item)

            norm_sample = normalize_food_name(sample)
            self.by_sample_normalized[norm_sample].append(item)

            for alias in item.aliases:
                self.by_alias_exact[alias].append((item, alias))
                norm_alias = normalize_food_name(alias)
                self.by_alias_normalized[norm_alias].append((item, alias))

    def match(self, ingredient_name: str) -> Tuple[Optional[NutritionItem], Optional[str], str, float]:
        """
        回傳：
        (item, matched_alias, match_method, confidence)
        """
        raw = safe_str(ingredient_name)
        norm = normalize_food_name(raw)

        # 1) exact sample
        exact_samples = self.by_sample_exact.get(raw, [])
        if exact_samples:
            return exact_samples[0], None, "exact_sample", 1.00

        # 2) exact alias
        exact_aliases = self.by_alias_exact.get(raw, [])
        if exact_aliases:
            item, alias = exact_aliases[0]
            return item, alias, "exact_alias", 0.98

        # 3) normalized sample
        norm_samples = self.by_sample_normalized.get(norm, [])
        if norm_samples:
            return norm_samples[0], None, "normalized_sample", 0.93

        # 4) normalized alias
        norm_aliases = self.by_alias_normalized.get(norm, [])
        if norm_aliases:
            item, alias = norm_aliases[0]
            return item, alias, "normalized_alias", 0.90

        return None, None, "none", 0.0

    def generate_candidates(self, ingredient_name: str, top_k: int = 10) -> List[Tuple[NutritionItem, str, float, str]]:
        """
        回傳 candidate list:
        [(item, alias_hit, score, detail), ...]
        """
        raw = safe_str(ingredient_name)
        norm = normalize_food_name(raw)

        scored = []

        for item in self.items:
            best_alias = ""
            best_score = 0.0
            detail_parts = []

            sample = item.sample_name
            norm_sample = normalize_food_name(sample)

            # sample exact / normalized
            if raw == sample:
                score = 1.00
                scored.append((item, "", score, "sample_exact"))
                continue

            if norm == norm_sample:
                score = 0.93
                scored.append((item, "", score, "sample_normalized"))
                continue

            # similarity on sample
            jac_sample = jaccard_similarity(norm, norm_sample)
            ov_sample = overlap_score(norm, norm_sample)
            score_sample = jac_sample * 0.65 + ov_sample * 0.35
            detail_parts.append(f"sample(jac={jac_sample:.3f},ov={ov_sample:.3f})")

            # alias similarity
            alias_best_score = 0.0
            alias_best_name = ""
            for alias in item.aliases:
                norm_alias = normalize_food_name(alias)
                if raw == alias:
                    alias_best_score = 0.98
                    alias_best_name = alias
                    break
                if norm == norm_alias:
                    alias_best_score = max(alias_best_score, 0.90)
                    alias_best_name = alias
                    continue

                jac_alias = jaccard_similarity(norm, norm_alias)
                ov_alias = overlap_score(norm, norm_alias)
                score_alias = jac_alias * 0.65 + ov_alias * 0.35
                if score_alias > alias_best_score:
                    alias_best_score = score_alias
                    alias_best_name = alias

            # description hint
            desc_score = 0.0
            desc = safe_str(item.description)
            if desc and raw in desc:
                desc_score = 0.15
            elif desc and norm and norm in normalize_food_name(desc):
                desc_score = 0.10

            final_score = max(score_sample, alias_best_score) + desc_score
            final_score = min(final_score, 0.99)

            if alias_best_score > score_sample:
                best_alias = alias_best_name

            if final_score > 0:
                detail_parts.append(f"alias={alias_best_name or '-'}")
                detail_parts.append(f"desc_bonus={desc_score:.2f}")
                scored.append((item, best_alias, final_score, "; ".join(detail_parts)))

        scored.sort(key=lambda x: x[2], reverse=True)
        return scored[:top_k]


# =========================
# 解析 recipes
# =========================

def load_recipe_ingredients(recipes_json: list) -> List[RecipeIngredient]:
    rows: List[RecipeIngredient] = []

    for recipe in recipes_json:
        recipe_id = safe_str(recipe.get("recipe_id"))
        recipe_name = safe_str(recipe.get("name"))
        ingredients = recipe.get("ingredients", [])

        for ing in ingredients:
            rows.append(
                RecipeIngredient(
                    recipe_id=recipe_id,
                    recipe_name=recipe_name,
                    ingredient_name_raw=safe_str(ing.get("name_raw")),
                    ingredient_name=safe_str(ing.get("name")),
                    amount_raw=ing.get("amount_raw"),
                    amount_value=ing.get("amount_value"),
                    amount_unit=ing.get("amount_unit"),
                    amount_note=ing.get("amount_note"),
                )
            )

    return rows


# =========================
# 主流程
# =========================

def run_analysis(
    recipes_path: Path,
    nutrition_path: Path,
    output_dir: Path,
    top_k_candidates: int = 10,
) -> None:
    ensure_dir(output_dir)

    print(f"[INFO] Loading recipes from: {recipes_path}")
    recipes_json = load_json(recipes_path)

    print(f"[INFO] Loading nutrition data from: {nutrition_path}")
    nutrition_json = load_json(nutrition_path)

    recipe_ingredients = load_recipe_ingredients(recipes_json)
    nutrition_items = build_nutrition_items(nutrition_json)
    nutrition_index = NutritionIndex(nutrition_items)

    print(f"[INFO] Loaded {len(recipe_ingredients)} recipe ingredients")
    print(f"[INFO] Loaded {len(nutrition_items)} nutrition items")

    match_results: List[MatchResult] = []
    unmatched_rows: List[RecipeIngredient] = []
    candidate_rows: List[CandidateRow] = []

    for ing in recipe_ingredients:
        query_name = ing.ingredient_name or ing.ingredient_name_raw
        normalized_name = normalize_food_name(query_name)

        matched_item, matched_alias, method, confidence = nutrition_index.match(query_name)

        if matched_item:
            match_results.append(
                MatchResult(
                    recipe_id=ing.recipe_id,
                    recipe_name=ing.recipe_name,
                    ingredient_name_raw=ing.ingredient_name_raw,
                    ingredient_name=ing.ingredient_name,
                    normalized_name=normalized_name,
                    match_status="matched",
                    match_method=method,
                    matched_food_id=matched_item.food_id,
                    matched_sample_name=matched_item.sample_name,
                    matched_alias=matched_alias,
                    confidence=confidence,
                )
            )
        else:
            match_results.append(
                MatchResult(
                    recipe_id=ing.recipe_id,
                    recipe_name=ing.recipe_name,
                    ingredient_name_raw=ing.ingredient_name_raw,
                    ingredient_name=ing.ingredient_name,
                    normalized_name=normalized_name,
                    match_status="unmatched",
                    match_method="none",
                    matched_food_id=None,
                    matched_sample_name=None,
                    matched_alias=None,
                    confidence=0.0,
                )
            )
            unmatched_rows.append(ing)

            candidates = nutrition_index.generate_candidates(query_name, top_k=top_k_candidates)
            for rank, (item, alias_hit, score, detail) in enumerate(candidates, start=1):
                candidate_rows.append(
                    CandidateRow(
                        recipe_id=ing.recipe_id,
                        recipe_name=ing.recipe_name,
                        ingredient_name_raw=ing.ingredient_name_raw,
                        ingredient_name=ing.ingredient_name,
                        normalized_name=normalized_name,
                        candidate_rank=rank,
                        candidate_food_id=item.food_id,
                        candidate_sample_name=item.sample_name,
                        candidate_alias_hit=alias_hit,
                        candidate_score=round(score, 4),
                        score_detail=detail,
                    )
                )

    # 輸出 match_results.csv
    match_results_csv = output_dir / "match_results.csv"
    write_csv(
        match_results_csv,
        [asdict(r) for r in match_results],
        fieldnames=list(MatchResult.__dataclass_fields__.keys()),
    )

    # unmatched unique 統計
    unmatched_counter = Counter()
    unmatched_raw_examples: Dict[str, Counter] = defaultdict(Counter)
    unmatched_recipe_examples: Dict[str, Counter] = defaultdict(Counter)

    token_counter = Counter()
    prefix_counter = Counter()
    suffix_counter = Counter()

    for ing in unmatched_rows:
        name = ing.ingredient_name or ing.ingredient_name_raw
        unmatched_counter[name] += 1
        unmatched_raw_examples[name][ing.ingredient_name_raw] += 1
        unmatched_recipe_examples[name][ing.recipe_name] += 1

        norm = normalize_food_name(name)
        tokens = generate_char_tokens(norm, min_n=1, max_n=2)
        token_counter.update(tokens)
        prefix_counter[prefix_of(norm, 2)] += 1
        suffix_counter[suffix_of(norm, 2)] += 1

    unmatched_unique_rows = []
    for name, freq in unmatched_counter.most_common():
        unmatched_unique_rows.append({
            "ingredient_name": name,
            "normalized_name": normalize_food_name(name),
            "frequency": freq,
            "top_name_raw_examples": " | ".join(
                [f"{k}({v})" for k, v in unmatched_raw_examples[name].most_common(5)]
            ),
            "top_recipe_examples": " | ".join(
                [f"{k}({v})" for k, v in unmatched_recipe_examples[name].most_common(5)]
            ),
        })

    unmatched_unique_csv = output_dir / "unmatched_unique.csv"
    write_csv(
        unmatched_unique_csv,
        unmatched_unique_rows,
        fieldnames=[
            "ingredient_name",
            "normalized_name",
            "frequency",
            "top_name_raw_examples",
            "top_recipe_examples",
        ],
    )

    unmatched_token_csv = output_dir / "unmatched_token_stats.csv"
    write_csv(
        unmatched_token_csv,
        [{"token": k, "frequency": v} for k, v in token_counter.most_common()],
        fieldnames=["token", "frequency"],
    )

    unmatched_prefix_csv = output_dir / "unmatched_prefix_stats.csv"
    write_csv(
        unmatched_prefix_csv,
        [{"prefix": k, "frequency": v} for k, v in prefix_counter.most_common()],
        fieldnames=["prefix", "frequency"],
    )

    unmatched_suffix_csv = output_dir / "unmatched_suffix_stats.csv"
    write_csv(
        unmatched_suffix_csv,
        [{"suffix": k, "frequency": v} for k, v in suffix_counter.most_common()],
        fieldnames=["suffix", "frequency"],
    )

    unmatched_candidates_csv = output_dir / "unmatched_candidates.csv"
    write_csv(
        unmatched_candidates_csv,
        [asdict(r) for r in candidate_rows],
        fieldnames=list(CandidateRow.__dataclass_fields__.keys()),
    )

    # summary
    total = len(match_results)
    matched = sum(1 for r in match_results if r.match_status == "matched")
    unmatched = total - matched
    match_rate = matched / total if total else 0.0

    summary = {
        "recipes_path": str(recipes_path),
        "nutrition_path": str(nutrition_path),
        "total_ingredients": total,
        "matched_ingredients": matched,
        "unmatched_ingredients": unmatched,
        "match_rate": round(match_rate, 4),
        "unique_unmatched_names": len(unmatched_counter),
        "output_dir": str(output_dir),
    }

    summary_path = output_dir / "summary.json"
    with summary_path.open("w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)

    print("\n[SUMMARY]")
    for k, v in summary.items():
        print(f"- {k}: {v}")

    print("\n[OUTPUT FILES]")
    print(f"- {match_results_csv}")
    print(f"- {unmatched_unique_csv}")
    print(f"- {unmatched_token_csv}")
    print(f"- {unmatched_prefix_csv}")
    print(f"- {unmatched_suffix_csv}")
    print(f"- {unmatched_candidates_csv}")
    print(f"- {summary_path}")


# =========================
# CLI
# =========================

def build_argparser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Analyze unmatched ingredients between recipes and nutrition data.")
    parser.add_argument(
        "--recipes",
        type=Path,
        default=Path("recipes.json"),
        help="Path to recipes.json"
    )
    parser.add_argument(
        "--nutrition",
        type=Path,
        default=Path("nutrition_data.json"),
        help="Path to nutrition_data.json"
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("output_unmatched_analysis"),
        help="Directory to write output CSV files"
    )
    parser.add_argument(
        "--top-k-candidates",
        type=int,
        default=10,
        help="Number of candidate matches to keep for each unmatched ingredient"
    )
    return parser


def main() -> int:
    parser = build_argparser()
    args = parser.parse_args()

    if not args.recipes.exists():
        print(f"[ERROR] recipes file not found: {args.recipes}", file=sys.stderr)
        return 1

    if not args.nutrition.exists():
        print(f"[ERROR] nutrition file not found: {args.nutrition}", file=sys.stderr)
        return 1

    run_analysis(
        recipes_path=args.recipes,
        nutrition_path=args.nutrition,
        output_dir=args.output_dir,
        top_k_candidates=args.top_k_candidates,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


# python analyze_unmatched.py \
#   --recipes workspace/src/recipe_nutrition_unmatch/data/input/recipes.json \
#   --nutrition workspace/src/recipe_nutrition_unmatch/data/input/nutrition_data.json \
#   --output-dir workspace/src/recipe_nutrition_unmatch/data/output