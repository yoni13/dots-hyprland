#!/usr/bin/env python3
"""OCR script using easyOCR - reads text from an image and prints it to stdout."""
import sys
import easyocr


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <image_path> [lang ...]", file=sys.stderr)
        sys.exit(1)

    image_path = sys.argv[1]
    langs = sys.argv[2:] if len(sys.argv) > 2 else ["en","ch_tra"]

    reader = easyocr.Reader(langs, gpu=True, verbose=False)
    results = reader.readtext(image_path, detail=0, paragraph=True)
    print("\n".join(results))


if __name__ == "__main__":
    main()
