# Prompt 08: Integration 2B — deploy and prove the first real records live

You are the builder for **one integration step** in KilnWatch. Integration 2A proved the registry locally against real PostGIS, validated Terraform, created only the remote-state bucket, and produced a reviewed read-only plan (75 to add). The user has now **authorized deployment** of that reviewed scope into their own AWS account. Hapur is confirmed as the district for the 39 records.

Your goal: apply the reviewed infrastructure, load the 39 real candidates through the private path, publish the two approved images, and prove authenticated reads and evidence delivery work live. Then remove the temporary runner.

Work sequentially in this chat. Do not use parallel agents, delegation or auditors. Do not commit, push or stage, retrain or rerun inference, enable optional services, or begin Phase 3.

## People

- **AWS teammate:** the infrastructure owner. They delegated these decisions: the user's account, IAM user `aryaman` (never root), `ap-south-1`, 7-day backups with deletion protection, `PriceClass_200`, an S3 remote state backend, and publication of the two reviewed PNGs.
- **ML team mate:** model and evidence interpretation. Not needed for this step.
- **User:** owns the account and its credits, and personally performs every password or sign-in action.

## Read first

1. `AGENTS.md`, `App/docs/HANDOVER.md`, `App/docs/integration-status.md` (the Integration 2A section).
2. `AWS/docs/first-record-runbook.md`, in full: §4a state bucket, §5–§9, and "Deployment review (Integration 2A)", including rollback, runner cleanup and costs. This runbook is now your **authorized** sequence, as amended below.
3. `AWS/docs/local-verification.md` (the Integration 2A section).

## Ground rules for this deployment

- **Credentials.** Use only the `kilnwatch` CLI profile. If the session has expired, ask the user to run `! aws login --profile kilnwatch --region ap-south-1` themselves. Check `aws sts get-caller-identity --profile kilnwatch`: the ARN must be `…:user/aryaman` and the account must match `AWS/backend.hcl`. Stop if either is wrong.
- **You never see a password, access key, ID token or the database secret's value.** Never print them, pass them as command arguments, write them to tracked files or put them in SSM command text. Tokens live only in mode-600 files under ignored `.local/integration-2b/`.
- **The repo is public.** Tracked docs must not contain the account ID, ARNs that include it, email addresses, the RDS hostname or tokens. Put Terraform outputs and identifiers in ignored `.local/integration-2b/outputs.json`. Docs may refer to them by output name.
- **Allowed cloud writes:**
  - the reviewed Terraform apply;
  - private `imports/` uploads;
  - the two approved `evidence/` PNGs and one CloudFront-denial probe object (below);
  - the database migration, reader bootstrap and imports through the runner;
  - one Cognito test inspector;
  - an optional AWS Budget alert (§1);
  - the later runner-removal apply.

  Nothing else. **No `terraform destroy`.** Do not disable deletion protection, change backups or manually change resources outside Terraform, except where this prompt explicitly says so.
- If any step fails, stop at that step and diagnose it read-only. Change only what the failure requires, re-plan and show the diff. **Never "fix forward" by widening IAM, security groups or bucket policy, or by opening RDS publicly.** If a fix would change the reviewed security shape, stop and ask the user.

## Corrections to the runbook found in orchestrator review (apply them, and document them in the runbook)

1. **The runner cannot list `imports/`.** Its IAM role allows only `s3:GetObject` on `imports/*`, so runbook §6's `aws s3 cp … input/ --recursive` will fail with `AccessDenied` on `ListObjectsV2`. Do not widen IAM. Download each required object by its exact key: `hapur.geojson`, `operator-source.tgz`, `evidence/manifest.json`, the two PNGs, and later `publication-receipt.json`.
2. **Use non-interactive SSM.** Running `aws ssm start-session` from here needs the Session Manager plugin and an interactive shell. Use `aws ssm send-command --document-name AWS-RunShellScript` instead, and read results with `get-command-invocation` (or a private S3 output prefix under `imports/` if the output is long). Keep the scripts free of secrets. They read the secrets themselves from Secrets Manager on the runner. Wait until the instance shows as `Online` in `aws ssm describe-instance-information` before sending commands.
3. **Runner removal is not only 5 destroys.** Setting `create_registry_runner=false` also changes the Secrets Manager endpoint policy in place (it drops the runner's `PutSecretValue` statement). Expect "5 to destroy, 1 to change" and review it before applying.

## §1 Preflight (read-only, except the optional budget)

- Confirm the identity (above) and that `AWS/backend.hcl` and `AWS/terraform.tfvars` are still ignored. Run `terraform init -backend-config=backend.hcl -lockfile=readonly`. The lock file must stay byte-identical.
- Confirm the Lambda ZIP matches the current source. If any file packaged by `AWS/scripts/package_api.py` changed after 2A's package (SHA `beeec4f9…`), repackage before planning, and record the new SHA either way.
- Re-run the Python suite without the database (expect 30 run, OK, 8 skipped). Do not rerun the local PostGIS proof.
- **Budget alert (optional, needs the user's yes):** ask the user for the email address they want to use. With their yes, create one AWS Budget: monthly cost limit USD 50, email alerts at 80% actual and 100% forecast. Do not read billing or credit data yourself. If the user declines, skip it.
- `terraform plan -out=.local/integration-2b/2b.tfplan` with the existing ignored `terraform.tfvars` (`create_registry_runner = true`). Expect **75 to add, 0 to change, 0 to destroy**, and the same resource set as the 2A review. If the count or set differs, stop and explain why before applying.

## §2 Apply (authorized)

- `terraform apply .local/integration-2b/2b.tfplan`. RDS and CloudFront can take 10–20 minutes, so wait patiently, and do not cancel or re-run apply concurrently.
- If the apply fails partway, do **not** destroy. Report the error, re-plan, and apply only the reviewed remainder.
- Save the outputs (`terraform output -json`) to `.local/integration-2b/outputs.json` (mode 600).
- Read-only checks after apply:
  - RDS: `PubliclyAccessible=false`, `StorageEncrypted=true`, `DeletionProtection=true`, `BackupRetentionPeriod=7`, engine 17.x.
  - Parameter group: `rds.force_ssl=1`, and **`log_statement` is `none` or unset** (it is the bootstrap precondition from finding 4). If it is `ddl` or `all`, stop before bootstrapping.
  - Lambda: `python3.12`, `x86_64`, VPC config present, and its role has no master-secret access.
  - CloudFront: the distribution is `Deployed` with `PriceClass_200`.
  - The data bucket's public access blocks are on.
  - `GET /health` returns 200 with `registry_readiness: not_checked`. Health is **not** proof that the database is ready.

## §3 Private migration, reader bootstrap and import (runner, via SSM)

Follow runbook §6, with corrections 1–2:
- On this workstation, build `operator-source.tgz` from the **current working tree** (it includes 2A's fixes). Upload only the required inputs to `imports/integration-1/`.
- On the runner:
  1. Install Python 3.12. Verify the AL2023 package names first, and report what actually worked.
  2. Create a venv and install from `AWS/requirements-operator.txt`.
  3. Fetch the RDS CA bundle.
  4. Set `AWS_REGION` and `AWS_DEFAULT_REGION` to `ap-south-1`.
  5. Run `migrate`, then `bootstrap_reader.py`, then `validate`, then `import`.
- Import twice. Expect 39 candidates and 39 observations inserted the first time, and `candidates_inserted=0, observations_inserted=0` on the replay.
- **Reader check:** using the reader secret through `connect_from_env`, `SELECT COUNT(*) FROM kilnwatch.candidates` returns 39. An `INSERT` attempt is denied (`42501`). Do not print the secret.
- If bootstrap fails, follow the runbook §6 recovery exactly. Do not improvise role drops.

## §4 Publish the two approved images (runbook §7)

- From this workstation, with the `kilnwatch` profile:
  - run `upload_evidence.py --publish-reviewed-evidence` for the two PNGs only;
  - then run `verify_publication.py` against `evidence_base_url`, writing the receipt to `.local/integration-1/publication-receipt.json`;
  - upload that receipt to `imports/integration-1/`.
- On the runner, re-import with `--publication-receipt`. Expect 0 new candidates and observations. The detail for `KW-6b3b38da681850e5af46b024f3d3f78e` must now carry both verified URLs.
- **CloudFront denial proof:**
  1. Upload one harmless text probe object to `imports/integration-2b/cloudfront-denial-probe.txt`.
  2. Request it through CloudFront. Also request a non-PNG path under `evidence/` and a missing `models/` key.
  3. All must be denied (403). Fetching the bucket's S3 URL directly must also be denied.
  4. Delete the probe object afterwards.

## §5 Test inspector and ID token (runbook §8)

- Ask the user which email address should own the test inspector. Then:
  - run `admin-create-user` with `custom:district=Hapur` and the email attribute, letting Cognito send its invitation, so the temporary password goes **only to the user's email**;
  - then run `admin-add-user-to-group` for `inspector`.
- **Token without exposure.** Add a small operator helper, `AWS/scripts/id_token.py` (boto3 `cognito-idp`):
  - it reads the username and client ID from arguments;
  - it reads the password, and any `NEW_PASSWORD_REQUIRED` new password, with `getpass`;
  - it uses `USER_PASSWORD_AUTH`;
  - it writes only `Authorization: <IdToken>` to `.local/integration-2b/auth-header`, with mode 600;
  - it never prints the token.

  The **user runs it themselves** with `! .venv-integration/bin/python AWS/scripts/id_token.py …`. You only reference the header file with `curl --header @file`. Delete it after the checks.

## §6 Live API and image checks (runbook §9)

Use `curl --fail-with-body --header @.local/integration-2b/auth-header` and save bodies under `.local/integration-2b/`. Prove:
- **List:** `GET /kilns?district=Hapur` returns 200 with exactly 39 records, all `flagged`, type `unverified`, `rules_assessment=not_evaluated` and exposure null.
- **Paging:** `limit=10` pages cover 39 unique IDs, and the final `next_cursor` is null.
- **Detail:** `GET /kilns/KW-6b3b38da681850e5af46b024f3d3f78e` returns 200 with both verified evidence URLs. Each URL returns `image/png` over HTTPS, and its SHA-256 matches the manifest.
- **Refusals:**

  | Request | Expected |
  |---|---|
  | No token | 401 |
  | Malformed token | 401 |
  | `district=Meerut` | 403 |
  | Unknown well-formed ID | 404 |
  | Invalid `limit`/status | 400 |
  | `/public/kilns` | 503, no private fields |
  | `POST /jobs` with the token | 501 |
- **Swift decode:** run `KILNWATCH_REAL_CONTRACT_LIST=<absolute path to live list.json> swift test` in `App/Packages/KilnWatchCore`. Report it separately: it proves the live body decodes, not that the simulator app connected.
- Do **not** run a database-outage test against the live system. That failure path was proven locally in 2A.

## §7 Clean up the temporary runner (authorized)

1. Via SSM, delete `~/kilnwatch-proof` on the runner.
2. Set `create_registry_runner = false` in the ignored tfvars. Plan, and expect 5 to destroy and 1 to change (the endpoint policy).
3. Show the plan, then apply it.
4. Keep RDS, the data, the secrets, the evidence objects and the receipt.
5. Delete `imports/integration-1/operator-source.tgz`. Keep the other `imports/` inputs (private, small, useful for re-import) unless the user asks otherwise.
6. Delete `.local/integration-2b/auth-header`.
7. Sign out with `aws logout --profile kilnwatch` only if the user asks; the next phase may need the session.

## §8 Documentation

Update these, keeping them concise and free of account identifiers:
- `AWS/docs/local-verification.md`: a new "Integration 2B — live deployment" section.
- `AWS/docs/first-record-runbook.md`: corrections 1–3, exactly what worked on the runner, and the current deployed state.
- `App/docs/integration-status.md` and `App/docs/HANDOVER.md`: AWS is **deployed** in `ap-south-1`, with real records live; Phase 3 is next, pending the user's request.

Record which output names the app will need for Phase 3: `api_base_url`, `cognito_user_pool_id`, `cognito_app_client_id`, `cognito_issuer` and `evidence_base_url`. Store their values only in `.local/integration-2b/outputs.json`.

## Report format

Keep these separate:
1. Identity check result (ARN type only, no account ID).
2. Plan/apply: the counts, the duration, any failure and its resolution, and the post-apply checks including `log_statement`.
3. Runner: the Python install method that worked, migrate/bootstrap/import outputs (first and replay counts), and the reader SELECT/deny results.
4. Publication: the upload result, receipt verification, the re-import counts, CloudFront denials and the probe deletion.
5. Cognito: the user was created and added to the group, and the token was obtained by the user (state how; no values).
6. A table of live API results with status codes, paging and image checksums.
7. The Swift live-body decode result.
8. Runner cleanup: the plan counts and apply result, and what was deleted and kept.
9. Budget alert: created, or skipped.
10. Files changed, and cloud resources now running, with the cost estimate repeated from 2A (about $38/month always-on).
11. Remaining limits and next actions, split into **AWS teammate**, **ML team mate** and **App** (Phase 3 inputs).

Confirm there were no commits, pushes, inference, training, optional services or Phase 3 work. Do not call an unrun check a pass.

## Stop point

Stop after the report. The orchestrator reviews the live evidence before the user requests Phase 3, the app's real registry and evidence UI.
