"""Compatibility entry point for the canonical recipe mapping importer."""

from __future__ import annotations

try:
    from .append_recipe_mapping import AppendRecipeMappingImporter, main
except ImportError:  # pragma: no cover
    from append_recipe_mapping import AppendRecipeMappingImporter, main


RecipeMappingUpserter = AppendRecipeMappingImporter


if __name__ == "__main__":
    main()
