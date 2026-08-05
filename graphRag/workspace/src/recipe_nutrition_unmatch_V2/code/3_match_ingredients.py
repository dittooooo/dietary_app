import json
import os
import difflib
from typing import List, Dict, Optional

def get_shortest_name_info(candidates: List[Dict]) -> Optional[Dict[str, str]]:
    """Heuristic: Choose the candidate with the shortest formal name (most generic)."""
    if not candidates:
        return None
    # Sort by length of '樣品名稱'
    sorted_candidates = sorted(candidates, key=lambda x: len(x['樣品名稱']))
    best = sorted_candidates[0]
    return {
        "db_id": best['整合編號'],
        "db_name": best['樣品名稱']
    }

def main():
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    recipes_file = os.path.join(base_dir, 'data', 'input', 'recipes.json')
    # Use the enriched database from output
    nutrition_file = os.path.join(base_dir, 'data', 'output', 'nutrition_enriched.json')
    output_file = os.path.join(base_dir, 'data', 'output', 'recipes_with_ids.json')

    # Fallback to the non-enriched one if enriched doesn't exist yet
    if not os.path.exists(nutrition_file):
        print(f"Warning: Enriched nutrition data not found at {nutrition_file}. Falling back to categorized data.")
        nutrition_file = os.path.join(base_dir, 'data', 'output', 'nutrition_data_categorized.json')

    if not os.path.exists(recipes_file) or not os.path.exists(nutrition_file):
        print("Error: Input files missing.")
        return

    # Load data
    print(f"Loading recipes from {recipes_file}...")
    with open(recipes_file, 'r', encoding='utf-8') as f:
        recipes = json.load(f)

    print(f"Loading nutrition data from {nutrition_file}...")
    with open(nutrition_file, 'r', encoding='utf-8') as f:
        nutrition_data = json.load(f)

    # 1. Build lookup maps
    # name_to_items maps any name (formal or alias) to a list of nutrition item objects
    name_to_items = {}
    all_known_names = []

    for category in nutrition_data:
        for item in nutrition_data[category]:
            formal_name = item['樣品名稱']
            aliases = [a.strip() for a in (item.get('俗名') or "").split(',') if a.strip()]
            
            all_names = set([formal_name] + aliases)
            for name in all_names:
                if name not in name_to_items:
                    name_to_items[name] = []
                    all_known_names.append(name)
                name_to_items[name].append(item)

    print(f"Indexed {len(all_known_names)} unique names from nutrition database.")

    # 2. Process matching
    stats = {"exact": 0, "fuzzy": 0, "none": 0}
    
    # Cache unique ingredient names to avoid redundant matching
    unique_ingredient_names = set()
    for recipe in recipes:
        for ing in recipe.get('ingredients', []):
            unique_ingredient_names.add(ing['name'])
    
    print(f"Matching {len(unique_ingredient_names)} unique ingredient names...")
    
    name_mapping = {} # maps recipe_ing_name -> db_id
    
    for ing_name in unique_ingredient_names:
        # Phase A: Exact Match
        if ing_name in name_to_items:
            name_mapping[ing_name] = get_shortest_name_info(name_to_items[ing_name])
            stats["exact"] += 1
            continue
            
        # Phase B: Fuzzy Match (difflib)
        matches = difflib.get_close_matches(ing_name, all_known_names, n=1, cutoff=0.95)
        if matches:
            best_name = matches[0]
            name_mapping[ing_name] = get_shortest_name_info(name_to_items[best_name])
            stats["fuzzy"] += 1
        else:
            name_mapping[ing_name] = None
            stats["none"] += 1

    # 3. Apply mapping to recipes
    print("Updating recipes with DB IDs and Names...")
    for recipe in recipes:
        for ing in recipe.get('ingredients', []):
            info = name_mapping.get(ing['name'])
            if info:
                ing['db_id'] = info['db_id']
                ing['樣品名稱'] = info['db_name']
            else:
                ing['db_id'] = None
                ing['樣品名稱'] = None

    # 4. Save results
    print(f"Saving results to {output_file}...")
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(recipes, f, ensure_ascii=False, indent=2)

    print("\nMatching Summary:")
    print(f" - Exact Matches: {stats['exact']}")
    print(f" - Fuzzy Matches (>= 0.95): {stats['fuzzy']}")
    print(f" - Unmatched: {stats['none']}")
    print(f"Success! Output at {output_file}")

if __name__ == "__main__":
    main()
