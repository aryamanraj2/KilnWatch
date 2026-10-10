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

# Integration 2A — local database proof and deployment preflight (2026-10-09)

Sequential, no agents. No `apply`, uploads, live migration/import/bootstrap, Cognito
users, inference, training, commits or pushes. The local database proof below is a
**local** proof on a disposable cluster, not an AWS or RDS proof.

## Code and configuration changes

- `registry/store.py`: the evidence upsert keeps an existing `published_url` when a
  replay has no receipt, and rejects (rolling back the whole batch) a replay that would
  change the bytes of a side that already has a verified URL (finding 1).
- `scripts/bootstrap_reader.py`: the failure message now names the exact
  `pg_roles` check and both recovery branches (finding 4).
- `tests/test_postgis.py`: six new opt-in tests (listed below); the rollback test now
  includes evidence rows.
- Terraform: `fmt` whitespace in `api.tf`, `bridge.tf`, `database.tf`, `network.tf`,
  `variables.tf`; `api.tf` had an HCL syntax error (a single-line block closed on the
  next line) that blocked `init`, fixed by moving the brace. Addendum: region default
  `ap-south-1`, RDS retention on, `PriceClass_200`, partial S3 backend with
  `required_version >= 1.10`, `backend.hcl.example`, `backend.hcl` ignored.

## Synthetic tests

Before the PostGIS enablement: **30 run, OK, 8 skipped** (the 8 PostGIS tests).
After, with `KILNWATCH_TEST_DB_PORT=55432`: **30 run, OK, 0 skipped.**

## Local PostgreSQL/PostGIS proof (disposable cluster)

Homebrew `postgresql@17` 17.11 with Homebrew `postgis` 3.6.4
(`POSTGIS="3.6.4" PGSQL="170"`); extension files in `postgresql@17`'s share directory.
Throwaway cluster under `.local/integration-2a/pg` (`initdb`, `scram-sha-256`, password
from a mode-600 file), listening only on `127.0.0.1:55432`, `ssl=on` with a throwaway
CA and a server certificate whose only name is `localhost`. Started with `pg_ctl`
(no `brew services`), stopped and the data directory removed after the proof.

PostGIS tests (all **ok**, real database, synthetic data):
`test_retry_reorder_human_state_and_provenance`,
`test_mid_transaction_failure_rolls_back_every_table` (now with evidence rows),
`test_evidence_republication_guard`, `test_district_conflict_rolls_back`,
`test_migration_checksum_tamper_detected`,
`test_persisted_list_filters_pagination_and_detail`,
`test_importer_role_persists_but_cannot_decide`,
`test_bootstrap_recovery_and_reader_is_select_only`.

**Bug found by the real run:** `bootstrap_reader.py` called
`format('… PASSWORD %L', %s)` with an untyped pg8000 parameter; PostgreSQL rejected it
(`42P18 could not determine data type of parameter $1`), so the script could never
create the reader on any real server. Fixed with `%s::text`.

- **Roles:** the bootstrapped `kilnwatch_api` login can `SELECT` every `kilnwatch`
  table; `INSERT`, `UPDATE` and `DELETE` on all five tables, and `UPDATE` of
  `status`/`review_state`/`assessment`, fail with `42501`. A `kilnwatch_importer`
  login runs `persist` (insert, `SELECT … FOR UPDATE`, evidence upsert and its
  publication merge) but cannot update `status`/`review_state`/`assessment` (`42501`).
- **Bootstrap recovery** (Secrets Manager stubbed in-process, no network or AWS):
  a forced commit failure leaves no role and a secret for a nonexistent role; a rerun
  creates the role and overwrites the secret with a new password that logs in. When the
  commit lands but the client sees an error, the role exists, the stored password logs
  in, and a rerun refuses.
- **TLS through `registry.db.connect_from_env`:** `DB_HOST=localhost` with the
  throwaway CA connects (TLSv1.3); `127.0.0.1` fails (`IP address mismatch`); a wrong
  CA fails (`unable to get local issuer certificate`). This proves the connector checks
  chain and hostname, not that RDS's certificate works.
- **Real records** (`registry.cli migrate` as `postgres`, then `registry.cli import` as
  a `kilnwatch_importer` login over TLS; real `hapur.geojson`, district `Hapur`, real
  `evidence/manifest.json`, no receipt): import 39 candidates / 39 observations; replay
  0 / 0. A **simulated** human decision (`confirmed`/`approved` on
  `KW-fd84509a2e3558a9bd529edaa5b4b97b`, set as `postgres`) survived a third replay
  (0 / 0) and was then reverted so the saved list is the unreviewed import. Tables:
  1 run, 39 candidates, 39 observations, 39 run links, 2 evidence rows.
- **Handler** (`api_handler.handler` as `kilnwatch_api` over TLS, synthetic test-only
  JWT claims): list 200 with 39; `limit=10` → 4 pages, 39 unique IDs, final
  `next_cursor=None`; detail `KW-6b3b38da681850e5af46b024f3d3f78e` 200 with
  `before_metadata`/`after_metadata` and null URLs; Meerut 403; unknown ID 404;
  `status=bad` 400; wrong port 503 and stopped cluster 503, never an empty list.
- **Swift:** `KILNWATCH_REAL_CONTRACT_LIST=.local/integration-2a/persisted-list.json
  swift test` → **26 tests passed**, including
  `localRealDetectionContractDecodesThroughExistingClient`. No Swift change.

Limits: local `postgres` is a true superuser, not RDS's `rds_superuser`; PostGIS 3.6.4
locally vs 3.5.x on RDS 17; RDS TLS, parameter groups and extension availability stay
unproven until deployment. This is database → handler → Swift decode, not API Gateway,
Cognito or AWS.

## Package (Python 3.12)

`AWS/build/api_handler.zip` SHA-256
`beeec4f9a9b2d9b29567d59a6c01f448ab4dd04221d3d3785ce238ae5ee661b9`, 94 entries. Top level:
`api_handler.py`, `rds-ca.pem`, `registry/{__init__,contract,db,store}.py`, `pg8000`,
`scramp`, `asn1crypto`, `dateutil`, `six.py` and their `dist-info`; no `evidence.py`,
`cli.py` or `pyproj`. Unpacked and imported with `/usr/local/bin/python3.12 -I`
(3.12.8): `api_handler`, `registry.store`, `pg8000` load from the ZIP; `rds-ca.pem`
loads into an `ssl` context (111 CA certificates); `/health` returns 200. This is a
compatibility smoke test, not a Lambda invocation.

## Terraform

Terraform 1.16.5 (official darwin_arm64 zip, SHA-256 `ecdef65e…4b7dc` matched
`SHA256SUMS`) in ignored `.local/tools/terraform`. `hashicorp/aws 6.68.0`,
`archive 2.8.1`, `random` from the unchanged lock file (`git diff` empty, SHA-256
`3238e308…df6f53` before and after). `init -backend=false -lockfile=readonly`,
`fmt -check -recursive` and `validate` pass. Then `init -backend-config=backend.hcl`
on the S3 state bucket and a read-only plan: **75 to add, 0 change, 0 destroy**.
Details and the plan review are in the runbook's deployment review.

## Portability checklist (ignored artifacts)

Copy privately (not Git, never with credentials) to another workstation:

| Path | Bytes | SHA-256 |
|---|---|---|
| `best.pt` | 19,713,480 | `3bcbcd0af696278d894ab6f463c81a742c596192d0493a470f0d03ac4b61f799` |
| `args.yaml` | 1,678 | `495598de9bbc87cd5928c965c6d145c60e50c7643d4889b242a908145f56afad` |
| `scores.json` | 994 | `8ac9b684b62db6094f6d5a65b7bdf094bd72ea70d811af4ecf0d0bf1b4c7c504` |
| `.local/integration-1/hapur.geojson` | 30,388 | `b1e9d177f68d58b48bdd75ff12f93ea244f66944d391710d433a8e2f6be013d0` |
| `.local/integration-1/hapur.scenes.json` | 24,261 | `1a4719f99cdc446c71920e61526e6b2f6907a1dfc30e4dba6a8cc8abd6f2e78b` |
| `.local/integration-1/before-scene.json` | 25,079 | `62bcd44f3182b5df8956de2dda5210789ec545b2ecb2c1c1828b75f80498ace1` |
| `.local/integration-1/evidence/manifest.json` | 4,328 | `7432c03d6aff6dcce1f2d358562b683646e08feb2de29823346265dbf4ebda0e` |
| `.local/integration-1/evidence/77aa718e….png` (before) | 136,079 | `77aa718e93395c091017e1e4094ca714c8191a57e13f16759f077afce4a498fc` |
| `.local/integration-1/evidence/a0a6c2ca….png` (after) | 147,338 | `a0a6c2ca17915c9ce3efc4f7bf52efc2a9b23628e6dd794673167087b9d42cc5` |

Regenerable: `.venv-integration/` (from the requirements files), `AWS/build/`
(`package_api.py`), previews and real list/detail JSON (from the inputs above).
**Not regenerable:** the weights `best.pt`; without them the 39 candidates cannot be
reproduced.

# Integration 2B — live deployment (2026-10-10)

Sequential, no agents, `kilnwatch` profile (IAM user `aryaman`, account matched
`backend.hcl`). No commits, pushes, inference, training, optional services or Phase 3.
Identifiers and Terraform outputs are kept only in ignored
`.local/integration-2b/outputs.json`; this document refers to output names.

## Status: deployed except CloudFront

- **73 of 75 planned resources are live in `ap-south-1`.** CloudFront refused
  `CreateDistributionWithTags` with `AccessDenied: Your account must be verified before
  you can add new CloudFront resources` (an AWS account-level gate, not a code or IAM
  issue). The user is opening an AWS Support case. A fresh plan shows exactly the
  reviewed remainder: **2 to add** (`aws_cloudfront_distribution.evidence`,
  `aws_s3_bucket_policy.evidence`), 0 change, 0 destroy. Saved privately as
  `2b-remainder.tfplan`; apply it after AWS confirms verification.
- Evidence publication, the receipt re-import and the CloudFront denial proof are
  therefore **not run**. The detail record carries image metadata and `null` URLs.
- **Auth decision (user, 2026-10-10):** the iOS app is for a demo video with
  placeholder data and will not sign in. No Cognito test inspector was created and no
  real ID token was used. `AWS/scripts/id_token.py` exists for later use and is unrun.

## Preflight

- Lock file byte-identical (`3238e308…`) after `init -backend-config=backend.hcl
  -lockfile=readonly`. Lambda ZIP unchanged: SHA-256 `beeec4f9…ee661b9`; packaged files
  equal current source; deployed `CodeSha256` matches.
- Python suite without a database: 30 run, OK, 8 skipped.
- Plan: 75 to add, 0 change, 0 destroy; resource set identical to the 2A plan.
- AWS Budget `kilnwatch-monthly-50` created (USD 50/month; email at 80% actual and
  100% forecast).

## Apply and post-apply checks

Apply ran 19:15–19:27 UTC (RDS 7 m 58 s), then failed on CloudFront as above. No
destroy. Read-only checks:

- RDS: `PubliclyAccessible=false`, `StorageEncrypted=true`, `DeletionProtection=true`,
  `BackupRetentionPeriod=7`, PostgreSQL 17.9, parameter group `in-sync`.
- Parameters: `rds.force_ssl=1`, `log_statement=none` (catalogue and live `SHOW`).
- Plan drift fixed: the provider defaulted `apply_method=immediate` on the static
  `rds.force_ssl`, while RDS reports `pending-reboot`; the next plan showed a perpetual
  in-place change that RDS would reject. `database.tf` now pins
  `apply_method = "pending-reboot"`. Value and security unchanged.
- Lambda: `python3.12`, `x86_64`, two private subnets, one SG; inline policy names only
  the reader secret (no master secret).
- Data bucket: all four public access blocks on.
- `GET /health` → 200, `registry_readiness: not_checked`.

## Runner (SSM, non-interactive)

- AL2023 2023.12 ships Python 3.9. `dnf install -y python3.12 python3.12-pip` gave
  Python 3.12.14 / pip 23.2.1. Venv from `requirements-operator.txt`: pg8000 1.31.5,
  boto3 1.42.73, pyproj 3.7.2. RDS CA bundle: 111 certificates.
- The first exact-key download returned 403: the runner's inline policy references the
  RDS master-secret ARN, so Terraform creates it only after RDS finishes. It worked once
  apply reached that point. Inputs verified by SHA-256 on the runner.
- `migrate` → applied `001_registry.sql`. Server: PostgreSQL 17.9, PostGIS 3.5.6, TLSv1.3.
- `bootstrap_reader.py` → reader login provisioned (first run, no recovery needed).
- `validate` → 39 records; input SHA `b1e9d177…`, evidence manifest SHA `7432c03d…`.
- `import` → 39 candidates / 39 observations; replay → **0 / 0** (same run ID).
- **Reader:** the runner role cannot *read* the reader secret (by design it may only
  write it), so `connect_from_env` with that secret is not possible there; IAM was not
  widened. As admin in a rolled-back transaction, `SET LOCAL ROLE kilnwatch_api`:
  `SELECT COUNT(*) FROM kilnwatch.candidates` = 39; `INSERT` → `42501`.
  `has_table_privilege`: SELECT true; INSERT/UPDATE/DELETE false. The reader secret
  itself was exercised by the live Lambda (below).

## Live API

Two kinds of evidence, reported separately:

**Through API Gateway (real HTTPS, no token):**

| Request | Result |
|---|---|
| `GET /kilns?district=Hapur`, no token | 401 |
| Same, malformed bearer | 401 |
| `GET /kilns/{id}`, no token | 401 |
| `POST /jobs`, no token | 401 |
| `GET /public/kilns` | 503 `publication_unavailable`, no private fields |
| `GET /health` | 200 `not_checked` |

**Direct `lambda:Invoke` by the operator with synthetic Hapur inspector claims**
(correct `aud`; bypasses API Gateway and Cognito, so it is *not* proof of the JWT
authorizer accepting a real token). This exercises the deployed Lambda → private
Secrets Manager endpoint → reader secret → RDS TLS path:

| Request | Result |
|---|---|
| `GET /kilns?district=Hapur` | 200, 39 records, all `flagged`/`pending`, `type_verification=unverified`, `rules_assessment=not_evaluated`, exposure null |
| `limit=10` paging | 4 pages, 39 unique IDs, final `next_cursor` null |
| `GET /kilns/KW-6b3b38da681850e5af46b024f3d3f78e` | 200; before/after metadata SHAs present; URLs null (not published) |
| `district=Meerut` | 403 `forbidden_district` |
| Unknown well-formed ID | 404 |
| `status=bad`, `limit=0` | 400 `invalid_filter` |
| `POST /jobs` | 501 |
| `/public/kilns` | 503 |

Not run: Cognito user, real ID-token requests, image HTTPS/checksum checks, database
outage test (proven locally in 2A; not to be run live).

Workstation note: `aws login` sessions need `botocore[crt]` for boto3 scripts. Instead of
adding a dependency, run them with
`eval "$(aws configure export-credentials --profile kilnwatch --region ap-south-1 --format env)"`
in a subshell (credentials stay in the environment, never printed or in arguments).

## Swift

`KILNWATCH_REAL_CONTRACT_LIST=<abs>/.local/integration-2b/live-list.json swift test` →
**26 tests passed**, zero warnings, including
`localRealDetectionContractDecodesThroughExistingClient`. Decoding proof only; the app
did not contact AWS.

# Integration 2C — public read API (2026-10-10)

Sequential, no agents, `kilnwatch` profile (IAM user `aryaman`). No commits, pushes,
Cognito users, inference, training, optional services, portal or Phase 3 work.

## Status: public read API live; CloudFront still pending

AWS has not yet verified the account (user, 2026-10-10), so CloudFront, evidence
publication, the denial probe and runner removal (Part B) were **not run**. Public
detail returns image metadata with `null` URLs until then.

## Code

- `registry/contract.py`: `public_view` allowlist projection (see `App/docs/api-contract.md`).
- `registry/store.py`: `public_near`, `public_list`, `public_detail`. Each hard-codes
  `c.status='flagged'` in SQL. Radius uses `ST_DWithin` on `geography` and
  `CEIL(ST_Distance(...))::int` for `distance_m`, with a `ponytail:` note about the
  skipped GiST index.
- `lambda/api_handler.py`: public routes before the identity check; strict query shapes;
  `public, max-age=60` on success, `no-store` on errors; shared 503 path.
- `api.tf`: `GET /public/kilns/{id}` (no auth); `$default` stage throttling (public
  routes 10/s burst 20, default 50/s burst 100); `aws_cloudwatch_log_group.api_lambda`
  with 14-day retention (imported, then the `import` block was removed).

## Tests

- Unit (no database): **34 run, OK, 8 skipped** (the PostGIS tests). New
  `PublicAPITests`: allowlist, no-claims reads with `/kilns` still 401, 21 invalid
  queries, non-flagged 404 identical to unknown, 503 on failure.
- Disposable cluster (recreated as in 2A under `.local/integration-2c/`: PostgreSQL
  17.11 + PostGIS 3.6.4, `127.0.0.1:55432`, `kilnwatch_test`, TLS with a throwaway CA):
  **35 run, OK, 0 skipped.** New `test_public_near_flagged_only_paging_and_detail`:
  inside-footprint distance 0, radius inclusion/exclusion at 100/2000/5000 m, distance
  ordering, a confirmed kiln excluded in SQL from near, list and detail, district paging,
  detail. All nine PostGIS tests passed. Python 3.13's strict TLS checks needed the throwaway
  CA to carry `keyUsage` and the server certificate an authority key identifier.
- Real local data (39 Hapur records, SELECT-only `kilnwatch_api` over TLS, no claims):
  near Hapur town r=2000 → 1 kiln (1,823 m); r=5000 → 22; near the evidence kiln → 0 m
  first; district paging 4 pages / 39 unique; a simulated decision hid that kiln from
  near, list (38) and detail (404, same body as unknown), then was reverted; 400s; wrong
  port 503. Cluster stopped and its data directory removed.
- Swift: `KILNWATCH_REAL_CONTRACT_LIST` with the local near-point and district bodies,
  then with the live ones → **26 tests passed** each, zero warnings. No Swift change.

## Package and deploy

`AWS/build/api_handler.zip` SHA-256
`f4fc23cb624f1a520d507ede70ffb1d8dbaabbf823542631c7a987ae75bcc8b6` (94 entries; packaged
source files byte-identical to the repository; Python 3.12 import smoke test passed).
Deployed `CodeSha256` matches.

**Targeted plan/apply** (`-target` on `aws_lambda_function.api`,
`aws_apigatewayv2_route.get_public_kiln`, `aws_apigatewayv2_stage.default`,
`aws_cloudwatch_log_group.api_lambda`): **1 import, 1 add, 3 in-place, 0 destroy.**
`-target` was used because an untargeted apply would retry the still-blocked CloudFront
distribution and fail. After apply and removing the `import` block, the targeted plan
shows no changes and the untargeted plan shows only the 2 CloudFront resources.
`/aws/lambda/kilnwatch-api` retention is 14 days. No reserved concurrency.

## Live HTTPS (`api_base_url`, no token)

| Request | Result |
|---|---|
| `lat=28.73&lon=77.78&radius_m=2000` | 200, 1 kiln, `distance_m` 1,823, flagged, no `review_state`/`provenance`, `public, max-age=60` |
| same, `radius_m=5000` | 200, 22 kilns, sorted, max 4,986 m |
| near the evidence kiln (default radius) | 200, 4 kilns, `KW-6b3b38da…` first at 0 m |
| `district=Hapur&limit=10` | 4 pages, 39 unique IDs, final `next_cursor` null |
| `/public/kilns/KW-6b3b38da681850e5af46b024f3d3f78e` | 200, metadata present, URLs null |
| unknown well-formed ID | 404 `not_found`, `no-store` |
| `radius_m=99999`, `lat=999`, `district`+`lat`/`lon`, `status=flagged` | 400 `invalid_filter` each |
| `/kilns` without token | 401 |
| `/health` | 200 |

Throttling confirmed read-only with `apigatewayv2 get-stage`: default 50/100, both public
routes 10/20. No load test.

