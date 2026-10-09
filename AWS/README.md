# KilnWatch AWS infrastructure (staged foundation)

This Terraform root is aligned with the KilnWatch model scripts and architecture described in the project README and concept PDF. It provisions the shared foundation for the current hackathon work. It is not yet a complete production deployment: the repository currently contains dataset preparation, training and scene detection scripts, but no application frontend, API contract, database migrations, or deployable inference container.

## Current deployment scope

- Primary AWS region: `us-west-2`, matching the Sentinel-2 public data location and the model repository's training example.
- Private, versioned S3 bucket for model artefacts, imagery and evidence; ECR repository, ECS/Fargate, Step Functions, API Gateway, Lambda, Cognito, private PostgreSQL, and basic alarms/logging are included.
- The DB master password is generated and managed by RDS in Secrets Manager. It is not supplied in Terraform variables.
- API Gateway has authenticated inspector routes and a read-only public resident route. The Lambda implementation is still a stub and returns empty/example responses; it does not query RDS or launch the workflow yet.
- Amplify and SageMaker training are disabled. SageMaker IAM roles/policies are also omitted unless training is explicitly enabled.
- The ECS task definition points at the KilnWatch inference ECR repository's `bootstrap` image tag. Push a compatible container before starting inference jobs; until then the state machine cannot successfully run inference.

The README in the application repository describes the target experience and staged model/app tracks. The infrastructure deliberately leaves those unfinished integration points visible instead of claiming the app is deployed.

## Initial setup

1. Use Terraform 1.6 or newer and AWS credentials for the target account. Confirm `us-west-2` is enabled and review the charges for RDS, NAT-free VPC networking, Fargate and other resources before applying.
2. Copy `terraform.tfvars.example` to `terraform.tfvars`. Set a globally unique lowercase `bucket_name_prefix`. Keep the local `.tfvars`, Terraform state, plans and AWS credentials private.
3. Run:

   ```sh
   terraform init
   terraform fmt -recursive
   terraform validate
   terraform plan
   ```

4. Review the plan and apply only after confirming the account, region, resource names and expected costs.

Terraform state contains infrastructure metadata and the RDS-managed secret reference. Use a private encrypted remote backend with locking before sharing this state with a team. Do not commit state.

## Model artefact path

The repository's `scripts/train.py` uploads run artefacts below the S3 prefix passed with `--s3`, followed by the run name. For example:

```sh
python scripts/train.py --data /path/to/kilns/kilns_full.yaml --name baseline \
  --s3 s3://YOUR_BUCKET/models
```

This produces keys such as `models/baseline/weights/best.pt`. The ECS task receives `DATA_BUCKET` and `MODEL_S3_PREFIX=models/`; the future inference container must select the desired run/version and implement the input/output S3 contract. The current `scripts/detect_scene.py` produces local GeoJSON and does not yet upload scene results or integrate with the API workflow.

## API and application integration still required

- Implement Lambda persistence and queries against PostGIS; add schema migrations for the kiln registry, rule evidence, review queue, inspections and audit history.
- Implement `POST /jobs` to validate input and start Step Functions. The current response is explicitly `501`.
- Implement public data filtering on `GET /public/kilns`; expose only the approved resident fields and continue labelling detections as pending inspection.
- Add role/district authorization for review and inspector writes. Cognito JWT authentication alone is not the full authorization policy described in the design.
- Package a PostgreSQL driver with Lambda and add private network access to Secrets Manager and Step Functions (VPC endpoints or an approved egress design). The private subnets have no NAT gateway.
- Build and push the inference image to the Terraform output `ecr_repository_url` using the `bootstrap` tag, then update the task's job input/output handling. The workflow currently invokes the task without a real job payload contract.
- Build the iOS and web clients against the final API response contract. No frontend source or Amplify repository settings are present in the provided GitHub repository at this time.

The public route and Cognito configuration are scaffolding only until those handlers are implemented. Keep `frontend_origin` set to the exact deployed site origin before browser-based release; for local development, set it to the actual dev-server origin.

## Deferred services

Keep `enable_amplify = false` until the web repository/branch and build command/output directory are known. Keep `enable_sagemaker_training_job = false` while training is underway. The checked-in training script is a local/Kaggle-style Ultralytics script, not a SageMaker training container; enabling the Terraform SageMaker job requires a compatible container and explicit input/output contract. `enable_agentcore` also remains false until the agent container and API integration are ready.

## Important operational notes

- RDS is private. Its master credential is managed by RDS/Secrets Manager; no database password is included in this folder.
- There is no NAT gateway. Private Lambda code cannot reach public endpoints. Add only the private service endpoints or egress that the completed API actually needs; AgentCore invocation also needs a supported connectivity path.
- RDS deletion protection is disabled and final snapshots are skipped for prototype cleanup. Change both before production and protect any data that must be retained.
- The S3 bucket blocks public access, enables encryption and versioning, and does not auto-delete objects.
- The model dataset is CC BY-NC 4.0; retain attribution and check the license before commercial use or redistribution.
- A model flag or rule-distance calculation is not a legal finding. Only an inspector verdict or approved human review should change a kiln's status.

## Outputs

```sh
terraform output
terraform output -raw api_base_url
terraform output -raw data_bucket_name
terraform output -raw ecr_repository_url
```

Do not run `terraform destroy` unless you intend to remove all managed resources and have preserved any data you need.
