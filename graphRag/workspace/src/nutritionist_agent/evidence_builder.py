"""Deterministic evidence for advice; missing data never means dietary safety."""
from __future__ import annotations

from collections import defaultdict
from datetime import date

from .disease_rules import DIRECT_CONDITIONS, convert_unit, evaluate_rule
from .models import DietRecord, DishNutrition, UserProfile
from .nutrition_calculator import COMMON_NUTRIENT_ALIASES, COMMON_NUTRIENT_ORDER


UNITS = {n: {"熱量": "kcal", "鈉": "mg"}.get(n, "g") for n in COMMON_NUTRIENT_ORDER}
GOALS = {
    "增肌": {"蛋白質": "increase"},
    "減重": {"熱量": "decrease"},
    "減脂": {"熱量": "decrease"},
    "低鈉": {"鈉": "decrease"},
    "控血壓": {"鈉": "decrease"},
    "控糖": {},  # Total carbohydrate/sugar is not a prediction of glycemic response.
    "均衡飲食": {},
    "體重維持": {},
}
PATTERNS = {
    "oily": ("油膩", "偏油", "油炸", "炸", "奶油"),
    "salty": ("偏鹹", "太鹹", "很鹹", "加醬"),
    "sweet": ("全糖", "偏甜", "太甜", "加糖", "甜點"),
    "vegetables": ("蔬菜", "青菜", "沙拉"),
}
NEGATED = ("無糖", "不加糖", "無加糖", "少糖", "少油", "不油", "不鹹", "少鹽", "少醬", "不加醬")


def nutrient_name(value: str | None) -> str:
    return COMMON_NUTRIENT_ALIASES.get(str(value), str(value))


def summarize_recent_records(records: list[DietRecord], today: date | None = None) -> dict:
    today = today or date.today()
    recent, excluded, undated, future = [], 0, 0, 0
    patterns = defaultdict(lambda: {"weighted_mentions": 0.0, "evidence": []})
    for record in records:
        try:
            age = (today - date.fromisoformat(record.date or "")).days
        except ValueError:
            undated += len(record.record)
            continue
        if age < 0:
            future += len(record.record)
            continue
        if age >= 7:
            excluded += len(record.record)
            continue
        for item in record.record:
            entry = {"date": record.date, "dish_name": item.dish_name, "note": item.note,
                     "amount": item.amount, "meal_type": item.meal_type,
                     "recorded_nutrition": item.nutrition.model_dump(exclude_none=True) if item.nutrition else {}}
            recent.append(entry)
            text = f"{item.dish_name} {item.note or ''}"
            for token in NEGATED:
                text = text.replace(token, "")
            for pattern, tokens in PATTERNS.items():
                if any(token in text for token in tokens):
                    patterns[pattern]["weighted_mentions"] += 1 / (age + 1)
                    patterns[pattern]["evidence"].append(entry)
    recent.sort(key=lambda x: x["date"], reverse=True)
    return {"as_of": today.isoformat(), "window_days": 7, "recent": recent,
            "patterns": dict(patterns), "excluded_old_items": excluded,
            "undated_items": undated, "future_items": future,
            "interpretation": "詞語及備註線索，非實測攝取量；近期權重僅用來排列提醒，不作臨床判定"}


def build_evidence(profile: UserProfile, records: list[DietRecord], dishes: list[DishNutrition],
                   rows: list[dict], disease_groups: list[dict], today: date | None = None) -> dict:
    facts, assessments = [], []
    def fact(key: str, category: str, text: str, **details: object) -> None:
        facts.append({"id": key, "category": category, "text": text, **details})

    values = {}
    contributors = defaultdict(lambda: defaultdict(lambda: defaultdict(float)))
    for row in rows:
        name = nutrient_name(row.get("nutrition_name_zh") or row.get("nutrition_name"))
        food = row.get("food_item_name")
        value = convert_unit(row.get("amount_per_serving"), row.get("nutrition_unit"), UNITS.get(name))
        if food and value is not None and value > 0:
            contributors[row.get("dish_name")][name][food] += value
    for dish in dishes:
        valid = {}
        for n in dish.nutrients:
            if n.name == "熱量" and n.calorie_status != "calculated":
                continue
            value = convert_unit(n.amount_per_serving, n.unit, UNITS.get(n.name))
            if value is not None:
                valid[n.name] = value
        values[dish.dish_name] = valid
        fact(f"N{len(values)}", "nutrition",
             f"{dish.dish_name}可用於比較的營養項目：" + ("、".join(valid) or "資料不足"),
             dish_name=dish.dish_name, strategy=dish.retrieval_strategy,
             completeness="partial" if len(valid) < len(UNITS) else "summary_fields_available",
             missing=[n for n in UNITS if n not in valid],
             main_contributors={name: sorted(foods, key=foods.get, reverse=True)[:3]
                                for name, foods in contributors[dish.dish_name].items()},
             quality="recipe_proxy" if dish.retrieval_strategy == "dish_match" else "ingredient_or_food_proxy")

    # Only compare like-for-like recipe estimates; exclude ingredient fallback proxies.
    relative = {}
    comparable = len(dishes) > 1 and all(d.retrieval_strategy == "dish_match" for d in dishes)
    if comparable:
        for name in UNITS:
            if not all(name in values[d.dish_name] for d in dishes):
                continue
            column = {d.dish_name: values[d.dish_name][name] for d in dishes}
            low, high = min(column.values()), max(column.values())
            if low == high:
                continue
            relative[name] = {dish: ("lower" if v == low else "higher" if v == high else "middle")
                              for dish, v in column.items()}
            fact(f"C{len(relative)}", "comparison",
                 f"{name}只在本次提供份量的食譜估算間相對比較，不代表絕對高低。",
                 nutrient=name, comparison=relative[name])

    by_dish_nutrient = defaultdict(list)
    for row in rows:
        key = (row.get("dish_name"), nutrient_name(row.get("nutrition_name_zh") or row.get("nutrition_name")))
        by_dish_nutrient[key].append(row)
    directions = defaultdict(set)
    conflicts = defaultdict(set)
    required_ids, unresolved = [], False
    status_text = {"disease_not_found": "資料庫未找到此疾病，不能判定料理符合疾病需求",
                   "no_rules": "疾病存在但沒有飲食規則，不能判定料理符合疾病需求",
                   "missing_disease_name": "已勾選慢性病但未提供疾病名稱，無法查詢特定疾病規則"}
    for index, group in enumerate(disease_groups, 1):
        key = f"D{index}"
        required_ids.append(key)
        name = group["requested"] or "未提供名稱的慢性病"
        if group["status"] != "rules_found":
            unresolved = True
            fact(key, "disease", f"{name}：{status_text[group['status']]}", status=group["status"])
            continue
        details = []
        for rule in group["rules"]:
            nutrient = nutrient_name(rule["nutrient"].get("name_zh") or rule["nutrient"].get("name"))
            direction = rule.get("direction")
            if direction == "adjust_by_stage" or rule.get("food_level_condition") == "high_potassium":
                unresolved = True
            if rule.get("food_level_condition") in DIRECT_CONDITIONS:
                directions[nutrient].add(direction)
            for dish in dishes:
                result = evaluate_rule(rule, by_dish_nutrient[(dish.dish_name, nutrient)])
                assessment = {**result, "dish_name": dish.dish_name, "disease": name, "nutrient": nutrient,
                              "relation": rule.get("relation"), "direction": direction,
                              "condition": rule.get("food_level_condition"),
                              "rule_note": rule.get("food_level_note") or rule.get("target_note"),
                              "graph_reason": rule.get("reason"),
                              "source": rule.get("sources_json"), "source_status": "graph_rule_not_independently_verified"}
                assessments.append(assessment)
                details.append(assessment)
                if result["assessment"] == "potential_conflict":
                    conflicts[dish.dish_name].add((name, rule["id"]))
        fact(key, "disease", f"{name}已主動檢索全部資料庫規則；以下判斷限於已辨識食材，未觸發不等於整餐安全。",
             status=group["status"], rule_count=len(group["rules"]), assessments=details)

    goal = (profile.diet_goal or "").strip()
    goal_directions = {}
    for token, mapping in GOALS.items():
        if token in goal:
            goal_directions.update(mapping)
    if goal:
        required_ids.append("G")
        fact("G", "goal", f"使用者目標是「{goal}」；僅評估下列可用方向，不推算個人每日需求。",
             recognized=any(token in goal for token in GOALS),
             directions=goal_directions, subordinate_to_disease=True,
             available_comparisons=[n for n in goal_directions if n in relative])
    history = summarize_recent_records(records, today)
    if history["recent"]:
        required_ids.append("H")
        fact("H", "history", "僅依最近七日實際提供的料理與備註提出調整，可引用具體餐點；不代表完整飲食或每日達標。",
             history=history)
    else:
        fact("H", "history", "沒有日期有效的最近七日紀錄；不得把舊紀錄說成近期習慣。",
             history=history)

    # Lexicographic priority: disease caution precedes relative nutrient direction and goal.
    # Missing disease identity/stage blocks automatic ranking, never rewards an absence of evidence.
    coverage = defaultdict(set)
    for assessment in assessments:
        coverage[assessment["rule_id"]].add(assessment["assessment"] == "insufficient")
    unequal_coverage = any(len(states) > 1 for states in coverage.values())
    unresolved = unresolved or any(len(ds) > 1 for ds in directions.values())
    preferred, decision_reason = None, "缺少可支持唯一推薦的比較證據"
    if comparable and relative and not unresolved and not unequal_coverage:
        applicable = {n: next(iter(ds)) for n, ds in directions.items()
                      if len(ds) == 1 and ds <= {"increase", "decrease"} and n in relative}
        def score(dish: DishNutrition) -> tuple:
            def favor(mapping: dict) -> int:
                return sum(relative[n][dish.dish_name] == ("higher" if direction == "increase" else "lower")
                           for n, direction in mapping.items() if n in relative)
            # Goal rules that conflict with disease directions never influence ranking.
            allowed_goals = {n: v for n, v in goal_directions.items()
                             if n not in directions or directions[n] == {v}}
            return (-len(conflicts[dish.dish_name]), favor(applicable), favor(allowed_goals))
        ranked = sorted(((score(d), d.dish_name) for d in dishes), reverse=True)
        if ranked[0][0] != ranked[1][0]:
            preferred = ranked[0][1]
            decision_reason = "依已知疾病注意訊號優先，其次比較疾病方向與使用者目標；僅為本次候選的暫定相對選擇"
    # A relative choice is deliberately narrower than `preferred_dish`: it only
    # describes the direction of comparable recipe estimates for disease-related
    # nutrients.  It remains available when incomplete ingredient coverage blocks
    # a broader suitability recommendation.
    relative_choice = None
    # An unresolved stage/medication-dependent rule prevents a safety claim, but
    # it does not erase a clear like-for-like comparison for other direct rules.
    # Missing disease identities or missing rule sets still block this guidance.
    if comparable and all(group["status"] == "rules_found" for group in disease_groups):
        disease_directions = {
            nutrient: next(iter(direction))
            for nutrient, direction in directions.items()
            if len(direction) == 1 and direction <= {"increase", "decrease"} and nutrient in relative
        }
        if disease_directions:
            scores = {
                dish.dish_name: sum(
                    relative[nutrient][dish.dish_name] == ("higher" if direction == "increase" else "lower")
                    for nutrient, direction in disease_directions.items()
                )
                for dish in dishes
            }
            ranked_choices = sorted(scores.items(), key=lambda item: item[1], reverse=True)
            if len(ranked_choices) > 1 and ranked_choices[0][1] > ranked_choices[1][1]:
                relative_choice = {
                    "dish_name": ranked_choices[0][0],
                    "nutrients": [
                        nutrient for nutrient, direction in disease_directions.items()
                        if relative[nutrient][ranked_choices[0][0]]
                        == ("higher" if direction == "increase" else "lower")
                    ],
                }
    return {"facts": facts, "required_ids": required_ids, "preferred_dish": preferred,
            "decision_reason": decision_reason, "unresolved_medical_context": unresolved,
            "disease_status": [{"name": g["requested"], "status": g["status"]} for g in disease_groups],
            "rules_evaluated": len(assessments), "relative_comparisons": relative,
            "relative_choice": relative_choice,
            "unequal_disease_coverage": unequal_coverage,
            "priority": ["disease", "goal", "nutrition_comparison", "recent_records"],
            "limitations": "資料為參考食譜，未確認店家實際食材、烹調與份量；不據此宣稱治療、每日達標或疾病安全"}
