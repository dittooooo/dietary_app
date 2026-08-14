from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List


@dataclass
class IngredientNormalizer:
    alias_map: Dict[str, str]

    def normalize(self, raw_name: str) -> str:
        key = raw_name.strip().lower()
        return self.alias_map.get(key, raw_name.strip())

    def normalize_list(self, items: List[str]) -> List[str]:
        return [self.normalize(x) for x in items]


DEFAULT_NORMALIZER = IngredientNormalizer(
    alias_map={
        "雞丁": "雞肉",
        "雞胸肉": "雞肉",
        "雞腿肉": "雞肉",
        "去骨雞腿": "雞肉",
        "乾辣椒": "辣椒",
        "花生米": "花生",
        "白糖": "糖",
        "砂糖": "糖",
        "醬汁": "醬油",
        "蕃茄": "番茄",
    }
)