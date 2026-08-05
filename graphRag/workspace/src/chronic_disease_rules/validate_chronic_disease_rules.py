import json
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent
RULES_PATH = BASE_DIR / "chronic_disease_rules.json"
NUTRIENT_INDEX_PATH = BASE_DIR / "nutrient_rules_index.json"

EXPECTED_DISEASES = {
    "hypertension",
    "hyperlipidemia",
    "diabetes_mellitus",
    "cardiovascular_disease",
    "chronic_kidney_disease",
    "stroke",
    "metabolic_syndrome",
    "gout",
    "hyperuricemia",
    "gastroesophageal_reflux_disease",
}

RELATION_TYPES = {"recommend", "limit", "prohibit"}
TARGET_DIRECTIONS = {"increase", "decrease", "avoid", "replace", "maintain", "adjust_by_stage"}


def load_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def require(condition, message, errors):
    if not condition:
        errors.append(message)


def validate_rules(payload):
    errors = []
    diseases = payload.get("diseases", [])
    disease_ids = {disease.get("disease_id") for disease in diseases}

    require(disease_ids == EXPECTED_DISEASES, f"disease ids mismatch: {sorted(disease_ids)}", errors)
    require(len(diseases) == 10, f"expected 10 diseases, got {len(diseases)}", errors)
    require(payload.get("metadata", {}).get("relation_types") == ["recommend", "limit", "prohibit"], "metadata relation_types must be fixed order", errors)

    for disease in diseases:
        disease_id = disease.get("disease_id")
        relations = disease.get("disease_nutrient_relations", [])
        require(relations, f"{disease_id} has no disease_nutrient_relations", errors)

        seen = set()
        for index, relation in enumerate(relations):
            label = f"{disease_id}.disease_nutrient_relations[{index}]"
            relation_type = relation.get("relation")
            nutrient_en = relation.get("nutrient_name_en")
            key = (relation_type, nutrient_en)

            require(relation_type in RELATION_TYPES, f"{label} invalid relation: {relation_type}", errors)
            require(nutrient_en, f"{label} missing nutrient_name_en", errors)
            require(relation.get("nutrient_name_zh"), f"{label} missing nutrient_name_zh", errors)
            require(relation.get("reason"), f"{label} missing reason", errors)
            require(key not in seen, f"{disease_id} duplicated relation/nutrient: {key}", errors)
            seen.add(key)

            target_rule = relation.get("target_rule") or {}
            require(target_rule.get("direction") in TARGET_DIRECTIONS, f"{label} invalid target_rule.direction: {target_rule.get('direction')}", errors)

            food_rule = relation.get("food_level_rule") or {}
            require(food_rule.get("basis") == "per_100g", f"{label} food_level_rule.basis must be per_100g", errors)
            require(isinstance(relation.get("example_foods"), list), f"{label} example_foods must be a list", errors)
            require(isinstance(relation.get("sources"), list) and relation.get("sources"), f"{label} sources must be a non-empty list", errors)

    return errors


def validate_nutrient_index(payload, nutrient_index):
    errors = []
    relation_nutrients = {
        relation["nutrient_name_en"]
        for disease in payload.get("diseases", [])
        for relation in disease.get("disease_nutrient_relations", [])
    }
    indexed_nutrients = {item.get("nutrient_name_en") for item in nutrient_index.get("nutrients", [])}

    require(relation_nutrients == indexed_nutrients, "nutrient index does not match nutrients used by disease rules", errors)
    for item in nutrient_index.get("nutrients", []):
        require(item.get("related_diseases"), f"{item.get('nutrient_id')} has no related diseases", errors)
        for related in item.get("related_diseases", []):
            require(related.get("disease_id") in EXPECTED_DISEASES, f"{item.get('nutrient_id')} has unexpected disease {related.get('disease_id')}", errors)
            require(related.get("relation") in RELATION_TYPES, f"{item.get('nutrient_id')} has invalid relation {related.get('relation')}", errors)

    return errors


def main():
    rules = load_json(RULES_PATH)
    nutrient_index = load_json(NUTRIENT_INDEX_PATH)

    errors = []
    errors.extend(validate_rules(rules))
    errors.extend(validate_nutrient_index(rules, nutrient_index))

    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        raise SystemExit(1)

    print("validation passed")


if __name__ == "__main__":
    main()
