# Prompt 16c: Evidence images through CloudFront in the second account

You are the builder for **one step** of KilnWatch. The main AWS account (`ap-south-1`) can't create CloudFront until AWS verifies it (a Support case is open). The two approved satellite PNGs for `KW-6b3b38da681850e5af46b024f3d3f78e` are still unpublished, so the app and the API show "Satellite images not yet published".

The user has decided to serve the images through a **CloudFront distribution in their second AWS account**. That's the same account that already serves Bedrock in prompt 16b; it belongs to a teammate, who has agreed. The images stay in the main account's **private** S3 bucket. CloudFront reads them through Origin Access Control (OAC). The bucket uses SSE-S3 (AES256), so no KMS key policy is involved.

**The user gave the go by running this prompt.** The scope is exactly the following:
1. the Terraform changes below;
2. a targeted apply that creates the OAC and the distribution in the second account and the evidence bucket policy in the main account;
3. publishing and verifying the 2 PNGs;
4. re-importing that one record with the publication receipt (on the runner, through SSM);
5. the denial probe;
6. updating the opt-in Swift contract test;
7. docs.

Work sequentially. Do not use sub-agents. Do not commit, push or stage. No `terraform destroy`, no untargeted apply, and no provider-lock change.

**Do NOT remove the registry runner** (prompt 09 Part B step 5 is skipped). The teammates' rules engine needs it later to write assessments.

## Read first

- `AGENTS.md`, and `App/docs/prompts/17-orchestrator-handover.md` §3 and §5a/§5b if present.
- `App/docs/prompts/09-public-read.md` **Part B** and `App/docs/prompts/08-first-record-deploy.md` **§4** (publish), **§6** (live image checks) and **§3** (the runner and SSM import pattern). This prompt reuses their steps.
- `AWS/bridge.tf` (the current OAC, distribution and bucket policy; the last two have never been created), `AWS/versions.tf`, `AWS/outputs.tf`, `AWS/scripts/upload_evidence.py`, `AWS/scripts/verify_publication.py`, `AWS/docs/first-record-runbook.md` §7.
- `App/docs/prompts/16b-phase-4a-bedrock-cross-account.md` (how the second account was used before).

## Ground rules

- **Two profiles.** `kilnwatch` is the main account, IAM user `aryaman`. The second account's profile (`kilnwatch-bedrock`) must not be root. The user signs in to both **in their own terminal**. Never ask for or print keys, passwords or tokens.
- **Identifiers.** Never print or write either account ID, any ARN, the distribution ID or domain, the API URL or ID, or emails into tracked files or the chat. Keep them in `.local/phase-4/cdn/` and the ignored `AWS/terraform.tfvars`.
- **Credentials for Terraform.** Earlier steps exported the main account's credentials into the environment with `aws configure export-credentials --profile kilnwatch --format env`.
  - For the second account, use an AWS config profile that calls `credential_process = aws configure export-credentials --profile kilnwatch-bedrock --format process`, for example a profile named `kilnwatch-cdn-tf` in `~/.aws/config` (outside the repo).
  - The aliased provider uses `profile = var.cdn_profile`.
  - No long-lived access keys, and no credentials in any tracked or ignored repo file.
- **Bucket policy.** It must stay exactly as narrow as planned: `s3:GetObject` on `evidence/*.png` only, for the `cloudfront.amazonaws.com` service principal, with the condition `AWS:SourceArn` = **that one distribution's ARN**. Nothing else.

## Step 0 — check with the user

Ask:
1. "Has the second account's owner agreed to host the image CDN until the hackathon ends?"
2. "Are you signed in to both `kilnwatch` and `kilnwatch-bedrock`?"
3. "Has AWS verified the main account in the meantime?" If yes, stop: the plain prompt 09 Part B in the main account is better.

## Step 1 — Terraform (keeps the main-account path for later)

1. **New variables:**
   - `evidence_cdn_account`: `"main"` or `"second"`, default `"main"`, validated;
   - `cdn_profile`: string, default `""`.
2. **An aliased provider** `aws.cdn` in `versions.tf`: the same `hashicorp/aws` provider, `region = var.aws_region`, `profile = var.cdn_profile != "" ? var.cdn_profile : null`, and the same `default_tags`. No new provider source and no version change. `git diff --quiet AWS/.terraform.lock.hcl` must pass.
3. **In `bridge.tf`:**
   - add `count = var.evidence_cdn_account == "main" ? 1 : 0` to `aws_cloudfront_distribution.evidence`. It isn't in state, so nothing moves. Leave the existing main-account OAC alone; it already exists, costs nothing, and is reused if the setup switches back.
   - add `aws_cloudfront_origin_access_control.evidence_cdn` and `aws_cloudfront_distribution.evidence_cdn` with `provider = aws.cdn` and `count = var.evidence_cdn_account == "second" ? 1 : 0`. Use the **same settings** as the main distribution: the origin is the main bucket's regional domain name, `https-only`, GET/HEAD only, `PriceClass_200`, the same cache behaviour and the 403 error response. Only the OAC reference and the comment differ.
   - add a local `evidence_distribution` that picks whichever distribution exists. The bucket policy's `AWS:SourceArn` and the `evidence_base_url` output both use it.
4. **The ignored `AWS/terraform.tfvars`:** `evidence_cdn_account = "second"`, `cdn_profile = "kilnwatch-cdn-tf"`.
5. **Checks:** `fmt` and `validate`. Then a plan with `-target` on the second-account OAC and distribution plus `aws_s3_bucket_policy.evidence`, saved to `.local/phase-4/cdn/cdn.tfplan` with `terraform show` beside it.
   - **Expected:** 3 to add (2 in the second account, 1 bucket policy in the main account), 0 to change, 0 to destroy.
   - Show the summary and the bucket-policy JSON in the chat with the ARNs redacted. If anything else appears, stop.
   - Also confirm that a plan with `evidence_cdn_account = "main"` (passed as `-var`) shows the main distribution but **doesn't apply it**. That's just a dry check of the switch-back path.
6. Apply the saved plan. If the second account also returns "account must be verified", stop and report; don't work around it.
7. Wait for the distribution to finish deploying (`aws cloudfront wait distribution-deployed` with the second profile).

## Step 2 — publish, verify and re-import (prompt 08 §4 and §3, prompt 09 Part B steps 2–4)

1. **Publish** the two approved PNGs with `AWS/scripts/upload_evidence.py` (main account). Then run `verify_publication.py` against the new `evidence_base_url`: HTTPS, `image/png`, matching checksums. Upload the receipt the way the runbook says.
2. **Re-import on the runner through SSM `send-command`** with `--publication-receipt`. Download each needed file by key, because the runner can only `GetObject` on `imports/*`.
   - **Expected:** 0 new candidates, 0 new observations.
   - Both image URLs then appear in the protected and public detail for `KW-6b3b38…`, and all other 38 kilns still have null URLs.
3. **Denial probe:**
   - through CloudFront, a probe object, a non-PNG path under `evidence/` and anything under `models/` are denied;
   - direct S3 access to the PNGs is denied;
   - delete the probe object afterwards.
4. **Live API:** `GET /public/kilns/KW-6b3b38…` returns both URLs. Each URL fetches `image/png` with the expected size and checksum. Cache headers are sane.

## Step 3 — app check

1. Update the opt-in Swift test (`KILNWATCH_REAL_CONTRACT_LIST` in `KilnWatchCoreTests.swift`), which expects null image URLs. It should now accept them for `KW-6b3b38…` only and still require null for the others.
2. Run `swift test` in `App/Packages/KilnWatchCore`, with and without the environment variable, using a freshly saved live district body under `.local/`.
3. Run the root `xcodebuild` build with zero warnings.
4. In the Simulator with live config, open `KW-6b3b38…` and save one light and one dark screenshot of the before/after comparator to `App/docs/screens/phase-4/evidence-live-{light,dark}.png`. Check that the dates and the Copernicus attribution show and the image is pixel-sharp. If the screen still says "not yet published", investigate before reporting.

## Step 4 — documents and report

- **`AWS/docs/local-verification.md` and the runbook:** "Evidence CDN in the second account", with no identifiers. Include:
  - how it works;
  - why (the main account is unverified);
  - **switch-back**, once AWS verifies the main account: set `evidence_cdn_account = "main"`, run a targeted apply of the main distribution plus the bucket policy, republish the receipt, re-import, then a targeted destroy-by-count of the second-account distribution. That needs the user's go, and CloudFront disables a distribution before it deletes it.
  - **after the hackathon:** remove the second-account distribution and the Bedrock role.
- **`App/docs/HANDOVER.md`:** one line, "Evidence images live via CloudFront in the second account; runner kept for the rules-engine apply."
- **`App/docs/api-contract.md`:** note that image URLs are now non-null for published evidence.

Report, keeping **Terraform**, **live checks**, and **app checks** separate:
1. The plan and apply summary, and the bucket policy (redacted).
2. The publish and verify results, the re-import counts, and the denial-probe table.
3. The Swift test counts, the build result and the screenshot paths.
4. **Leak check:**
   - `git status --short`;
   - grep every changed and new tracked file for both account IDs, the API host and ID, and the CloudFront domain and ID: expect 0;
   - `git diff --quiet AWS/.terraform.lock.hcl`.
5. Open questions, at most 3.
