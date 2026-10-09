# KilnWatch: model, AWS and app integration status

Inspected 2026-10-09 on `main`, starting at `eb78715`. This is a source inspection, not a deployment or runtime audit. The user confirms **AWS is not deployed yet**. AWS CLI and Terraform were not available on this chat's shell PATH; no account inventory, cloud writes, training or deployment was performed.

## Integration 1 builder results (2026-10-09)

**Local implementation and contract proof prepared; AWS is still not deployed.**
Full verified results and explicit unrun checks:
[`AWS/docs/local-verification.md`](../../AWS/docs/local-verification.md).
Deployment sequence for review:
[`AWS/docs/first-record-runbook.md`](../../AWS/docs/first-record-runbook.md).
The older inspection sections below describe the pre-bridge source gaps.

- User supplied root `best.pt`, then `args.yaml`/`scores.json`. Checkpoint verified
  kiln-trained OBB, classes CFCBK/FCBK/Zigzag, SHA-256
  `3bcbcd0af696278d894ab6f463c81a742c596192d0493a470f0d03ac4b61f799`;
  embedded baseline settings match the supplied run configuration. Scores equal
  the checked-in baseline; no independent evaluation/retraining. Saved Kaggle
  version/run identity and cryptographic metric/weight linkage remain missing.
- One fixed real Hapur inference: 120 patches, 55 raw detections → **39 candidates**.
  Scene `S2B_T43RGM_20261005T053448_L2A`, actual acquisition
  `2026-10-05T05:41:03.148Z`. All remain satellite-flagged/pending inspection.
- One real, visually inspected 256 px before/after pair on a matching EPSG:32643
  native grid; before scene `S2A_T43RGM_20231205T053206_L2A`, acquisition
  `2023-12-05T05:40:56.807Z`. Checksums, metadata, pixel placement and whole-batch
  dry run passed. Co-registration/field interpretation unverified; images unpublished.
  Raw data/previews/images and weights remain ignored in the workspace.
- Added strict conversion, stable exact-output IDs, migrations, transactional import,
  district-scoped list/detail reads, closed public endpoint, driver packaging, TLS,
  runtime/admin credential separation, private secret endpoint and evidence-only
  CloudFront OAC source. Added optional controlled SSM runner source/runbook.
- Shared core supports null exposure/imagery, unassessed rules, unverified type,
  provenance/image metadata and pagination while preserving legacy fixtures/routes.
  Minimal app text/gates prevent zero counts, confident model type or mock satellite
  imagery being presented as real evidence. Phase 3 fetching/comparison is deferred.
- Python: **22 passed, 2 real PostGIS tests skipped** (24 discovered). Core:
  **26 tests passed, zero warnings**, including Python-produced synthetic responses
  and the actual 39-record local payload through decoder/URLProtocol client.
  Prescribed root app build passed with **zero warnings**. Lambda package/import/CA
  checks and notebook syntax/paths passed. Synthetic/API repositories are not DB proof.
- Unrun: actual PostGIS persistence (local extension/Docker unavailable), Terraform
  fmt/validate/plan (tool absent), all AWS deployment/authenticated/image checks.
  No deployment, training, commit/push, agents or Phase 3 work was performed.

Handoff: **ML team mate** supplies saved-run identity/evidence interpretation;
**AWS teammate** confirms account/state/district/publication, completes real DB tests
and reviews the deployment plan before authorized cloud writes; **App** reviews the
contract and waits for live proof before a separately requested Phase 3.

## Integration 2A — local database proof and deployment preflight (2026-10-09)

**AWS is still not deployed. No apply.** Evidence:
[`AWS/docs/local-verification.md`](../../AWS/docs/local-verification.md) (Integration 2A)
and the runbook's "Deployment review (Integration 2A)". Integration 1 is committed at
`6092cf8`.

- Fixed: replaying evidence without a receipt no longer erases a verified URL; a
  replay that would swap published bytes is rejected and rolled back.
- Real local PostGIS 3.6.4 / PostgreSQL 17.11 proof: 30 Python tests run, OK, 0
  skipped; real 39-record import 39/39, replay 0/0, human state kept; reader is
  SELECT-only, importer can't change decisions; TLS checks hostname and CA; handler
  list/pages/detail/403/404/400/503 correct; Swift decodes the persisted list.
- Fixed a real bug found there: `bootstrap_reader.py` could not create the reader on any
  PostgreSQL server (untyped `format()` parameter).
- Terraform 1.16.5: `fmt`/`validate` pass, lock file unchanged; one pre-existing HCL
  syntax error in `api.tf` fixed.
- Addendum decisions applied: `ap-south-1`; RDS 7-day backups, deletion protection,
  final snapshot; CloudFront `PriceClass_200`; S3 remote state with native locking.
  Publication of the two reviewed PNGs approved (upload in 2B).
- Only AWS write: state bucket `kilnwatch-tfstate-<account-id>-ap-south-1` (private,
  versioned, SSE-S3, TLS-only policy; verified). Read-only plan: **75 to add**.
  Estimated always-on cost ≈ **$38/month** before credits (estimate; assumptions in
  the runbook).

### App / Phase 3 follow-ups

- `App/KilnWatch/Features/Kiln/KilnView.swift:45` ("Within 800 m"), `:170`/`:212`
  (a fixed 800 m `MapCircle` and caption) and
  `App/KilnWatch/Design/Components/ExposureBlock.swift:4,29,43` hard-code 800 m. The
  800 m vs 1,000 m (UP) habitation rule is unresolved. Real records don't reach this
  view yet (no registry fetching). Resolve the rule and drive the radius from data in
  Phase 3; not changed now.

## People and ownership

- **ML team mate:** trained checkpoint, training-run metadata, detection output, imagery provenance and model evaluation.
- **AWS teammate:** AWS account and deployment, registry/database, evidence storage/delivery, authentication, permissions and backend API.
- **App orchestrator/builder:** the shared app contract, Swift compatibility, phase prompts and subsequent iOS integration.

The user runs a phase prompt in a fresh chat and returns its report. Work one step at a time, with no parallel agents. Do not commit or push without a user request.

## What the merged source contains

| Area | Implemented in source | Gap before a real app connection |
|---|---|---|
| Model preparation/training | `Model/scripts/prepare_data.py`, `train.py`, baseline/main Kaggle notebooks | Obtain the saved kiln-trained checkpoint; fix notebook paths after the move into `Model/` |
| Baseline results | `Model/results/baseline_scores.json`: YOLO11s-OBB, 20 epochs, 128 px, any-kiln AP50 0.8622 on full test data | This is not 86% accuracy or proof of field performance. No completed larger-model scores are checked in |
| Scene detection | `Model/scripts/detect_scene.py`: Earth Search, RGB tiling, normalization, OBB inference, merge and GeoJSON output | No importer, stable registry IDs, evidence pair generation or automatic S3/registry publishing |
| AWS foundation | Terraform for S3, ECR, ECS/Fargate, Step Functions, RDS, Lambda/HTTP API, Cognito and logging | Not deployed; containers, database schema and application handlers remain unfinished |
| Registry | Private PostgreSQL instance definition, with a comment to enable PostGIS | No migrations, import code or persisted kiln queries |
| API | JWT-protected `/kilns`, `/kilns/{id}`, `/jobs`; public `/health` and `/public/kilns` | Handler is a stub; no real records, route/rule/verdict handlers or app-compatible list envelope |
| Evidence | Private, encrypted, versioned S3 bucket definition | No evidence-cutting script, image metadata contract, CloudFront distribution or bucket-to-distribution policy |
| Agents | Strands/AgentCore container source, evidence/triage/resident behaviors | Disabled by default, not deployed; works from supplied JSON, not real registry tools. No actual route solver, citation validator, streaming planner or app-facing agent endpoint |
| App | Phases 0–2; shared models/client, Today, map selection, location, Maps handoffs and route cache | Real backend not connected. Kilns/details use records already in AppModel; they do not independently fetch the registry. Ask/verdict/sign-in remain mock flows |

## Where to get `best.pt`

`best.pt` is produced by the ML team mate's completed kiln-training run. It is not generated by merging Git branches. `Model/.gitignore` deliberately excludes `*.pt`, `*.geojson` and `runs/`.

Ask the **ML team mate** to open the **saved version** of the Kaggle notebook used for training, inspect its Output files, and download the run's `weights/best.pt`. Also preserve `scores.json`, `args.yaml`, run/version identity and the relevant training log. The baseline notebook searches recursively because Ultralytics may nest run folders; `runs/kilnwatch/baseline/weights/best.pt` is an example, not a verified exact path. A completed larger run may instead be under `main/weights/best.pt`.

If the run was local, the trainer printed its actual output directory; look under that directory's `weights/`. If the optional S3 upload was used, inspect the supplied bucket/prefix and run name. In this project AWS is not deployed, so no project bucket location is established.

Verify the checkpoint is the **kiln-trained OBB checkpoint**, not the generic pretrained `yolo11s-obb.pt`. Record its hash and class mapping. If the training output was never saved and the session is gone, its recovery is unverified; a metrics file cannot recreate the weights. Do not launch another training run as an automatic fallback.

The checkpoint is sufficient to run the detector. The detector then produces the GeoJSON; the AWS/app connection additionally needs registry records and evidence images.

## Integration mismatches to resolve first

1. **API shape:** Lambda currently emits `{"items": [], "nextToken": null}`. `KilnWatchAPI.kilns()` expects `{"kilns": [...]}`. API error bodies also differ from the contract's nested error object. The current HTTP API uses root paths, while the proposal's example base URL includes `/v1`; decide one consistent base-path convention.
2. **Geometry:** detector GeoJSON polygons are closed rings of `[longitude, latitude]` pairs. Core footprint polygons use four coordinate objects without the closing corner. Conversion and validation belong in the importer.
3. **Dates/provenance:** detector features include `scene_id` and a date-only `scene_date`; the Swift decoder requires RFC 3339 timestamps with an offset. Preserve the actual STAC acquisition timestamp. The current model provenance is only the weights basename, not a verified version/hash.
4. **Missing facts:** detections contain no assessed violations, population counts, stable kiln ID or before/after image URLs. Core currently requires exposure counts and both evidence URLs. Model-only records need an explicit unknown/not-evaluated representation; never copy fixture counts, invent dates/images or treat unassessed records as compliant.
5. **Type reliability:** the ML team mate reports substantial FCBK/Zigzag confusion on fresh imagery. Detector source assigns the same class score to `detection_confidence` and `type_confidence`; these are not independently calibrated. A score over 0.7 does not make baseline type trustworthy. Do not produce C-TECH-10K conclusions from it.
6. **Database access:** Lambda is in private subnets without NAT or service endpoints. Its Secrets Manager IAM permission is not a network path. A compatible packaged PostgreSQL driver, schema and secret-access endpoint/egress plan are needed. Laptop access to private RDS also requires a deliberate migration/import execution path.
7. **Authentication:** Cognito has a public client and the HTTP API JWT authorizer, but no managed-login domain/code-flow configuration, role groups, district custom attribute or Verified Permissions policy store. JWT authentication alone does not enforce the inspector's district permissions. Token type must be decided against this HTTP API, not the older REST API example.
8. **Inference automation:** Step Functions only launches an ECS task using an image tag. No inference Dockerfile, job input/output mapping, ingestion trigger or registry-publishing step exists in the checked-in pipeline. Reuse a local baseline run for the first bridge; automate inference later.
9. **Moved paths:** both Kaggle notebooks still call `KilnWatch/scripts/...`; those files now live at `KilnWatch/Model/scripts/...`. AWS/model README paths also need updating.

## How AWS will be used

First bridge: **saved baseline checkpoint → local Hapur detection/evidence preparation → import into registry → Lambda read API → Swift decoder**.

- **S3:** keep model artefacts and raw detection exports private; store generated evidence PNGs separately from private inspector photos.
- **RDS/PostGIS:** keep stable candidate IDs, geographic footprints, acquisition/model provenance and later measured assessments. Re-imports must not duplicate records or overwrite human decisions.
- **API Gateway + Lambda:** return authenticated, filtered records in the shared app contract. They do not train the model.
- **Cognito:** authenticate inspectors; server-side policy must separately enforce the allowed reads/writes.
- **CloudFront:** deliver explicitly publishable satellite evidence from a private S3 origin. This distribution is proposed, not currently implemented. Do not expose the entire shared bucket.
- **Later:** Fargate/Step Functions automate scene processing; Bedrock/Strands/AgentCore use real registry tools for planning and explanations; Amazon Location supplies road data. The first bridge does not need these enabled.

## Sequential checkpoints

1. **Integration 1:** recover/verify the existing checkpoint; build import, evidence preparation, read API and Swift contract tests locally; produce a reviewed deployment runbook. Prompt: `prompts/05-model-aws-bridge.md`.
2. **Deployment verification:** with the AWS teammate, review account/region, required resources and the concrete plan; deploy/import after explicit authorization. Prove a real record and its evidence can be retrieved with a valid inspector token, while disallowed requests fail.
3. **App Phase 3:** resume evidence UI and real registry fetching once the record/image contract is established. Do not show mock imagery or counts as real evidence.
4. **Measured rules/population and planned routes:** add the required geographic layers, measured assessments and real route output. Raw detections alone cannot supply these.
5. **Agent integration and remaining app phases:** registry-backed planner/streaming, sign-in, verdict capture/sync, Hindi/accessibility and release checks, each scoped separately.

Integration 1 prepares the software and local proof. It must not be reported as a live AWS/app connection before checkpoint 2 succeeds. Model improvement is separate; do not require a larger model merely to verify the data path.

## Documentation checked

- [AWS HTTP API JWT authorizers](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-jwt-authorizer.html): token validation and claims reach Lambda; application permissions still need enforcement.
- [Secrets Manager VPC endpoints](https://docs.aws.amazon.com/secretsmanager/latest/userguide/vpc-endpoint-overview.html): a private access path without opening public database access.
- [RDS PostGIS](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.PostgreSQL.CommonDBATasks.PostGIS.html): extension setup is distinct from provisioning the database instance.
- [CloudFront S3 origin access control](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html): private S3 origin with controlled distribution access.
- [Ultralytics training](https://docs.ultralytics.com/modes/train/) and [Kaggle notebook documentation](https://www.kaggle.com/docs/notebooks): training artifacts must be retained separately from source code.

No claim is made here that the friend's local diagnostic scripts, actual Hapur output, weights or larger training results have been independently reproduced.
