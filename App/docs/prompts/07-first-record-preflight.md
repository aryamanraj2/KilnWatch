# Prompt 07: Integration 2A — local database proof and deployment preflight

You are the builder for **one integration step** in KilnWatch. Integration 1 built the model → registry → read API → Swift bridge and proved it locally with synthetic tests and the real 39-candidate Hapur export. It did **not** prove real PostgreSQL/PostGIS persistence, Terraform validity or anything in AWS. This step closes the local database gate, fixes the review findings below, validates Terraform offline, and prepares the deployment review. **AWS is not deployed and stays undeployed in this step.**

Work sequentially in this chat. Do not use parallel agents, delegation, background agent teams or auditors. Do not commit, push, stage, deploy, retrain, rerun model inference or begin Phase 3. Stop at the stop point below.

## People

- **ML team mate:** owns the checkpoint, training-run identity, model evaluation and interpretation of the evidence images.
- **AWS teammate:** owns the AWS account, profile, region, Terraform state, network, identity, registry, storage and deployment.
- **App orchestrator/builder:** owns the shared contract, Swift compatibility and later app phases.

These people are human teammates, not agents. Ask the user when you need an input or operational choice. Do not contact teammates yourself, and never ask for passwords, access keys or tokens in chat.

## Read first

1. Root `AGENTS.md`, then `App/docs/HANDOVER.md`, `App/docs/integration-status.md` (its older "pre-bridge" sections are historical).
2. `AWS/docs/local-verification.md` and `AWS/docs/first-record-runbook.md`. Runbook commands are review material. Execute only what this prompt authorizes.
3. Source you will touch or prove: `AWS/registry/{contract,evidence,store,db,cli}.py`, `AWS/migrations/001_registry.sql`, `AWS/lambda/api_handler.py`, `AWS/scripts/*.py`, `AWS/tests/*`, and all `AWS/*.tf` plus `AWS/.terraform.lock.hcl`.
4. `App/docs/api-contract.md` for the record shape. You should not need to change Swift. If you find that you do, stop and report the reason first.

## State the orchestrator verified on 2026-10-09 (do not repeat)

- Integration 1 is now **committed and pushed**: `main` = `origin/main` = `6092cf8`. Only `App/docs/screens/phase-2/*.log` are untracked. Preserve them.
- Ignored local artifacts exist only on this machine: root `best.pt`, `args.yaml` and `scores.json`; `.local/integration-1/` (492 KB: `hapur.geojson`, scene JSON, `evidence/` with two PNGs and `manifest.json`, previews, real list/detail JSON); `.venv-integration/` (Python **3.13.3**); `AWS/build/`. Do not delete, regenerate or move them. The orchestrator re-confirmed the SHA-256 prefixes for `best.pt` (`3bcbcd0af696…`) and `hapur.geojson` (`b1e9d177f68d…`).
- The orchestrator reran `PYTHONPATH=AWS .venv-integration/bin/python -m unittest discover -s AWS/tests` at HEAD: **24 run, OK, 2 skipped** (the PostGIS tests). You do not need to rerun it before you change anything.
- Local tooling: **no Docker, Podman, Colima or OrbStack. No Terraform/OpenTofu. No AWS CLI.** Homebrew is present. Homebrew `postgresql@17` 17.11 is installed (`psql`, `postgres`, `initdb`, `pg_ctl`), **without** the PostGIS extension. `python3.12` is at `/usr/local/bin/python3.12`.
- Model inference, the evidence pair and the 39-record conversion are done and valid. **Do not rerun detection, recut evidence or retrain.**

## Step 0 — ask the user once, then continue the independent work

Ask the user these questions in a single message at the start. While you wait, continue with section A, because it needs no new tools.

1. **PostGIS tooling approval.** Recommended: `brew install postgis`, then a throwaway cluster under `.local/integration-2a/pg` (created with `initdb`, run with `pg_ctl`, listening only on `127.0.0.1:55432`, no `brew services`, removed after the proof). The alternatives are installing a container runtime (Docker Desktop/OrbStack/Colima), or having the **AWS teammate** run the tests on their machine. Before installing, confirm that the formula's extension files reach `postgresql@17`'s extension directory (`$(/opt/homebrew/opt/postgresql@17/bin/pg_config --sharedir)/extension/postgis.control`). If it builds only for another PostgreSQL major, report that and ask. Do not upgrade or replace the existing `postgresql@17`.
2. **Terraform tooling approval.** Recommended: the official Terraform CLI zip for darwin_arm64 from `releases.hashicorp.com`, verified against its `SHA256SUMS`, unpacked to ignored `.local/tools/terraform`. The alternative is `brew install hashicorp/tap/terraform`. Use a current 1.x release that satisfies `required_version >= 1.6.0`.
3. **AWS teammate availability for a plan.** Has the AWS teammate supplied an AWS account ID, a named profile on this machine with read access, the region, and the state/backend decision, and explicitly approved a **read-only `terraform plan`** in this step? If not, skip section F's plan and AWS CLI installation, and record the plan as blocked.

If the user declines a tool, mark the dependent check **unrun** with the reason. Never substitute mocks, transaction spies or a different database to "close" the persistence gate.

## Review findings to resolve (orchestrator review of `6092cf8`)

Labels: **[bug]** confirmed code defect, **[gap]** missing test evidence, **[runbook]** documentation/procedure hardening, **[decision]** an owner decision. Keep each fix minimal.

1. **[bug] Replaying evidence import erases verified publication URLs.** `AWS/registry/store.py:31` upserts `kilnwatch.evidence` with `metadata=EXCLUDED.metadata`. `AWS/registry/evidence.py:82-86` adds `published_url` only when `--publication-receipt` is passed. A later replay without the receipt (a routine retry, or runbook §6 run after §7) therefore silently replaces verified metadata, and `Registry._records` (`store.py:67`) returns `evidence.before/after = null` again. Fix in the upsert so that:
   - a replay with the same `sha256` never drops an existing `published_url` (the merged metadata keeps it);
   - a replay that would change the `sha256`/`object_key` of a side that already has a verified `published_url` is **rejected** (raise, roll back the whole batch) rather than silently swapping published evidence;
   - first insert, unpublished-to-unpublished replay and unpublished-to-published (receipt) replay all still work.

   Add a regression test that **runs against real PostGIS** (section B). It must use explicitly synthetic test images/receipts, never a fabricated receipt for the real evidence pair.
2. **[gap] The real PostGIS tests cover only migration replay, retry/reordering, human-state retention, SRID/validity and rollback.** `AWS/tests/test_postgis.py` does not prove role permissions, persisted reads, evidence round trips, district conflicts or migration tamper detection. Section B lists the required additions. The rollback test (`test_postgis.py:39-45`) also does not check `kilnwatch.evidence`. Add it there with a record that carries evidence metadata.
3. **[gap] Credential separation has never run against a real database.** `AWS/scripts/bootstrap_reader.py` creates `kilnwatch_api` and grants `kilnwatch_reader`. Prove the following in the disposable cluster (section B):
   - the created login can `SELECT`, and `INSERT`/`UPDATE`/`DELETE` on every `kilnwatch` table is denied, including `UPDATE` of `status`/`review_state`/`assessment`;
   - a `kilnwatch_importer` login can run `persist` (including the evidence upsert and `SELECT … FOR UPDATE`) but cannot update `status`/`review_state`/`assessment`.
4. **[runbook] The bootstrap recovery is vague.** `bootstrap_reader.py:27-36` writes the secret before `COMMIT`. If the commit fails, the secret holds a password for a role that does not exist. A rerun recovers, because the role is absent, so a new password is created and the secret is overwritten. If the commit succeeded server-side but the client saw an error, the role exists and matches the secret. Prove the first case locally by stubbing Secrets Manager in-process (no network, no AWS) and forcing the commit to fail. Then replace "reconcile" in the script message and runbook §6 with these exact checks and steps. Also note that `CREATE ROLE … PASSWORD` text reaches the server. The AWS teammate must confirm the RDS `log_statement` parameter is not `ddl`/`all` when bootstrapping (the default is `none`).
5. **[runbook] The runner commands never set an AWS region.** `AWS/registry/db.py:12` and `bootstrap_reader.py:28` create boto3 clients without an explicit region. Lambda sets `AWS_REGION` itself; the SSM runner shell does not reliably. Add `export AWS_REGION=<region> AWS_DEFAULT_REGION=<region>` to runbook §6. Do not change the code for this.
6. **[runbook] Runbook §6 uploads the whole `.local/integration-1/` directory** (previews and real list/detail JSON included) to `imports/`. The bucket is private and the data is small, but upload only the required inputs: `hapur.geojson`, `evidence/` and `operator-source.tgz`, plus the receipt later.
7. **[runbook/infra] No Terraform backend is configured.** `AWS/versions.tf` has no `backend` block, so runbook §4's "agreed encrypted/locked backend" would silently fall back to local state. Do **not** add a backend block in this step. Use `terraform init -backend=false` for offline validation. In the runbook, state that a `backend "s3" {}` partial block (with a private, ignored `-backend-config` file) is added only after the AWS teammate decides the bucket, key, region, encryption and locking, and that state must never be local on a laptop for a shared deployment.
8. **[gap] Terraform formatting.** `AWS/bridge.tf`, `AWS/api.tf:42-49`, `AWS/database.tf:31-45` and `AWS/variables.tf:186-190` are not `terraform fmt` aligned, so `fmt -check` will fail. Run `terraform fmt -recursive` (whitespace only) and report the files it changed.
9. **[gap] Runtime version.** The local venv is Python 3.13. Lambda and the runner use 3.12. After repackaging, import the unpacked ZIP with `/usr/local/bin/python3.12 -I` (pure-Python modules: `api_handler`, `registry.store`, `pg8000`), then load the bundled `rds-ca.pem` into an `ssl` context. This is a compatibility smoke test, not a Lambda invocation.
10. **[decision] CloudFront price class.** `AWS/bridge.tf:11` uses `PriceClass_100`, which has no edge locations in India, so NCR inspectors would be served from Europe or North America. `PriceClass_200` includes India. Raise this with the AWS teammate; do not change it unilaterally.
11. **[decision] RDS retention.** `AWS/database.tf:21-25` sets `deletion_protection=false`, `skip_final_snapshot=true`, a 1-day backup and `apply_immediately=true`. Once human review state is stored, data loss matters. Ask the AWS teammate to choose before real data is retained. Do not change it unilaterally.
12. **[note] The Lambda `Errors` alarm cannot see registry outages.** `api_handler.py:74-77` converts database failures into 503 responses, so the alarm in `AWS/workflow.tf:41-53` never fires for them. Record this as later observability work, such as an API Gateway 5xx alarm. Do not build it now.
13. **[app, Phase 3 backlog — do not fix now]** `App/KilnWatch/Features/Kiln/KilnView.swift:45` ("Within 800 m"), `:170`/`:212` (a fixed 800 m `MapCircle` and caption), and `App/KilnWatch/Design/Components/ExposureBlock.swift:4,29,43` hard-code 800 m. The 800 m versus 1,000 m (UP) habitation rule is unresolved. Real records do not reach this view yet, because the app has no registry fetching. Record this in integration-status under App/Phase 3 follow-ups only.

## A. Minimal code and runbook fixes (no new tools needed)

- Implement finding 1 in `AWS/registry/store.py` (SQL, plus a small Python guard if needed). Keep `persist`'s single transaction, its parameterized queries and its counts. Do not change `contract.py`'s IDs or serializer.
- Update the message in `AWS/scripts/bootstrap_reader.py` per finding 4, with the smallest possible change.
- Apply runbook findings 4–7 to `AWS/docs/first-record-runbook.md`.
- Run the existing Python suite. All non-PostGIS tests must still pass.

## B. Local PostGIS persistence proof (after tooling approval)

Disposable setup, with everything under ignored `.local/integration-2a/`:

- `initdb -U postgres` with a password from a mode-600 file and `scram-sha-256` auth. Set `listen_addresses='127.0.0.1'`, port `55432`, and `ssl=on` with a throwaway CA and a server certificate whose only name is `localhost` (OpenSSL, generated locally, never committed). Start it with `pg_ctl`, then `createdb kilnwatch_test`. Never point any test at RDS or any other database. The test file already refuses anything except `127.0.0.1` and `kilnwatch_test`. Keep that guard.
- Keep test credentials out of Git and out of command arguments where practical (use environment variables or a private file).

Then:

1. Run the existing suite with `KILNWATCH_TEST_DB_PORT=55432` and the password. Both existing PostGIS tests must run, not skip. Report exact counts.
2. Extend `AWS/tests/test_postgis.py` minimally (still opt-in, still synthetic data) to prove:
   - the evidence republication guard from finding 1 (same sha keeps `published_url`; a changed sha on a published side is rejected and rolls back);
   - evidence rows are included in the rollback assertion;
   - a district conflict on re-import raises and rolls back;
   - migration ledger tamper detection: a changed checksum for an applied migration raises. Use a temporary copy or monkeypatch, and never edit `001_registry.sql`;
   - persisted `Registry.list` with district and status filters, keyset pagination (no duplicates or gaps across pages, a correct final `next_cursor=None`) and `Registry.detail`, including another district's ID returning `None`;
   - the role permissions and bootstrap behaviour in findings 3–4, with Secrets Manager stubbed in-process. Drop the test roles in teardown, and only inside this disposable cluster.
3. **TLS proof through the production connector.** Use `registry.db.connect_from_env` with `DB_HOST=localhost`, the throwaway CA as `DB_CA_BUNDLE`, and `DB_USER`/`DB_PASSWORD` set and `DB_SECRET` unset. It must connect. With `DB_HOST=127.0.0.1` (hostname mismatch) and with a wrong CA, it must **fail**. This demonstrates that the connector verifies the certificate chain and hostname. It does not prove that RDS's certificate works.
4. **Real-record persistence (local only).** Through `python -m registry.cli migrate` (as `postgres`) and then `registry.cli import` (as a `kilnwatch_importer` login, over TLS via `connect_from_env`), import the real `.local/integration-1/hapur.geojson` with district `Hapur` and the real `evidence/manifest.json`, **without** a publication receipt. Expect 39 candidates and 39 observations inserted. Replay the same command and expect `candidates_inserted=0` and `observations_inserted=0`. Then set one candidate's `status`/`review_state` as `postgres` (a simulated human decision, labelled as such), replay again, and confirm it is unchanged.
5. **Persisted read → Lambda handler → Swift.** As the bootstrapped `kilnwatch_api` login, call the real `api_handler.handler(event, None)` with synthetic, explicitly test-only JWT claims (`COGNITO_CLIENT_ID` set to a matching synthetic value) over TLS. Prove each of these:
   - the list returns 200 with 39 records;
   - `limit=10` pages cover all 39 exactly once;
   - the detail for `KW-6b3b38da681850e5af46b024f3d3f78e` has `before_metadata`/`after_metadata` and null URLs;
   - another district returns 403, an unknown ID returns 404, and an invalid filter returns 400;
   - stopping the cluster or using a wrong port gives 503 and never an empty list.

   Save the 39-record list body to `.local/integration-2a/persisted-list.json`. Run the existing opt-in Swift test with `KILNWATCH_REAL_CONTRACT_LIST=<absolute path>` from `App/Packages/KilnWatchCore` (`swift test`). This proves database-read → handler → Swift decode. It does **not** prove API Gateway, Cognito or AWS.
6. Stop the cluster. Remove only `.local/integration-2a/pg` after you have saved the logs and results you will cite. Leave `brew`-installed tools in place, report them, and tell the user how to uninstall them if wanted.

Limits to state honestly: the local `postgres` superuser is not RDS's `rds_superuser`. PostGIS 3.6 locally is not necessarily RDS's PostGIS version. Real RDS TLS, parameter groups and extension availability remain unproven until deployment.

## C. Package the Lambda before Terraform reads it

- Run `AWS/scripts/package_api.py` after the `store.py` change (it needs network access for wheels and the RDS CA bundle). Record the artifact SHA-256 and the ZIP file list. The expected top level is: `api_handler.py`, `rds-ca.pem`, `registry/{__init__,contract,db,store}.py`, and the pinned `pg8000`/`scramp`/`asn1crypto`/`dateutil`/`six` packages. Nothing else (no `evidence.py`, `cli.py` or `pyproj`).
- Run finding 9's Python 3.12 import smoke test.

## D. Terraform offline checks (after tooling approval)

From `AWS/`:

```sh
terraform init -backend=false -lockfile=readonly   # never -upgrade; lock file must stay byte-identical
terraform fmt -recursive
terraform fmt -check -recursive
terraform validate
```

- Confirm `git diff --stat AWS/.terraform.lock.hcl` is empty. `.terraform/` is ignored.
- If `validate` fails on pre-existing scaffolding (for example the disabled SageMaker/AgentCore resources against the locked `hashicorp/aws 6.68.0` schema), report the exact error. Apply a minimal fix only if it is mechanical, keeps the feature disabled and needs no provider change. Otherwise stop and ask.
- No credentials are needed for these steps. Do not run `plan` here unless section F's conditions are met.

## E. Name-collision and resource review from source (no AWS access needed)

List what a first apply would create from the current source with default/example variables and `create_registry_runner` both false and true. Disabled options do not mean that only registry resources exist. Cover at least:
- VPC/subnets/IGW/route tables/SGs;
- S3 and its policy/versioning/encryption/public-access block;
- the ECR repositories (inference and agents);
- the ECS cluster and task definition, plus the Step Functions state machine (scaffolding, never started);
- RDS, its parameter and subnet groups, and the RDS-managed master secret;
- the reader secret and the Secrets Manager interface endpoint (two ENIs);
- Lambda, the HTTP API, routes, stage and log groups;
- Cognito pool/client/group;
- CloudFront with OAC;
- SNS and the alarm;
- the optional runner (EC2 t3.micro with a **public IPv4 address**, an instance profile and an SSM role).

Confirm that AgentCore, SageMaker training, Amplify and the demo ECS service are count-0 by default. List the fixed names that could collide in an account (for example the IAM roles `kilnwatch-*`, Cognito `kilnwatch-users`, log groups and the secret name). Give the AWS teammate the read-only commands to check for those collisions before planning.

## F. Real plan — only with explicit AWS teammate inputs and user approval

Only if Step 0 question 3 was answered yes:
- Install the AWS CLI by the user-approved method, set `AWS_PROFILE`/`AWS_REGION` for the named profile, and run `aws sts get-caller-identity`. The account ID must match what the AWS teammate stated. If it does not, stop.
- Copy `terraform.tfvars.example` to the ignored `AWS/terraform.tfvars` with the approved values. Use the agreed backend only if the AWS teammate has provided it. Otherwise plan with no backend (a plan writes no state), and say so.
- Run `terraform plan -out=first-record.tfplan` and `terraform show -no-color first-record.tfplan > .local/integration-2a/plan.txt`. Keep the plan and its text private and ignored. They can contain account IDs and ARNs. No `apply`, `import`, `state push`, bootstrap or any other write.
- Review the complete planned resource set against section E. Check that RDS is not publicly accessible, that there are two private endpoint subnets, that the bucket policy is limited to `evidence/*.png` for that distribution's ARN, that the Lambda role reads only the reader secret, that disabled services are absent, and that no inference/training/agent execution is planned.

If no plan is authorized, record "plan blocked: missing AWS teammate inputs" and list them.

## G. Deployment review (write into the runbook as a new section)

Add a concise "Deployment review (Integration 2A)" section to `AWS/docs/first-record-runbook.md` covering:
- the resource set from E/F;
- data retention (finding 11) and what `terraform destroy` would delete;
- the private access paths;
- the runtime role and secret separation;
- the public evidence scope (two PNGs only, everything else private) and the price class decision (finding 10);
- expected runtime omissions (`/routes/today`, rules, verdicts, agents and jobs are 501/absent, and `/health` is not a readiness check);
- rollback/recovery, including bootstrap recovery (finding 4) and evidence republication (finding 1);
- temporary runner cleanup.

**Recurring-cost categories:** RDS instance-hours, storage and backup; the interface endpoint (per AZ-hour plus data); Secrets Manager secrets and API calls; the runner instance, EBS and its public IPv4 address; CloudFront; Lambda; the HTTP API; CloudWatch Logs; S3; ECR storage. Quote prices only from current official AWS pricing pages for the chosen region, with the date. Do not invent a monthly total.

## H. Documentation updates

Update these with exact evidence and remaining blockers. Keep them concise, and do not rewrite history sections.
- `AWS/docs/local-verification.md`: a new dated "Integration 2A" section.
- `App/docs/integration-status.md`: a new "Integration 2A" section, plus the App/Phase 3 follow-up in finding 13.
- `App/docs/HANDOVER.md`: a short Integration 2A paragraph and updated next steps. Note that Integration 1 is committed at `6092cf8`.
- The runbook (A and G).

Add a short **portability checklist** to `local-verification.md`. List the ignored artifacts needed on another workstation, each with its path, size and SHA-256: `best.pt`, `args.yaml`, `scores.json`, `.local/integration-1/hapur.geojson`, the scene JSONs, `evidence/manifest.json` and the two PNGs. Transfer them privately (not Git, no credentials). Note what can be regenerated (the venv, `AWS/build/`) and what cannot (the weights).

## Report format (return this to the user for the orchestrator)

Keep the following separate:
1. Files changed, with one line on behaviour for each.
2. Review findings 1–13: fixed / documented / deferred, with test names.
3. **Synthetic tests:** exact Python run/pass/skip counts before and after the PostGIS enablement.
4. **Real database proof:** the PostGIS version, every PostGIS test name and result, the real 39-record import and replay counts, human-state retention, role-permission results, TLS pass/fail cases, handler status codes and pagination results.
5. **Swift:** the result of the opt-in decode of the persisted list. Note that no other Swift change was made.
6. **Package:** the ZIP SHA-256, its file list and the Python 3.12 smoke result.
7. **Terraform:** versions, the `fmt` changes, the `validate` result, confirmation that the lock file is unchanged, and the plan result or "blocked" with its reason.
8. Deployment review summary and cost categories (with sources if quoted).
9. Tools installed and how to remove them. Confirm that no AWS writes, commits, pushes, inference or training happened.
10. Remaining blockers and owner questions, split into **AWS teammate**, **ML team mate** and **App**.

Do not call a skipped or mocked check a pass. Do not describe the local database proof as an AWS proof.

## Stop point

Stop after the report. Do **not** run `terraform apply`. Do not create cloud resources or state, upload or publish objects, run a live migration/import/bootstrap, create a Cognito user or token, run inference or training, start Phase 3, or stage, commit or push. The orchestrator reviews your evidence before the user authorizes deployment (Integration 2B).

## Addendum (2026-10-09) — AWS teammate answers, relayed by the user

These answers replace Step 0's questions and the "do not change unilaterally" notes on findings 10 and 11. Everything else in this prompt still applies.

**Account and access**
- The deployment uses **the user's own AWS account** (it holds the credits), through the IAM user `aryaman`. **Never use the root user.**
- You must never see, request or store a password or access key. The user signs in to the CLI themselves, in this chat, using the `!` prefix:
  - preferred: `! aws login --profile kilnwatch --region ap-south-1` (AWS CLI v2's console-credential sign-in);
  - if that command is unavailable: `! aws configure --profile kilnwatch`, with the user typing the keys into the prompt, never into chat.
- Then run `aws sts get-caller-identity --profile kilnwatch`. Confirm the ARN is `…:user/aryaman` (not root) and ask the user to confirm the 12-digit account ID. If either check fails, stop.

**Tools approved**
- Homebrew `postgis`, Terraform (the verified official zip in `.local/tools`, or Homebrew), and the AWS CLI v2 (`brew install awscli`).

**Region: `ap-south-1` (Mumbai)**
- Set `ap-south-1` in `terraform.tfvars.example`, as the `aws_region` default in `variables.tf`, in the ignored `terraform.tfvars`, and in the runbook.
- With read-only CLI calls, confirm that `ap-south-1` offers RDS PostgreSQL 17 on `db.t4g.micro` and a PostGIS version for that engine.
- Detection imagery is still read from Earth Search in us-west-2 by the local and offline scripts. That does not affect this deployment.

**Database retention: backups on**
- In `AWS/database.tf`: `backup_retention_period = 7`, `deletion_protection = true`, `skip_final_snapshot = false` with a fixed `final_snapshot_identifier`, and `copy_tags_to_snapshot = true`.
- Document that `terraform destroy` will now refuse to delete the database until deletion protection is deliberately turned off.

**CDN: `PriceClass_200`** (includes India edge locations)
- Set it in `AWS/bridge.tf`. Do not use `PriceClass_All`.

**Evidence publication approved**
- The AWS teammate approves publishing the two reviewed Copernicus PNGs. Record the approval only. The upload still happens in 2B.

**Remote Terraform state on S3 (this cloud write is authorized)**
- Add a partial `backend "s3" {}` block to `AWS/versions.tf`. Raise `required_version` to `>= 1.10` so S3-native locking (`use_lockfile = true`) works without DynamoDB. Do not change the provider lock file.
- Add a committed `AWS/backend.hcl.example` and an ignored `AWS/backend.hcl` (add it to `AWS/.gitignore`) containing:
  - `bucket = "kilnwatch-tfstate-<account-id>-ap-south-1"`
  - `key = "kilnwatch/hackathon/terraform.tfstate"`
  - `region = "ap-south-1"`
  - `encrypt = true`
  - `use_lockfile = true`
- With the AWS CLI and the `kilnwatch` profile, create **only this one state bucket**, outside Terraform. Configure it with:
  - all four Block Public Access settings on;
  - versioning enabled;
  - default SSE-S3 encryption;
  - a bucket policy that denies `aws:SecureTransport = false`.
- Verify each setting with read-only calls. Then run `terraform init -backend-config=backend.hcl -lockfile=readonly`.
- Put the bootstrap commands, and how to remove the bucket, into the runbook.

**Read-only plan authorized**
- Run the plan against the S3 backend with `create_registry_runner = true` (the temporary private path for migration and import) and `bucket_name_prefix = "kilnwatch"`. Leave every other optional service disabled.
- Before planning, run section E's read-only name-collision check in this account.
- The plan's temporary lock object in the state bucket is expected.
- **No apply.** Create no other resources and no state.

**Cost estimate (the AWS teammate asked for one)**
- Base it on official `ap-south-1` prices: the AWS Price List API through the CLI (read-only), or the AWS pricing pages. Cite the date and source.
- Give one line per service from section G, with stated assumptions. For example: a 730-hour month for always-on resources, about 4 runner-hours including its public IPv4 address, two images, and low request volume.
- Give a monthly total **clearly labelled as an estimate under those assumptions**. Separate always-on costs from one-time and temporary ones.
- Ask the user to check their credit balance and expiry, and any services the credits exclude, under Billing → Credits. Do not read billing data yourself.

The stop point is unchanged: no `apply`, no uploads, no live migration/import/bootstrap and no Cognito users. Report the bucket you created and its verified settings separately from everything else.
