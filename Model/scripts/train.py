"""Train a YOLO11-OBB kiln detector, then score it on the test sets that matter.

    python Model/scripts/train.py --data /tmp/kilns/kilns_full.yaml --model yolo11s-obb.pt --epochs 20 --name baseline

Scores land in <project>/<name>/scores.json, one entry per --eval yaml (default:
kilns_full.yaml and kilns_strict.yaml next to --data):
  full     the dataset's whole test split -- compare with the SentinelKilnDB paper
  strict   test_ncr.txt -- the NCR score (honest only for a model trained on strict)
Each has mAP50 over the three types, AP50 per type, and any_kiln_AP50 with types
ignored, which is the paper's "any kiln" column.

With --s3 s3://bucket/prefix, the weights, config, curves and scores are uploaded
to <prefix>/<name>/ (needs AWS credentials in the environment).
"""

import argparse
import json
from pathlib import Path
import time

import ultralytics
from ultralytics import YOLO


def score(model, data, imgsz, batch):
    m = model.val(data=data, split="test", imgsz=imgsz, batch=batch, plots=False, verbose=False)
    out = {
        "mAP50": float(m.box.map50),
        "mAP50-95": float(m.box.map),
        "precision": float(m.box.mp),
        "recall": float(m.box.mr),
        "per_type_AP50": {model.names[int(c)]: float(ap)
                          for c, ap in zip(m.box.ap_class_index, m.box.ap50)},
    }
    try:
        # Types merged into one class: is there a kiln here at all?
        a = model.val(data=data, split="test", imgsz=imgsz, batch=batch,
                      single_cls=True, plots=False, verbose=False)
        out["any_kiln_AP50"] = float(a.box.map50)
    except Exception as e:                      # keep the type scores if this fails
        out["any_kiln_AP50"] = f"failed: {e}"
    return out


def upload(run_dir, s3_uri, name):
    import boto3

    bucket, _, prefix = s3_uri.removeprefix("s3://").partition("/")
    s3 = boto3.client("s3")
    keep = ["weights/best.pt", "weights/last.pt", "args.yaml", "results.csv",
            "results.png", "scores.json"]
    for rel in keep:
        f = run_dir / rel
        if f.exists():
            key = "/".join(p for p in (prefix.rstrip("/"), name, rel) if p)
            s3.upload_file(str(f), bucket, key)
            print(f"uploaded s3://{bucket}/{key}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--data", type=Path, required=True, help="training yaml")
    ap.add_argument("--model", default="yolo11s-obb.pt")
    ap.add_argument("--epochs", type=int, default=20)
    ap.add_argument("--imgsz", type=int, default=128)
    ap.add_argument("--batch", type=int, default=64)
    ap.add_argument("--name", default="baseline")
    ap.add_argument("--project", default="runs/kilnwatch")
    ap.add_argument("--cache", default=False,
                    help="'ram' caches all tiles in memory (~4 GB for the full set)")
    ap.add_argument("--fraction", type=float, default=1.0,
                    help="train on this share of the train set -- for smoke tests")
    ap.add_argument("--hours", type=float,
                    help="stop after this many hours, with the learning-rate schedule fitted "
                         "to it (overrides --epochs) -- keeps a run inside Kaggle's 12 h limit")
    ap.add_argument("--eval", action="append", metavar="NAME=YAML",
                    help="test sets to score; default full and strict next to --data")
    ap.add_argument("--s3", help="s3://bucket/prefix to upload the run to")
    args = ap.parse_args()

    evals = dict(e.split("=", 1) for e in args.eval) if args.eval else {
        n: str(args.data.parent / f"kilns_{n}.yaml") for n in ("full", "strict")
        if (args.data.parent / f"kilns_{n}.yaml").exists()}

    start = time.time()
    model = YOLO(args.model)
    model.train(data=str(args.data), epochs=args.epochs, imgsz=args.imgsz, batch=args.batch,
                project=args.project, name=args.name, exist_ok=True, cache=args.cache,
                fraction=args.fraction, seed=0, time=args.hours)
    run_dir = Path(model.trainer.save_dir)
    minutes = (time.time() - start) / 60

    best = YOLO(run_dir / "weights" / "best.pt")
    scores = {
        "model": args.model, "data": str(args.data), "epochs": args.epochs,
        "imgsz": args.imgsz, "batch": args.batch, "fraction": args.fraction, "hours": args.hours,
        "epochs_run": model.trainer.epoch + 1,
        "train_minutes": round(minutes, 1),
        "dataset": "SentinelKilnDB (Kaggle rishabhsnip/sentinelkiln-dataset), CC BY-NC 4.0",
        "ultralytics": ultralytics.__version__,
        "test": {n: score(best, y, args.imgsz, args.batch) for n, y in evals.items()},
    }
    (run_dir / "scores.json").write_text(json.dumps(scores, indent=2))
    print(json.dumps(scores["test"], indent=2))
    print(f"\nrun saved to {run_dir}")

    if args.s3:
        upload(run_dir, args.s3, args.name)


if __name__ == "__main__":
    main()
