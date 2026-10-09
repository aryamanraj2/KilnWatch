"""Draw converted OBB labels on random tiles and save one contact sheet.

If boxes don't sit on kilns, or colours (classes) look wrong, fix the labels
before training -- most "bad model" bugs are label bugs.

    python scripts/show_labels.py D:/ncr/train --n 20 --out labels_check.png
"""

import argparse
from pathlib import Path
import random

from PIL import Image, ImageDraw

CLASSES = ["CFCBK", "FCBK", "Zigzag"]          # same order as filter_ncr.py
COLOURS = [(255, 64, 64), (255, 220, 0), (0, 200, 255)]
SCALE = 4                                       # 128 px tiles are tiny; draw at 512


def draw(img_path, label_path):
    img = Image.open(img_path).convert("RGB")
    w, h = img.size
    img = img.resize((w * SCALE, h * SCALE), Image.NEAREST)
    d = ImageDraw.Draw(img)

    if label_path.exists():
        for line in label_path.read_text().split("\n"):
            parts = line.split()
            if len(parts) != 9:
                continue
            cls = int(parts[0])
            xy = [float(v) for v in parts[1:]]
            pts = [(xy[i] * w * SCALE, xy[i + 1] * h * SCALE) for i in range(0, 8, 2)]
            d.polygon(pts, outline=COLOURS[cls], width=2)
            d.text((pts[0][0] + 3, pts[0][1] + 3), CLASSES[cls], fill=COLOURS[cls])

    d.text((4, 4), img_path.stem, fill=(255, 255, 255))
    return img


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("split_dir", type=Path, help="e.g. ncr/train (has images/ and labels/)")
    ap.add_argument("--n", type=int, default=20)
    ap.add_argument("--cols", type=int, default=5)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--out", type=Path, default=Path("labels_check.png"))
    args = ap.parse_args()

    labelled = sorted((args.split_dir / "labels").glob("*.txt"))
    if not labelled:
        raise SystemExit(f"no labels in {args.split_dir / 'labels'}")
    random.Random(args.seed).shuffle(labelled)

    tiles = []
    for lbl in labelled[:args.n]:
        img = args.split_dir / "images" / f"{lbl.stem}.png"
        if img.exists():
            tiles.append(draw(img, lbl))

    tw, th = tiles[0].size
    rows = (len(tiles) + args.cols - 1) // args.cols
    sheet = Image.new("RGB", (args.cols * tw, rows * th))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % args.cols) * tw, (i // args.cols) * th))
    sheet.save(args.out)
    print(f"wrote {args.out} ({len(tiles)} tiles)")


if __name__ == "__main__":
    main()
