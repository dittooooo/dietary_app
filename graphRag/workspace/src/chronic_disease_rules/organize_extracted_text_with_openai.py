from __future__ import annotations

import argparse
import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from dotenv import load_dotenv
from openai import OpenAI
from pydantic import BaseModel, Field


BASE_DIR = Path(__file__).resolve().parent
DEFAULT_INPUT_DIR = BASE_DIR / "extracted_text"
DEFAULT_PROMPT_PATH = BASE_DIR / "prompt" / "create_data.txt"
DEFAULT_OUTPUT_DIR = BASE_DIR / "output" / "structured_chronic_disease_rules"


class RecommendedFoodGroup(BaseModel):
    category: str = ""
    foods: list[str] = Field(default_factory=list)
    benefit: str = ""


class AvoidOrReduceGroup(BaseModel):
    category: str = ""
    foods: list[str] = Field(default_factory=list)


class NutritionField(BaseModel):
    target: str = ""
    note: str = ""


class FatGuideline(BaseModel):
    total_fat: str = ""
    saturated_fat: str = ""
    trans_fat: str = ""
    cholesterol: str = ""
    note: str = ""


class FiberGuideline(BaseModel):
    soluble_fiber: str = ""
    total_fiber: str = ""
    note: str = ""


class NutritionGuideline(BaseModel):
    calories: NutritionField = Field(default_factory=NutritionField)
    sodium: NutritionField = Field(default_factory=NutritionField)
    protein: NutritionField = Field(default_factory=NutritionField)
    fat: FatGuideline = Field(default_factory=FatGuideline)
    sugar: NutritionField = Field(default_factory=NutritionField)
    fiber: FiberGuideline = Field(default_factory=FiberGuideline)


class BeneficialFoods(BaseModel):
    recommended_food_groups: list[RecommendedFoodGroup] = Field(default_factory=list)


class FoodsToLimit(BaseModel):
    avoid_or_reduce: list[AvoidOrReduceGroup] = Field(default_factory=list)


class DietPattern(BaseModel):
    recommended_patterns: list[str] = Field(default_factory=list)
    core_principle: str = ""


class DiseaseDietRule(BaseModel):
    disease_id: str = ""
    disease_name_zh: str = ""
    disease_name_en: str = ""
    nutrition_guideline: NutritionGuideline = Field(default_factory=NutritionGuideline)
    beneficial_foods: BeneficialFoods = Field(default_factory=BeneficialFoods)
    foods_to_limit: FoodsToLimit = Field(default_factory=FoodsToLimit)
    diet_pattern: DietPattern = Field(default_factory=DietPattern)
    risk_notes: list[str] = Field(default_factory=list)


class SourceDocumentOutput(BaseModel):
    items: list[DiseaseDietRule] = Field(default_factory=list)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Use the OpenAI SDK to transform extracted chronic disease text files "
            "into structured JSON based on the prompt template."
        )
    )
    parser.add_argument("--input-dir", type=Path, default=DEFAULT_INPUT_DIR)
    parser.add_argument("--prompt-path", type=Path, default=DEFAULT_PROMPT_PATH)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument(
        "--model",
        default=os.getenv("OPENAI_MODEL", "gpt-4.1"),
        help="OpenAI model name. Defaults to OPENAI_MODEL or gpt-4.1.",
    )
    parser.add_argument(
        "--extensions",
        nargs="+",
        default=[".txt", ".md"],
        help="File extensions to process. Defaults to .txt .md",
    )
    parser.add_argument(
        "--max-files",
        type=int,
        default=None,
        help="Optional cap on the number of input files to process.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite existing per-file outputs if they already exist.",
    )
    return parser.parse_args()


def normalize_extensions(extensions: list[str]) -> set[str]:
    normalized = set()
    for extension in extensions:
        if not extension:
            continue
        normalized.add(extension if extension.startswith(".") else f".{extension}")
    return normalized


def iter_source_files(input_dir: Path, extensions: set[str]) -> list[Path]:
    files = [path for path in input_dir.iterdir() if path.is_file() and path.suffix.lower() in extensions]
    return sorted(files)


def build_prompt(prompt_template: str, source_file: str, document_text: str) -> list[dict[str, Any]]:
    developer_prompt = (
        f"{prompt_template.strip()}\n\n"
        "Additional output rules:\n"
        "1. Return data that fits the provided structured schema exactly.\n"
        "2. If the document covers multiple diseases, return one item per disease.\n"
        "3. Keep unknown or missing values as empty strings or empty arrays.\n"
        "4. Do not add markdown fences.\n"
        "5. Preserve medically meaningful staging or special conditions in risk_notes.\n"
    )
    user_prompt = (
        f"Source file: {source_file}\n"
        "Please read the following extracted document text and organize it into structured JSON.\n\n"
        f"{document_text}"
    )
    return [
        {"role": "developer", "content": developer_prompt},
        {"role": "user", "content": user_prompt},
    ]


def parse_document(
    client: OpenAI,
    model: str,
    prompt_template: str,
    source_path: Path,
) -> SourceDocumentOutput:
    document_text = source_path.read_text(encoding="utf-8")
    messages = build_prompt(
        prompt_template=prompt_template,
        source_file=source_path.name,
        document_text=document_text,
    )

    if hasattr(client, "responses"):
        response = client.responses.parse(
            model=model,
            input=messages,
            text_format=SourceDocumentOutput,
        )
        parsed = response.output_parsed
    elif hasattr(client, "beta") and hasattr(client.beta, "chat") and hasattr(client.beta.chat, "completions"):
        response = client.beta.chat.completions.parse(
            model=model,
            messages=messages,
            response_format=SourceDocumentOutput,
        )
        parsed = response.choices[0].message.parsed
    else:
        raise AttributeError(
            "This installed openai SDK supports neither client.responses nor "
            "client.beta.chat.completions.parse. Please upgrade the openai package."
        )

    if parsed is None:
        raise ValueError(f"No structured output was returned for {source_path.name}.")
    return parsed


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def process_files(
    client: OpenAI,
    model: str,
    prompt_path: Path,
    input_dir: Path,
    output_dir: Path,
    extensions: set[str],
    max_files: int | None,
    overwrite: bool,
) -> None:
    prompt_template = prompt_path.read_text(encoding="utf-8")
    source_files = iter_source_files(input_dir=input_dir, extensions=extensions)
    if max_files is not None:
        source_files = source_files[:max_files]

    combined_diseases: list[dict[str, Any]] = []
    manifest_items: list[dict[str, Any]] = []
    errors: list[dict[str, str]] = []

    for source_path in source_files:
        output_path = output_dir / f"{source_path.stem}.json"
        if output_path.exists() and not overwrite:
            existing_items = json.loads(output_path.read_text(encoding="utf-8"))
            if isinstance(existing_items, list):
                combined_diseases.extend(existing_items)
            manifest_items.append(
                {
                    "source_file": source_path.name,
                    "output_file": output_path.name,
                    "status": "skipped_existing",
                }
            )
            continue

        try:
            parsed = parse_document(
                client=client,
                model=model,
                prompt_template=prompt_template,
                source_path=source_path,
            )
            parsed_payload = [item.model_dump(mode="json") for item in parsed.items]
            write_json(output_path, parsed_payload)
            combined_diseases.extend(parsed_payload)
            manifest_items.append(
                {
                    "source_file": source_path.name,
                    "output_file": output_path.name,
                    "status": "completed",
                    "disease_count": len(parsed.items),
                }
            )
            print(f"completed {source_path.name} -> {output_path.name}")
        except Exception as exc:
            errors.append({"source_file": source_path.name, "error": str(exc)})
            manifest_items.append(
                {
                    "source_file": source_path.name,
                    "status": "failed",
                }
            )
            print(f"failed {source_path.name}: {exc}")

    write_json(
        output_dir / "_all_documents.json",
        combined_diseases,
    )
    manifest = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "model": model,
        "input_dir": str(input_dir),
        "prompt_path": str(prompt_path),
        "output_dir": str(output_dir),
        "documents": manifest_items,
        "errors": errors,
    }
    write_json(output_dir / "_manifest.json", manifest)


def main() -> None:
    load_dotenv()
    args = parse_args()

    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise EnvironmentError("OPENAI_API_KEY is required.")
    if not args.prompt_path.exists():
        raise FileNotFoundError(f"Prompt file not found: {args.prompt_path}")
    if not args.input_dir.exists():
        raise FileNotFoundError(f"Input directory not found: {args.input_dir}")

    client = OpenAI(api_key=api_key)
    process_files(
        client=client,
        model=args.model,
        prompt_path=args.prompt_path,
        input_dir=args.input_dir,
        output_dir=args.output_dir,
        extensions=normalize_extensions(args.extensions),
        max_files=args.max_files,
        overwrite=args.overwrite,
    )


if __name__ == "__main__":
    main()
