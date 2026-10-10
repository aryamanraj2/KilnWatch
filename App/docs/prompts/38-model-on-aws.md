# Prompt 38 (M0): run the kiln detector on AWS (ECR + Fargate + Step Functions)

You are the builder for **one infrastructure step**. Work sequentially in this one chat. No sub-agents. Don't commit, push or stage. The repo is public.

**Goal:** the detector that produced the 39 Hapur candidates (`Model/scripts/detect_scene.py` with the verified baseline `best.pt`) runs **on AWS**, not only on a laptop:
- an image in the existing ECR repo `aws_ecr_repository.inference`;
- a run as the existing Fargate task `aws_ecs_task_definition.inference`;
- started by the existing Step Functions state machine `aws_sfn_state_machine.inference`;
- reading the weights from S3 `models/` and writing the GeoJSON to S3 `detections/`.

Today these resources are **scaffolding**: the image tag points at nothing, and the state machine's comment says "Replace container command/input mapping". This makes them real. **No registry import in this step**: the registry stays as it is.

This machine has **no Docker**. Build the image on **AWS CodeBuild**, from a source zip in S3.

**The user gave the go by running this prompt.** The scope is exactly:
1. **New files:**
   - `AWS/inference/` (Dockerfile, `entrypoint.py`, `requirements.txt` pinned to `Model/requirements-integration.txt`, `buildspec.yml`);
   - `AWS/inference.tf` (the CodeBuild project, its role and log group), gated by `enable_model_pipeline` (default `false`);
   - tests for `entrypoint.py`.
2. **Edits:**
   - `aws_ecs_task_definition.inference`: ARM64 runtime, CPU and memory variables, the command taken from the input;
   - `aws_sfn_state_machine.inference`: the container override from the execution input;
   - the ECS task role policy, **narrowed** to read `models/*` and write `detections/*`, never widened.
3. **Uploads:** the verified `best.pt`, its artifact manifest and the build zip, to the data bucket's `models/` and `build/` prefixes.
4. **Plan and apply:** **one** targeted plan and apply for exactly those resources. Expect additions plus in-place changes and a task-definition replacement (a new revision is normal). Anything else, stop.
5. **One** CodeBuild build. Up to **2** Step Functions executions: the 2026-10-05 after scene, and optionally the 2023-12-05 before scene (that one feeds the later change triage).

**Out of scope:** the registry import, RDS, the API, the Lambdas, Bedrock, the CDN, the evidence cut, the tfvars beyond `enable_model_pipeline = true` and the image tag, schedules or triggers (manual starts only), the provider lock (`hashicorp/aws 6.68.0`), `destroy` and untargeted applies. If something needs one of these, stop and report.

## Rules

- **Never write or print** account IDs, ARNs, the API URL, CloudFront domains, bucket names, ECR URIs or the RDS host. Read them from `.local/integration-2b/outputs.json` and the tfvars without printing them. Save new private values to `.local/m0/` only.
- **Credentials:** the `kilnwatch` profile; Terraform binary `.local/tools/terraform/terraform`. Sign-ins happen only in the user's terminal.
- **Product:** the output is **candidates**. It's never "kilns found violating". The model score is not accuracy. Don't quote AP50 as accuracy.

## Step 0: preflight and cost (read-only; stop if a check fails)

1. **Weights:** find the verified baseline `best.pt` and its artifact manifest (see `Model/README.md` and `AWS/docs/first-record-runbook.md` §1–2; the SHA is recorded there). Check the SHA-256 matches.
2. **Local reference:** `.local/integration-1/hapur.geojson` (SHA-256 `b1e9d177…13d0`, 39 features). Find the exact after-scene ID it used from its provenance. The before scene is `S2A_T43RGM_20231205T053206_L2A`.
3. **Access checks** (counts only):
   - `ecr describe-repositories`;
   - `ecs list-clusters`;
   - `stepfunctions list-state-machines`;
   - `codebuild list-projects`.

   If CodeBuild or Fargate is blocked on the account ("Operation not allowed", or similar), stop and report.
4. **Cost:**
   - CodeBuild on ARM, about 10–15 min: about $0.15;
   - Fargate ARM at about 4 vCPU / 16 GB for about 10–20 min per scene: about $0.05–0.15 per run;
   - ECR at about 2 GB: about $0.20 a month;
   - S3: negligible.

   Report the total. **If it is above $5 for this step, stop.**

## Step 1: image and entrypoint

- **`AWS/inference/Dockerfile`:** `python:3.12-slim` on **linux/arm64**, with the system libs rasterio needs (or wheels only). Install the pinned requirements with the **CPU** torch wheel. Copy `Model/scripts/detect_scene.py` and `verify_checkpoint.py` unchanged; don't edit model code. Run as a non-root user.
- **`entrypoint.py`** takes `--scene <stac id>`, `--run-id <id>`, the S3 prefixes from the env, and nothing else. It:
  1. downloads `models/best.pt` and the manifest;
  2. **verifies the checkpoint hash** (refuse to run on a mismatch);
  3. runs `detect_scene.py --scene … --weights … --artifact-manifest … --out /tmp/out.geojson` with the **same defaults as the local run** (`--conf`, `--iou`, `--ios`; check the local run's provenance);
  4. uploads `detections/<run-id>/kilns.geojson` and `detections/<run-id>/run.json` (scene, model SHA, input SHA, counts, timings, image digest).

  It writes nothing outside `detections/`. Logs hold counts and timings only.
- **Tests (no network):** argument validation, hash refusal, the S3 key layout, and that a failure exits non-zero.
- **`buildspec.yml`:** ECR login, `docker build --platform linux/arm64`, then push tag `m0-<short git sha>`. The CodeBuild project uses an ARM image (`aws/codebuild/amazonlinux-aarch64-standard:3.0`) with privileged mode for Docker. Its role can push only to the inference repo, read only `build/*` and write only its own log group.

## Step 2: Terraform

- **ECS:** the task definition gets `runtime_platform { cpu_architecture = "ARM64", operating_system_family = "LINUX" }`, with CPU and memory from variables (4096 / 16384 by default, adjustable). Keep the log group.
- **Step Functions:** `RunInferenceTask` passes `Overrides.ContainerOverrides[0].Command` built from the execution input (`$.scene`, `$.run_id`), with a timeout of 3600 s. Keep the existing subnets and security group. Add a `Catch` that ends in `Fail` with no data echo.
- **IAM:** narrow `ecs_task_s3` to `s3:GetObject` on `models/*` and `s3:PutObject` on `detections/*`. Keep `ListBucket` only if it's needed, with a prefix condition.
- **`AWS/inference.tf`:** the CodeBuild project, its role and its log group (`count = var.enable_model_pipeline ? 1 : 0`).
- **Plan and apply:** `fmt`, `validate`, then one targeted plan on exactly these resources, saved to `.local/m0/m0.tfplan`. Read it; anything outside the list, stop. Apply it.

## Step 3: build, run, compare

1. Zip the build context (`COPYFILE_DISABLE=1`, no `._*`), upload it to `build/m0/`, start **one** CodeBuild build and wait. Record the image digest.
2. Set the image tag (ignored tfvars), apply the task definition only (a targeted apply of `aws_ecs_task_definition.inference` and `aws_sfn_state_machine.inference`, expect 1 replace + 1 in-place change), then start the execution `{"scene": "<after scene id>", "run_id": "m0-after"}` and wait.
3. **Compare** `detections/m0-after/kilns.geojson` with the local `hapur.geojson`:
   - the feature count;
   - one-to-one footprint matching by IoU (report how many have IoU ≥ 0.9, the median IoU, and anything unmatched);
   - class and score differences;
   - whether `registry.contract.convert` gives the **same 39 kiln IDs**.

   CPU and GPU float differences can move a footprint slightly, which changes an ID. Report it honestly, and **do not import**.
4. Optional, only if run 1 matched well: the execution `{"scene": "S2A_T43RGM_20231205T053206_L2A", "run_id": "m0-before"}`. Report the count, and how many of today's 39 have a match in 2023 (IoU ≥ 0.3), only as a fact for later change triage.

## Step 4: docs and report

- **`AWS/docs/local-verification.md`:** a "M0: detector on AWS (38)" entry with:
  - the runtime, timings and cost;
  - the comparison table;
  - how to start a run (with placeholders);
  - the rollback: `enable_model_pipeline = false`, a targeted apply, needs a go.
- **`App/docs/plan-final-stretch.md`:** don't edit it. The orchestrator updates it.

**Report:**
- the preflight and cost;
- the plan and apply summaries;
- the build time and image size;
- run times;
- the comparison table;
- the leak check:
  - grep the changed tracked files for every identifier from `.local` (expect 0);
  - `git diff --quiet AWS/.terraform.lock.hcl`;
  - only the allowed files touched;
- open limits (ARM CPU vs the original runtime; no import; manual start only).
