import json
import os
from collections import defaultdict

def organize_nutrition_by_category():
    # Define paths
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    input_file = os.path.join(base_dir, 'data', 'input', 'nutrition_data.json')
    output_dir = os.path.join(base_dir, 'data', 'output')
    output_file = os.path.join(output_dir, 'nutrition_data_categorized.json')

    # Create output directory if it doesn't exist
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
        print(f"Created directory: {output_dir}")

    # Load nutrition data
    print(f"Loading data from {input_file}...")
    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except FileNotFoundError:
        print(f"Error: {input_file} not found.")
        return
    except json.JSONDecodeError:
        print(f"Error: Failed to decode JSON from {input_file}.")
        return

    # Group data by category
    categorized_data = defaultdict(list)
    print("Categorizing ingredients...")
    
    for item in data:
        category = item.get('食品分類', '未分類')
        categorized_data[category].append(item)

    # Sort categories for cleaner output
    sorted_categories = dict(sorted(categorized_data.items()))

    # Log statistics
    print(f"Found {len(sorted_categories)} categories.")
    for category, items in sorted_categories.items():
        print(f" - {category}: {len(items)} items")

    # Save organized data
    print(f"Saving categorized data to {output_file}...")
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(sorted_categories, f, indent=2, ensure_ascii=False)

    print("Success!")

if __name__ == "__main__":
    organize_nutrition_by_category()
