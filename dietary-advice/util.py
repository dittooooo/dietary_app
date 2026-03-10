def normalize_unit(unit):
    unit_map = {
        "g": "克",
        "克": "克",
        "公克": "克",
        "kg": "公斤",
        "公斤": "公斤",
        "cc": "毫升",
        "c.c.": "毫升",
        "ml": "毫升",
        "毫升": "毫升"
    }
    if unit in unit_map:
        return unit_map[unit]
    return unit