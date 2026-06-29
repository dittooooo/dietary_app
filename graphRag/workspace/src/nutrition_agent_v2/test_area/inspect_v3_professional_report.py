from __future__ import annotations

import json
import sys
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent
WORKSPACE_DIR = BASE_DIR.parents[3]
if str(WORKSPACE_DIR) not in sys.path:
    sys.path.insert(0, str(WORKSPACE_DIR))

from src.nutrition_agent_v2.test_area.inspect_professional_report import read_xlsx


def main() -> None:
    path = BASE_DIR / "professional_nutrition_issue_report_v3.xlsx"
    workbook = read_xlsx(path)
    print(list(workbook))
    for name, rows in workbook.items():
        print("=" * 80)
        print(name)
        print(json.dumps(rows[:6], ensure_ascii=False, indent=2)[:8000])


if __name__ == "__main__":
    main()
