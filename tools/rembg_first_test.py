from pathlib import Path
import sys

from PIL import Image, ImageOps
from rembg import remove


INPUT_DIR = Path(r"C:\Users\smtdi\Documents\GitHub\10no104.github.io\img\original\done")
OUTPUT_DIR = Path(r"C:\Users\smtdi\Documents\GitHub\10no104.github.io\img\edited\test")
VALID_EXTS = {".jpg", ".jpeg", ".png", ".webp"}


def main() -> int:
    try:
        source = sorted(
            path for path in INPUT_DIR.iterdir() if path.is_file() and path.suffix.lower() in VALID_EXTS
        )[0]

        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        target = OUTPUT_DIR / f"{source.stem}.png"

        print(f"START: {source.name}", flush=True)
        with Image.open(source) as image:
            image = ImageOps.exif_transpose(image).convert("RGBA")
            print("LOADED", flush=True)
            print("REMOVING BG", flush=True)
            result = remove(image)
            print("DONE", flush=True)
            result.save(target, format="PNG")
        print(f"SAVED: {target}", flush=True)
        return 0
    except Exception as exc:
        name = source.name if "source" in locals() else "UNKNOWN"
        print(f"ERROR: {name}: {exc}", flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
