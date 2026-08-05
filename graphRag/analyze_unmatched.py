#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Compatibility wrapper.

The actual implementation lives at:
  workspace/src/recipe_nutrition_unmatch/analyze_unmatched.py

This file lets you keep using:
  python analyze_unmatched.py ...
from the repo root.
"""

from __future__ import annotations

import runpy
from pathlib import Path


def main() -> None:
    target = (
        Path(__file__).resolve().parent
        / "workspace"
        / "src"
        / "recipe_nutrition_unmatch"
        / "analyze_unmatched.py"
    )
    runpy.run_path(str(target), run_name="__main__")


if __name__ == "__main__":
    main()

