from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from neo4j import GraphDatabase


def main() -> None:
    parser = argparse.ArgumentParser(description="Verify recipe ids imported into Neo4j.")
    parser.add_argument("--mapping-path", type=Path, required=True)
    parser.add_argument("--deleted-recipe-id", default=None)
    args = parser.parse_args()

    recipes = json.loads(args.mapping_path.read_text(encoding="utf-8"))
    recipe_ids = [str(recipe.get("recipe_id") or "").strip() for recipe in recipes if recipe.get("recipe_id")]

    driver = GraphDatabase.driver(
        os.getenv("NEO4J_URI", "bolt://localhost:7687"),
        auth=(os.getenv("NEO4J_USER", "neo4j"), os.getenv("NEO4J_PASSWORD", "password")),
    )
    try:
        with driver.session() as session:
            imported = session.run(
                """
                UNWIND $recipe_ids AS recipe_id
                MATCH (d:Dish {recipe_id: recipe_id})
                RETURN count(DISTINCT d.recipe_id) AS count
                """,
                recipe_ids=recipe_ids,
            ).single()["count"]
            total = session.run("MATCH (d:Dish) RETURN count(d) AS count").single()["count"]
            deleted_count = None
            if args.deleted_recipe_id:
                deleted_count = session.run(
                    "MATCH (d:Dish {recipe_id: $recipe_id}) RETURN count(d) AS count",
                    recipe_id=args.deleted_recipe_id,
                ).single()["count"]
    finally:
        driver.close()

    print(
        json.dumps(
            {
                "json_recipe_ids": len(recipe_ids),
                "imported_recipe_ids_found": imported,
                "deleted_recipe_id": args.deleted_recipe_id,
                "deleted_recipe_id_count": deleted_count,
                "total_dish_count": total,
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
