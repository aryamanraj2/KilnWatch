# Integration 1 local verification — 2026-10-09

Work completed sequentially on `main`; no agents/delegation, cloud writes, deployment,
training, commits, pushes or Phase 3 work. Existing user changes to AGENTS/HANDOVER,
integration-status and the phase prompt were preserved. This is a local source/test
proof, not an AWS connection or database persistence proof.

## Real inputs and verified local results

- Root `best.pt` supplied by the user; OBB load succeeded under Ultralytics 8.4.174 /
  Torch 2.14.1. 19,713,480 bytes; SHA-256
  `3bcbcd0af696278d894ab6f463c81a742c596192d0493a470f0d03ac4b61f799`.
  Classes: CFCBK / FCBK / Zigzag. Embedded baseline settings: 20 requested epochs,
  128 px, batch 64, full dataset. Checkpoint epoch=-1 is stripped and does not prove
  completed epochs. No model evaluation or training was run.
- The user subsequently supplied `args.yaml` and `scores.json` from the ML team mate.
  Major run settings match the checkpoint. Uploaded scores equal
  `Model/results/baseline_scores.json`. Args stores optimizer=auto and
  warmup_bias_lr=0.1; checkpoint stores resolved MuSGD and OBB-adjusted 0.0.
  Configuration agreement does not cryptographically link metrics to weights.
  Saved Kaggle notebook version/run identity remains missing.
- Existing scene detector with added manifest/hash/acquisition provenance: fixed
  Hapur AOI, `--end 2026-10-09 --days 45 --max-cloud 1 --batch 16`, checkpoint above.
  Selected scene `S2B_T43RGM_20261005T053448_L2A`, actual STAC acquisition
  `2026-10-05T05:41:03.148Z`. 1003×1131 source pixels → 120 patches → 55 raw
  detections → 39 candidates (5 CFCBK, 34 FCBK). No kiln truth/field precision claim.
- First sorted candidate: `KW-6b3b38da681850e5af46b024f3d3f78e`; one before/after
  pair cut from real source COGs. Before `S2A_T43RGM_20231205T053206_L2A`, actual
  STAC acquisition `2023-12-05T05:40:56.807Z`. Both 256×256 RGBA PNG, native
  EPSG:32643, transform `[765270,10,0,3184300,0,-10]`, nodata fraction 0, fixed RGB
  reflectance rendering using the source STAC scale/offset. Validated pixel corner
  placement against geographic footprint, dimensions and object checksums.
- Both images inspected directly: road/field landmarks show no gross displacement.
  Precise co-registration, pixel cloud/haze quality and kiln/change interpretation
  remain unverified. Historical footprint is unknown; no repeated-image change claim.
- Whole real batch validation/dry run accepts 39, with one evidence pair. Real local
  list/detail produced through the same converter/API serializer used by the bridge;
  all are flagged, unverified, rules not evaluated, exposure null. Unpublished URLs
  are null even when local image metadata exists. This is no database write.
- An additional Swift URLProtocol/decoder test consumed this actual 39-record local
  body. It proves the real local producer/client shape, not an AWS HTTP connection.
- Raw export, scenes, source imagery, preview, real JSON and PNGs stay ignored under
  `.local/integration-1/`; weights/args/scores are ignored at the workspace root.
  Small checkpoint manifest and synthetic unit fixtures are suitable for source.

## Synthetic tests and build/package checks

| Check | Verified result |
|---|---|
| Python `unittest discover -s AWS/tests -v` | 24 tests discovered: **22 passed, 2 explicitly skipped** |
| Conversion | Axis order/open corners, invalid/crossing geometry/confidence, exact/source timestamps, unknown type, unassessed facts, high-score unverified type, retry/reordering/corner rotation |
| Import unit checks | Complete validation before writes; transaction commit/rollback spies; status/review/assessment excluded from importer updates. **Not actual DB proof** |
| API checks | Shared envelope/detail serializer, filters/pages, 400/401/403/404/503, access-token/missing-claims denial, district isolation, sanitized DB failure, public endpoint unavailable/no private fields |
| Persisted-read unit check | Driver-compatible cursor closure and human status/review serialization; caught/fixed pg8000 cursor lacking a context-manager interface |
| Evidence synthetic checks | 256 px dimensions/checksums, footprint projection, matched historical grid, missing-before state, nodata and grid mismatch rejection |
| Generated synthetic Swift fixtures | Produced via production import preparation/evidence/API serializer, not a separately handcrafted Swift payload; include unknown type and unpublished metadata |
| KilnWatchCore | **26 tests passed**, including legacy fixtures/routes/outbox, Python list/detail/pages, malformed partial exposure, repeat-cursor failure and the real local 39-record decoder/client proof; **zero warnings** |
| Prescribed iPhone 17 app build | **BUILD SUCCEEDED, zero warnings** after final presentation safeguards |
| Lambda packaging | ZIP includes Python 3.12/x86_64-targeted pinned pure-Python pg8000 dependencies, read modules and RDS CA; local ZIP/module/driver imports and SSL CA context load passed |
| Notebook/source checks | Python code-cell syntax and corrected paths validated; training cells not executed; main 9-hour cap preserved; Python compilation and `git diff --check` passed |

The local Python environment emitted NumPy/rasterio and affine deprecation warnings;
they are dependency diagnostics, not zero-warning Python output. No extra screenshots,
videos, audits or simulator campaign were performed for this backend step. Focused
schema tests verify uncertain/unknown state; app source gates mock imagery to exact
fixture records with no configured API. Missing exposure/rules/images render honest
text using existing styles; no evidence loading/comparison redesign was added.

## Unrun checks and missing inputs

- **Actual PostgreSQL/PostGIS persistence:** psql is present, but no local PostGIS
  extension or Docker runtime. Two opt-in localhost-only tests are supplied for
  migration replay, actual retry/reordering without duplicates, human-state retention,
  spatial validity and rollback mid-batch. These must run before live import.
- **Terraform fmt/validate/plan:** Terraform absent; provider lock untouched. No
  identified/authorized account/profile/state owner, so no plan was generated.
- **AWS:** not deployed. AWS CLI absent. No RDS/secret/Lambda invocation, Cognito
  account/token, S3 upload, CloudFront retrieval or cloud access/denial test was run.
- **ML team mate:** saved Kaggle version/run identity, independent weight-to-score
  linkage, field precision/type assessment and interpretation of the selected pair.
- **AWS teammate:** account/profile/region/state, approved AOI/district assignment,
  publication policy, private migration/import runner, local PostGIS proof and plan
  review/deployment authorization. Review prototype backup/deletion behavior/costs.
- **App:** live endpoint/token/image proof and contract review before Phase 3. Registry
  fetching, evidence loading/comparison, rules/exposure, routes, agents, sign-in and
  verdict submission remain separate work. No fabricated Today route was added.

Security source uses trusted HTTP API JWT claims with explicit ID-token/client/role/
district checks; immutable district excluded from client writes; admin-only account
creation. Runtime gets only a dedicated SELECT role/secret, not RDS master. TLS checks
CA and hostname, with force_ssl configured. Lambda egress is limited to RDS and the
private Secrets Manager endpoint. CloudFront OAC policy only grants satellite PNG
prefix reads; public registry publication is disabled. Verified Permissions and
managed login are not claimed implemented/deployed.

Next artifact for review: [first-record-runbook.md](first-record-runbook.md).
