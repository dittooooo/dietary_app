from pathlib import Path
import io

import fitz
from pypdf import PdfReader
from PIL import Image
from rapidocr_onnxruntime import RapidOCR


BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"
TEXT_DIR = BASE_DIR / "extracted_text"


def extract_text_pdf(pdf_path: Path) -> str:
    reader = PdfReader(str(pdf_path))
    pages = []
    for i, page in enumerate(reader.pages, start=1):
        text = page.extract_text() or ""
        pages.append(f"===== PAGE {i} =====\n{text.strip()}\n")
    return "\n".join(pages)


def extract_ocr_pdf(pdf_path: Path) -> str:
    doc = fitz.open(str(pdf_path))
    ocr = RapidOCR()
    pages = []
    for i in range(doc.page_count):
        page = doc.load_page(i)
        pix = page.get_pixmap(matrix=fitz.Matrix(2, 2), alpha=False)
        img = Image.open(io.BytesIO(pix.tobytes("png")))
        result, _ = ocr(img)
        text = "\n".join(line[1] for line in result) if result else ""
        pages.append(f"===== PAGE {i + 1} =====\n{text.strip()}\n")
    return "\n".join(pages)


def main() -> None:
    TEXT_DIR.mkdir(parents=True, exist_ok=True)
    for pdf_path in sorted(DATA_DIR.glob("*.pdf")):
        if "代謝症候群" in pdf_path.name:
            text = extract_ocr_pdf(pdf_path)
        else:
            text = extract_text_pdf(pdf_path)
        out_path = TEXT_DIR / f"{pdf_path.stem}.txt"
        out_path.write_text(text, encoding="utf-8")
        print(f"wrote {out_path}")


if __name__ == "__main__":
    main()
