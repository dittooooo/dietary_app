// query_examples_V6_1.cypher
// 適用版本：kg_builder_V6_1.py
// 目前已寫入 Dish：義式千層麵、洋蔥鱸魚豆腐湯
//
// 使用方式：
// 1. 在 Neo4j Browser 中逐段貼上執行
// 2. 或用 :play / 複製需要的查詢
//
// 注意：
// - 主展示鏈建議優先使用「只查單一路徑」的查詢
// - 若畫面太亂，先不要同時查 Source / Disease
// - 目前 Dish 主鍵是 recipe_id，但平常展示可先用 name 查


// ============================================================
// A. 基本檢查
// ============================================================

// A1. 查看目前有哪些 Dish
MATCH (d:Dish)
RETURN d.recipe_id AS recipe_id, d.name AS dish_name, d.servings AS servings
ORDER BY dish_name;

// A2. 查看目前有哪些 Ingredient
MATCH (i:Ingredient)
RETURN i.name AS ingredient_name
ORDER BY ingredient_name;

// A3. 查看目前有哪些 FoodItem
MATCH (f:FoodItem)
RETURN f.name AS fooditem_name, f.nutrition_sample_name AS matched_sample_name, f.nutrition_match_by AS matched_by
ORDER BY fooditem_name;

// A4. 查看目前有哪些 Nutrient
MATCH (n:Nutrient)
RETURN n.name AS nutrient_name
ORDER BY nutrient_name;

// A5. 查看目前有哪些 Biomarker
MATCH (b:Biomarker)
RETURN b.name AS biomarker_name
ORDER BY biomarker_name;

// A6. 查看目前有哪些 Disease
MATCH (d:Disease)
RETURN d.name AS disease_name, d.description AS description
ORDER BY disease_name;


// ============================================================
// B. Dish -> Ingredient
// ============================================================

// B1. 查看「義式千層麵」有哪些 Ingredient
MATCH (d:Dish {name: "義式千層麵"})-[r:CONTAINS]->(i:Ingredient)
RETURN d.name AS dish, i.name AS ingredient, r.amount AS amount, r.unit AS unit, r.name_raw AS name_raw
ORDER BY ingredient;

// B2. 查看「洋蔥鱸魚豆腐湯」有哪些 Ingredient
MATCH (d:Dish {name: "洋蔥鱸魚豆腐湯"})-[r:CONTAINS]->(i:Ingredient)
RETURN d.name AS dish, i.name AS ingredient, r.amount AS amount, r.unit AS unit, r.name_raw AS name_raw
ORDER BY ingredient;

// B3. 顯示 Dish -> Ingredient 路徑（義式千層麵）
MATCH p =
(d:Dish {name: "義式千層麵"})
-[:CONTAINS]->
(i:Ingredient)
RETURN p;

// B4. 顯示 Dish -> Ingredient 路徑（洋蔥鱸魚豆腐湯）
MATCH p =
(d:Dish {name: "洋蔥鱸魚豆腐湯"})
-[:CONTAINS]->
(i:Ingredient)
RETURN p;


// ============================================================
// C. Dish -> Ingredient -> FoodItem
// ============================================================

// C1. 義式千層麵：Ingredient 對應到哪個 FoodItem
MATCH
(d:Dish {name: "義式千層麵"})
-[:CONTAINS]->
(i:Ingredient)
-[:MAP_TO]->
(f:FoodItem)
RETURN d.name AS dish, i.name AS ingredient, f.name AS fooditem
ORDER BY ingredient;

// C2. 洋蔥鱸魚豆腐湯：Ingredient 對應到哪個 FoodItem
MATCH
(d:Dish {name: "洋蔥鱸魚豆腐湯"})
-[:CONTAINS]->
(i:Ingredient)
-[:MAP_TO]->
(f:FoodItem)
RETURN d.name AS dish, i.name AS ingredient, f.name AS fooditem
ORDER BY ingredient;

// C3. 義式千層麵：顯示 Dish -> Ingredient -> FoodItem 路徑
MATCH p =
(d:Dish {name: "義式千層麵"})
-[:CONTAINS]->
(i:Ingredient)
-[:MAP_TO]->
(f:FoodItem)
RETURN p;

// C4. 洋蔥鱸魚豆腐湯：顯示 Dish -> Ingredient -> FoodItem 路徑
MATCH p =
(d:Dish {name: "洋蔥鱸魚豆腐湯"})
-[:CONTAINS]->
(i:Ingredient)
-[:MAP_TO]->
(f:FoodItem)
RETURN p;


// ============================================================
// D. Dish -> Ingredient -> FoodItem -> Nutrient
// ============================================================

// D1. 義式千層麵：看完整營養節點
MATCH
(d:Dish {name: "義式千層麵"})
-[:CONTAINS]->
(i:Ingredient)
-[:MAP_TO]->
(f:FoodItem)
-[r:HAS_NUTRIENT]->
(n:Nutrient)
RETURN d.name AS dish, i.name AS ingredient, f.name AS fooditem, n.name AS nutrient, r.amount AS amount, r.unit AS unit
ORDER BY ingredient, nutrient;

// D2. 洋蔥鱸魚豆腐湯：看完整營養節點
MATCH
(d:Dish {name: "洋蔥鱸魚豆腐湯"})
-[:CONTAINS]->
(i:Ingredient)
-[:MAP_TO]->
(f:FoodItem)
-[r:HAS_NUTRIENT]->
(n:Nutrient)
RETURN d.name AS dish, i.name AS ingredient, f.name AS fooditem, n.name AS nutrient, r.amount AS amount, r.unit AS unit
ORDER BY ingredient, nutrient;

// D3. 義式千層麵：只看核心營養（熱量、蛋白質、脂肪、飽和脂肪、鈉、糖）
MATCH
(d:Dish {name: "義式千層麵"})
-[:CONTAINS]->
(i:Ingredient)
-[:MAP_TO]->
(f:FoodItem)
-[r:HAS_NUTRIENT]->
(n:Nutrient)
WHERE n.name IN ["熱量", "蛋白質", "脂肪", "飽和脂肪", "鈉", "糖"]
RETURN d.name AS dish, i.name AS ingredient, f.name AS fooditem, n.name AS nutrient, r.amount AS amount, r.unit AS unit
ORDER BY ingredient, nutrient;

// D4. 洋蔥鱸魚豆腐湯：只看核心營養
MATCH
(d:Dish {name: "洋蔥鱸魚豆腐湯"})
-[:CONTAINS]->
(i:Ingredient)
-[:MAP_TO]->
(f:FoodItem)
-[r:HAS_NUTRIENT]->
(n:Nutrient)
WHERE n.name IN ["熱量", "蛋白質", "脂肪", "飽和脂肪", "鈉", "糖"]
RETURN d.name AS dish, i.name AS ingredient, f.name AS fooditem, n.name AS nutrient, r.amount AS amount, r.unit AS unit
ORDER BY ingredient, nutrient;

// D5. 義式千層麵：顯示 Dish -> Ingredient -> FoodItem -> Nutrient 路徑
MATCH p =
(d:Dish {name: "義式千層麵"})
-[:CONTAINS]->
(i:Ingredient)
-[:MAP_TO]->
(f:FoodItem)
-[:HAS_NUTRIENT]->
(n:Nutrient)
RETURN p;

// D6. 洋蔥鱸魚豆腐湯：顯示 Dish -> Ingredient -> FoodItem -> Nutrient 路徑
MATCH p =
(d:Dish {name: "洋蔥鱸魚豆腐湯"})
-[:CONTAINS]->
(i:Ingredient)
-[:MAP_TO]->
(f:FoodItem)
-[:HAS_NUTRIENT]->
(n:Nutrient)
RETURN p;


// ============================================================
// E. 你最想看的主展示鏈：Dish -> Ingredient -> Nutrient -> Biomarker
// ============================================================
//
// 說明：
// - 這組查詢故意不把 Source / Disease 拉進來，畫面會比較乾淨
// - 若不想看到 FoodItem，可用 RETURN d, i, n, b

// E1. 義式千層麵：主展示鏈（含 FoodItem）
MATCH
(d:Dish {name: "義式千層麵"})
-[:CONTAINS]->
(i:Ingredient)
-[:MAP_TO]->
(f:FoodItem)
-[:HAS_NUTRIENT]->
(n:Nutrient)
-[:AFFECTS_BIOMARKER]->
(b:Biomarker)
RETURN d, i, f, n, b;

// E2. 洋蔥鱸魚豆腐湯：主展示鏈（含 FoodItem）
MATCH
(d:Dish {name: "洋蔥鱸魚豆腐湯"})
-[:CONTAINS]->
(i:Ingredient)
-[:MAP_TO]->
(f:FoodItem)
-[:HAS_NUTRIENT]->
(n:Nutrient)
-[:AFFECTS_BIOMARKER]->
(b:Biomarker)
RETURN d, i, f, n, b;

// E3. 義式千層麵：主展示鏈（不顯示 FoodItem）
MATCH
(d:Dish {name: "義式千層麵"})
-[:CONTAINS]->
(i:Ingredient)
-[:MAP_TO]->
(:FoodItem)
-[:HAS_NUTRIENT]->
(n:Nutrient)
-[:AFFECTS_BIOMARKER]->
(b:Biomarker)
RETURN d, i, n, b;

// E4. 洋蔥鱸魚豆腐湯：主展示鏈（不顯示 FoodItem）
MATCH
(d:Dish {name: "洋蔥鱸魚豆腐湯"})
-[:CONTAINS]->
(i:Ingredient)
-[:MAP_TO]->
(:FoodItem)
-[:HAS_NUTRIENT]->
(n:Nutrient)
-[:AFFECTS_BIOMARKER]->
(b:Biomarker)
RETURN d, i, n, b;

// E5. 義式千層麵：單一路徑版本（最適合 Graph 視圖）
MATCH p =
(d:Dish {name: "義式千層麵"})
-[:CONTAINS]->
(i:Ingredient)
-[:MAP_TO]->
(f:FoodItem)
-[:HAS_NUTRIENT]->
(n:Nutrient)
-[:AFFECTS_BIOMARKER]->
(b:Biomarker)
RETURN p;

// E6. 洋蔥鱸魚豆腐湯：單一路徑版本（最適合 Graph 視圖）
MATCH p =
(d:Dish {name: "洋蔥鱸魚豆腐湯"})
-[:CONTAINS]->
(i:Ingredient)
-[:MAP_TO]->
(f:FoodItem)
-[:HAS_NUTRIENT]->
(n:Nutrient)
-[:AFFECTS_BIOMARKER]->
(b:Biomarker)
RETURN p;


// ============================================================
// F. Nutrient -> Biomarker
// ============================================================

// F1. 查看目前哪些 Nutrient 會影響哪些 Biomarker
MATCH (n:Nutrient)-[r:AFFECTS_BIOMARKER]->(b:Biomarker)
RETURN n.name AS nutrient, b.name AS biomarker, r.relation AS relation, r.effect AS effect
ORDER BY nutrient, biomarker;

// F2. 只看核心營養對 Biomarker 的影響
MATCH (n:Nutrient)-[r:AFFECTS_BIOMARKER]->(b:Biomarker)
WHERE n.name IN ["熱量", "蛋白質", "脂肪", "飽和脂肪", "鈉", "糖"]
RETURN n.name AS nutrient, b.name AS biomarker, r.relation AS relation, r.effect AS effect
ORDER BY nutrient, biomarker;

// F3. 顯示 Nutrient -> Biomarker 路徑
MATCH p =
(n:Nutrient)-[:AFFECTS_BIOMARKER]->(b:Biomarker)
RETURN p;


// ============================================================
// G. Disease 規則層（文字/表格用途）
// ============================================================

// G1. 查看所有 Disease -> Nutrient 飲食規則
MATCH (d:Disease)-[r:HAS_DIET_RULE]->(n:Nutrient)
RETURN d.name AS disease, n.name AS nutrient, r.rule_type AS rule_type, r.min_value AS min_value, r.max_value AS max_value, r.unit AS unit, r.label AS label, r.note AS note
ORDER BY disease, nutrient;

// G2. 查看某疾病，例如高血壓的飲食規則
MATCH (d:Disease {name: "高血壓"})-[r:HAS_DIET_RULE]->(n:Nutrient)
RETURN d.name AS disease, n.name AS nutrient, r.rule_type AS rule_type, r.min_value AS min_value, r.max_value AS max_value, r.unit AS unit, r.label AS label, r.note AS note
ORDER BY nutrient;

// G3. 查看 Disease -> Biomarker
MATCH (d:Disease)-[:AFFECTS]->(b:Biomarker)
RETURN d.name AS disease, b.name AS biomarker
ORDER BY disease, biomarker;

// G4. 查看 Disease -> Biomarker -> Nutrient 的規則背景鏈
MATCH (d:Disease)-[:AFFECTS]->(b:Biomarker)<-[:AFFECTS_BIOMARKER]-(n:Nutrient)
RETURN d.name AS disease, b.name AS biomarker, n.name AS nutrient
ORDER BY disease, biomarker, nutrient;


// ============================================================
// H. Dish 接到 Disease 背景鏈（展示時通常不建議一次拉太多）
// ============================================================

// H1. 義式千層麵：Dish -> Ingredient -> Nutrient -> Biomarker -> Disease
MATCH
(d:Dish {name: "義式千層麵"})
-[:CONTAINS]->
(i:Ingredient)
-[:MAP_TO]->
(:FoodItem)
-[:HAS_NUTRIENT]->
(n:Nutrient)
-[:AFFECTS_BIOMARKER]->
(b:Biomarker)
<-[:AFFECTS]-
(dis:Disease)
RETURN d, i, n, b, dis;

// H2. 洋蔥鱸魚豆腐湯：Dish -> Ingredient -> Nutrient -> Biomarker -> Disease
MATCH
(d:Dish {name: "洋蔥鱸魚豆腐湯"})
-[:CONTAINS]->
(i:Ingredient)
-[:MAP_TO]->
(:FoodItem)
-[:HAS_NUTRIENT]->
(n:Nutrient)
-[:AFFECTS_BIOMARKER]->
(b:Biomarker)
<-[:AFFECTS]-
(dis:Disease)
RETURN d, i, n, b, dis;

// H3. 義式千層麵：只看與高血壓有關的背景鏈
MATCH
(d:Dish {name: "義式千層麵"})
-[:CONTAINS]->
(i:Ingredient)
-[:MAP_TO]->
(:FoodItem)
-[:HAS_NUTRIENT]->
(n:Nutrient)
-[:AFFECTS_BIOMARKER]->
(b:Biomarker)
<-[:AFFECTS]-
(dis:Disease {name: "高血壓"})
RETURN d, i, n, b, dis;

// H4. 洋蔥鱸魚豆腐湯：只看與腎臟病有關的背景鏈
MATCH
(d:Dish {name: "洋蔥鱸魚豆腐湯"})
-[:CONTAINS]->
(i:Ingredient)
-[:MAP_TO]->
(:FoodItem)
-[:HAS_NUTRIENT]->
(n:Nutrient)
-[:AFFECTS_BIOMARKER]->
(b:Biomarker)
<-[:AFFECTS]-
(dis:Disease {name: "腎臟病"})
RETURN d, i, n, b, dis;


// ============================================================
// I. 來源資料檢查（除錯用，不建議主展示使用）
// ============================================================

// I1. 查看 Dish 的來源
MATCH (d:Dish)-[:EXTRACTED_FROM]->(s:Source)
RETURN d.name AS dish, s.name AS source_name, s.type AS source_type
ORDER BY dish;

// I2. 查看 Ingredient mapping 來源
MATCH (i:Ingredient)-[:MAPPED_FROM]->(s:Source)
RETURN i.name AS ingredient, s.name AS source_name, s.type AS source_type
ORDER BY ingredient;

// I3. 查看 FoodItem nutrition 來源
MATCH (f:FoodItem)-[:DERIVED_FROM]->(s:Source)
RETURN f.name AS fooditem, s.name AS source_name, s.type AS source_type
ORDER BY fooditem;


// ============================================================
// J. 常用除錯查詢
// ============================================================

// J1. 找出沒有對到 Nutrition 的 FoodItem
MATCH (f:FoodItem)
WHERE NOT (f)-[:HAS_NUTRIENT]->(:Nutrient)
RETURN f.name AS fooditem_without_nutrition
ORDER BY fooditem_without_nutrition;

// J2. 找出沒有接到 Biomarker 的 Nutrient
MATCH (n:Nutrient)
WHERE NOT (n)-[:AFFECTS_BIOMARKER]->(:Biomarker)
RETURN n.name AS nutrient_without_biomarker
ORDER BY nutrient_without_biomarker;

// J3. 找出沒有 Ingredient 的 Dish
MATCH (d:Dish)
WHERE NOT (d)-[:CONTAINS]->(:Ingredient)
RETURN d.recipe_id AS recipe_id, d.name AS dish_without_ingredient;

// J4. 找出沒有 FoodItem mapping 的 Ingredient
MATCH (i:Ingredient)
WHERE NOT (i)-[:MAP_TO]->(:FoodItem)
RETURN i.name AS ingredient_without_fooditem
ORDER BY ingredient_without_fooditem;


// ============================================================
// K. 清理 / 重跑時可能用到
// ============================================================

// K1. 刪除所有資料（危險，慎用）
// MATCH (n) DETACH DELETE n;

// K2. 只刪除 Disease / Biomarker / 規則層
// MATCH (d:Disease) DETACH DELETE d;
// MATCH (b:Biomarker) DETACH DELETE b;

// K3. 只刪除 Dish / Ingredient / FoodItem / Nutrient 層
// MATCH (d:Dish) DETACH DELETE d;
// MATCH (i:Ingredient) DETACH DELETE i;
// MATCH (f:FoodItem) DETACH DELETE f;
// MATCH (n:Nutrient) DETACH DELETE n;
