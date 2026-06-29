from __future__ import annotations

import argparse
import json
from typing import Any, Dict, List

try:
    from .knowledge_agent_importer import (
        NEO4J_PASSWORD,
        NEO4J_URI,
        NEO4J_USER,
        KnowledgeAgentImporter,
    )
except ImportError:
    from knowledge_agent_importer import (
        NEO4J_PASSWORD,
        NEO4J_URI,
        NEO4J_USER,
        KnowledgeAgentImporter,
    )


DELETE_BATCH_SIZE = 10000


class FoodItemNutritionSchemaMigrator(KnowledgeAgentImporter):
    """Move nutrition access to Ingredient -> FoodItem -> Nutrition."""

    def migrate(self, *, dry_run: bool = False) -> Dict[str, Any]:
        before = self.schema_counts()
        if dry_run:
            return {"dry_run": True, "before": before}

        self.create_schema()
        sources = self.load_sources()
        self.import_nutrition_components()
        self.import_food_items_and_nutrition(sources["food_rows"])
        maps_created = self.ensure_maps_to_from_matched_food_id()
        deleted_direct_nutrition = self.delete_ingredient_has_nutrition()
        after = self.schema_counts()
        return {
            "dry_run": False,
            "before": before,
            "maps_to_created_or_matched": maps_created,
            "deleted_ingredient_has_nutrition": deleted_direct_nutrition,
            "after": after,
        }

    def ensure_maps_to_from_matched_food_id(self) -> int:
        query = """
        MATCH (i:Ingredient)
        WHERE i.matched_food_id IS NOT NULL
        MATCH (f:FoodItem {food_id: i.matched_food_id})
        MERGE (i)-[m:MAPS_TO]->(f)
        ON CREATE SET
            m.method = coalesce(i.mapping_method, "matched_food_id"),
            m.source = "migrate_fooditem_nutrition_schema",
            m.created_by_version = "fooditem_nutrition_schema_v1"
        SET m.updated_by_version = "fooditem_nutrition_schema_v1"
        RETURN count(m) AS count
        """
        with self.driver.session() as session:
            return int(session.run(query).single()["count"])

    def delete_ingredient_has_nutrition(self) -> int:
        total = 0
        query = f"""
        MATCH (:Ingredient)-[r:HAS_NUTRITION]->(:Nutrition)
        WITH r LIMIT {DELETE_BATCH_SIZE}
        DELETE r
        RETURN count(r) AS deleted
        """
        with self.driver.session() as session:
            while True:
                deleted = int(session.run(query).single()["deleted"])
                total += deleted
                if deleted == 0:
                    return total

    def schema_counts(self) -> Dict[str, List[Dict[str, Any]]]:
        queries = {
            "nodes": """
                MATCH (n)
                RETURN labels(n) AS labels, count(*) AS count
                ORDER BY count DESC
            """,
            "relationships": """
                MATCH ()-[r]->()
                RETURN type(r) AS type, count(*) AS count
                ORDER BY count DESC
            """,
            "relationship_patterns": """
                MATCH (a)-[r]->(b)
                RETURN labels(a) AS from_labels, type(r) AS rel, labels(b) AS to_labels, count(*) AS count
                ORDER BY count DESC
            """,
        }
        with self.driver.session() as session:
            return {name: session.run(query).data() for name, query in queries.items()}


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Migrate nutrition graph to Dish -> Ingredient -> FoodItem -> Nutrition."
    )
    parser.add_argument("--dry-run", action="store_true", help="Only print current schema counts.")
    args = parser.parse_args()

    migrator = FoodItemNutritionSchemaMigrator(NEO4J_URI, NEO4J_USER, NEO4J_PASSWORD)
    try:
        print(json.dumps(migrator.migrate(dry_run=args.dry_run), ensure_ascii=False, indent=2))
    finally:
        migrator.close()


if __name__ == "__main__":
    main()
