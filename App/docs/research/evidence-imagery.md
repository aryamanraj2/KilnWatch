# Evidence imagery: what the before/after patches look like

Researched 2026-10-09. I queried the Earth Search STAC live for Hapur (28.73° N, 77.78° E).

## Integration 1 implementation note

The implemented contract preserves legacy `before`/`after` URL strings and adds
`before_metadata`/`after_metadata`; the object-valued proposal below is superseded
by `api-contract.md` for this bridge. Unpublished/unavailable URL sides are null.
The preparer uses RGB source bands with each scene's STAC scale/offset and a fixed
0–0.3 reflectance stretch, rather than the `visual` asset. This deliberate choice
keeps the same explicit rendering across dates without per-patch normalization.
The real pair is 2023-12-05 / 2026-10-05 on one native EPSG:32643 grid; no historical
kiln outline, precise co-registration or change conclusion is asserted. Public
CloudFront source is prepared, not deployed, and PNGs are still local/unpublished.

## Recommendation

For each kiln, the backend cuts **two 256 × 256 px PNGs (2.56 km square, 10 m/px)** centred on the kiln centroid. Both come from the same Sentinel-2 MGRS tile and the **same UTM pixel grid**: "before" is the clearest 2023–24 kiln-season scene, and "after" is the October 2026 scene the detector ran on. Use the 8-bit `visual` (true-colour) asset for both, so they share one fixed stretch. Do not use the model's per-patch min-max normalisation, which changes contrast from patch to patch and invents "change". Serve the PNGs from **public CloudFront with immutable, content-hashed keys** and S3 behind Origin Access Control; do not use signed URLs. The app upscales with **`.interpolation(.none)` at an integer device-pixel factor**: honest square pixels suit a measuring instrument, and smoothing implies detail that 10 m data does not have. The backend sends the **footprint in patch pixel coordinates** alongside lat/lon, so the overlay never depends on map projection maths on the phone.

## What a patch looks like

- A kiln is tiny: an FCBK trench is roughly 6–15 px long at 10 m. In a 128 px patch it fills about a tenth of the width. A 256 px patch centred on the kiln still shows it clearly at 2–3× zoom, and it fits the **800 m buffer (160 px diameter)** and the **1 km school/kiln rings (200 px)**. A 128 px patch cannot hold either ring.
- Size: 256 × 256 × 3 bytes is 196 KB raw. Expect roughly 100–170 KB as PNG, which is about 3 MB for nine stops × two seasons and fine for the offline route cache. Do not use JPEG, because its 8 × 8 blocks become 7× magnified artefacts. Lossless WebP or HEIC would be smaller, but PNG costs nothing to decode and is simplest.

## Pairing before and after

- **The dataset tiles are not a usable "before".** SentinelKilnDB was cut in Google Earth Engine (`COPERNICUS/S2_SR_HARMONIZED`, Nov 2023–Feb 2024, <1 % cloud, QA60 masking) on a grid stepped in **degrees** (0.0027° stride). They do not align pixel-for-pixel with our UTM patches, and they are licensed CC BY-NC.
- Instead, re-cut "before" from Earth Search `sentinel-2-c1-l2a`. Live query: Hapur is MGRS **43RGM, EPSG:32643**, with **7 scenes under 1 % cloud between Nov 2023 and Feb 2024** (e.g. `S2B_T43RGM_20231210T053918_L2A`, 0.0002 %) and fresh clear scenes on 2026-10-02 and 2026-10-05. Each MGRS tile is one fixed 10 m UTM grid (109.8 km, 10980 × 10980 px, per the collection's `proj:shape`), so a patch with identical bounds lands on the same pixels in both seasons. Residual misregistration between dates should be sub-pixel; I did not verify this, so check the first pair by eye.
- Rule: "before" = least cloud in Nov 2023–Feb 2024 on the same MGRS tile; "after" = the scene that produced the detection. Store both `scene_id`s so the pair can be reproduced.
- Attribution must be visible under the comparator: **"Contains modified Copernicus Sentinel data 2023, 2026"**. If dataset tiles or labels are shown, also credit SentinelKilnDB (CC BY-NC 4.0).

## Lat/lon → pixel, and why the server should do it

The patch is north-up in **UTM grid north**, not true north. At Hapur, in zone 43 (central meridian 75° E), the grid convergence is **1.34°**. A naive linear lat/lon mapping on the phone would put a polygon corner off by about **1.5 px at 64 px from centre and 4.2 px at the patch corner**: visible at 7× zoom, and it would make a correct box look misdrawn. The exact mapping is `(E, N) = UTM43N(lat, lon)`, then `col = (E − x0)/10` and `row = (y0 − N)/10`, with `(x0, y0)` the patch's top-left corner. The detector already outputs pixel corners before georeferencing, so the server can send them directly.

Proposed `evidence` block (extends concept page 15):

```json
"evidence": {
  "patch_px": 256, "gsd_m": 10, "crs": "EPSG:32643",
  "geotransform": [x0, 10, 0, y0, 0, -10],
  "before": { "url": "https://img.kilnwatch.example/p/3f9c…png", "scene_id": "S2B_T43RGM_20231210T053918_L2A", "acquired": "2023-12-10" },
  "after":  { "url": "https://img.kilnwatch.example/p/a71e…png", "scene_id": "S2B_T43RGM_20261005T053448_L2A", "acquired": "2026-10-05" },
  "footprint_px": [[121.4,119.0],[136.2,124.8],[134.6,129.1],[119.8,123.3]],
  "before_footprint_px": [[…]] | null,
  "centroid_px": [128.0, 124.1],
  "attribution": "Contains modified Copernicus Sentinel data 2023, 2026"
}
```

Pixel convention: continuous coordinates with the origin at the **top-left corner of the top-left pixel**, x to the right and y down (the GDAL and DOTA convention), so the centre of pixel (i, j) is (i+0.5, j+0.5). `before_footprint_px` comes from the 2023–24 label when one exists. It is null for a new kiln, and the after footprint is null for "no longer detected".

## Client example (`Image.interpolation(_:)` confirmed in the iOS 27 SwiftUI interface)

```swift
struct EvidencePatch: View {
    let image: UIImage            // decoded from the cached PNG (scale 1, 256 px)
    let footprint: [CGPoint]      // footprint_px
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geo in
            let k = max(1, floor(geo.size.width * displayScale / image.size.width))   // whole device pixels per source pixel
            let side = image.size.width * k / displayScale                          // points
            ZStack {
                Image(uiImage: image).resizable().interpolation(.none)
                Path { p in p.addLines(footprint.map { CGPoint(x: $0.x * side / 256, y: $0.y * side / 256) }); p.closeSubpath() }
                    .stroke(.white, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))   // "flagged", not a verdict
            }
            .frame(width: side, height: side)
            .accessibilityLabel("Satellite image, kiln outline shown")
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
```

A non-integer factor gives source pixels that alternate between 7 and 8 device pixels wide, and the mismatch shimmers in a wipe comparator. To zoom, crop the centre 128 px (concept-style framing) and keep the factor an integer.

## Public vs signed

The evidence is Copernicus open data, and the resident portal shows the same images publicly (concept page 14). Signing adds key groups and URL expiry, but buys no confidentiality. Expiring URLs also break the offline route cache unless the app stores bytes rather than URLs. Use **public, immutable, content-addressed keys** (`Cache-Control: public, max-age=31536000, immutable`) with S3 locked to CloudFront via OAC. Keep **field photos from verdicts private**: upload them with S3 presigned PUTs, read them back through signed URLs if they are ever needed, and never put them on the public distribution.

## Evidence

- SentinelKilnDB paper, imagery and tiling method: https://bytez.com/docs/neurips/121530/paper. Repo (PNG tiles, split counts): https://github.com/rishabh-mondal/SENTINELKILNDB_NeurIPS_2025
- Earth Search C1 L2A collection (`visual` = 8-bit uint8 TCI COG, 10 m): https://earth-search.aws.element84.com/v1/collections/sentinel-2-c1-l2a. The live `/v1/search` for 77.78,28.73 returned the scenes cited above.
- Copernicus attribution wording: https://sentinels.copernicus.eu/documents/247904/690755/Sentinel_Data_Legal_Notice (also https://documentation.dataspace.copernicus.eu/FAQ.html)
- CloudFront private content (signed URLs or cookies plus origin lockdown): https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/PrivateContent.html
- DOTA pixel-coordinate labels and conversion to YOLO-OBB: https://github.com/ultralytics/ultralytics/blob/7f43c3eece58ffa0ed8297ed71c29ec860a50164/docs/en/datasets/obb/index.md
- Convergence figure: γ = atan(tan(Δλ)·sin φ) with Δλ = 2.78°, φ = 28.73° gives 1.337° (computed locally).

## Open questions for the backend owner

1. Accept re-cutting "before" from Earth Search on the UTM grid, rather than reusing the dataset PNGs? This also takes the CC BY-NC tiles out of the public portal.
2. Are 256 px patches acceptable (rings fit), or do you want 128 px plus a separate context image?
3. Does any kiln straddle an MGRS tile edge? Those kilns need both patches from the neighbouring tile.
4. Who owns the "clearest scene" choice when October haze (concept page 8) hides a kiln? Proposal: send `after.cloud_pct` and a haze flag, and the app labels the image "hazy scene".
5. Confirm the `footprint_px` corner order (clockwise from the detector's first corner) and that it uses the same pixel origin as above.
