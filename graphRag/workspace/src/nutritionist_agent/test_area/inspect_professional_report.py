from __future__ import annotations

import json
import re
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET


BASE_DIR = Path(__file__).resolve().parent
XLSX_PATH = BASE_DIR / "professional_nutrition_issue_report - 複製.xlsx"
NS = {
    "a": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
    "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
    "rel": "http://schemas.openxmlformats.org/package/2006/relationships",
}


def main() -> None:
    workbook = read_xlsx(XLSX_PATH)
    for sheet_name, rows in workbook.items():
        print("=" * 80)
        print(sheet_name)
        print(json.dumps(rows[:6], ensure_ascii=False, indent=2))


def read_xlsx(path: Path) -> dict[str, list[list[object]]]:
    with zipfile.ZipFile(path) as zf:
        shared = read_shared_strings(zf)
        sheet_paths = read_sheet_paths(zf)
        workbook: dict[str, list[list[object]]] = {}
        for sheet_name, sheet_path in sheet_paths:
            workbook[sheet_name] = read_sheet(zf, sheet_path, shared)
        return workbook


def read_shared_strings(zf: zipfile.ZipFile) -> list[str]:
    if "xl/sharedStrings.xml" not in zf.namelist():
        return []
    root = ET.fromstring(zf.read("xl/sharedStrings.xml"))
    strings = []
    for si in root.findall("a:si", NS):
        strings.append("".join(si.itertext()))
    return strings


def read_sheet_paths(zf: zipfile.ZipFile) -> list[tuple[str, str]]:
    wb_root = ET.fromstring(zf.read("xl/workbook.xml"))
    rel_root = ET.fromstring(zf.read("xl/_rels/workbook.xml.rels"))
    rels = {
        rel.attrib["Id"]: rel.attrib["Target"]
        for rel in rel_root.findall("rel:Relationship", NS)
    }
    sheets = []
    for sheet in wb_root.findall(".//a:sheet", NS):
        name = sheet.attrib["name"]
        rel_id = sheet.attrib[f"{{{NS['r']}}}id"]
        target = rels[rel_id].lstrip("/")
        if not target.startswith("xl/"):
            target = "xl/" + target
        sheets.append((name, target))
    return sheets


def read_sheet(zf: zipfile.ZipFile, path: str, shared: list[str]) -> list[list[object]]:
    root = ET.fromstring(zf.read(path))
    rows = []
    for row in root.findall(".//a:sheetData/a:row", NS):
        values = []
        expected_col = 1
        for cell in row.findall("a:c", NS):
            col = col_index(re.match(r"([A-Z]+)", cell.attrib.get("r", "A")).group(1))
            while expected_col < col:
                values.append("")
                expected_col += 1
            values.append(read_cell(cell, shared))
            expected_col += 1
        rows.append(values)
    return rows


def read_cell(cell: ET.Element, shared: list[str]) -> object:
    value_node = cell.find("a:v", NS)
    if value_node is None:
        inline = cell.find("a:is", NS)
        return "".join(inline.itertext()) if inline is not None else ""
    value = value_node.text or ""
    if cell.attrib.get("t") == "s":
        return shared[int(value)]
    if cell.attrib.get("t") == "str":
        return value
    try:
        number = float(value)
        return int(number) if number.is_integer() else number
    except ValueError:
        return value


def col_index(col: str) -> int:
    total = 0
    for char in col:
        total = total * 26 + ord(char) - ord("A") + 1
    return total


if __name__ == "__main__":
    main()
