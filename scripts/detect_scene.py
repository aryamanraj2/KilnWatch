"""Find kilns in fresh Sentinel-2 imagery and write them as map polygons.

    python scripts/detect_scene.py --aoi hapur_test --weights best.pt --out kilns.geojson

Steps (PDF section 02, "Running it on new imagery"), each mirroring how
SentinelKilnDB tiles were made, because a model only works on data that looks
like its training data:
  1 select   the clearest Sentinel-2 L2A scene per MGRS tile over the area
  2 read     red, green, blue (B4, B3, B2) at 10 m, straight from the public COGs
  3 cut      128 x 128 px patches with a 30 px overlap (stride 98)
  4 scale    min-max each patch and each band to 0-255
  5 detect   YOLO11-OBB on every patch
  6 merge    rotated NMS across overlaps and across neighbouring MGRS tiles
  7 place    pixel corners -> lat/lon polygons

Without --weights it stops after step 4; with --save-patches that is how the
patches get compared with the dataset's own tiles.

Each feature carries the fields of the kiln record the model owns (PDF p.15).
kiln_id, first_seen and status are assigned by the registry, not here.
detection_confidence and type_confidence are both YOLO's score for the predicted
type until a separate any-kiln score exists.
"""

import argparse
from datetime import date, datetime, timedelta, timezone
import json
import math
import os
from pathlib import Path
import sys
import urllib.request

import numpy as np
import rasterio
from rasterio.warp import transform_bounds
from rasterio.windows import Window, from_bounds
from pyproj import Transformer
from shapely import STRtree
from shapely.geometry import Polygon

sys.path.insert(0, str(Path(__file__).parent))
from prepare_data import AOI as DATASET_AOI  # noqa: E402

STAC = "https://earth-search.aws.element84.com/v1/search"
COLLECTION = "sentinel-2-c1-l2a"
PATCH, STRIDE = 128, 98
WORK_CRS = "EPSG:32643"      # UTM 43N: metric, and fine a few degrees into zone 44

# (lat_min, lat_max, lon_min, lon_max), same convention as prepare_data.py
AOI = dict(DATASET_AOI, **{
    "hapur_test": (28.68, 28.78, 77.73, 77.83),     # ~11 x 10 km around Hapur town
})

# Public bucket: no credentials, no directory listings.
os.environ.setdefault("AWS_NO_SIGN_REQUEST", "YES")
os.environ.setdefault("GDAL_DISABLE_READDIR_ON_OPEN", "EMPTY_DIR")
os.environ.setdefault("CPL_VSIL_CURL_ALLOWED_EXTENSIONS", ".tif")


def stac(body):
    req = urllib.request.Request(STAC, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=60))["features"]


def search(box, start, end, max_cloud):
    """STAC items over the box, clearest first."""
    lat_min, lat_max, lon_min, lon_max = box
    items = stac({
        "collections": [COLLECTION],
        "bbox": [lon_min, lat_min, lon_max, lat_max],
        "datetime": f"{start}T00:00:00Z/{end}T23:59:59Z",
        "query": {"eo:cloud_cover": {"lte": max_cloud}},
        "limit": 200,
    })
    # Completeness first: a half-empty scene at a swath edge leaves a hole in the area.
    return sorted(items, key=lambda f: (round(f["properties"]["s2:nodata_pixel_percentage"] / 5),
                                        f["properties"]["eo:cloud_cover"],
                                        -datetime.fromisoformat(f["properties"]["datetime"]).timestamp()))


def pick_scenes(items):
    """One scene per MGRS tile: the clearest, then the most complete, then the newest."""
    best = {}
    for f in items:
        best.setdefault(f["properties"]["grid:code"], f)
    return list(best.values())


def read_rgb(item, box):
    """The box's part of the scene as an (H, W, 3) uint16 RGB array, plus its
    affine transform and CRS. None if the scene doesn't reach the box."""
    lat_min, lat_max, lon_min, lon_max = box
    arrays = []
    for band in ("red", "green", "blue"):
        with rasterio.open(item["assets"][band]["href"]) as src:
            if not arrays:
                bounds = transform_bounds("EPSG:4326", src.crs, lon_min, lat_min, lon_max, lat_max)
                win = from_bounds(*bounds, transform=src.transform)
                win = win.intersection(Window(0, 0, src.width, src.height))
                win = win.round_offsets().round_lengths()
                if win.width < PATCH or win.height < PATCH:
                    return None
                transform, crs = src.window_transform(win), src.crs
            arrays.append(src.read(1, window=win))
    return np.dstack(arrays), transform, crs


def norm(band):
    """Per patch, per band, identical to SentinelKilnDB."""
    band = band.astype(np.float32)
    return ((band - band.min()) / (band.max() - band.min() + 1e-5) * 255).astype("uint8")


def starts(n):
    """Patch offsets along one axis: stride 98, plus a last patch flush with the edge."""
    s = list(range(0, n - PATCH + 1, STRIDE))
    if s and s[-1] != n - PATCH:
        s.append(n - PATCH)
    return s


def patches(rgb, max_nodata):
    """-> (row, col, normalised RGB uint8 patch) for every usable patch."""
    h, w, _ = rgb.shape
    for r in starts(h):
        for c in starts(w):
            raw = rgb[r:r + PATCH, c:c + PATCH]
            if (raw == 0).any(axis=2).mean() > max_nodata:
                continue
            yield r, c, np.dstack([norm(raw[..., i]) for i in range(3)])


def lonlat_of_pixel(transform, crs, x, y):
    to_ll = Transformer.from_crs(crs, "EPSG:4326", always_xy=True)
    return to_ll.transform(*(transform * (x, y)))


def detect(model, batch, conf, imgsz):
    """YOLO on a list of RGB patches -> per patch list of (corners_px, cls, conf).
    Ultralytics treats numpy input as BGR (like cv2.imread of the training PNGs),
    so channels are flipped here."""
    bgr = [np.ascontiguousarray(p[..., ::-1]) for p in batch]
    out = []
    for r in model.predict(bgr, imgsz=imgsz, conf=conf, agnostic_nms=True, verbose=False):
        o = r.obb
        out.append(list(zip(o.xyxyxyxy.cpu().numpy(), o.cls.cpu().numpy().astype(int),
                            o.conf.cpu().numpy())))
    return out


def merge(dets, iou_thr, ios_thr):
    """Greedy rotated NMS in metres, types ignored. A box is dropped if it overlaps a
    stronger one by IoU > iou_thr, or if most of it lies inside one (intersection over
    the smaller box > ios_thr) -- that catches kilns cut in half at a patch edge."""
    dets = sorted(dets, key=lambda d: -d["conf"])
    polys = [d["poly"] for d in dets]
    tree = STRtree(polys)
    dropped = set()
    keep = []
    for i, d in enumerate(dets):
        if i in dropped:
            continue
        keep.append(d)
        for j in tree.query(polys[i]):
            if j <= i or j in dropped:
                continue
            inter = polys[i].intersection(polys[j]).area
            if not inter:
                continue
            union = polys[i].area + polys[j].area - inter
            if inter / union > iou_thr or inter / min(polys[i].area, polys[j].area) > ios_thr:
                dropped.add(j)
    return keep


def shape_of(poly):
    """Length, width (m) and orientation (degrees from north, 0-180) of a box."""
    pts = list(poly.minimum_rotated_rectangle.exterior.coords)[:3]
    e1 = (pts[1][0] - pts[0][0], pts[1][1] - pts[0][1])
    e2 = (pts[2][0] - pts[1][0], pts[2][1] - pts[1][1])
    long_e = max(e1, e2, key=lambda e: math.hypot(*e))
    angle = math.degrees(math.atan2(long_e[0], long_e[1])) % 180
    return max(math.hypot(*e1), math.hypot(*e2)), min(math.hypot(*e1), math.hypot(*e2)), angle


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    where = ap.add_mutually_exclusive_group()
    where.add_argument("--aoi", choices=AOI, default="hapur_test")
    where.add_argument("--bbox", type=float, nargs=4, metavar=("LON_MIN", "LAT_MIN", "LON_MAX", "LAT_MAX"))
    ap.add_argument("--end", default=date.today().isoformat(), help="last acquisition date")
    ap.add_argument("--days", type=int, default=45, help="search window before --end")
    ap.add_argument("--max-cloud", type=float, default=1.0, help="scene cloud cover, percent")
    ap.add_argument("--scene", nargs="+", help="use these STAC item ids instead of searching")
    ap.add_argument("--weights", help="trained best.pt; omit to only cut patches")
    ap.add_argument("--conf", type=float, default=0.25)
    ap.add_argument("--iou", type=float, default=0.3, help="merge: IoU above which boxes are one kiln")
    ap.add_argument("--ios", type=float, default=0.6, help="merge: share of the smaller box inside the larger")
    ap.add_argument("--max-nodata", type=float, default=0.01, help="skip patches with more no-data than this")
    ap.add_argument("--batch", type=int, default=256)
    ap.add_argument("--out", type=Path, default=Path("kilns.geojson"))
    ap.add_argument("--save-patches", type=Path, help="also write each patch as <lat>_<lon>.png")
    args = ap.parse_args()

    if args.bbox:
        lon_min, lat_min, lon_max, lat_max = args.bbox
        box, aoi_name = (lat_min, lat_max, lon_min, lon_max), "bbox"
    else:
        box, aoi_name = AOI[args.aoi], args.aoi

    if args.scene:
        items = stac({"collections": [COLLECTION], "ids": args.scene, "limit": len(args.scene)})
        missing = set(args.scene) - {f["id"] for f in items}
        if missing:
            raise SystemExit(f"scenes not found over the area: {sorted(missing)}")
    else:
        start = (date.fromisoformat(args.end) - timedelta(days=args.days)).isoformat()
        found = search(box, start, args.end, args.max_cloud)
        if not found:
            raise SystemExit(f"no scene under {args.max_cloud}% cloud between {start} and "
                             f"{args.end} -- widen --days or raise --max-cloud")
        items = pick_scenes(found)

    model = None
    if args.weights:
        from ultralytics import YOLO
        model = YOLO(args.weights)
    if args.save_patches:
        args.save_patches.mkdir(parents=True, exist_ok=True)
        from PIL import Image

    to_work = {}
    dets, scenes = [], []
    for item in items:
        p = item["properties"]
        print(f"{item['id']}  {p['datetime'][:10]}  cloud {p['eo:cloud_cover']:.2f}%")
        got = read_rgb(item, box)
        if got is None:
            print("  doesn't reach the area, skipped")
            continue
        rgb, transform, crs = got
        if crs not in to_work:
            to_work[crs] = Transformer.from_crs(crs, WORK_CRS, always_xy=True)

        cut = list(patches(rgb, args.max_nodata))
        print(f"  {rgb.shape[1]} x {rgb.shape[0]} px -> {len(cut)} patches")
        scenes.append({"id": item["id"], "date": p["datetime"][:10],
                       "cloud_cover": p["eo:cloud_cover"], "patches": len(cut)})

        if args.save_patches:
            for r, c, patch in cut:
                lon, lat = lonlat_of_pixel(transform, crs, c + PATCH / 2, r + PATCH / 2)
                Image.fromarray(patch).save(args.save_patches / f"{lat:.4f}_{lon:.4f}.png")

        if model is None:
            continue
        for i in range(0, len(cut), args.batch):
            chunk = cut[i:i + args.batch]
            for (r, c, _), found in zip(chunk, detect(model, [x[2] for x in chunk], args.conf, PATCH)):
                for corners, cls, conf in found:
                    xs, ys = transform * (corners[:, 0] + c, corners[:, 1] + r)
                    wx, wy = to_work[crs].transform(xs, ys)
                    dets.append({"poly": Polygon(zip(wx, wy)), "cls": int(cls), "conf": float(conf),
                                 "scene": item["id"], "date": p["datetime"][:10]})
        print(f"  {len(dets)} raw detections so far")

    if not scenes:
        raise SystemExit("no scene covered the area")
    if model is None:
        print(f"\nno --weights: cut patches only" +
              (f", saved to {args.save_patches}" if args.save_patches else ""))
        return

    kept = merge(dets, args.iou, args.ios)
    to_ll = Transformer.from_crs(WORK_CRS, "EPSG:4326", always_xy=True)
    features = []
    for d in kept:
        xs, ys = d["poly"].exterior.xy
        lons, lats = to_ll.transform(list(xs), list(ys))
        clon, clat = to_ll.transform(d["poly"].centroid.x, d["poly"].centroid.y)
        length, width, angle = shape_of(d["poly"])
        features.append({
            "type": "Feature",
            "geometry": {"type": "Polygon",
                         "coordinates": [[[round(x, 6), round(y, 6)] for x, y in zip(lons, lats)]]},
            "properties": {
                "type": model.names[d["cls"]],
                "detection_confidence": round(d["conf"], 3),
                "type_confidence": round(d["conf"], 3),
                "scene_id": d["scene"],
                "scene_date": d["date"],
                "centroid": [round(clon, 6), round(clat, 6)],
                "area_m2": round(d["poly"].area),
                "length_m": round(length),
                "width_m": round(width),
                "orientation_deg": round(angle),
            },
        })

    out = {
        "type": "FeatureCollection",
        "features": features,
        "kilnwatch": {
            "created": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "aoi": {"name": aoi_name, "lat_min": box[0], "lat_max": box[1],
                    "lon_min": box[2], "lon_max": box[3]},
            "scenes": scenes,
            "model": Path(args.weights).name,
            "params": {"conf": args.conf, "iou": args.iou, "ios": args.ios,
                       "patch": PATCH, "stride": STRIDE, "max_nodata": args.max_nodata},
        },
    }
    args.out.write_text(json.dumps(out, indent=1))
    types = {}
    for f in features:
        types[f["properties"]["type"]] = types.get(f["properties"]["type"], 0) + 1
    print(f"\n{len(dets)} raw detections -> {len(features)} kilns {types}\nwrote {args.out}")


if __name__ == "__main__":
    main()
