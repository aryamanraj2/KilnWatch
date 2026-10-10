# Prompt 09: Integration 2C — public read API, quick fixes, and CloudFront completion when verified

You are the builder for **one integration step** in KilnWatch. AWS is live in `ap-south-1`: 73 of 75 resources exist, and the 39 Hapur candidates are in RDS. CloudFront and its bucket policy are blocked until AWS verifies the account. Cognito sign-in is **not** used by the iOS app for now.

The user has approved **public, no-login reads** of satellite-flagged candidates, always presented as "Flagged by satellite · pending inspection". This step turns `/public/kilns` from a permanent 503 into a safe public read API. The resident web portal (built next, by the **AWS teammate**) and the iOS demo will both use it. The protected inspector `/kilns` routes stay exactly as they are.

Work sequentially in this chat. Do not use parallel agents or delegation. Do not commit, push or stage, run inference or training, create Cognito users, start Phase 3 or the portal, or enable optional services (AgentCore, SageMaker, Amplify, the demo ECS service).

## People

- **AWS teammate:** owns the infrastructure and will build the resident portal on top of this API.
- **ML team mate:** not needed for this step.
- **User:** owns the account. Sign-in is the user's job: if the CLI session has expired, ask them to run `! aws login --profile kilnwatch --region ap-south-1`.

## Read first

1. `AGENTS.md`, `App/docs/HANDOVER.md`, and the Integration 2B sections of `App/docs/integration-status.md` and `AWS/docs/local-verification.md`.
2. `AWS/docs/first-record-runbook.md`, including the 2A deployment review and the 2B notes.
3. `AWS/lambda/api_handler.py`, `AWS/registry/{contract,store}.py`, `AWS/api.tf`, `AWS/tests/*`, and `App/docs/api-contract.md`.
4. `App/Packages/KilnWatchCore/Sources/KilnWatchCore/Models.swift` (`Kiln`). The public body must decode into the existing `KilnList` envelope / `Kiln` with `JSONDecoder.kilnWatch`, **without any Swift change**.

## Ground rules (same as 2B)

- Use the `kilnwatch` profile only. Check `sts get-caller-identity` first: the ARN must be IAM user `aryaman`, never root.
- The repo is public. Never write the account ID, ARNs, the RDS hostname, emails or tokens into tracked files. Identifiers stay in `.local/integration-2b/outputs.json`.
- Never widen IAM, security groups or the bucket policy, and never expose RDS. No `terraform destroy`.
- **Deployment of this step's reviewed changes is authorized.** Show each plan before applying it.

## Part A — public read API

### A1. A public projection with an explicit allowlist

Add one function to `AWS/registry/contract.py`, for example `public_view(record)`, that builds the public record from the shared serializer's output. Use an **allowlist** (copy only the named keys), never a delete-list.
- **Keep:** `kiln_id`, `footprint`, `type`, `type_confidence`, `detection_confidence`, `type_verification`, `first_seen`, `last_seen`, `status`, `violations`, `rules_assessment`, `exposure`, `district`, and `evidence` (`before`/`after` URLs plus their metadata; satellite scene, attribution and checksums are public).
- **Drop:** `review_state`, `provenance` (the internal input hash and import time), the raw `assessment`, and anything else.
- `provenance` is optional in Swift, so dropping it keeps decoding valid. Unknown extra keys such as `distance_m` are ignored by Swift.

### A2. Which records are public

Show only `status = 'flagged'`, enforced **in SQL**, not only in Python. A kiln that a person later marks `not_a_kiln`, `compliant`, `closed` or `confirmed` disappears from the public API until a separate publication policy covers those outcomes. Document this choice in the contract.

### A3. Endpoints

Two endpoints, both `GET`, both with no auth. Add the second route to Terraform; `GET /public/kilns` already exists.

**1. `GET /public/kilns`** accepts exactly one of two query shapes:
- **Near a point:** `lat`, `lon`, optional `radius_m`.
  - `lat` and `lon` must be finite, `lat` in −90..90 and `lon` in −180..180.
  - `radius_m` is an integer from 100 to 5000, default 2000.
  - Returns flagged kilns whose footprint lies within the radius, sorted by distance and capped at 50. Each record adds `distance_m`, the integer metres from the point to the footprint (`ST_Distance` on `geography`, 0 if the point is inside).
  - Response: `{"kilns": [...], "next_cursor": null}`.
- **District list:** `district`, optional `cursor`, optional `limit`. Same validation and keyset paging as the protected list, flagged only.
- Anything else returns **400** with the contract's nested error: mixed shapes, unknown keys, out-of-range values, or `status`.

**2. `GET /public/kilns/{id}`** returns the public detail of a flagged kiln, or **404** with the same body whether the ID is unknown or the kiln is not flagged. Do not leak which of the two it was.

Database failures return **503**, never an empty list. Public responses send `cache-control: public, max-age=60`. Errors keep `no-store`.

### A4. Store queries

Add the queries to `AWS/registry/store.py` and reuse its `_records` path and the shared serializer:
- parameterized SQL only;
- `ST_DWithin(o.footprint::geography, ST_SetSRID(ST_MakePoint(%s,%s),4326)::geography, %s)` for the radius, with `ST_Distance` for `distance_m`;
- mind the `[lon, lat]` argument order.

Mark the deliberate shortcut in the code: `# ponytail: geography cast skips the gist index; fine at this scale, add a geography index or ST_DWithin on geometry with a bbox prefilter if it grows past tens of thousands.`

The Lambda keeps using the dedicated **SELECT-only reader login**. No new database role is needed.

### A5. Abuse and cost protection

This is the first unauthenticated database-backed route, so add throttling in `AWS/api.tf` on the `$default` stage:
- `route_settings` for `GET /public/kilns` and `GET /public/kilns/{id}`, about 10 requests/second with a burst of 20;
- a sensible `default_route_settings`.

**Do not set Lambda reserved concurrency.** New accounts often have a total concurrency limit of 10, and reserving it fails.

CORS: leave `frontend_origin` alone for now. The portal step will set the real origin.

### A6. Tests (keep them small)

- **Unit tests:** the allowlist drops `review_state` and `provenance` and keeps everything Swift needs; query validation covers every 400 case; a non-flagged kiln returns 404; a database failure returns 503; the public route needs no claims while `/kilns` still requires them.
- **Real PostGIS:**
  - Recreate the disposable local cluster exactly as in 2A: `127.0.0.1:55432`, `kilnwatch_test`, TLS, everything under `.local/integration-2c/`.
  - Add an opt-in test covering: radius inclusion and exclusion, distance ordering, the inside-footprint distance of 0, the flagged-only filter in SQL, district paging and detail.
  - Run all PostGIS tests, report exact counts, then stop the cluster and remove its data directory.
- **Swift:** produce a public near-point body from a test (synthetic or the local real import) and decode it through the existing opt-in `KILNWATCH_REAL_CONTRACT_LIST` test. Do not change Swift.

### A7. Deploy (authorized)

1. Repackage with `AWS/scripts/package_api.py` and record the ZIP SHA-256.
2. **While CloudFront is still blocked,** a plain full `apply` would retry CloudFront and fail. Plan with `-target` only on the resources this step changes: `aws_lambda_function.api`, the new public detail route, `aws_apigatewayv2_stage.default`, and A8's log group/import.
   - Show the plan. Expect only those in-place updates, creates or imports.
   - Apply it, and state in the report that `-target` was used and why.
3. Once AWS verifies the account, run the normal untargeted plan instead (see Part B).

### A8. Quick fix: Lambda log retention

Lambda auto-created `/aws/lambda/kilnwatch-api` with no retention limit. Manage it in Terraform:
- add an `aws_cloudwatch_log_group` with `retention_in_days = 14`;
- add an `import {}` block (Terraform ≥ 1.5) so the existing group is imported, not recreated;
- remove the `import` block after a successful apply. Keep it minimal.

### A9. Live checks over real HTTPS (no token needed now)

Test against `api_base_url`:
- **Near Hapur town** (`lat=28.73&lon=77.78&radius_m=2000`): 200, sorted `distance_m`, every record `flagged`, and no `review_state` or `provenance` keys.
- **Radius 5000:** a larger or equal count.
- **District list:** `district=Hapur` with `limit=10` pages through **39** unique IDs, and the final cursor is null.
- **Detail:** `/public/kilns/KW-6b3b38da681850e5af46b024f3d3f78e` returns 200. An unknown well-formed ID returns 404.
- **Bad input:**
  - `radius_m=99999` returns 400;
  - `lat=999` returns 400;
  - mixing `district` with `lat`/`lon` returns 400;
  - `status=flagged` returns 400.
- **Unchanged routes:** `/kilns` without a token is still 401, and `/health` returns 200.
- **Swift:** decode the live near-point and district bodies with `KILNWATCH_REAL_CONTRACT_LIST` and `swift test`.
- **Throttling:** confirm it from the stage configuration (read-only `get-stage`). Do not load-test.

## Part B — complete CloudFront ONLY if AWS has verified the account

First ask the user whether the AWS Support case is resolved. If it is **not** resolved, skip Part B entirely and report that it is pending.

If it **is** resolved, run 2B's remaining authorized sequence (`App/docs/prompts/08-first-record-deploy.md` §2, §4 and §7):
1. **Remaining resources.** Run an untargeted plan. It should show the CloudFront distribution and bucket policy to add, plus any drift you can explain. Apply it.
2. **Images.** Publish the two approved PNGs, verify them with `verify_publication.py` (HTTPS, `image/png`, checksums), and upload the receipt.
3. **Re-import.** On the runner via SSM, re-import with `--publication-receipt`. Expect 0 new candidates and 0 new observations. Both URLs then appear in protected **and public** detail.
4. **Denial probe.** Confirm CloudFront denies the probe object, any non-PNG path under `evidence/` and `models/`, and that direct S3 access is denied. Then delete the probe.
5. **Runner removal.** Plan with `create_registry_runner=false`: expect 5 to destroy and 1 to change (the endpoint policy). Apply it. Delete `operator-source.tgz` from `imports/`, and keep RDS, the data and the evidence.

## Part C — documentation

Update these concisely, with no identifiers:
- `App/docs/api-contract.md`: the public endpoints, both query shapes, the projection allowlist, the flagged-only policy, errors, caching and throttling.
- `AWS/docs/local-verification.md` and the runbook: an Integration 2C section, with CloudFront completed or pending.
- `App/docs/integration-status.md` and `App/docs/HANDOVER.md`: the public API is live; note it is ready for the resident portal (AWS teammate) and for Phase 3's demo data; the iOS app needs no sign-in for public reads; and the protected inspector routes still require Cognito later (Phase 5).

## Report format

1. Files changed, one line each.
2. The public projection's allowlist, and where flagged-only is enforced.
3. Tests: unit counts, the PostGIS test names and counts, and the Swift decode results.
4. Package SHA, the targeted plan and apply (why `-target` was used), and the log group import.
5. A table of live HTTPS results with status codes, counts and paging.
6. Part B: done (with each sub-result) or pending verification.
7. Cost changes (expected none of note; the runner removal saves about $0.42/day).
8. Remaining items for the **AWS teammate** (portal next), the **ML team mate** (none) and **App** (Phase 3 can use the public API).

Confirm there were no commits, pushes, Cognito users, inference, training, optional services, portal or Phase 3 work.

## Stop point

Stop after the report. The orchestrator reviews it, then writes the resident portal instruction set for the AWS teammate.
