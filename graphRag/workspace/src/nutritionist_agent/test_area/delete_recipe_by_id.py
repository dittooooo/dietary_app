from __future__ import annotations

import argparse
import json
import os

from neo4j import GraphDatabase


def main() -> None:
    parser = argparse.ArgumentParser(description="Delete one Dish by recipe_id from Neo4j.")
    parser.add_argument("recipe_id")
    args = parser.parse_args()

    driver = GraphDatabase.driver(
        os.getenv("NEO4J_URI", "bolt://localhost:7687"),
        auth=(os.getenv("NEO4J_USER", "neo4j"), os.getenv("NEO4J_PASSWORD", "password")),
    )
    try:
        with driver.session() as session:
            before = session.run(
                "MATCH (d:Dish {recipe_id: $recipe_id}) RETURN count(d) AS count",
                recipe_id=args.recipe_id,
            ).single()["count"]
            relationships = session.run(
                "MATCH (d:Dish {recipe_id: $recipe_id})-[r]-() RETURN count(r) AS count",
                recipe_id=args.recipe_id,
            ).single()["count"]
            session.run(
                "MATCH (d:Dish {recipe_id: $recipe_id}) DETACH DELETE d",
                recipe_id=args.recipe_id,
            ).consume()
            after = session.run(
                "MATCH (d:Dish {recipe_id: $recipe_id}) RETURN count(d) AS count",
                recipe_id=args.recipe_id,
            ).single()["count"]
    finally:
        driver.close()

    print(
        json.dumps(
            {
                "recipe_id": args.recipe_id,
                "before_delete_dish_count": before,
                "before_delete_relationship_count": relationships,
                "after_delete_dish_count": after,
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
