from __future__ import annotations

import argparse
import json
from pathlib import Path

try:
    from .knowledge_agent_importer import (
        FOOD_MAPPING_PATH,
        NEO4J_PASSWORD,
        NEO4J_URI,
        NEO4J_USER,
        KnowledgeAgentImporter,
        load_recipe_records,
    )
except ImportError:  # pragma: no cover
    from knowledge_agent_importer import (
        FOOD_MAPPING_PATH,
        NEO4J_PASSWORD,
        NEO4J_URI,
        NEO4J_USER,
        KnowledgeAgentImporter,
        load_recipe_records,
    )


class AppendRecipeMappingImporter(KnowledgeAgentImporter):
    """Reusable recipe-only entry point using the canonical importer logic."""

    def import_mapping_file(
        self,
        mapping_path: Path,
        *,
        dry_run: bool = False,
        strict_mapping: bool = False,
    ):
        self.create_schema()
        self.load_food_index_from_database()
        records = load_recipe_records(Path(mapping_path))

        recipe_rows, ingredient_rows, report = self._prepare_recipe_rows(
            records,
            strict_mapping=strict_mapping,
        )
        if not dry_run:
            self._remove_old_recipe_relationships([row["recipe_id"] for row in recipe_rows])
            self._write_recipe_rows(recipe_rows)

        return {
            "mapping_path": str(mapping_path),
            "dry_run": dry_run,
            "recipes_written": len(recipe_rows),
            "ingredients_written": len(ingredient_rows),
            **report,
        }


def main() -> None:
    parser = argparse.ArgumentParser(description="Import a recipe mapping JSON into an existing graph.")
    parser.add_argument("--mapping-path", type=Path, default=FOOD_MAPPING_PATH)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--strict-mapping", action="store_true")
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()

    importer = AppendRecipeMappingImporter(NEO4J_URI, NEO4J_USER, NEO4J_PASSWORD)
    try:
        if args.verify_only:
            result = {
                "counts": importer.counts(),
                "mapping_violations": importer.mapping_violations(),
            }
        else:
            result = importer.import_mapping_file(
                args.mapping_path,
                dry_run=args.dry_run,
                strict_mapping=args.strict_mapping,
            )
        print(json.dumps(result, ensure_ascii=False, indent=2))
    finally:
        importer.close()


if __name__ == "__main__":
    main()
