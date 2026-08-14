import os, json
from pprint import pprint
from web_scraping import scrape_icook_recipe

def main():
    file = "recipe-data/recipes.json"
    recipe_count = 2041
    print("----------------START----------------")
    for i in range(485001, 485500):
        url = "https://icook.tw/recipes/" + str(i)
        recipe = scrape_icook_recipe(url, i)

        if recipe is not None:
            recipe_count += 1
            if(os.path.exists(file)):
                with open(file, "r", encoding="utf-8") as f:
                    data = json.load(f)
            else:
                data = []
        
            data.append(recipe)
            with open(file, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
            print("目前爬取到 ", recipe_count, " 筆食譜資料")
        else:
            print("食譜不存在: ", url)
        
    print("----------------END----------------")
    print("總共爬取到 ", recipe_count, " 筆食譜資料")
main()