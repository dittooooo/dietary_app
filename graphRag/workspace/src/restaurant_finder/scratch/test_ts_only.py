from restaurant_finder_V3 import RestaurantFinder
from config import load_config
import time

def main():
    config = load_config()
    finder = RestaurantFinder(config)
    
    # Try just the first text search
    query = finder.text_search_templates[0]
    print(f"Testing primary query: {query}")
    try:
        results = finder._text_search(query=query, max_pages=1)
        print(f"Success! Found {len(results)} restaurants on Page 1.")
        
        # Now try Page 2
        print(f"Testing Page 2 for same query...")
        results2 = finder._text_search(query=query, max_pages=2)
        print(f"Total results: {len(results2)}")
    except Exception as e:
        print(f"Failed: {e}")

if __name__ == "__main__":
    main()
