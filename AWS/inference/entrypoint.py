"""Fargate entrypoint for the kiln detector (prompt 38).

    python entrypoint.py --scene S2B_T43RGM_20261005T053448_L2A --run-id m0-after

Reads DATA_BUCKET, MODEL_S3_PREFIX and OUTPUT_S3_PREFIX from the environment, nothing else.
Downloads the checkpoint and its manifest, refuses to run unless both match the manifest
baked into the image, runs detect_scene.py with the local Hapur run's settings, and writes
only <OUTPUT_S3_PREFIX><run-id>/kilns.geojson and run.json. The output is candidates, not
findings. Logs hold counts and timings only.
"""
import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import tempfile
import time
import urllib.request

HERE = Path(__file__).resolve().parent
PINNED_MANIFEST = HERE / "model" / "checkpoint-manifest.json"
DETECT = HERE / "model" / "detect_scene.py"
# The local run's provenance (.local/integration-1/hapur.geojson and the runbook §2).
DETECT_ARGS = ["--aoi", "hapur_test", "--conf", "0.25", "--iou", "0.3", "--ios", "0.6", "--batch", "16"]
SCENE = re.compile(r"S2[ABC]_T\d{2}[A-Z]{3}_\d{8}T\d{6}_L2A")
RUN_ID = re.compile(r"[a-z0-9][a-z0-9-]{0,62}")
ENV = ("DATA_BUCKET", "MODEL_S3_PREFIX", "OUTPUT_S3_PREFIX")


def parse(argv):
    ap = argparse.ArgumentParser(description="Run the kiln detector on one Sentinel-2 scene.")
    ap.add_argument("--scene", required=True, help="one Sentinel-2 L2A STAC item id")
    ap.add_argument("--run-id", required=True, help="lowercase letters, digits and dashes")
    args = ap.parse_args(argv)
    if not SCENE.fullmatch(args.scene):
        ap.error("--scene must be one Sentinel-2 L2A STAC item id")
    if not RUN_ID.fullmatch(args.run_id):
        ap.error("--run-id must be 1-63 lowercase letters, digits and dashes")
    return args


def settings(environ):
    values = {k: environ.get(k, "") for k in ENV}
    if not all(values.values()):
        raise SystemExit("missing environment: " + ", ".join(k for k, v in values.items() if not v))
    for k in ENV[1:]:
        if values[k].startswith("/") or not values[k].endswith("/"):
            raise SystemExit(f"{k} must be a relative prefix ending in /")
    return values


def keys(model_prefix, output_prefix, run_id):
    return {"weights": f"{model_prefix}best.pt",
            "manifest": f"{model_prefix}checkpoint-manifest.json",
            "geojson": f"{output_prefix}{run_id}/kilns.geojson",
            "run": f"{output_prefix}{run_id}/run.json"}


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def verify(weights, manifest):
    """The checkpoint is a pickle: load it only if it is the verified baseline."""
    expected = json.loads(PINNED_MANIFEST.read_text())["sha256"]
    if json.loads(Path(manifest).read_text()).get("sha256") != expected or sha256(weights) != expected:
        raise SystemExit("checkpoint hash differs from the pinned manifest; refusing to run")
    return expected


def image_digest():
    uri = os.environ.get("ECS_CONTAINER_METADATA_URI_V4")
    if not uri:
        return None
    try:
        with urllib.request.urlopen(uri, timeout=5) as r:
            return json.load(r).get("ImageID")
    except Exception:
        return None


def run(argv, environ=os.environ, s3=None, detect=subprocess.run):
    args = parse(argv)
    env = settings(environ)
    k = keys(env["MODEL_S3_PREFIX"], env["OUTPUT_S3_PREFIX"], args.run_id)
    if s3 is None:
        import boto3
        s3 = boto3.client("s3")
    bucket = env["DATA_BUCKET"]
    work = Path(tempfile.mkdtemp())
    weights, manifest, out = work / "best.pt", work / "checkpoint-manifest.json", work / "out.geojson"

    t0 = time.monotonic()
    s3.download_file(bucket, k["weights"], str(weights))
    s3.download_file(bucket, k["manifest"], str(manifest))
    model_sha = verify(weights, manifest)
    t1 = time.monotonic()
    detect([sys.executable, str(DETECT), "--scene", args.scene, "--weights", str(weights),
            "--artifact-manifest", str(manifest), "--out", str(out), *DETECT_ARGS], check=True)
    t2 = time.monotonic()

    geo = json.loads(out.read_text())
    meta = geo["kilnwatch"]
    by_type = dict(Counter(f["properties"]["type"] for f in geo["features"]))
    timings = {"download_verify_s": round(t1 - t0, 1), "detect_s": round(t2 - t1, 1)}
    s3.upload_file(str(out), bucket, k["geojson"], ExtraArgs={"ContentType": "application/geo+json"})
    timings["total_s"] = round(time.monotonic() - t0, 1)
    record = {
        "schema_version": 1,
        "run_id": args.run_id,
        "scene": args.scene,
        "scenes": meta["scenes"],
        "model_sha256": model_sha,
        "model_version": meta["model_version"],
        "registry_input_sha256": sha256(out),
        "candidates": len(geo["features"]),
        "by_type": by_type,
        "params": meta["params"],
        "timings": timings,
        "image_digest": image_digest(),
        "runtime": {"machine": platform.machine(), "python": platform.python_version()},
        "created": meta["created"],
    }
    s3.put_object(Bucket=bucket, Key=k["run"], Body=json.dumps(record, indent=1).encode(),
                  ContentType="application/json")
    print(json.dumps({"run_id": args.run_id, "candidates": record["candidates"], "by_type": by_type,
                      "timings": timings}))
    return 0


def main(argv=None):
    try:
        return run(sys.argv[1:] if argv is None else argv)
    except SystemExit:
        raise
    except Exception as e:  # The type only: messages can carry bucket names or ARNs.
        print(f"run failed: {type(e).__name__}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
