import os, json, pprint
from web_scraping import scrape_icook_recipe

def main():
    file = "recipe-data/recipes.json"
    for i in range(480000, 480007):
        url = "https://icook.tw/recipes/" + str(i)
        recipe = scrape_icook_recipe(url, i)

        if recipe is not None:
            if(os.path.exists(file)):
                with open(file, "r", encoding="utf-8") as f:
                    data = json.load(f)
            else:
                data = []
        
            data.append(recipe)
            pprint(data)
            with open(file, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
        else:
            print("食譜不存在: ", url)

main()