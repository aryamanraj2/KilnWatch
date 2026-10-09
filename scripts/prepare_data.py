"""Prepare SentinelKilnDB for Ultralytics OBB training and NCR evaluation.

Writes, under --dst:
  {train,val,test}/images  {train,val,test}/labels   the whole dataset
  test_ncr.txt       NCR test tiles, plus the nearest empty test tiles
  train_strict.txt   train tiles sharing no ground with a test_ncr tile
  val_strict.txt     the same for val
  kilns_full.yaml    official split -- comparable with the paper (test = all test tiles)
  kilns_strict.yaml  strict split -- the honest NCR score (test = test_ncr.txt)

Why two setups: kilns look alike across South Asia, so training uses the whole
dataset (the NCR area alone holds ~1/7 of the boxes). But the dataset's split puts
overlapping tiles in train and test -- 260 of 339 NCR test tiles share ground with
a train/val tile -- so a model trained on the official split has already seen most
NCR test kilns. The strict lists drop those tiles.

Every NCR tile contains a kiln; the dataset's empty tiles are all far away. The
nearest of them are added to test_ncr so precision is measured at all.

Tile filenames are "<lat>_<lon>.png", so geography is a string parse. --src can be
the extracted folder (Kaggle: /kaggle/input/...) or the downloaded .zip, read in place.
List files hold absolute paths, so prepare the data where you train.

    python scripts/prepare_data.py --src /kaggle/input/sentinelkiln-dataset --dst /tmp/kilns --link
    python scripts/prepare_data.py --src "dataset for KilnWatch.zip" --dst kilns --dry-run
"""

import argparse
from collections import Counter, defaultdict
import math
import os
from pathlib import Path
import zipfile

TILE_PX = 128
TILE_KM = 1.28          # 128 px x 10 m
SPLITS = ("train", "val", "test")

# Keep this order identical to `names:` in the written yaml. Verified against the
# dataset: every yolo_obb index matches its dota_labels name (0 CFCBK, 1 FCBK, 2 Zigzag).
CLASSES = ["CFCBK", "FCBK", "Zigzag"]
CLASS_IDX = {n.lower(): i for i, n in enumerate(CLASSES)}

# (lat_min, lat_max, lon_min, lon_max)
AOI = {
    # The PDF's first deployment: Hapur, Ghaziabad, Baghpat, Meerut, plus Delhi itself.
    "ncr_up": (28.30, 29.30, 76.80, 78.20),
    "igp_wide": (27.50, 30.50, 75.50, 80.00),
}


class Source:
    """The dataset as relative names like 'train/images/28.75_78.54.png', whether it
    is an extracted folder or the zip, with or without a top-level folder."""

    def __init__(self, src):
        if src.suffix.lower() == ".zip":
            self.zip = zipfile.ZipFile(src)
            names = [n for n in self.zip.namelist() if not n.endswith("/")]
            self.root = next(n for n in names if "train/images/" in n).split("train/images/")[0]
            self.names = [n[len(self.root):] for n in names if n.startswith(self.root)]
            return

        self.zip = None
        src = src.resolve()                       # symlinks must point at absolute paths
        self.root = src if (src / "train" / "images").is_dir() else next(
            d for d in src.iterdir() if (d / "train" / "images").is_dir())
        self.names = [f"{split}/{d.name}/{e.name}"
                      for split in SPLITS
                      for d in (self.root / split).iterdir() if d.is_dir()
                      for e in os.scandir(d) if e.is_file()]

    def read(self, name):
        return self.zip.read(self.root + name) if self.zip else (self.root / name).read_bytes()

    def size(self, name):
        return self.zip.getinfo(self.root + name).file_size if self.zip else (self.root / name).stat().st_size

    def path(self, name):
        return None if self.zip else self.root / name

    def files(self, split, sub, ext):
        """stem -> name for files in <split>/<sub>/."""
        prefix = f"{split}/{sub}/"
        return {Path(n).stem: n for n in self.names if n.startswith(prefix) and n.endswith(ext)}

    def subdirs(self, split):
        return {n.split("/")[1] for n in self.names if n.startswith(split + "/") and n.count("/") == 2}


def coords(stem):
    """'28.6400_77.2100' (or '28.64,77.21') -> (28.64, 77.21); None if not a pair."""
    try:
        lat, lon = stem.replace(",", "_").split("_")
        return float(lat), float(lon)
    except ValueError:
        return None


def inside(lat, lon, box):
    lat_min, lat_max, lon_min, lon_max = box
    return lat_min <= lat <= lat_max and lon_min <= lon <= lon_max


def is_number(s):
    try:
        float(s)
        return True
    except ValueError:
        return False


def find_label_dir(split, dirs, name=None):
    """The YOLO-OBB label folder for a split. Refuses to guess between several
    candidates -- picking the DOTA folder by accident silently corrupts classes."""
    if name:
        if name not in dirs:
            raise SystemExit(f"{split}: no folder named {name!r}; have {sorted(dirs)}")
        return name

    obb = [d for d in dirs if "obb" in d.lower() and "dota" not in d.lower()]
    if len(obb) != 1:
        raise SystemExit(f"{split}: can't pick a YOLO-OBB label folder from "
                         f"{sorted(dirs)} -- pass --labels-dir")
    return obb[0]


def parse_line(line, stats):
    """One label line -> (class_index, 8 coords), or None.

    Layouts seen in the wild:
      CFCBK x1 y1 ... x4 y4          class name first
      0 x1 y1 ... x4 y4              class index first (YOLO-OBB)
      x1 y1 ... x4 y4 CFCBK [diff]   class after coords (DOTA)
    """
    parts = line.replace(",", " ").split()
    if len(parts) < 9:
        return None

    if not is_number(parts[0]):
        cls, nums = parts[0], parts[1:9]
    elif not is_number(parts[8]):
        cls, nums = parts[8], parts[0:8]
        stats["dota_layout"] += 1
    else:
        cls, nums = parts[0], parts[1:9]

    idx = CLASS_IDX.get(cls.lower())
    if idx is None:
        if not is_number(cls):
            stats[f"unknown_class:{cls}"] += 1
            return None
        idx = int(float(cls))
        if not 0 <= idx < len(CLASSES):
            stats[f"bad_index:{idx}"] += 1
            return None

    return idx, [float(v) for v in nums]


def convert(text, stats):
    """One label file's text -> (Ultralytics OBB text, per-class counts)."""
    out, per_class = [], Counter()
    for line in text.split("\n"):
        parsed = parse_line(line, stats)
        if parsed is None:
            continue
        idx, nums = parsed

        # Normalise only if the coords are clearly in pixel space.
        if max(nums) > 1.5:
            nums = [v / TILE_PX for v in nums]
            stats["pixel_coords"] += 1
        nums = [min(max(v, 0.0), 1.0) for v in nums]

        out.append(" ".join([str(idx)] + [f"{v:.6f}" for v in nums]))
        per_class[CLASSES[idx]] += 1

    return "\n".join(out) + ("\n" if out else ""), per_class


def nearest(stems, box, k):
    """The k stems closest to the box centre, in degrees."""
    clat, clon = (box[0] + box[1]) / 2, (box[2] + box[3]) / 2

    def dist(stem):
        lat, lon = coords(stem)
        return (lat - clat) ** 2 + (lon - clon) ** 2

    return sorted(stems, key=dist)[:k]


def overlap_test(points, km):
    """-> f(lat, lon): True if a tile centred there lies within `km` of any point
    on both axes. With km = TILE_KM that means the two tiles share ground."""
    cell = 0.05                                   # ~5.5 km; neighbours cover km < 5
    assert km < 5, "raise `cell` for larger buffers"
    grid = defaultdict(list)
    for lat, lon in points:
        grid[(math.floor(lat / cell), math.floor(lon / cell))].append((lat, lon))

    def hit(lat, lon):
        gi, gj = math.floor(lat / cell), math.floor(lon / cell)
        kx = 111.32 * math.cos(math.radians(lat))
        for di in (-1, 0, 1):
            for dj in (-1, 0, 1):
                for a, b in grid.get((gi + di, gj + dj), ()):
                    if abs(a - lat) * 110.57 < km and abs(b - lon) * kx < km:
                        return True
        return False

    return hit


def write_yaml(path, train, val, test):
    path.write_text("\n".join([
        f"path: {path.parent.resolve().as_posix()}",
        f"train: {train}",
        f"val: {val}",
        f"test: {test}",
        "names:",
        *[f"  {i}: {n}" for i, n in enumerate(CLASSES)],
    ]) + "\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--src", type=Path, default=Path("/kaggle/input/sentinelkiln-dataset"),
                    help="dataset folder or .zip")
    ap.add_argument("--dst", type=Path, default=Path("/tmp/kilns"))
    ap.add_argument("--eval-aoi", choices=AOI, default="ncr_up",
                    help="box whose test tiles make up test_ncr.txt")
    ap.add_argument("--neg-ratio", type=float, default=0.5,
                    help="empty tiles added to test_ncr per kiln tile, nearest first")
    ap.add_argument("--buffer-km", type=float, default=0.0,
                    help="extra gap between strict train/val tiles and test_ncr tiles")
    ap.add_argument("--labels-dir", help="exact name of the YOLO-OBB label folder "
                                         "inside each split (auto-detected if omitted)")
    ap.add_argument("--link", action="store_true",
                    help="symlink images instead of copying (folder --src only)")
    ap.add_argument("--dry-run", action="store_true",
                    help="count only; copy and write nothing")
    args = ap.parse_args()

    src = Source(args.src)
    if args.link and src.zip:
        raise SystemExit("--link needs an extracted folder, not a zip")

    dst = args.dst.resolve()
    box = AOI[args.eval_aoi]
    tiles, labelled, per_class, stats, total_bytes = {}, {}, {}, Counter(), 0
    test_counts = {}

    for split in SPLITS:
        label_dir = find_label_dir(split, src.subdirs(split), args.labels_dir)
        labels = src.files(split, label_dir, ".txt")
        images = src.files(split, "images", ".png")
        print(f"{split:>6}: {len(images)} images, labels from {label_dir} ({len(labels)} files)")

        img_dst, lbl_dst = dst / split / "images", dst / split / "labels"
        if not args.dry_run:
            img_dst.mkdir(parents=True, exist_ok=True)
            lbl_dst.mkdir(parents=True, exist_ok=True)

        tiles[split], labelled[split], per_class[split] = {}, set(), Counter()
        for stem, img in images.items():
            c = coords(stem)
            if c is None:
                stats["unparsed_filename"] += 1
                continue
            tiles[split][stem] = c

            if not args.dry_run:
                out = img_dst / f"{stem}.png"
                if args.link:
                    if not out.exists():
                        out.symlink_to(src.path(img))
                else:
                    out.write_bytes(src.read(img))
                    total_bytes += src.size(img)

            # No .txt means a negative tile. Ultralytics reads a missing
            # label as background, so leave it absent on purpose.
            if stem in labels:
                text, counts = convert(src.read(labels[stem]).decode(), stats)
                if counts:
                    labelled[split].add(stem)
                    per_class[split] += counts
                    if split == "test":
                        test_counts[stem] = counts
                if not args.dry_run:
                    (lbl_dst / f"{stem}.txt").write_text(text)

    # test_ncr: every test tile in the box, plus the nearest empty test tiles.
    test = tiles["test"]
    in_box = [s for s, c in test.items() if inside(*c, box)]
    kiln_tiles = sum(1 for s in in_box if s in labelled["test"])
    empty_far = [s for s, c in test.items() if not inside(*c, box) and s not in labelled["test"]]
    added = nearest(empty_far, box, round(kiln_tiles * args.neg_ratio))
    test_ncr = in_box + added

    # strict: drop train/val tiles sharing ground with any test_ncr tile.
    shares_ground = overlap_test([test[s] for s in test_ncr], TILE_KM + args.buffer_km)
    strict = {split: [s for s, c in tiles[split].items() if not shares_ground(*c)]
              for split in ("train", "val")}

    print()
    for split in SPLITS:
        n = len(tiles[split])
        print(f"{split:>6}: {n:>6} tiles  {sum(per_class[split].values()):>6} boxes  "
              f"{n - len(labelled[split]):>6} empty  {dict(per_class[split])}")

    ncr_boxes = sum((test_counts[s] for s in in_box if s in test_counts), Counter())
    far = coords(added[-1]) if added else None
    print(f"\ntest_ncr: {len(test_ncr)} tiles = {len(in_box)} in {args.eval_aoi} "
          f"({kiln_tiles} with kilns) + {len(added)} empty"
          + (f", farthest at {far[0]:.2f},{far[1]:.2f}" if far else "")
          + f"\n          boxes {dict(ncr_boxes)}")
    for split in ("train", "val"):
        dropped = len(tiles[split]) - len(strict[split])
        print(f"{split}_strict: {len(strict[split])} tiles ({dropped} dropped for sharing "
              f"ground with test_ncr)")
    if total_bytes:
        print(f"\ncopied {total_bytes / 1e6:.0f} MB of imagery")

    # Anything here deserves a look before training.
    if stats:
        print("\nchecks:")
        for k, v in sorted(stats.items()):
            print(f"  {k}: {v}")

    if args.dry_run:
        return

    def write_list(name, split, stems):
        (dst / name).write_text("".join(f"{dst.as_posix()}/{split}/images/{s}.png\n" for s in stems))

    write_list("test_ncr.txt", "test", test_ncr)
    write_list("train_strict.txt", "train", strict["train"])
    write_list("val_strict.txt", "val", strict["val"])
    write_yaml(dst / "kilns_full.yaml", "train/images", "val/images", "test/images")
    write_yaml(dst / "kilns_strict.yaml", "train_strict.txt", "val_strict.txt", "test_ncr.txt")
    print(f"\nwrote {dst / 'kilns_full.yaml'} and {dst / 'kilns_strict.yaml'}")


if __name__ == "__main__":
    main()
