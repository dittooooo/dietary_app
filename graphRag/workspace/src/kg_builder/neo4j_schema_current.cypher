/*
 * Editable Neo4j schema baseline.
 *
 * Snapshot source: the connected Neo4j database, 2026-08-23.
 * This file creates only constraints and user-managed indexes.
 * Existing constraints and indexes are left unchanged by IF NOT EXISTS.
 * Neo4j relationship endpoint types are documented below because Neo4j does
 * not enforce a complete relational schema for relationship endpoints.
 */

// -------------------------------------------------------------------------
// Node uniqueness constraints
// -------------------------------------------------------------------------

CREATE CONSTRAINT dish_recipe_id_unique IF NOT EXISTS
FOR (n:Dish) REQUIRE n.recipe_id IS UNIQUE;

CREATE CONSTRAINT ingredient_name_unique IF NOT EXISTS
FOR (n:Ingredient) REQUIRE n.name IS UNIQUE;

CREATE CONSTRAINT ingredient_matched_food_id_required IF NOT EXISTS
FOR (n:Ingredient) REQUIRE n.matched_food_id IS NOT NULL;

CREATE CONSTRAINT ingredient_matched_food_id_required IF NOT EXISTS
FOR (n:Ingredient) REQUIRE n.matched_food_id IS NOT NULL;

CREATE CONSTRAINT disease_name_unique IF NOT EXISTS
FOR (n:Disease) REQUIRE n.name IS UNIQUE;

CREATE CONSTRAINT disease_id_unique IF NOT EXISTS
FOR (n:Disease) REQUIRE n.disease_id IS UNIQUE;

CREATE CONSTRAINT nutrition_name_unique IF NOT EXISTS
FOR (n:Nutrition) REQUIRE n.name IS UNIQUE;

CREATE CONSTRAINT nutrition_id_unique IF NOT EXISTS
FOR (n:Nutrition) REQUIRE n.nutrition_id IS UNIQUE;

CREATE CONSTRAINT fooditem_food_id_unique IF NOT EXISTS
FOR (n:FoodItem) REQUIRE n.food_id IS UNIQUE;

// -------------------------------------------------------------------------
// User-managed range indexes
// -------------------------------------------------------------------------

CREATE RANGE INDEX dish_name_index IF NOT EXISTS
FOR (n:Dish) ON (n.name);

CREATE RANGE INDEX fooditem_name_index IF NOT EXISTS
FOR (n:FoodItem) ON (n.name);

CREATE RANGE INDEX ingredient_matched_food_name_index IF NOT EXISTS
FOR (n:Ingredient) ON (n.matched_food_name);

CREATE RANGE INDEX nutrition_category_index IF NOT EXISTS
FOR (n:Nutrition) ON (n.category);

CREATE RANGE INDEX nutrition_is_core_index IF NOT EXISTS
FOR (n:Nutrition) ON (n.is_core);

// Neo4j also maintains NODE and RELATIONSHIP token lookup indexes.
// They are system indexes and normally should not be recreated manually.

// -------------------------------------------------------------------------
// Logical graph schema
// -------------------------------------------------------------------------
// (:Dish)-[:CONTAINS]->(:Ingredient)
// (:Ingredient)-[:MAPS_TO]->(:FoodItem)
// (:FoodItem)-[:HAS_NUTRITION]->(:Nutrition)
// (:Disease)-[:HAS_DIET_RULE]->(:Nutrition)

// -------------------------------------------------------------------------
// Optional verification queries
// -------------------------------------------------------------------------

// SHOW CONSTRAINTS;
// SHOW INDEXES;
// MATCH (n) UNWIND labels(n) AS label
// RETURN label, count(*) AS node_count ORDER BY label;
// MATCH ()-[r]->()
// RETURN type(r) AS relationship_type, count(*) AS relationship_count
// ORDER BY relationship_type;

// Check for an Ingredient that maps to multiple FoodItems.
// MATCH (i:Ingredient)-[:MAPS_TO]->(f:FoodItem)
// WITH i, collect(f.food_id) AS food_ids
// WHERE size(food_ids) > 1
// RETURN i.name AS ingredient_name, food_ids
// ORDER BY size(food_ids) DESC;
