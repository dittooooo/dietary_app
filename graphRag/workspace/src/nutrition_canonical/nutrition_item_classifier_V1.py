
# -*- coding: utf-8 -*-
"""
nutrition_item_classifier.py

功能：
1. 讀取 nutrition_data.json
2. 讀取 ingredient_standardization_schema.json 與 classifier_rules.json
3. 將每筆營養資料分類為 canonical ingredient / subtype / derived product / commercial item 等
4. 輸出標準化結果 JSON 與摘要統計 JSON
5. 可依 canonical_name 產生 sibling_group_key 與 representative_candidate_rank

預設輸出：
- classified_nutrition_items.json
- classified_nutrition_summary.json

使用方式：
    python nutrition_item_classifier.py \\
        --nutrition-data /mnt/data/nutrition_data.json \\
        --schema /mnt/data/ingredient_standardization_schema.json \\
        --rules /mnt/data/classifier_rules.json \\
        --output-dir /mnt/data/output_classifier

注意：
- 本程式以規則式分類為主，適合作為第一版 canonicalization pipeline。
- 若要擴充更多食材，只需要補 classifier_rules.json。
"""
from __future__ import annotations

import json
import re
import unicodedata
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple


# -----------------------------
# Helpers
# -----------------------------

def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def save_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def to_list(value: Any) -> List[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return [str(x).strip() for x in value if str(x).strip()]
    return [str(value).strip()] if str(value).strip() else []


def unique_keep_order(items: Iterable[str]) -> List[str]:
    seen = set()
    result = []
    for item in items:
        if item not in seen:
            seen.add(item)
            result.append(item)
    return result


def contains_any(text: str, patterns: Iterable[str]) -> bool:
    return any(p and p in text for p in patterns)


def fullwidth_normalize(text: str) -> str:
    return unicodedata.normalize("NFKC", text)


def normalize_parentheses(text: str) -> str:
    pairs = {
        "（": "(",
        "）": ")",
        "【": "[",
        "】": "]",
        "｛": "{",
        "｝": "}",
    }
    for src, dst in pairs.items():
        text = text.replace(src, dst)
    return text


def collapse_spaces(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def strip_prefix_tokens(text: str, prefixes: List[str]) -> str:
    changed = True
    result = text
    while changed:
        changed = False
        for token in prefixes:
            if result.startswith(token):
                result = result[len(token):].strip()
                changed = True
    return result


def strip_outer_parenthetical(text: str) -> str:
    """
    移除最外層括號資訊後的核心字串，但保留原字串供 flavor / state 偵測使用。
    例：
    中脂調味保久乳(布丁) -> 中脂調味保久乳
    """
    return re.sub(r"\([^)]*\)", "", text).strip()


def split_aliases(alias_text: Optional[str], delimiters: List[str]) -> List[str]:
    if not alias_text:
        return []
    text = alias_text
    for d in delimiters:
        text = text.replace(d, "|")
    parts = [p.strip() for p in text.split("|")]
    return unique_keep_order([p for p in parts if p])


def safe_int(value: Any, default: int = 0) -> int:
    try:
        return int(value)
    except Exception:
        return default


# -----------------------------
# Normalizer
# -----------------------------

class TextNormalizer:
    def __init__(self, rules: Dict[str, Any]) -> None:
        cfg = rules.get("text_normalization", {})
        self.character_replacements: Dict[str, str] = cfg.get("character_replacements", {})
        self.prefix_tokens: List[str] = cfg.get("strip_prefix_tokens", [])
        self.alias_delimiters: List[str] = cfg.get("split_alias_delimiters", [",", "，", "、"])
        self.trim_whitespace = bool(cfg.get("trim_whitespace", True))
        self.normalize_fullwidth_halfwidth = bool(cfg.get("normalize_fullwidth_halfwidth", True))
        self.normalize_parentheses_flag = bool(cfg.get("normalize_parentheses", True))
        self.lowercase_english = bool(cfg.get("lowercase_english", True))
        self.collapse_spaces_flag = bool(cfg.get("collapse_spaces", True))
        self.remove_duplicate_aliases = bool(cfg.get("remove_duplicate_aliases", True))

    def normalize_text(self, text: Optional[str]) -> str:
        if text is None:
            return ""
        result = str(text)
        if self.trim_whitespace:
            result = result.strip()
        if self.normalize_fullwidth_halfwidth:
            result = fullwidth_normalize(result)
        if self.normalize_parentheses_flag:
            result = normalize_parentheses(result)
        for src, dst in self.character_replacements.items():
            result = result.replace(src, dst)
        if self.lowercase_english:
            def lower_en(match: re.Match[str]) -> str:
                return match.group(0).lower()
            result = re.sub(r"[A-Za-z]+", lower_en, result)
        if self.collapse_spaces_flag:
            result = collapse_spaces(result)
        return result

    def normalize_name(self, text: Optional[str]) -> str:
        result = self.normalize_text(text)
        result = strip_prefix_tokens(result, self.prefix_tokens)
        return result

    def normalize_aliases(self, alias_text: Optional[str]) -> List[str]:
        aliases = split_aliases(alias_text, self.alias_delimiters)
        aliases = [self.normalize_text(x) for x in aliases if x]
        if self.remove_duplicate_aliases:
            aliases = unique_keep_order(aliases)
        return aliases


# -----------------------------
# Data structures
# -----------------------------

@dataclass
class RawNutritionItem:
    source_id: Optional[str]
    raw_category: Optional[str]
    raw_name: str
    raw_description: Optional[str]
    raw_aliases: List[str]
    raw_record: Dict[str, Any] = field(default_factory=dict)


@dataclass
class ClassifiedItem:
    source_id: Optional[str]
    raw_name: str
    raw_category: Optional[str]
    raw_description: Optional[str]
    raw_aliases: List[str]

    normalized_name: str
    normalized_description: str
    normalized_aliases: List[str]

    canonical_name: Optional[str]
    canonical_group: Optional[str]

    match_type: str
    entity_role: str

    is_base_food: bool
    is_query_default: bool
    is_search_hidden_by_default: bool

    search_priority: int
    specificity_score: int

    processing_level: Optional[str]
    state_tags: List[str]
    flavor_tags: List[str]
    brand_tags: List[str]
    exclude_reasons: List[str]

    representative_candidate_rank: Optional[int]
    sibling_group_key: Optional[str]
    canonical_query_terms: List[str]

    debug_flags: Dict[str, Any]
    raw_record: Dict[str, Any]

    def to_dict(self) -> Dict[str, Any]:
        return {
            "source_id": self.source_id,
            "raw_name": self.raw_name,
            "raw_category": self.raw_category,
            "raw_description": self.raw_description,
            "raw_aliases": self.raw_aliases,
            "normalized_name": self.normalized_name,
            "normalized_description": self.normalized_description,
            "normalized_aliases": self.normalized_aliases,
            "canonical_name": self.canonical_name,
            "canonical_group": self.canonical_group,
            "match_type": self.match_type,
            "entity_role": self.entity_role,
            "is_base_food": self.is_base_food,
            "is_query_default": self.is_query_default,
            "is_search_hidden_by_default": self.is_search_hidden_by_default,
            "search_priority": self.search_priority,
            "specificity_score": self.specificity_score,
            "processing_level": self.processing_level,
            "state_tags": self.state_tags,
            "flavor_tags": self.flavor_tags,
            "brand_tags": self.brand_tags,
            "exclude_reasons": self.exclude_reasons,
            "representative_candidate_rank": self.representative_candidate_rank,
            "sibling_group_key": self.sibling_group_key,
            "canonical_query_terms": self.canonical_query_terms,
            "debug_flags": self.debug_flags,
            "raw_record": self.raw_record,
        }


# -----------------------------
# Classifier
# -----------------------------

class NutritionItemClassifier:
    def __init__(self, schema: Dict[str, Any], rules: Dict[str, Any]) -> None:
        self.schema = schema
        self.rules = rules
        self.normalizer = TextNormalizer(rules)

        self.query_default_rules: Dict[str, int] = rules.get("query_default_rules", {})
        self.group_assignment_by_category: Dict[str, str] = rules.get("group_assignment_by_category", {})
        self.processing_keywords: Dict[str, List[str]] = rules.get("processing_detection", {}).get("processing_keywords", {})
        self.subtype_keywords: Dict[str, Dict[str, str]] = rules.get("state_and_subtype_keywords", {})
        self.brand_keywords: List[str] = rules.get("brand_detection", {}).get("brand_keywords", [])
        self.flavor_keywords: List[str] = rules.get("flavor_detection", {}).get("flavor_keywords", [])
        self.derived_product_cfg: Dict[str, Any] = rules.get("derived_product_detection", {})
        self.hard_exclusion_cfg: Dict[str, Any] = rules.get("hard_exclusion_patterns", {})
        self.canonical_alias_map: Dict[str, List[str]] = rules.get("canonical_alias_map", {})
        self.canonical_resolution_rules: List[Dict[str, Any]] = rules.get("canonical_resolution_rules", [])
        self.seasoning_group_map: Dict[str, str] = rules.get("seasoning_detection", {}).get("canonical_groups", {})
        self.postprocess_cfg: Dict[str, Any] = rules.get("classification_postprocessing", {})

        self.alias_to_canonical = self._build_alias_to_canonical()

    def _build_alias_to_canonical(self) -> Dict[str, str]:
        alias_map: Dict[str, str] = {}
        for canonical, aliases in self.canonical_alias_map.items():
            norm_can = self.normalizer.normalize_name(canonical)
            alias_map[norm_can] = canonical
            for alias in aliases:
                norm_alias = self.normalizer.normalize_name(alias)
                alias_map[norm_alias] = canonical
        return alias_map

    def parse_raw_item(self, row: Dict[str, Any]) -> RawNutritionItem:
        source_fields = self.schema.get("source_fields", {})
        source_id = row.get(source_fields.get("id", "整合編號"))
        raw_category = row.get(source_fields.get("category", "食品分類"))
        raw_name = row.get(source_fields.get("name", "樣品名稱"))
        raw_description = row.get(source_fields.get("description", "內容物描述"))
        raw_aliases = self.normalizer.normalize_aliases(row.get(source_fields.get("aliases", "俗名")))

        return RawNutritionItem(
            source_id=source_id,
            raw_category=raw_category,
            raw_name=str(raw_name or "").strip(),
            raw_description=raw_description,
            raw_aliases=raw_aliases,
            raw_record=row,
        )

    def classify_item(self, item: RawNutritionItem) -> ClassifiedItem:
        normalized_name = self.normalizer.normalize_name(item.raw_name)
        normalized_description = self.normalizer.normalize_text(item.raw_description)
        normalized_aliases = [self.normalizer.normalize_name(x) for x in item.raw_aliases]
        parenthetical_stripped_name = strip_outer_parenthetical(normalized_name)

        texts_all = [normalized_name, parenthetical_stripped_name, normalized_description] + normalized_aliases
        searchable_text = " | ".join([x for x in texts_all if x]).strip()

        # Base defaults
        canonical_name: Optional[str] = None
        canonical_group: Optional[str] = self._infer_group_from_category(item.raw_category)
        match_type = "uncertain"
        entity_role = "unknown"
        is_base_food = False
        is_query_default = False
        is_search_hidden_by_default = True
        search_priority = self.query_default_rules.get(match_type, 5)
        specificity_score = 50
        processing_level: Optional[str] = "unknown"
        state_tags: List[str] = []
        flavor_tags: List[str] = []
        brand_tags: List[str] = []
        exclude_reasons: List[str] = []
        representative_candidate_rank: Optional[int] = None
        sibling_group_key: Optional[str] = None
        canonical_query_terms: List[str] = []
        debug_flags: Dict[str, Any] = {}

        # 1) Hard exclusion
        hard_contains = self.hard_exclusion_cfg.get("contains_any", [])
        if contains_any(searchable_text, hard_contains):
            assign = self.hard_exclusion_cfg.get("assign", {})
            match_type = assign.get("match_type", "mixed_food")
            entity_role = assign.get("entity_role", "mixed_item")
            is_base_food = bool(assign.get("is_base_food", False))
            is_query_default = bool(assign.get("is_query_default", False))
            is_search_hidden_by_default = bool(assign.get("is_search_hidden_by_default", True))
            search_priority = safe_int(assign.get("search_priority", self.query_default_rules.get(match_type, 0)))
            exclude_reasons.extend(assign.get("exclude_reasons", []))
            debug_flags["hard_exclusion"] = True

        # 2) Detect brand
        for kw in self.brand_keywords:
            if kw and kw in searchable_text:
                brand_tags.append(kw)
        brand_tags = unique_keep_order(brand_tags)
        if brand_tags and "hard_exclusion" not in debug_flags:
            assign = self.rules.get("brand_detection", {}).get("assign", {})
            match_type = assign.get("match_type", "brand_or_commercial_item")
            entity_role = assign.get("entity_role", "commercial_product")
            is_base_food = False
            default_visibility = self.rules.get("brand_detection", {}).get("default_visibility", {})
            is_query_default = bool(default_visibility.get("is_query_default", False))
            is_search_hidden_by_default = bool(default_visibility.get("is_search_hidden_by_default", True))
            search_priority = max(0, self.query_default_rules.get(match_type, 10) - safe_int(default_visibility.get("search_priority_penalty", 0)))
            exclude_reasons.append("brand_or_commercial_item")
            debug_flags["brand_detected"] = True

        # 3) Flavor detection
        for kw in self.flavor_keywords:
            if kw and kw in searchable_text:
                flavor_tags.append(kw)
        flavor_tags = unique_keep_order(flavor_tags)
        if flavor_tags and "hard_exclusion" not in debug_flags:
            if match_type in {"uncertain", "brand_or_commercial_item"}:
                match_type = "beverage_variant" if "乳" in searchable_text or "奶" in searchable_text else match_type
                entity_role = self.rules.get("flavor_detection", {}).get("assign", {}).get("entity_role", entity_role)
            default_visibility = self.rules.get("flavor_detection", {}).get("default_visibility", {})
            is_query_default = bool(default_visibility.get("is_query_default", False))
            is_search_hidden_by_default = bool(default_visibility.get("is_search_hidden_by_default", True))
            penalty = safe_int(default_visibility.get("search_priority_penalty", 0))
            search_priority = max(0, (search_priority or self.query_default_rules.get(match_type, 20)) - penalty)
            exclude_reasons.append("flavored_variant")
            debug_flags["flavor_detected"] = True

        # 4) Derived product detection
        if "hard_exclusion" not in debug_flags:
            derived_contains = self.derived_product_cfg.get("contains_any", [])
            derived_exceptions = self.derived_product_cfg.get("exceptions_allow_base", [])
            has_derived_signal = contains_any(searchable_text, derived_contains)
            has_derived_exception = contains_any(searchable_text, derived_exceptions)
            if has_derived_signal and not has_derived_exception:
                assign = self.derived_product_cfg.get("assign", {})
                if match_type in {"uncertain", "brand_or_commercial_item"}:
                    match_type = assign.get("match_type", "derived_product")
                    entity_role = assign.get("entity_role", "derived_food")
                is_base_food = False
                is_query_default = bool(assign.get("is_query_default", False))
                is_search_hidden_by_default = bool(assign.get("is_search_hidden_by_default", True))
                penalty = safe_int(assign.get("search_priority_penalty", 35))
                base_priority = self.query_default_rules.get(match_type, 30)
                search_priority = max(0, base_priority - penalty)
                exclude_reasons.append("derived_product")
                debug_flags["derived_product_detected"] = True

        # 5) Processing detection
        processing_level, processing_tags = self._detect_processing(searchable_text)
        state_tags.extend(processing_tags)

        # 6) State / subtype detection
        subtype_tags = self._detect_subtypes(searchable_text)
        state_tags.extend(subtype_tags)
        state_tags = unique_keep_order(state_tags)

        # 7) Canonical alias resolution
        canonical_name, alias_match = self._resolve_by_alias(normalized_name, normalized_aliases, normalized_description)
        if canonical_name:
            canonical_query_terms.extend([canonical_name] + self.canonical_alias_map.get(canonical_name, []))
            canonical_query_terms = unique_keep_order(canonical_query_terms)
            if match_type == "uncertain":
                if alias_match == "exact_name":
                    match_type = "exact_base_food"
                    entity_role = "base_food"
                    is_base_food = True
                    is_query_default = True
                    is_search_hidden_by_default = False
                else:
                    match_type = "alias_of_base_food"
                    entity_role = "base_food"
                    is_base_food = True
                    is_query_default = True
                    is_search_hidden_by_default = False
                search_priority = self.query_default_rules.get(match_type, 90)
                debug_flags["alias_resolved"] = True

        # 8) Canonical rule resolution
        rule_matched = self._match_canonical_rule(searchable_text)
        if rule_matched:
            canonical_name = rule_matched["canonical_name"]
            canonical_group = rule_matched.get("canonical_group", canonical_group)
            canonical_query_terms.extend([canonical_name] + self.canonical_alias_map.get(canonical_name, []))
            canonical_query_terms = unique_keep_order(canonical_query_terms)

            excluded_by_rule = contains_any(searchable_text, rule_matched.get("exclude_if_contains_any", []))
            default_subtypes = rule_matched.get("default_subtypes", [])
            hide_subtypes = rule_matched.get("hide_subtypes", [])

            if excluded_by_rule:
                exclude_reasons.append("excluded_by_canonical_rule")
                if match_type == "uncertain":
                    match_type = "derived_product"
                    entity_role = "derived_food"
                    is_base_food = False
                    is_query_default = False
                    is_search_hidden_by_default = True
                    search_priority = self.query_default_rules.get(match_type, 30)
            else:
                # subtype / exact / processing variant
                if normalized_name == self.normalizer.normalize_name(canonical_name):
                    if match_type in {"uncertain", "brand_or_commercial_item"}:
                        match_type = "exact_base_food"
                        entity_role = "base_food"
                        is_base_food = True
                        is_query_default = True
                        is_search_hidden_by_default = False
                elif normalized_name in [self.normalizer.normalize_name(x) for x in default_subtypes]:
                    if match_type in {"uncertain", "brand_or_commercial_item", "alias_of_base_food"}:
                        match_type = "subtype_of_base_food"
                        entity_role = "subtype"
                        is_base_food = True
                        is_query_default = True
                        is_search_hidden_by_default = False
                elif hide_subtypes and contains_any(searchable_text, hide_subtypes):
                    if match_type in {"uncertain", "brand_or_commercial_item", "alias_of_base_food"}:
                        match_type = "derived_product"
                        entity_role = "derived_food"
                        is_base_food = False
                        is_query_default = False
                        is_search_hidden_by_default = True
                        search_priority = self.query_default_rules.get(match_type, 30)
                        exclude_reasons.append("hidden_subtype_for_default_query")
                else:
                    if match_type in {"uncertain", "brand_or_commercial_item"}:
                        if processing_level not in {None, "unknown", "fresh", "raw"}:
                            match_type = "processing_variant"
                            entity_role = "subtype"
                            is_base_food = True
                            is_query_default = False
                            is_search_hidden_by_default = False
                        else:
                            match_type = "subtype_of_base_food"
                            entity_role = "subtype"
                            is_base_food = True
                            is_query_default = True
                            is_search_hidden_by_default = False

                search_priority = max(search_priority, safe_int(rule_matched.get("default_priority", self.query_default_rules.get(match_type, 50))))
                debug_flags["canonical_rule_matched"] = True

        # 9) Seasoning inference
        canonical_name, canonical_group, match_type, entity_role, is_base_food = self._apply_seasoning_inference(
            searchable_text,
            canonical_name,
            canonical_group,
            match_type,
            entity_role,
            is_base_food,
        )

        # 10) Category fallback
        if not canonical_group:
            canonical_group = self._infer_group_from_category(item.raw_category)
        if not canonical_name:
            canonical_name = self._fallback_canonical_name(normalized_name)

        # 11) Fallback defaults if still uncertain
        if match_type == "uncertain":
            if canonical_name:
                match_type = "subtype_of_base_food"
                entity_role = "subtype"
                is_base_food = True
                is_query_default = False
                is_search_hidden_by_default = False
                search_priority = self.query_default_rules.get(match_type, 88) - 20
                exclude_reasons.append("fallback_inferred")
            else:
                entity_role = "unknown"
                is_base_food = False
                is_query_default = False
                is_search_hidden_by_default = True
                search_priority = self.query_default_rules.get(match_type, 5)

        # 12) Post processing
        if self.postprocess_cfg.get("if_brand_and_flavored_then_hide", False):
            if brand_tags and flavor_tags:
                is_query_default = False
                is_search_hidden_by_default = True
                is_base_food = False
                exclude_reasons.append("brand_and_flavored_hidden")

        if self.postprocess_cfg.get("if_derived_product_then_not_default", False):
            if match_type == "derived_product":
                is_query_default = False
                is_search_hidden_by_default = True

        if self.postprocess_cfg.get("if_mixed_food_then_not_base_food", False):
            if match_type == "mixed_food":
                is_base_food = False
                is_query_default = False
                is_search_hidden_by_default = True

        # 13) Specificity / sibling key
        specificity_score = self._compute_specificity(
            normalized_name=normalized_name,
            canonical_name=canonical_name,
            state_tags=state_tags,
            flavor_tags=flavor_tags,
            brand_tags=brand_tags,
            processing_level=processing_level,
            match_type=match_type,
        )
        sibling_group_key = self._build_sibling_group_key(
            canonical_name=canonical_name,
            processing_level=processing_level,
            state_tags=state_tags,
            flavor_tags=flavor_tags,
            match_type=match_type,
        )

        exclude_reasons = unique_keep_order(exclude_reasons)
        state_tags = unique_keep_order([x for x in state_tags if x])
        flavor_tags = unique_keep_order([x for x in flavor_tags if x])
        brand_tags = unique_keep_order([x for x in brand_tags if x])

        return ClassifiedItem(
            source_id=item.source_id,
            raw_name=item.raw_name,
            raw_category=item.raw_category,
            raw_description=item.raw_description,
            raw_aliases=item.raw_aliases,
            normalized_name=normalized_name,
            normalized_description=normalized_description,
            normalized_aliases=normalized_aliases,
            canonical_name=canonical_name,
            canonical_group=canonical_group,
            match_type=match_type,
            entity_role=entity_role,
            is_base_food=is_base_food,
            is_query_default=is_query_default,
            is_search_hidden_by_default=is_search_hidden_by_default,
            search_priority=max(0, min(100, search_priority)),
            specificity_score=max(0, min(100, specificity_score)),
            processing_level=processing_level,
            state_tags=state_tags,
            flavor_tags=flavor_tags,
            brand_tags=brand_tags,
            exclude_reasons=exclude_reasons,
            representative_candidate_rank=representative_candidate_rank,
            sibling_group_key=sibling_group_key,
            canonical_query_terms=canonical_query_terms,
            debug_flags=debug_flags,
            raw_record=item.raw_record,
        )

    def _infer_group_from_category(self, raw_category: Optional[str]) -> Optional[str]:
        if not raw_category:
            return None
        raw_category_norm = self.normalizer.normalize_text(raw_category)
        for key, val in self.group_assignment_by_category.items():
            if key in raw_category_norm:
                return val
        return None

    def _detect_processing(self, searchable_text: str) -> Tuple[Optional[str], List[str]]:
        detected_level = "unknown"
        tags: List[str] = []
        for level, keywords in self.processing_keywords.items():
            if contains_any(searchable_text, keywords):
                detected_level = level
                tags.extend([kw for kw in keywords if kw in searchable_text][:2])
                # 保留第一個較強訊號即可
                if level in {"ultra_heat_treated", "sauce", "paste", "powder", "canned", "pickled"}:
                    break
        return detected_level, unique_keep_order(tags)

    def _detect_subtypes(self, searchable_text: str) -> List[str]:
        found: List[str] = []
        for _, mapping in self.subtype_keywords.items():
            for kw, tag in mapping.items():
                if kw in searchable_text:
                    found.append(tag)
        return unique_keep_order(found)

    def _resolve_by_alias(self, normalized_name: str, normalized_aliases: List[str], normalized_description: str) -> Tuple[Optional[str], Optional[str]]:
        if normalized_name in self.alias_to_canonical:
            canonical = self.alias_to_canonical[normalized_name]
            if normalized_name == self.normalizer.normalize_name(canonical):
                return canonical, "exact_name"
            return canonical, "name_alias"

        for alias in normalized_aliases:
            if alias in self.alias_to_canonical:
                return self.alias_to_canonical[alias], "alias_field"

        # 只用 description 作為弱訊號
        for alias, canonical in self.alias_to_canonical.items():
            if alias and alias in normalized_description:
                return canonical, "description_alias"
        return None, None

    def _match_canonical_rule(self, searchable_text: str) -> Optional[Dict[str, Any]]:
        for rule in self.canonical_resolution_rules:
            if contains_any(searchable_text, rule.get("when_contains_any", [])):
                return rule
        return None

    def _apply_seasoning_inference(
        self,
        searchable_text: str,
        canonical_name: Optional[str],
        canonical_group: Optional[str],
        match_type: str,
        entity_role: str,
        is_base_food: bool,
    ) -> Tuple[Optional[str], Optional[str], str, str, bool]:
        # 如果已明確被分到 canonical，可不覆蓋；但調味料若名稱非常明確，仍可修正 group
        matched_canonical = None
        matched_group = canonical_group
        for seasoning_name, group in self.seasoning_group_map.items():
            if seasoning_name in searchable_text:
                matched_canonical = seasoning_name
                matched_group = group
                break

        if matched_canonical:
            if canonical_name is None:
                canonical_name = matched_canonical
            if canonical_group is None:
                canonical_group = matched_group
            if match_type in {"uncertain", "brand_or_commercial_item"}:
                match_type = "seasoning_or_sauce"
                entity_role = "seasoning"
                is_base_food = True
        return canonical_name, canonical_group, match_type, entity_role, is_base_food

    def _fallback_canonical_name(self, normalized_name: str) -> Optional[str]:
        # 從名稱直接取較簡單的 fallback
        # 例如：低筋麵粉 -> 麵粉
        fallback_pairs = [
            ("低筋麵粉", "麵粉"),
            ("中筋麵粉", "麵粉"),
            ("高筋麵粉", "麵粉"),
            ("嫩豆腐", "豆腐"),
            ("板豆腐", "豆腐"),
            ("凍豆腐", "豆腐"),
            ("雞蛋豆腐", "豆腐"),
            ("百頁豆腐", "豆腐"),
        ]
        for src, dst in fallback_pairs:
            if src in normalized_name:
                return dst
        return normalized_name if normalized_name else None

    def _compute_specificity(
        self,
        normalized_name: str,
        canonical_name: Optional[str],
        state_tags: List[str],
        flavor_tags: List[str],
        brand_tags: List[str],
        processing_level: Optional[str],
        match_type: str,
    ) -> int:
        score = 40
        if canonical_name and normalized_name == self.normalizer.normalize_name(canonical_name):
            score -= 10
        if state_tags:
            score += min(20, len(state_tags) * 6)
        if flavor_tags:
            score += min(15, len(flavor_tags) * 8)
        if brand_tags:
            score += min(12, len(brand_tags) * 6)
        if processing_level and processing_level not in {"unknown", "fresh", "raw"}:
            score += 10
        if match_type in {"derived_product", "brand_or_commercial_item", "beverage_variant"}:
            score += 10
        return max(0, min(100, score))

    def _build_sibling_group_key(
        self,
        canonical_name: Optional[str],
        processing_level: Optional[str],
        state_tags: List[str],
        flavor_tags: List[str],
        match_type: str,
    ) -> Optional[str]:
        if not canonical_name:
            return None
        state_core = [x for x in state_tags if x not in {"生", "熟"}]
        key_parts = [canonical_name]
        if processing_level and processing_level != "unknown":
            key_parts.append(processing_level)
        if state_core:
            key_parts.extend(sorted(state_core))
        if flavor_tags and match_type == "beverage_variant":
            key_parts.extend(sorted(flavor_tags))
        return "::".join(key_parts[:6])

    def assign_representative_ranks(self, items: List[ClassifiedItem]) -> None:
        groups: Dict[str, List[ClassifiedItem]] = defaultdict(list)
        for item in items:
            if item.canonical_name:
                groups[item.canonical_name].append(item)

        for _, siblings in groups.items():
            siblings.sort(
                key=lambda x: (
                    not x.is_query_default,
                    x.is_search_hidden_by_default,
                    -x.search_priority,
                    x.specificity_score,
                    len(x.normalized_name),
                    x.normalized_name,
                )
            )
            for idx, item in enumerate(siblings, start=1):
                item.representative_candidate_rank = idx

    def classify_all(self, rows: List[Dict[str, Any]]) -> List[ClassifiedItem]:
        classified: List[ClassifiedItem] = []
        for row in rows:
            raw_item = self.parse_raw_item(row)
            classified_item = self.classify_item(raw_item)
            classified.append(classified_item)
        self.assign_representative_ranks(classified)
        return classified

    def build_summary(self, items: List[ClassifiedItem]) -> Dict[str, Any]:
        by_match_type = Counter(item.match_type for item in items)
        by_entity_role = Counter(item.entity_role for item in items)
        by_group = Counter(item.canonical_group or "NULL" for item in items)
        hidden_count = sum(1 for item in items if item.is_search_hidden_by_default)
        default_count = sum(1 for item in items if item.is_query_default)
        base_food_count = sum(1 for item in items if item.is_base_food)

        by_canonical: Dict[str, Dict[str, Any]] = {}
        grouped: Dict[str, List[ClassifiedItem]] = defaultdict(list)
        for item in items:
            grouped[item.canonical_name or "NULL"].append(item)

        for canonical_name, siblings in sorted(grouped.items(), key=lambda x: (-len(x[1]), x[0])):
            sorted_siblings = sorted(
                siblings,
                key=lambda x: (
                    not x.is_query_default,
                    x.is_search_hidden_by_default,
                    -x.search_priority,
                    x.representative_candidate_rank or 99999,
                    x.normalized_name,
                )
            )
            by_canonical[canonical_name] = {
                "count": len(sorted_siblings),
                "top_items": [
                    {
                        "raw_name": s.raw_name,
                        "match_type": s.match_type,
                        "entity_role": s.entity_role,
                        "search_priority": s.search_priority,
                        "is_query_default": s.is_query_default,
                        "representative_candidate_rank": s.representative_candidate_rank,
                    }
                    for s in sorted_siblings[:10]
                ],
            }

        return {
            "total_items": len(items),
            "base_food_count": base_food_count,
            "default_query_count": default_count,
            "hidden_by_default_count": hidden_count,
            "by_match_type": dict(by_match_type),
            "by_entity_role": dict(by_entity_role),
            "by_canonical_group": dict(by_group),
            "by_canonical_name_top": dict(list(by_canonical.items())[:100]),
        }


# -----------------------------
# Fixed paths config
# -----------------------------

NUTRITION_DATA_PATH = Path(r"C:\Users\PARALELL\Desktop\code4\workspace\src\nutrition_canonical\input\nutrition_data.json")
SCHEMA_PATH = Path(r"C:\Users\PARALELL\Desktop\code4\workspace\src\nutrition_canonical\input\ingredient_standardization_schema.json")
RULES_PATH = Path(r"C:\Users\PARALELL\Desktop\code4\workspace\src\nutrition_canonical\input\classifier_rules.json")
OUTPUT_DIR = Path(r"C:\Users\PARALELL\Desktop\code4\workspace\src\nutrition_canonical\output")

CLASSIFIED_OUTPUT_NAME = "classified_nutrition_items.json"
SUMMARY_OUTPUT_NAME = "classified_nutrition_summary.json"


def main() -> None:
    schema = load_json(SCHEMA_PATH)
    rules = load_json(RULES_PATH)
    nutrition_rows = load_json(NUTRITION_DATA_PATH)

    if not isinstance(nutrition_rows, list):
        raise ValueError("nutrition_data.json must be a JSON array.")

    classifier = NutritionItemClassifier(schema=schema, rules=rules)
    classified_items = classifier.classify_all(nutrition_rows)

    detailed_output = [item.to_dict() for item in classified_items]
    summary_output = classifier.build_summary(classified_items)

    classified_path = OUTPUT_DIR / CLASSIFIED_OUTPUT_NAME
    summary_path = OUTPUT_DIR / SUMMARY_OUTPUT_NAME

    save_json(classified_path, detailed_output)
    save_json(summary_path, summary_output)

    print(f"[nutrition_item_classifier] input rows: {len(nutrition_rows)}")
    print(f"[nutrition_item_classifier] detailed output: {classified_path}")
    print(f"[nutrition_item_classifier] summary output: {summary_path}")


if __name__ == "__main__":
    main()
