# Prompt 05: Integration 1 — baseline model to AWS registry/read API

You are the builder for **one integration step** in KilnWatch. The model, AWS foundation and iOS app are now together on `main`. The orchestrator has inspected the source and written `App/docs/integration-status.md`. Build the first model-to-registry/read-API bridge and verify its payload with the app's existing Swift package. Prepare a concrete deployment runbook; **AWS has not been deployed yet**.

Work sequentially. No parallel agents, delegation, audits, commits or pushes. Do not begin Phase 3 UI, retraining, full inference automation, agents, route planning or verdict submission. Do not apply Terraform, create/update cloud resources, upload to a live bucket or write to a live database in this step. Local implementation, tests and deployment preparation are the authorized deliverables. A later deployment request will authorize the live writes.

## People to name consistently

- **ML team mate:** supplies the kiln-trained `best.pt`, corresponding run metadata/evaluation and any existing Hapur detection output. Owns model quality and training.
- **AWS teammate:** owns the AWS account, deployment, registry/backend, storage, identity and network configuration.
- **App orchestrator/builder:** owns the shared contract, Swift compatibility and later app phases.

These are human teammates, not agents to spawn. Ask the user for missing artifact paths or operational choices; do not send messages to teammates.

## Read before changing anything

1. Root `AGENTS.md`, `App/docs/HANDOVER.md`, `App/docs/build-plan.md` and `App/docs/DESIGN.md`. Older instructions naming PortalAPP/parallel waves are historical; the user's current branch is `main` and work is sequential.
2. `App/docs/integration-status.md`, then `App/docs/api-contract.md`.
3. `Model/results/baseline_scores.json`, `Model/scripts/{prepare_data,train,detect_scene}.py`, both `Model/notebooks/` notebooks and `Model/Readme.md`.
4. All relevant `AWS/*.tf`, `AWS/README.md`, `AWS/lambda/api_handler.py` and agent source. Identify default-disabled resources and the actual HTTP API/auth configuration.
5. `App/Packages/KilnWatchCore/{Sources,Tests}`, `App/KilnWatch/KilnWatchApp.swift` and app presentation helpers. Read `App/docs/research/evidence-imagery.md`, `auth.md`, `routing.md` and `agent-streaming.md` as proposals, not completed infrastructure.
6. Relevant concept sections in `App/docs/concept.txt`: model preprocessing, guardrails, architecture and the p.15 record.

Use primary AWS/PostGIS/Ultralytics documentation to verify decisions. For Swift schema/networking edits, use available Axiom data/networking/testing skills; for unavoidable presentation edits load design/SwiftUI skills. The binding design must remain intact. No framework or tool installation merely to inspect source; use project-local dependencies when needed for actual checks.

## Definition of this step

Implement a reproducible local path:

**existing kiln-trained checkpoint → small fixed Hapur run → real detection export and evidence → transactional registry import → list/detail JSON → KilnWatchCore decoder**.

Only one small area/run is needed. Prefer the ML team mate's already-produced Hapur export when its provenance can be verified. Build the software even if an input artifact is missing, but clearly mark real-input checks as blocked. Synthetic tests must be named as tests and never counted as real detection evidence. No claim of a live connection until the separate deployment verification succeeds.

## A. Locate and verify the checkpoint first

- Request the existing artifact path if not provided. The user has asked where to get `.pt`: explain that the ML team mate must retrieve the completed training run's `weights/best.pt` from the saved Kaggle version's Output, local trainer output directory, or an already-used artifact location.
- The baseline notebook searches nested run directories; do not assume one exact path. Its expected run name is `baseline`; the larger notebook uses `main`. `scores.json` and `args.yaml` should accompany the chosen weights. A generic downloaded `yolo11s-obb.pt` is not the trained kiln checkpoint.
- Verify a trusted checkpoint loads as OBB, its kiln class mapping, library version, run identity and SHA-256. Store a small artifact manifest, not weights or secrets, in source. Keep large weights, imagery and raw output in ignored locations. Do not recreate weights from metrics or start training if they are missing.
- Fix the moved paths in both notebooks (`KilnWatch/Model/scripts/...`, including the commented upload import), and relevant documentation. Verify notebook syntax/paths without executing training cells. Preserve the longer run's time cap; do not assert its completion or guarantee its duration.

## B. Define the actual shared record before implementing storage

Update `App/docs/api-contract.md` with a **backward-compatible, explicit schema** for a model-only candidate. Keep the main record/envelopes, snake_case conventions, unknown enum support and RFC 3339 timestamps. Make the implementation and representative JSON agree; no second incompatible candidate API for the app.

- Detector input: closed GeoJSON Polygon rings using `[longitude, latitude]`, centroid, predicted type/class score, scene identity/date and run-level metadata. Convert to the core's open four-corner coordinate-object footprint. Validate finite/range-correct coordinates, polygon shape and confidence values; reject malformed imports without partial writes.
- Assign a stable registry `kiln_id`. Keep import/run identity separate from site identity. Re-running the same input and reordered features must not duplicate candidates. Preserve any human verdict/review state on re-import. Cross-scene matching can remain a documented later task; do not pretend a geometry hash makes IDs stable across model versions.
- Recover the actual acquisition timestamp from source/STAC provenance rather than inventing midnight to satisfy Swift decoding. Keep import time separate from first/last observed scene times. A newly recorded detection is not proof a kiln first appeared on that date.
- Preserve model version/hash, source scene and input-file checksum. Explicitly identify the class score's meaning: current detector copies it into both confidence fields; do not claim two calibrated confidence measures.
- Baseline kiln type remains **unverified even when the score exceeds 0.7**. Represent this explicitly in optional provenance/verification metadata and prevent C-TECH-10K conclusions from it. Persist all candidates as satellite-flagged/pending review; neither an importer nor agent can set confirmed/compliant status.
- **Missing information is not zero:** model output contains no population counts or measured rule flags. Add the minimum optional fields/assessment states needed to express unknown exposure and rules not evaluated. An empty violation list must not mean rules passed. Do not copy fixture figures, generate made-up school/home points, fabricate an evidence URL or add a placeholder technology violation.
- Before/after evidence must tolerate an unavailable side. Preserve compatibility with the existing URL-string evidence form; add scene/acquisition/size/pixel-footprint/attribution metadata without needlessly replacing it. Core currently requires both URLs and exposure counts, so fix the semantic mismatch with deliberate optionals and focused tests, not silent decoding defaults.
- Prefer modifying existing shared core types over duplicating domain types. Mechanical app compile fixes and truthful unavailable/unverified text are in scope; comparison UI/image loading/redesign are Phase 3. Do not allow a live model record to display the mock Apple snapshot as real satellite evidence.

## C. Build evidence preparation for the first record

- Implement a small reproducible CLI/helper that cuts the proposed 256×256 PNG evidence patches from Sentinel-2 source scenes, preserving acquisition and source IDs, CRS/pixel grid, geotransform and footprint-in-patch pixel coordinates. Start with the after image; select a valid matching historical scene for before, or mark it unavailable.
- Follow the evidence research: align dates on the same grid; use consistent true-color rendering. The detector's per-patch training normalization is not the visual comparison pipeline. Dataset training tiles are not interchangeable with aligned historical evidence.
- Verify bounds/axis order/footprint placement, dimensions, nodata handling and attribution. Never reuse one image for both dates and claim change. Save an inspectable real pair when artifacts/source access permit.
- Produce a publication manifest for satellite evidence under an immutable/content-addressed prefix such as `evidence/`. Record object checksums and model/scene linkage. Keep model files, raw exports and future field photos private. Local test images are not public evidence.

## D. Implement registry schema and an idempotent importer

- Use the existing PostgreSQL/PostGIS direction. Add versioned SQL migrations enabling PostGIS and creating only the tables needed for import runs, candidates/observations and evidence/provenance. Use spatial data with explicit WGS84 SRID and constraints/indexes matching the initial read queries. Do not build the whole review console, assessment engine or verdict schema yet.
- Build a CLI import with validation/dry-run, transaction boundaries, row counts and safe retry behavior. Support importing one verified detection export and its evidence manifest. Use parameterized queries; migrations and import reruns must be idempotent. A bad record must not leave a half-imported batch or overwrite human state.
- Keep logical import/conversion independently testable without S3, a model download or live RDS. Prove actual persistence against a disposable local PostgreSQL/PostGIS database where tooling permits; a mocked repository is not database integration proof. If unavailable, report the exact unrun check and preserve the test/runbook.
- Reuse existing AWS structure. Package a compatible PostgreSQL driver for Lambda's Python/runtime/architecture; Terraform currently archives only `api_handler.py`, which will not package new modules or dependencies. Fix the build/package path and use pinned dependencies. No production passwords or hard-coded database credentials in source.

## E. Replace the read API placeholders

- Implement `GET /kilns?district=...&status=...` returning `{"kilns": [...]}` and `GET /kilns/{id}` returning the agreed record. Use the same serializer as contract tests. Set sensible result limits and document pagination if needed; do not truncate silently.
- Standardize nested error responses from the app contract and meaningful 400/401/403/404/5xx behavior. A database failure is an error, not a successful empty registry. Validate filters/IDs and do not return SQL errors or secrets.
- Use the existing **HTTP API JWT authorizer** and trusted claims passed to Lambda. Document the initial token type/read-permission policy and enforce it server-side. Missing role/district authorization data must not default to access. Keep a clearly controlled test identity provisioning procedure for the AWS teammate; no shared production password or fake bearer token in a live test.
- Cognito source lacks groups/district configuration and managed-login setup. Add only configuration required by this read proof; full iOS PKCE/Keychain sign-in remains Phase 5. If ID tokens are used initially, state that explicitly; access-token district claims need a real trusted mapping/trigger. Do not claim Verified Permissions exists—it is absent from current Terraform.
- Keep public endpoints from leaking unreviewed/private records or inspector information. Do not expand `/public/kilns` into a resident product in this step. Use an explicit approved-public projection or keep publication unavailable until its policy is defined.
- `/routes/today`, `/rules`, verdicts, jobs and agents remain separate work. Report these omissions honestly; do not create a fake one-stop inspection route just to make Today show imported data.

## F. Prepare the minimum AWS deployment changes and handoff

Prepare source and a runnable, reviewed deployment sequence, **without executing cloud writes**:

- Use existing S3/RDS/API/Cognito resources where suitable. Add CloudFront with origin access control and an S3 policy limited to publishable evidence objects; the shared bucket also holds private model artifacts. Public access to evidence through a distribution must not make the bucket or all prefixes public.
- Lambda is in private subnets with no NAT/endpoints. Provide the concrete Secrets Manager endpoint/network path and any S3 access needed by the implemented handler. IAM permission alone is insufficient. Keep RDS private; document how migrations/imports execute with private database access, rather than opening it to the internet.
- Separate runtime read permissions from administrative migration/import permissions where practical. Enforce TLS to the database and handle connection/secret failures without hiding them. Do not broaden IAM simply to make tests pass.
- Document account/profile/region and Terraform state ownership questions for the AWS teammate. Provide a redacted `terraform.tfvars.example` (the README references one that is missing), correct build commands, dependency packaging and required resource outputs.
- Keep AgentCore, SageMaker training, Amplify and optional long-running ECS service disabled. Do not build a new inference container/scene workflow merely to import an existing local export. Document those as later work.
- Run format/validation locally if Terraform is available; do not upgrade the checked-in provider lock unnecessarily. A plan may be generated only with an explicitly identified authorized account/profile and read access. If tools/account are unavailable, document the exact commands for the AWS teammate and label them unrun.
- The runbook must give: checkpoint retrieval/verification → local detection/evidence → package → infrastructure plan review → apply after user authorization → schema migration/import through the private path → acquire a legitimate test token → authenticated GET/image smoke checks → Swift decode. Include measured/quoted costs only if researched; do not invent a monthly total.

## Tests and evidence required

1. Conversion tests: closed-to-open polygon/axis order, bad geometry/confidence, exact scene timestamp, known/unknown types, unassessed exposure/rules, missing imagery and explicit unverified baseline type.
2. Import tests: retry/reordered input without duplicates, transaction rollback for malformed input, observation provenance and preservation of existing human decisions.
3. API tests: actual envelope/detail payload, filters, missing ID, denied identity/district, database failure and public-field projection.
4. Evidence tests: deterministic image dimensions, pixel-coordinate transformation, honest missing-before state and manifest checksums. Inspect the first real output rather than assuming alignment.
5. Python-to-Swift contract proof: generate JSON through the actual importer/API serializer, then decode it with `JSONDecoder.kilnWatch`. Use an offline `URLProtocol` test to exercise the existing API client with that body. Do not independently handcraft a second payload that only mirrors Swift expectations. Keep legacy fixtures/routes and the existing core suite passing.
6. If shared Swift/presentation code changed, run the prescribed root app build and core tests sequentially:

```sh
xcodebuild -project KilnWatch.xcodeproj -scheme KilnWatch -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Run `swift test` from `App/Packages/KilnWatchCore`. No extra screenshot/video campaign for this backend step. Verify changed unknown/unverified presentation with a focused check if needed.

Keep real smoke checks, synthetic tests and unrun deployment checks separate in the report. Never put weights, complete raw imagery/exports, tokens, account credentials, Terraform state or local secret variables into Git. Small clearly labeled unit fixtures and redacted manifests are appropriate.

## Deliverables and stop point

- Code: evidence preparation, registry migrations/import, read API, required packaging/Terraform source, focused tests and minimal backward-compatible core adjustments.
- Documentation: revised shared contract, artifact manifest template, accurate README paths, and `AWS/docs/first-record-runbook.md` with prerequisites/commands and ownership.
- Update `App/docs/integration-status.md` and HANDOVER with exact verified progress, input sources and remaining dependencies. Do not mark AWS deployed or Phase 3 complete.
- Report: files/behavior; checkpoint identity; real input/counts and provenance; Python/DB/Swift/build results; security/permission decisions; unrun checks; and a short handoff separated into **ML team mate**, **AWS teammate**, and **App**.
- If artifacts are missing, ask early and continue the independent software/tests/runbook work. Mark the real-data milestone incomplete instead of substituting mocks. If the completed training outputs were lost, report that before proposing retraining.

Stop after this integration step. The orchestrator/user reviews the implementation and deployment plan before any live deployment or Phase 3 work.
