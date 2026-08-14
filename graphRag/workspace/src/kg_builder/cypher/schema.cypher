// ===== Constraints =====
CREATE CONSTRAINT dish_name_unique IF NOT EXISTS
FOR (n:Dish) REQUIRE n.name IS UNIQUE;

CREATE CONSTRAINT ingredient_name_unique IF NOT EXISTS
FOR (n:Ingredient) REQUIRE n.name IS UNIQUE;

CREATE CONSTRAINT fooditem_name_unique IF NOT EXISTS
FOR (n:FoodItem) REQUIRE n.name IS UNIQUE;

CREATE CONSTRAINT nutrient_name_unique IF NOT EXISTS
FOR (n:Nutrient) REQUIRE n.name IS UNIQUE;

CREATE CONSTRAINT biomarker_name_unique IF NOT EXISTS
FOR (n:Biomarker) REQUIRE n.name IS UNIQUE;

CREATE CONSTRAINT disease_name_unique IF NOT EXISTS
FOR (n:Disease) REQUIRE n.name IS UNIQUE;

CREATE CONSTRAINT source_name_unique IF NOT EXISTS
FOR (n:Source) REQUIRE n.name IS UNIQUE;

// ===== Indexes =====
CREATE INDEX dish_alias_idx IF NOT EXISTS
FOR (n:Dish) ON (n.aliases);

CREATE INDEX ingredient_alias_idx IF NOT EXISTS
FOR (n:Ingredient) ON (n.aliases);