// // https://chatgpt.com/share/69da41c5-2924-83a7-911f-1c0853c85e40

// // ===== Sources =====
// MERGE (:Source {name: "食譜網站", type: "recipe"});
// MERGE (:Source {name: "台灣食品營養成分資料庫", type: "nutrition_db"});
// MERGE (:Source {name: "慢性病飲食手冊", type: "guideline"});

// // ===== Diseases / Biomarkers =====
// MERGE (d1:Disease {name: "糖尿病"});
// MERGE (d2:Disease {name: "高血壓"});
// MERGE (d3:Disease {name: "高血脂"});

// MERGE (b1:Biomarker {name: "血糖"});
// MERGE (b2:Biomarker {name: "血壓"});
// MERGE (b3:Biomarker {name: "血脂"});

// MERGE (b1)-[:ASSOCIATED_WITH]->(d1);
// MERGE (b2)-[:ASSOCIATED_WITH]->(d2);
// MERGE (b3)-[:ASSOCIATED_WITH]->(d3);

// // ===== Nutrients =====
// MERGE (n1:Nutrient {name: "碳水化合物"});
// MERGE (n2:Nutrient {name: "脂肪"});
// MERGE (n3:Nutrient {name: "鈉"});
// MERGE (n4:Nutrient {name: "蛋白質"});

// MERGE (n1)-[:AFFECTS {effect: "increase"}]->(b1);
// MERGE (n2)-[:AFFECTS {effect: "increase"}]->(b3);
// MERGE (n3)-[:AFFECTS {effect: "increase"}]->(b2);

// // ===== Example dish =====
// MERGE (dish:Dish {name: "宮保雞丁"})
//   SET dish.aliases = ["宮保雞柳", "kung pao chicken"];

// MERGE (i1:Ingredient {name: "雞肉"}) SET i1.aliases = ["雞丁", "雞腿肉", "雞胸肉"];
// MERGE (i2:Ingredient {name: "辣椒"}) SET i2.aliases = ["乾辣椒"];
// MERGE (i3:Ingredient {name: "花生"}) SET i3.aliases = ["花生米"];
// MERGE (i4:Ingredient {name: "糖"})   SET i4.aliases = ["砂糖", "白糖"];
// MERGE (i5:Ingredient {name: "醬油"}) SET i5.aliases = ["醬汁"];

// MERGE (dish)-[:CONTAINS {amount: 150, unit: "g"}]->(i1);
// MERGE (dish)-[:CONTAINS {amount: 20, unit: "g"}]->(i2);
// MERGE (dish)-[:CONTAINS {amount: 15, unit: "g"}]->(i3);
// MERGE (dish)-[:CONTAINS {amount: 8, unit: "g"}]->(i4);
// MERGE (dish)-[:CONTAINS {amount: 12, unit: "g"}]->(i5);

// // ===== Food items =====
// MERGE (f1:FoodItem {name: "雞肉(去皮)"});
// MERGE (f2:FoodItem {name: "辣椒"});
// MERGE (f3:FoodItem {name: "花生"});
// MERGE (f4:FoodItem {name: "砂糖"});
// MERGE (f5:FoodItem {name: "醬油"});

// MERGE (i1)-[:MAP_TO {confidence: 0.95}]->(f1);
// MERGE (i2)-[:MAP_TO {confidence: 0.99}]->(f2);
// MERGE (i3)-[:MAP_TO {confidence: 0.99}]->(f3);
// MERGE (i4)-[:MAP_TO {confidence: 0.99}]->(f4);
// MERGE (i5)-[:MAP_TO {confidence: 0.95}]->(f5);

// // ===== Nutrient values =====
// MATCH (n1:Nutrient {name:"碳水化合物"}), (n2:Nutrient {name:"脂肪"}), (n3:Nutrient {name:"鈉"}), (n4:Nutrient {name:"蛋白質"})
// MATCH (f1:FoodItem {name:"雞肉(去皮)"}), (f2:FoodItem {name:"辣椒"}), (f3:FoodItem {name:"花生"}), (f4:FoodItem {name:"砂糖"}), (f5:FoodItem {name:"醬油"})
// MERGE (f1)-[:HAS_NUTRIENT {amount: 27.0, unit: "g/100g"}]->(n4)
// MERGE (f1)-[:HAS_NUTRIENT {amount: 8.0, unit: "g/100g"}]->(n2)

// MERGE (f3)-[:HAS_NUTRIENT {amount: 16.0, unit: "g/100g"}]->(n4)
// MERGE (f3)-[:HAS_NUTRIENT {amount: 49.0, unit: "g/100g"}]->(n2)

// MERGE (f4)-[:HAS_NUTRIENT {amount: 100.0, unit: "g/100g"}]->(n1)

// MERGE (f5)-[:HAS_NUTRIENT {amount: 5600.0, unit: "mg/100g"}]->(n3);

// // ===== Provenance =====
// MATCH (s1:Source {name:"食譜網站"}), (s2:Source {name:"台灣食品營養成分資料庫"}), (s3:Source {name:"慢性病飲食手冊"})
// MATCH (dish:Dish {name:"宮保雞丁"}), (f1:FoodItem {name:"雞肉(去皮)"}), (n3:Nutrient {name:"鈉"})
// MERGE (dish)-[:EXTRACTED_FROM]->(s1);
// MERGE (f1)-[:DERIVED_FROM]->(s2);
// MERGE (n3)-[:SUPPORTED_BY]->(s3);