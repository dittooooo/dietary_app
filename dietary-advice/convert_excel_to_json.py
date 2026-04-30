import pandas as pd
import json

def convert_ods_to_json(ods_file, json_file, sheet_name=0):
    df = pd.read_excel(ods_file, engine="odf", sheet_name=sheet_name, header=1)
    df = df.dropna(how="all")
    df.columns = [str(col).strip() for col in df.columns]

    data = df.to_dict(orient="records")

    for row in data:
        for key, value in row.items():
            if pd.isna(value):
                row[key] = None

    with open(json_file, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

convert_ods_to_json("recipe-data/nutritionDB.ods", "recipe-data/nutrition_data.json")