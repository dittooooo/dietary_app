# Current Neo4j Schema

Snapshot read from the connected Neo4j database on 2026-08-23. This document describes the current database state; it is not a proposed redesign.

## Node Counts

| Label | Count |
|---|---:|
| `Disease` | 10 |
| `Dish` | 2,050 |
| `FoodItem` | 2,383 |
| `Ingredient` | 2,925 |
| `Nutrition` | 104 |
| `Biomarker` | 0 |

## Relationship Counts

| Relationship | From | To | Count |
|---|---|---|---:|
| `CONTAINS` | `Dish` | `Ingredient` | 15,915 |
| `MAPS_TO` | `Ingredient` | `FoodItem` | 2,925 |
| `HAS_NUTRITION` | `FoodItem` | `Nutrition` | 170,774 |
| `HAS_DIET_RULE` | `Disease` | `Nutrition` | 71 |

## Node Properties

The following properties were observed in the database. Properties marked as unique are backed by a Neo4j uniqueness constraint.

### `Dish`

- `recipe_id`: string, unique
- `name`: string
- `servings`: string
- `ingredient_count`: integer

### `Ingredient`

- `name`: string, unique
- `matched_food_id`: string, required mapping key; corresponds to `FoodItem.food_id`
- `matched_food_name`: string
- `original_name`: string

### `FoodItem`

- `food_id`: string, unique
- `name`: string
- `category`: string
- `source`: string
- `description`: string
- `alias`: string
- `aliases`: string

### `Nutrition`

- `nutrition_id`: string, unique
- `name`: string, unique
- `name_zh`: string
- `name_en`: string
- `unit`: string
- `category`: string
- `source_column`: string
- `is_core`: boolean-like property used by an index

### `Disease`

- `disease_id`: string, unique
- `name`: string, unique
- `name_en`: string
- `source`: string
- `diet_pattern`: string
- `risk_notes`: string
- `updated_by_version`: string

## Relationship Properties

### `CONTAINS`

Used as `(:Dish)-[:CONTAINS]->(:Ingredient)`.

- `matched_food_id`: string
- `matched_food_name`: string
- `original_name`: string
- `amount_raw`: string
- `amount`: float
- `amount_value`: float
- `unit`: string
- `amount_unit`: string
- `amount_note`: string
- `amount_per_serving`: float
- `order`: integer

### `MAPS_TO`

Used as `(:Ingredient)-[:MAPS_TO]->(:FoodItem)`.

Mapping rules:

- Each `Ingredient` must have exactly one outgoing `MAPS_TO` relationship.
- The target `FoodItem.food_id` must equal `Ingredient.matched_food_id`.
- Multiple `Ingredient` nodes may map to the same `FoodItem`.
- `Ingredient.matched_food_id` is the source of truth; `CONTAINS.matched_food_id` must not define a different mapping.

Neo4j does not enforce relationship cardinality with a standard uniqueness constraint. The importer or update transaction must remove any previous `MAPS_TO` relationship before creating the new one, and must update `Ingredient.matched_food_id` in the same transaction.

### `HAS_NUTRITION`

Used as `(:FoodItem)-[:HAS_NUTRITION]->(:Nutrition)`.

- `amount_per_100g`: float
- `value_per_100g`: float
- `unit`: string
- `basis`: string
- `source_column`: string

### `HAS_DIET_RULE`

Used as `(:Disease)-[:HAS_DIET_RULE]->(:Nutrition)`.

- `rule_type`: string
- `relation`: string
- `direction`: string
- `reason`: string
- `note`: string
- `target_note`: string
- `food_level`: string
- `food_level_condition`: string
- `food_level_note`: string
- `criteria_json`: string
- `food_level_rule_json`: string
- `example_foods_json`: string

## Constraints

The current database has these uniqueness constraints:

- `Dish.recipe_id`
- `Ingredient.name`
- `Ingredient.matched_food_id` must exist
- `Disease.name`
- `Disease.disease_id`
- `Nutrition.name`
- `Nutrition.nutrition_id`
- `FoodItem.food_id`

## User-Managed Indexes

- `Dish.name`
- `FoodItem.name`
- `Ingredient.matched_food_name`
- `Nutrition.category`
- `Nutrition.is_core`

Neo4j also has automatic node and relationship token lookup indexes.

## Important Design Notes

1. `Ingredient.name` is globally unique. The same ingredient node is reused across many dishes.
2. `Ingredient.matched_food_id` is the only mapping key from an Ingredient to a FoodItem.
3. Each Ingredient has exactly one `MAPS_TO` target, while multiple Ingredients may share the same FoodItem.
4. The `MAPS_TO` target must satisfy `FoodItem.food_id = Ingredient.matched_food_id`.
5. The one-to-one rule is an application-level invariant. It must be enforced by the importer or update transaction; the schema description alone cannot enforce it.
6. The current importer keeps all 2,383 unique FoodItems from `nutrition_data_categorized.json`. It skips recipe ingredients whose mapping ID is not present in that FoodItem source and reports them.


## Suggested Mapping-Aware Query

```cypher
MATCH (d:Dish)-[c:CONTAINS]->(i:Ingredient)
OPTIONAL MATCH (f:FoodItem {food_id: i.matched_food_id})
RETURN d.recipe_id AS recipe_id,
       d.name AS dish_name,
       i.name AS ingredient_name,
       c.amount_per_serving AS amount_per_serving,
       i.matched_food_id AS food_id,
       coalesce(f.name, i.matched_food_name) AS food_name
ORDER BY d.recipe_id, ingredient_name;
```

## Mapping Validation Query

Run this query after the data migration or whenever the mapping rules need to be audited. It returns only violations and does not modify data.

```cypher
MATCH (i:Ingredient)
OPTIONAL MATCH (i)-[m:MAPS_TO]->(f:FoodItem)
WITH i,
     count(m) AS map_count,
     collect(f.food_id) AS mapped_food_ids
WHERE map_count <> 1
   OR mapped_food_ids[0] <> i.matched_food_id
RETURN i.name AS ingredient_name,
       i.matched_food_id AS expected_food_id,
       map_count,
       mapped_food_ids
ORDER BY ingredient_name;
```
