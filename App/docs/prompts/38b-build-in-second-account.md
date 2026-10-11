# Prompt 38b: amendment to 38, build the image in the second account

Same chat as 38. **This file amends prompt 38; everything in 38 still applies except what is changed here.** No sub-agents. Don't commit, push or stage.

**Why:** 38 stopped at Step 0. CodeBuild's concurrent-build quota is **0** for every environment in the main account. The orchestrator checked the second account read-only: ARM/Medium (and ARM/Large) allow **15** concurrent builds in `ap-south-1`. So the image is **built in the second account** and **pushed into the main account's existing inference ECR repo**. Fargate, Step Functions, S3 and the runs stay in the main account, exactly as in 38.

**The user gave the go by running this prompt.** The scope of 38 changes as follows:

1. **CodeBuild moves to the second account** (`provider = aws.cdn`, region `ap-south-1`, same `cdn_profile` as the evidence CDN and the portal). In `AWS/inference.tf`, all gated by `enable_model_pipeline`:
   - a small **source bucket in the second account** (`bucket_prefix = "${var.project_name}-build-"`, public access blocked, SSE-S3, ownership enforced, a lifecycle rule that expires objects after 7 days);
   - the CodeBuild project (`aws/codebuild/amazonlinux-aarch64-standard:3.0`, `ARM_CONTAINER`, `BUILD_GENERAL1_SMALL` or Medium as the quota allows, privileged mode, source type `S3` from that bucket);
   - its role and log group. The role may: read only `build/*` in its own source bucket; write only its own log group; `ecr:GetAuthorizationToken`; and push only to the main account's inference repo (`ecr:BatchCheckLayerAvailability`, `InitiateLayerUpload`, `UploadLayerPart`, `CompleteLayerUpload`, `PutImage`, `BatchGetImage`) on that repo's ARN. Nothing else.
2. **One new main-account resource:** `aws_ecr_repository_policy` on `aws_ecr_repository.inference` that allows **only that CodeBuild role's ARN** the six push actions above. No account-wide principal, no `*`. This is the only cross-account write path.
3. **The build zip** goes to the second-account source bucket (`build/m0/`), not the main data bucket. The main data bucket and its policy stay untouched. `best.pt` and its manifest still go to the main bucket's `models/`, as in 38.
4. **Dockerfile:** pull the base image from `public.ecr.aws/docker/library/python:3.12-slim` (CodeBuild's shared IPs hit Docker Hub rate limits). Also copy `Model/scripts/prepare_data.py` unchanged; `detect_scene.py` imports it.
5. **`buildspec.yml`:** log in to the **main account's** registry (`aws ecr get-login-password | docker login --username AWS --password-stdin <main registry>`), with the registry host passed in as a CodeBuild environment variable from Terraform, never printed in logs; `docker build --platform linux/arm64`; push `m0-<short git sha>`; print only the image digest.
6. **ECS size:** change the defaults of the existing `ecs_task_cpu` and `ecs_task_memory` variables to `4096` and `16384` (don't add new variables). Check nothing else uses them; if something does, stop and report.
7. **Plan and apply** (still exactly two targeted applies):
   - (a) Step 2: the second-account bucket and its settings, the CodeBuild project, role, policy and log group, the main-account ECR repository policy, the task definition, the state machine and the narrowed task-role policy. Expect additions, in-place changes and a task-definition replacement. Anything else, stop.
   - (b) Step 3.2 as in 38 (image tag: task definition + state machine only).

**Preflight additions (read-only, stop on failure):**
- `kilnwatch-cdn-tf` can call `codebuild list-projects`, `s3api list-buckets` (count only) and `iam list-roles` (count only) in the second account. If any is denied, stop: the second account's owner may need to grant it.
- The quota line from the orchestrator: ARM/Medium = 15 in `ap-south-1` (re-check it, value only).
- Cost (unchanged estimate, about $0.65): CodeBuild now bills to the **second account**; say so in the report. The second account has no budget alarm, so remind the user.

**Rollback** (add to the docs): `enable_model_pipeline = false` and one targeted apply removes the second-account build resources and the ECR repository policy; empty the source bucket first if it has no `force_destroy`. Needs a go.

**Leak rules as in 38,** plus: never print the second account's ID, the registry host or the CodeBuild role ARN; the build logs must not echo them.

Then continue 38 from Step 1 with these changes, through both runs and the Step 4 report. The report adds: which account each resource is in, the ECR repository policy (principal masked) and the build time.
