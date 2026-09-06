"""Retained compatibility command for inspecting the current graph only."""

from __future__ import annotations

import argparse
import json

try:
    from .knowledge_agent_importer import NEO4J_PASSWORD, NEO4J_URI, NEO4J_USER, KnowledgeAgentImporter
except ImportError:  # pragma: no cover
    from knowledge_agent_importer import NEO4J_PASSWORD, NEO4J_URI, NEO4J_USER, KnowledgeAgentImporter


class FoodItemNutritionSchemaMigrator(KnowledgeAgentImporter):
    """Do not perform legacy relationship migration; use the canonical full import instead."""

    def migrate(self, *, dry_run: bool = True):
        if not dry_run:
            raise RuntimeError(
                "Legacy migration is disabled. Rebuild the empty database with knowledge_agent_importer.py."
            )
        return {"dry_run": True, "counts": self.counts(), "mapping_violations": self.mapping_violations()}


def main() -> None:
    parser = argparse.ArgumentParser(description="Inspect the current graph without legacy migration writes.")
    parser.add_argument("--dry-run", action="store_true", default=True)
    args = parser.parse_args()
    migrator = FoodItemNutritionSchemaMigrator(NEO4J_URI, NEO4J_USER, NEO4J_PASSWORD)
    try:
        print(json.dumps(migrator.migrate(dry_run=args.dry_run), ensure_ascii=False, indent=2))
    finally:
        migrator.close()


if __name__ == "__main__":
    main()
