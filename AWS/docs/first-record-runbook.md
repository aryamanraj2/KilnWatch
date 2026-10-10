# Integration 1 first-record deployment runbook

Prepared 2026-10-09 on main; **executed in Integration 2B (2026-10-10)**. Current state:
73 of 75 resources deployed in `ap-south-1`, migration/bootstrap/import done (39
records live behind the API). CloudFront is blocked by an AWS account-verification gate,
so §7 publication is pending. See "Deployed state (Integration 2B)" at the end and
`local-verification.md`. Commands below now include the corrections found in 2B.

## Verified local inputs and checks

- User supplied root `best.pt`, subsequently `args.yaml` and `scores.json`.
  `Model/results/checkpoint-manifest.json` records their checksums and configuration.
  Checkpoint SHA-256: `3bcbcd0af696278d894ab6f463c81a742c596192d0493a470f0d03ac4b61f799`.
  19,713,480 bytes; OBB; classes 0=CFCBK, 1=FCBK, 2=Zigzag;
  Ultralytics 8.4.174; embedded baseline, 20 requested epochs, 128 px, batch 64.
  A stripped epoch of -1 cannot establish completed epoch count. Uploaded metrics
  equal the existing baseline scores; no independent evaluation was run. Saved
  Kaggle version/run identity and cryptographic weight-to-score linkage remain missing.
- One fixed local Hapur run, AOI lat 28.68–28.78, lon 77.73–77.83,
  scene `S2B_T43RGM_20261005T053448_L2A`, actual STAC acquisition
  `2026-10-05T05:41:03.148Z`. 120 patches, 55 raw detections, 39 candidates
  (5 CFCBK, 34 FCBK). No field precision or technology finding is established.
- Local raw export, STAC items, previews and two PNGs are ignored under
  `.local/integration-1/`. Detector input SHA-256
  `b1e9d177f68d58b48bdd75ff12f93ea244f66944d391710d433a8e2f6be013d0`.
- First sorted observation `KW-6b3b38da681850e5af46b024f3d3f78e` has aligned
  256×256 RGBA evidence. Before `S2A_T43RGM_20231205T053206_L2A`, actual time
  `2023-12-05T05:40:56.807Z`; after as above. EPSG:32643, GDAL transform
  `[765270,10,0,3184300,0,-10]`; nodata 0 on both.
  Before SHA `77aa718e93395c091017e1e4094ca714c8191a57e13f16759f077afce4a498fc`;
  after SHA `a0a6c2ca17915c9ce3efc4f7bf52efc2a9b23628e6dd794673167087b9d42cc5`.
  Fixed RGB reflectance rendering (STAC band scale/offset, range 0–0.3); no
  patch-wise contrast normalization. Inspectable pair reviewed: roads/field grid
  show no gross displacement. Sub-pixel registration, seasonal/haze effects and
  actual kiln/change interpretation are unverified. No historical kiln footprint
  is asserted. Tile cloud percentage is not a pixel-level cloud assessment.
- Conversion/evidence validation accepts all 39, with one evidence pair and
  remaining imagery unavailable. Nothing is published; API URL fields remain null.
- Unit/API/evidence tests and Python-to-Swift decoder/client proof are local.
  The read repository in offline API tests is a test double, not RDS proof.
  Real PostGIS tests are provided but skipped here: psql exists, PostGIS extension
  and Docker do not. Terraform and AWS CLI are absent; fmt/validate/plan/apply and
  cloud smoke checks are unrun. See `local-verification.md` for final counts.

## Decisions the AWS teammate must confirm before planning

1. Account ID, named AWS profile (`kilnwatch`, IAM user, never root), region
   `ap-south-1` (Mumbai), deployment operator and state owner. Use private encrypted state with locking; agree backend configuration
   and credentials separately. No state, plans, tokens or local `.tfvars` in Git.
2. Approve district `Hapur` for this AOI. The importer receives an administrative
   district assignment; it does not establish district boundaries. Re-import with a
   different district is rejected. Multi-district identities are deferred.
   (Still open: the AWS teammate has not yet confirmed district `Hapur`.)
3. Review RDS 17/PostGIS support, instance/storage, Secrets Manager interface endpoint
   in two private subnets, CloudFront, logs and optional runner costs. **Decided
   2026-10-09:** 7-day backups, deletion protection and a final snapshot; see the
   cost estimate in the deployment review.
4. Approve public publication of only the selected Copernicus satellite PNGs
   (**approved 2026-10-09** by the AWS teammate; upload in 2B). Model,
   raw export, field-photo and import prefixes stay private. The resident endpoint
   remains unavailable (503) until a reviewed projection/policy exists.
5. Select an approved existing VPC runner/VPN, or review enabling the optional SSM
   runner (`create_registry_runner=true`). The optional EC2 runner is in a public
   subnet, has a public address for outbound downloads/SSM, IMDSv2, encrypted disk
   and **no inbound ports**. RDS remains private and only its runner/API SGs can connect.
   If using an existing runner, explicitly approve its SG/RDS access in Terraform.

## 1. Verify existing checkpoint — ML team mate / App

Do not train. Retrieve the matching saved notebook version ID/link from the
ML team mate. Keep weights and raw data in ignored storage.
From the repository root:

```sh
python3 -m venv .venv-integration
.venv-integration/bin/python -m pip install -r Model/requirements-integration.txt -r AWS/requirements-operator.txt
.venv-integration/bin/python Model/scripts/verify_checkpoint.py best.pt \
  --args args.yaml --scores scores.json \
  --out Model/results/checkpoint-manifest.json
```

Pass `--run-identity '<saved-version-link>'` when supplied. Load only a trusted
checkpoint; loading a PyTorch checkpoint can execute its embedded Python objects.
Both Kaggle notebook script paths are corrected to `KilnWatch/Model/scripts/`,
including the commented upload import. Python cell syntax/path checks passed
without executing training. The main notebook's 9-hour cap is preserved; completion
and duration of the larger model are not asserted.

## 2. Reproduce local detection/evidence — App / ML team mate

Prefer the existing verified output to avoid another inference run. To reproduce
this fixed run with the same scene (no training):

```sh
.venv-integration/bin/python Model/scripts/detect_scene.py --aoi hapur_test \
  --scene S2B_T43RGM_20261005T053448_L2A --weights best.pt \
  --artifact-manifest Model/results/checkpoint-manifest.json --batch 16 \
  --out .local/integration-1/hapur.geojson
.venv-integration/bin/python Model/scripts/prepare_evidence.py \
  --detections .local/integration-1/hapur.geojson \
  --scenes .local/integration-1/hapur.scenes.json \
  --before-scene .local/integration-1/before-scene.json \
  --district Hapur --out .local/integration-1/evidence
PYTHONPATH=AWS .venv-integration/bin/python -m registry.cli validate \
  --detections .local/integration-1/hapur.geojson --district Hapur \
  --evidence .local/integration-1/evidence/manifest.json \
  --preview .local/integration-1/registry-preview.json
```

The before scene is a saved STAC item. For another workstation, fetch its exact
item by Earth Search `POST /v1/search` with collection `sentinel-2-c1-l2a`,
`ids=["S2A_T43RGM_20231205T053206_L2A"]`; save the returned feature as
`before-scene.json`. Omit `--before-scene` if unavailable; do not substitute a
training tile or fabricate a date. `--index` chooses one sorted observation.
The preparer refuses out-of-bounds, >1% nodata, different CRS/grid, inconsistent
RGB band grid, missing radiometry or a historical timestamp not earlier than after.
Before has no observed historical outline. Attribution is in the manifest.

Export creation/import times change on repeat; raw checksums may therefore change.
IDs remain stable for identical scene/model/canonical footprint, including feature
reordering and rotated/reversed corner order. New geometry, scene or model may
create a different ID; cross-scene association requires later reviewed matching.

## 3. Package and verify locally — App / AWS teammate

```sh
.venv-integration/bin/python AWS/scripts/package_api.py
PYTHONPATH=AWS .venv-integration/bin/python -m unittest discover -s AWS/tests -v
PYTHONPATH=AWS .venv-integration/bin/python AWS/tests/generate_contract.py
xcodebuild -project KilnWatch.xcodeproj -scheme KilnWatch \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
(cd App/Packages/KilnWatchCore && swift test)
```

The Lambda package includes handler, registry read/serialization modules, pinned
pure-Python pg8000 dependencies and the RDS trust bundle. It targets Python 3.12,
x86_64; boto3 comes from the Lambda runtime. No native driver build on macOS is
shipped to Lambda. Runtime checks certificate chain **and hostname** using the RDS
bundle; no `sslmode=prefer` or TLS downgrade. Archive path is
`AWS/build/api_handler.zip`; packaging must run **before** Terraform validation/plan.
The local packaging test verifies ZIP contents/import and sanitized secret/connection
failure handling; an actual Lambda invocation remains unrun.

Disposable database proof, when Docker is available, using a LOCAL isolated port:

```sh
docker run --name kilnwatch-postgis-test -d -p 127.0.0.1:55432:5432 \
  -e POSTGRES_DB=kilnwatch_test -e POSTGRES_PASSWORD=local-disposable-test \
  postgis/postgis:17-3.5
# Wait until docker exec kilnwatch-postgis-test pg_isready succeeds.
KILNWATCH_TEST_DB_PORT=55432 KILNWATCH_TEST_DB_PASSWORD=local-disposable-test \
  PYTHONPATH=AWS .venv-integration/bin/python -m unittest discover -s AWS/tests -v
# Remove only this disposable container after reviewing results:
docker rm -f kilnwatch-postgis-test
```

These tests connect only to 127.0.0.1 and `kilnwatch_test`, run migrations twice,
prove reordered retries without duplicate observations, retain human status/review,
check SRID/validity and roll back a database constraint failure mid-batch. They must
pass before live import. Transaction spies are not a replacement for this proof.

## 4. Review infrastructure plan — AWS teammate (future, read access required)

```sh
export AWS_PROFILE=kilnwatch AWS_REGION=ap-south-1
aws sts get-caller-identity
cd AWS
cp terraform.tfvars.example terraform.tfvars
# Set approved names/region/runner choice in the ignored file.
cp backend.hcl.example backend.hcl   # ignored; set the account ID
terraform init -backend-config=backend.hcl -lockfile=readonly  # never -upgrade
terraform fmt -check -recursive
terraform validate
terraform plan -out=first-record.tfplan
terraform show first-record.tfplan
```

`AWS/versions.tf` has a partial `backend "s3" {}` block; its values live in the ignored
`AWS/backend.hcl` (template: `backend.hcl.example`). Locking is S3-native
(`use_lockfile = true`, Terraform >= 1.10, no DynamoDB). State for a shared deployment
must never be local on a laptop. `init -backend=false` remains available for offline
`validate`. The state bucket is created once, outside Terraform (section 4a).

Confirm identity, resource count, private RDS, two private Secrets Manager endpoint
interfaces, evidence-only S3 policy, runtime secret separation, and disabled optional
services. A plan is allowed only after the target profile/account and read access
are explicitly established. **Do not apply during this preparation step.**

Lambda can reach only RDS TCP 5432 and the Secrets Manager endpoint TCP 443.
Private DNS routes secret calls through the endpoint without NAT. The handler
reads image metadata from PostgreSQL and needs no S3 endpoint/IAM. The optional
runner uses outbound public connectivity to S3/SSM/packages and the private endpoint
to retrieve the master secret; a separate statement allows only its role to populate
the dedicated reader secret. IAM alone is not treated as a network path.

AgentCore, SageMaker training, Amplify and long-running ECS service stay disabled.
Existing batch ECS/Step Functions/ECR scaffolding remains unfinished; do not start
it or create an inference container in this step. The API has no StartExecution
permission and jobs return 501. Routes, rules, agents and verdict endpoints are absent.

## 4a. Terraform state bucket (created 2026-10-09, outside Terraform)

One bucket per account/region, created once with the AWS CLI by the `kilnwatch`
profile (IAM user, never root). Terraform never manages it.

```sh
export AWS_PROFILE=kilnwatch AWS_REGION=ap-south-1
B=kilnwatch-tfstate-<account-id>-ap-south-1
aws s3api create-bucket --bucket "$B" --create-bucket-configuration LocationConstraint=ap-south-1
aws s3api put-public-access-block --bucket "$B" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-versioning --bucket "$B" --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$B" --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-bucket-policy --bucket "$B" --policy '{"Version":"2012-10-17","Statement":[{"Sid":"DenyInsecureTransport","Effect":"Deny","Principal":"*","Action":"s3:*","Resource":["arn:aws:s3:::'"$B"'","arn:aws:s3:::'"$B"'/*"],"Condition":{"Bool":{"aws:SecureTransport":"false"}}}]}'
# Verify (read-only):
aws s3api get-public-access-block --bucket "$B"
aws s3api get-bucket-versioning --bucket "$B"
aws s3api get-bucket-encryption --bucket "$B"
aws s3api get-bucket-policy --bucket "$B"
```

**Removal** (only after the deployment is destroyed or its state moved; this deletes
every state version):

```sh
aws s3api list-object-versions --bucket "$B" --output json \
  --query '{Objects: [Versions, DeleteMarkers][][].{Key: Key, VersionId: VersionId}}' > /tmp/v.json
aws s3api delete-objects --bucket "$B" --delete file:///tmp/v.json   # skip if the list is empty
aws s3api delete-bucket --bucket "$B"
```

## 5. Apply only after explicit user authorization — AWS teammate

After plan review and user authorization, apply that reviewed plan:

```sh
terraform apply first-record.tfplan
terraform output -raw api_base_url
terraform output -raw evidence_base_url
terraform output -raw data_bucket_name
terraform output -raw rds_endpoint
terraform output -raw registry_admin_secret_arn
terraform output -raw registry_reader_secret_arn
terraform output -raw cognito_user_pool_id
terraform output -raw cognito_app_client_id
terraform output -raw registry_runner_id # only when optional runner enabled
```

No `/v1` is appended to `api_base_url`. Do not expose RDS publicly or temporarily
open port 5432 to a laptop. Do not print or store passwords in Terraform variables.

## 6. Migrate/import through the private path — AWS teammate

After deployment authorization, package this reviewed working tree's operator
source (does not require a commit) and upload source/inputs to **private** `imports/`:

```sh
# Repository root, on the approved operator workstation:
tar --exclude=__pycache__ -czf .local/integration-1/operator-source.tgz \
  AWS/registry AWS/migrations AWS/scripts AWS/lambda/requirements.txt AWS/requirements-operator.txt
# Upload only the required inputs, never previews or real list/detail JSON:
aws s3 cp .local/integration-1/hapur.geojson 's3://<data-bucket>/imports/integration-1/hapur.geojson'
aws s3 cp .local/integration-1/operator-source.tgz 's3://<data-bucket>/imports/integration-1/operator-source.tgz'
for f in manifest.json <before-sha>.png <after-sha>.png; do
  aws s3 cp ".local/integration-1/evidence/$f" "s3://<data-bucket>/imports/integration-1/evidence/$f"; done
# The publication receipt follows separately in section 7.
# Run the runner steps below with non-interactive SSM (correction 2), e.g.
#   aws ssm send-command --instance-ids '<registry-runner-id>' --document-name AWS-RunShellScript \
#     --parameters file://<script-params.json>
#   aws ssm get-command-invocation --command-id <id> --instance-id '<registry-runner-id>'
# after `aws ssm describe-instance-information` shows the runner Online.
```

On the approved SSM runner, using its instance role (no copied AWS access keys):

```sh
# Verified 2026-10-10 on AL2023 2023.12 (system Python 3.9): gives 3.12.14 / pip 23.2.1.
dnf install -y python3.12 python3.12-pip      # SSM runs as root; HOME may be unset
export HOME=/root; mkdir -p ~/kilnwatch-proof && cd ~/kilnwatch-proof
# Correction 1: the runner may only GetObject on imports/*, not list it. Fetch exact keys.
P='s3://<data-bucket>/imports/integration-1'
for k in hapur.geojson operator-source.tgz evidence/manifest.json \
         evidence/<before-sha>.png evidence/<after-sha>.png; do
  aws s3 cp "$P/$k" "input/$k"; done
tar -xzf input/operator-source.tgz
python3.12 -m venv .venv
.venv/bin/python -m pip install -r AWS/requirements-operator.txt
curl --fail --silent --show-error \
  https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -o rds-ca.pem
# boto3 needs an explicit region on the runner; Lambda sets AWS_REGION itself.
export AWS_REGION='<region>' AWS_DEFAULT_REGION='<region>'
export DB_HOST='<private-rds-endpoint>' DB_PORT=5432 DB_NAME=kilnwatch
export DB_CA_BUNDLE="$PWD/rds-ca.pem" DB_SECRET='<registry-admin-secret-arn>'
export REGISTRY_READER_SECRET='<registry-reader-secret-arn>'
PYTHONPATH=AWS .venv/bin/python -m registry.cli migrate
PYTHONPATH=AWS .venv/bin/python AWS/scripts/bootstrap_reader.py
PYTHONPATH=AWS .venv/bin/python -m registry.cli validate \
  --detections input/hapur.geojson --district Hapur --evidence input/evidence/manifest.json
PYTHONPATH=AWS .venv/bin/python -m registry.cli import \
  --detections input/hapur.geojson --district Hapur --evidence input/evidence/manifest.json
# Repeat the import and confirm candidates_inserted=0, observations_inserted=0.
```

The AL2023 AMI's AWS CLI/SSM availability and package commands must be checked
on the runner; they were not executed here. Migration uses the RDS-managed admin
secret; schema roles are NOLOGIN. Import grants cannot update human status/review/
assessment. The initial controlled administrative import may use master credentials;
subsequent automated imports should provision a login with `kilnwatch_importer`.
Lambda only reads the separate `kilnwatch_api` login/secret with `kilnwatch_reader`.
Do not grant it the master secret. Bootstrap creates the reader once, fails on an
existing role, and never prints credentials. Rotation needs its own reviewed procedure.

`CREATE ROLE … PASSWORD` text reaches the server. Before bootstrapping, the AWS
teammate confirms the RDS `log_statement` parameter is not `ddl` or `all` (the
default is `none`), so the password is not written to the database log.

Bootstrap writes the reader secret **before** `COMMIT`. If it fails, recover with
these checks, not guesswork:

1. As admin (`DB_SECRET` = master secret), run
   `SELECT 1 FROM pg_roles WHERE rolname='kilnwatch_api'`.
2. **No row:** the role creation rolled back. The secret may hold a password for a
   role that does not exist; that is harmless. Rerun `bootstrap_reader.py`. It makes
   a new password and overwrites the secret. (Proven locally with Secrets Manager
   stubbed in-process and a forced commit failure; see `local-verification.md`.)
3. **A row:** the commit landed server-side although the client saw an error. The
   secret was written first, so it matches. Do not rerun (it refuses an existing
   role). Verify the reader login, then stop if it fails and use a reviewed
   rotation; never drop the role ad hoc:

   The runner role cannot read the reader secret (it may only write it), so verify as
   admin in a rolled-back transaction instead (used in 2B):

   ```sh
   PYTHONPATH=AWS .venv/bin/python -c "from registry.db import connect_from_env as c; n=c(); k=n.cursor(); \
     k.execute('SET LOCAL ROLE kilnwatch_api'); k.execute('SELECT COUNT(*) FROM kilnwatch.candidates'); print(k.fetchone()[0]); n.rollback()"
   ```

Validate all inputs before opening the write transaction. Any database failure rolls
back the run/candidates/observations/evidence. Migration ledger locks and checksums
prevent an edited applied migration being silently accepted. Human status/review/
assessment are never updated by `persist`. Original observation provenance stays
intact; every input file/run links to the observation separately.

## 7. Publish only approved evidence and verify it — AWS teammate

The AWS teammate reviews the two selected PNGs/attribution, then uses an authorized
operator role with PutObject to **evidence/** (the runner has no such permission):

```sh
.venv-integration/bin/python AWS/scripts/upload_evidence.py \
  --manifest .local/integration-1/evidence/manifest.json --bucket '<data-bucket>' \
  --publish-reviewed-evidence
.venv-integration/bin/python AWS/scripts/verify_publication.py \
  --manifest .local/integration-1/evidence/manifest.json \
  --base-url 'https://<evidence-distribution>' --out .local/integration-1/publication-receipt.json
aws s3 cp .local/integration-1/publication-receipt.json \
  's3://<data-bucket>/imports/integration-1/publication-receipt.json'
```

CloudFront OAC signs requests to private S3; its bucket policy allows only
`evidence/*.png` for that exact distribution. Bucket public access blocks remain on.
Upload helper uses conditional writes with content-hashed keys; retries verify old
bytes. HTTPS verification checks image content type and object SHA, creating a
receipt. Before that proof the importer produces null URL fields, never placeholders.
On the runner, download the receipt and repeat the import with
`--publication-receipt input/publication-receipt.json`. IDs/human state stay intact;
metadata gains only verified distribution URLs. Verify requests for existing
`models/`, `imports/` and field-photo objects through CloudFront are denied; use
private test objects with the authorized operator, not real sensitive photos.

## 8. Provision a legitimate inspector and obtain an ID token — AWS teammate

Pool sign-up is admin-only; create a named individual test account with the
immutable `custom:district=Hapur` attribute and add it to `inspector` via
`admin-create-user` / `admin-add-user-to-group`. Send Cognito's invitation to the
intended owner, who chooses their own password. Do not share a production password.
District is in ID-token read attributes, never client write attributes. Only IAM
administrators may assign it/group membership. Group changes can take until tokens
expire (60 min); revoke/refresh test sessions when changing authorization.

For this read proof the public client allows USER_PASSWORD_AUTH/SRP; use Cognito's
legitimate auth flow and handle `NEW_PASSWORD_REQUIRED` for a new account. Store
credentials in a mode-600 ignored temporary request file or supply them via the
operator's secure tooling, not shell history. AWS CLI forms:

```sh
aws cognito-idp initiate-auth --client-id '<app-client-id>' \
  --auth-flow USER_PASSWORD_AUTH --auth-parameters file://<private-auth-parameters.json> \
  > <private-auth-response.json>
# If challenged, respond-to-auth-challenge using the returned Session and private
# challenge response file. Use AuthenticationResult.IdToken for this API proof.
```

The response and token remain local/private and are deleted after verification.
The HTTP API validates issuer, signature, expiry and audience; Lambda additionally
requires `token_use=id`, the configured client `aud`, a `sub`, exact inspector group
membership and a valid admin-assigned district. Missing claims deny access. Access
tokens do not have this district mapping and are refused. No fake bearer token is
used in a live request. Managed-login domain/OAuth PKCE/Keychain and Verified
Permissions are deferred; no source claims they have been deployed.

## 9. Read API/image smoke checks → Swift decode — AWS teammate / App

With the valid token in a private header file (avoid token in command arguments):

```sh
curl --fail-with-body --header @<private-header-file> \
  'https://<api-host>/kilns?district=Hapur' -o .local/live-list.json
curl --fail-with-body --header @<private-header-file> \
  'https://<api-host>/kilns/KW-6b3b38da681850e5af46b024f3d3f78e' -o .local/live-detail.json
```

Expect 39 flagged candidates, unknown exposure, `rules_assessment=not_evaluated`,
unverified type even for high scores, and metadata/verified URLs for one pair only.
GET list defaults to 100/max 200; `next_cursor` keyset pages are never silently
truncated. Core follows each page and fails repeated/empty invalid cursors. Detail
uses the same serializer; unknown/other-district IDs return 404.

Also verify: missing/expired token 401 at Gateway; valid account without inspector
or district 403; Hapur token requesting Meerut 403; invalid filters/IDs 400; missing
ID 404; `/public/kilns` 503 with no private fields; jobs 501. During a controlled
failure test, secret/database unavailability must produce 503 and no successful
empty list. Gateway-generated auth errors use its own body; Lambda-generated
errors use the contract's nested error. Health says readiness not checked, not DB OK.

Feed the real body into the existing decoder/client test:

```sh
(cd App/Packages/KilnWatchCore && \
  KILNWATCH_REAL_CONTRACT_LIST='<absolute-path-to-live-list.json>' swift test)
```

That test uses an offline URLProtocol body: it proves decoding/client compatibility,
not that the simulator itself contacted AWS. Live authenticated curl/image checks
must be reported separately. Leave Today/route service unconfigured; do not invent
a one-stop route. App registry fetching and evidence comparison/loading are Phase 3.

## Deployment review (Integration 2A)

Prepared 2026-10-09 with Terraform 1.16.5 and the locked `hashicorp/aws 6.68.0`.
`fmt -check` and `validate` pass. A **read-only plan** ran against the S3 backend in
the user's account (`ap-south-1`, profile `kilnwatch` = IAM user `aryaman`) with
`create_registry_runner=true` and `bucket_name_prefix=kilnwatch`:
**75 to add, 0 to change, 0 to destroy**, matching the source count below. Nothing
was applied. The plan and its text stay private in ignored files.

Plan review: RDS `publicly_accessible=false`, encrypted, deletion protection on,
7-day backups, final snapshot `kilnwatch-hackathon-db-final`; RDS subnet group and
the Secrets Manager endpoint use only the two private subnets (`10.40.11.0/24`,
`10.40.12.0/24`, no public IPs); bucket policy references only `evidence/*.png` and
the distribution's ARN; the Lambda role policy references only the reader secret;
CloudFront `PriceClass_200`; no AgentCore, SageMaker, Amplify, ECS service or any
execution resource. Region check (read-only, 2026-10-09): `ap-south-1` offers RDS
PostgreSQL 17.5–17.11 on `db.t4g.micro` (default 17.9); AWS's extension table lists
PostGIS 3.5.1 for 17.9 and 3.5.6 for 17.9 R2/17.10/17.11. The local proof used
PostGIS 3.6. The name-collision check below found **no** existing objects.

### Resource set from source (defaults, `alert_email=""`)

`create_registry_runner=false` creates **70** managed resources; `true` adds **5**
(runner IAM role, its SSM policy attachment and inline policy, instance profile, EC2
instance) and one SSM parameter read for the AL2023 AMI.

- **Network (15):** VPC, IGW, 2 public subnets (auto-assign public IPv4), 2 private
  subnets, public route table (0.0.0.0/0 → IGW) and private route table (no NAT), 4
  associations, SGs `ecs`, `lambda`, `db`.
- **Storage (6):** `random_id`, data bucket `<prefix>-data-<hex>` (`force_destroy=false`),
  public access block (all four on), SSE-S3, versioning; ECR `kilnwatch-inference`.
- **Database (4):** RDS PostgreSQL 17 `kilnwatch-hackathon-db` (`db.t4g.micro`, 20→100
  GB, encrypted, `publicly_accessible=false`, RDS-managed master secret), subnet group
  over the two private subnets, parameter group `kilnwatch-registry-pg17`
  (`rds.force_ssl=1`), empty reader secret `kilnwatch/hackathon/registry-reader`.
  RDS also creates its own `rds!db-…` master secret outside Terraform's naming.
- **Bridge (8):** CloudFront distribution + OAC `kilnwatch-evidence`, bucket policy,
  SGs `registry-runner` and `secrets-endpoint` (always created, even without a
  runner), two Lambda egress rules (5432 → db SG, 443 → endpoint SG), Secrets Manager
  interface endpoint in both private subnets (two ENIs, private DNS).
- **API (15):** Lambda `kilnwatch-api` (Python 3.12, x86_64, VPC), Cognito pool
  `kilnwatch-users`, client, group `inspector`, HTTP API `kilnwatch-api`, JWT
  authorizer, Lambda integration, 5 routes (`GET /kilns`, `GET /kilns/{id}`,
  `POST /jobs`, public `GET /health`, public `GET /public/kilns`), `$default` stage,
  access-log group `/aws/apigateway/kilnwatch` (14 days), invoke permission.
- **IAM (10):** roles `kilnwatch-ecs-execution`, `kilnwatch-ecs-task`,
  `kilnwatch-api-lambda`, `kilnwatch-step-functions` with their policies/attachments.
- **Scaffolding, never started (9):** ECS cluster `kilnwatch-cluster`, task definition
  `kilnwatch-inference` and log group `/aws/ecs/kilnwatch-inference`; Step Functions
  `kilnwatch-inference-workflow`; ECR `kilnwatch-strands-agents` + lifecycle policy; IAM
  role `kilnwatch-agentcore-runtime` with three inline policies (Bedrock invoke, ECR
  pull, logs). Disabled options do **not** mean only registry resources exist.
- **Alerting (3):** SNS `kilnwatch-alerts`, alarm `kilnwatch-api-lambda-errors`.

Count-0 by default: AgentCore runtime and its Lambda invoke policy, SageMaker training
role/job, Amplify app/branch, the demo ECS service, the SNS email subscription.
Nothing starts inference, training or an agent. The ECS task role can write the whole
data bucket, but nothing runs it.

Not managed by Terraform: the Lambda log group `/aws/lambda/kilnwatch-api` is created on
first invocation with **no retention limit**; Lambda's VPC ENIs.

### Name collisions to check before planning (AWS teammate, read-only)

Run 2026-10-09 in `ap-south-1` (account confirmed by the user): every name below was
absent; the account has only one existing VPC.

IAM role names are account-global; the rest are per region. CreateCluster, CreateTopic,
PutMetricAlarm and task-definition registration **adopt or overwrite** an existing
object of the same name instead of failing, so check those especially.

```sh
for r in kilnwatch-ecs-execution kilnwatch-ecs-task kilnwatch-api-lambda \
         kilnwatch-step-functions kilnwatch-agentcore-runtime kilnwatch-registry-runner; do
  aws iam get-role --role-name "$r" --query Role.Arn --output text 2>&1 | tail -1; done
aws cognito-idp list-user-pools --max-results 60 --query "UserPools[?Name=='kilnwatch-users']"
aws ecr describe-repositories --query "repositories[?starts_with(repositoryName,'kilnwatch-')].repositoryName"
aws logs describe-log-groups --log-group-name-prefix /aws/ecs/kilnwatch --query 'logGroups[].logGroupName'
aws logs describe-log-groups --log-group-name-prefix /aws/apigateway/kilnwatch --query 'logGroups[].logGroupName'
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/kilnwatch --query 'logGroups[].logGroupName'
aws ecs describe-clusters --clusters kilnwatch-cluster --query 'clusters[].status'
aws ecs list-task-definition-families --family-prefix kilnwatch-inference
aws stepfunctions list-state-machines --query "stateMachines[?name=='kilnwatch-inference-workflow']"
aws sns list-topics --query "Topics[?ends_with(TopicArn,':kilnwatch-alerts')]"
aws cloudwatch describe-alarms --alarm-names kilnwatch-api-lambda-errors --query 'MetricAlarms[].AlarmName'
aws lambda get-function --function-name kilnwatch-api --query Configuration.FunctionArn
aws apigatewayv2 get-apis --query "Items[?Name=='kilnwatch-api'].ApiId"
aws rds describe-db-instances --db-instance-identifier kilnwatch-hackathon-db
aws rds describe-db-subnet-groups --db-subnet-group-name kilnwatch-db-subnets
aws rds describe-db-parameter-groups --db-parameter-group-name kilnwatch-registry-pg17
aws secretsmanager list-secrets --include-planned-deletion \
  --query "SecretList[?Name=='kilnwatch/hackathon/registry-reader'].[Name,DeletedDate]"
aws cloudfront list-origin-access-controls --query "OriginAccessControlList.Items[?Name=='kilnwatch-evidence']"
aws rds describe-db-engine-versions --engine postgres --engine-version 17 \
  --query 'DBEngineVersions[].EngineVersion'   # PostGIS availability is per minor version
```

A reader secret still in its 7-day deletion window blocks re-creation with that name.

### Data retention (finding 11, decided by the AWS teammate)

`database.tf` now sets `backup_retention_period=7`, `deletion_protection=true`,
`skip_final_snapshot=false` with `final_snapshot_identifier=kilnwatch-hackathon-db-final`,
and `copy_tags_to_snapshot=true` (`apply_immediately=true` is unchanged). `terraform
destroy` will now **refuse to delete the database** until deletion protection is
deliberately turned off in a reviewed change and applied. After that, destroy takes
the final snapshot; that snapshot is kept, and billed as backup storage, until deleted
by hand. Destroy still deletes the reader secret (7-day recovery window), Cognito pool
and users, and log groups. It fails on the data bucket while it holds objects
(`force_destroy=false`) and on ECR repositories that hold images. The state bucket
is outside Terraform and is never destroyed by it.

### Access paths, roles and secrets

- RDS is private (two private subnets, no NAT, not publicly accessible); ingress 5432
  only from the Lambda SG and the runner SG. Never open 5432 to a laptop.
- Lambda egress: 5432 to the db SG, 443 to the Secrets Manager endpoint SG. Nothing else.
- The Lambda role reads **only** the reader secret (`kilnwatch_api`, `kilnwatch_reader`,
  SELECT-only, proven locally in Integration 2A). It never receives the master secret.
- The runner role (if enabled) reads the master secret, writes only the reader secret
  and reads `imports/*`. The endpoint policy allows only `GetSecretValue` on those two
  secrets, and `PutSecretValue` on the reader secret for the runner role.
- Importer logins (`kilnwatch_importer`) can insert and update observation times and
  evidence, but not `status`, `review_state` or `assessment` (proven locally).

### Public evidence scope and price class (finding 10, AWS teammate decides)

The bucket policy grants CloudFront (that distribution's ARN only) `GetObject` on
`evidence/*.png`. All other prefixes (`models/`, `imports/`, raw exports, field photos)
stay private and the public access block stays on. The AWS teammate
**approved publishing the two reviewed Copernicus PNGs** (recorded 2026-10-09; the
upload happens in 2B). `bridge.tf` now uses `PriceClass_200`, which includes India
edge locations (`PriceClass_100` has none). `PriceClass_All` is not used.

### Expected runtime omissions

`/routes/today`, rules, verdicts and agents are absent (no route). `POST /jobs` returns
501; `/public/kilns` returns 503. `/health` returns 200 with
`registry_readiness: not_checked`; it is **not** a readiness check. Registry outages
become 503 inside the handler, so the Lambda `Errors` alarm cannot see them (finding
12); an API Gateway 5xx alarm is later observability work.

### Rollback and recovery

- **Bad import:** `persist` is one transaction; any failure rolls back runs,
  candidates, observations and evidence. Replays insert nothing new and never touch
  human state.
- **Evidence republication (finding 1):** a replay without the receipt keeps the
  verified `published_url`. A replay that would change the bytes of a published side
  is rejected and rolls back the whole batch; publish new bytes under their new
  content-addressed key through a reviewed procedure instead.
- **Bootstrap failure (finding 4):** follow the role-exists check in section 6.
- **Infrastructure:** revert the Terraform change and plan again. Do not `destroy`
  while the retention settings above are unchanged.

### Temporary runner cleanup

After preserving verification evidence, set `create_registry_runner=false` and apply a
reviewed plan. Correction 3: expect **5 to destroy and 1 to change** — the Secrets
Manager endpoint policy is updated in place to drop the runner's `PutSecretValue`
statement. Delete the runner's
`~/kilnwatch-proof` beforehand (it holds the CA bundle and inputs, no credentials).
Remove `imports/integration-1/` objects once they are no longer needed. Do not destroy
RDS or data.

### Cost estimate (ap-south-1)

Source: AWS Price List API (`aws pricing get-products`, read-only), queried
2026-10-09, USD, on-demand, before free tier or credits. **Estimate only, under these
assumptions:** a 730-hour month; Single-AZ `db.t4g.micro` with 20 GB storage (gp2 and
gp3 are the same price here); backups stay inside the free allocation (equal to
provisioned storage) because the database is a few MB; two Secrets Manager secrets
(reader + RDS-managed master) both billed; low traffic (about 10,000 API requests a
month, one `GetSecretValue` per request, 256 MB × 1 s per invocation, under 0.1 GB of
logs); two small PNGs; the runner runs about 4 hours with an 8 GB gp3 root volume
and one public IPv4 address. ECR repositories stay empty.

| Service | Unit price | Monthly estimate |
|---|---|---|
| RDS `db.t4g.micro` | $0.021/hour | $15.33 |
| RDS storage, 20 GB | $0.131/GB-month | $2.62 |
| RDS backup storage | $0.095/GB-month beyond the free allocation | $0.00 |
| Secrets Manager interface endpoint, 2 AZs | $0.013/AZ-hour; $0.01/GB processed | $18.98 |
| Secrets Manager, 2 secrets + ~10k calls | $0.40/secret-month; $0.05/10k calls | $0.85 |
| CloudWatch alarm | $0.10/alarm-month | $0.10 |
| CloudWatch Logs | $0.67/GB ingested; $0.03/GB-month stored | ~$0.07 |
| Lambda | $0.20/million requests; $0.0000166667/GB-second | ~$0.04 |
| HTTP API | $1.05/million requests | ~$0.01 |
| CloudFront (India) | $0.109/GB; $0.012/10k HTTPS requests | ~$0.00 |
| S3 (data + state buckets) | $0.025/GB-month | ~$0.00 |
| ECR (empty) | $0.10/GB-month | $0.00 |
| **Always-on total** | | **≈ $38/month** |
| Runner t3.micro, ~4 h (one-time) | $0.0112/hour | $0.05 |
| Runner public IPv4, ~4 h | $0.005/hour | $0.02 |
| Runner EBS 8 GB gp3, ~4 h | $0.0912/GB-month | <$0.01 |
| **Temporary total** | | **≈ $0.07** |

If the runner were left on for a full month it would add about $12.56 (instance
$8.18, IPv4 $3.65, EBS $0.73). The interface endpoint and RDS make up about 90% of
the always-on cost. Cognito (a handful of users) and KMS (AWS-managed keys) are
assumed to cost nothing. The user should check the credit balance, its expiry and
any excluded services under Billing → Credits.

## Stop and hand off

- **ML team mate:** saved Kaggle version, review checkpoint/evaluation linkage,
  fresh-scene type confusion and real evidence interpretation. No retraining here.
- **AWS teammate:** confirm account/state/district/publication, run real PostGIS
  checks, review plan/costs, obtain deployment authorization, execute private-path
  migration/import and authenticated/image/denial smoke tests. Remove/disable the
  temporary runner after preserving verification evidence; do not destroy RDS/data.
- **App:** review revised contract and local proof. Resume Phase 3 only through a
  separate request after real endpoint/token/image checks and source review.

## Primary references used for the design

- [HTTP API JWT authorizers](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-jwt-authorizer.html)
  — signature/audience validation and trusted claims in Lambda, with application permissions still required.
- [Cognito user attributes](https://docs.aws.amazon.com/cognito/latest/developerguide/user-pool-settings-attributes.html)
  — custom attribute read/write permissions and ID-token claims.
- [Secrets Manager VPC endpoints](https://docs.aws.amazon.com/secretsmanager/latest/userguide/vpc-endpoint-overview.html)
  — private DNS/service access without NAT.
- [RDS PostgreSQL SSL](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/PostgreSQL.Concepts.General.SSL.html)
  — CA/hostname verification and force_ssl.
- [CloudFront OAC](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html)
  — private origin restricted to the distribution ARN; our additional prefix restriction is in Terraform.
- [PostGIS ST_GeomFromGeoJSON](https://postgis.net/docs/ST_GeomFromGeoJSON.html) and
  [ST_IsValid](https://postgis.net/docs/ST_IsValid.html) — geometry construction/validity.
- [Ultralytics OBB](https://docs.ultralytics.com/tasks/obb/) — custom weights/task/class interface.

## Deployed state (Integration 2B, 2026-10-10)

- **Live:** 73/75 resources (network, private RDS 17.9 + PostGIS 3.5.6, Secrets Manager
  endpoint, Lambda/HTTP API/Cognito pool, data bucket, scaffolding, alarm). Schema
  migrated, reader `kilnwatch_api` bootstrapped, 39 Hapur candidates imported (replay
  0/0). Runner still running (kept until publication finishes). Budget alert on.
- **Blocked:** `aws_cloudfront_distribution.evidence` and `aws_s3_bucket_policy.evidence`.
  CloudFront returned `AccessDenied: Your account must be verified before you can add new
  CloudFront resources`. Fix: AWS Support case (Account and billing). Then
  `terraform plan` (expect 2 to add, 0 change, 0 destroy), apply, and continue at §7.
- **Fixed during 2B:** `rds.force_ssl` now pins `apply_method = "pending-reboot"`
  (static parameter; avoids a perpetual diff RDS would reject).
- **Ordering note:** the runner's inline policy waits for the RDS master-secret ARN, so
  runner S3/secret access starts only after RDS is created.
- **Skipped by user decision:** Cognito test inspector and real-token checks (the app is
  a demo video with placeholders and will not sign in). `scripts/id_token.py` is ready if
  that changes. Unauthenticated gateway refusals and direct Lambda invokes with synthetic
  claims were verified instead (see `local-verification.md`).
- **Workstation boto3 scripts** (`upload_evidence.py`, `verify_publication.py`,
  `id_token.py`) with an `aws login` profile: run inside
  `( eval "$(aws configure export-credentials --profile kilnwatch --region ap-south-1 --format env)"; … )`
  rather than adding `botocore[crt]`.
- **Remaining after verification:** §7 upload + `verify_publication.py` + receipt
  re-import; CloudFront denial probe (`imports/integration-2b/cloudfront-denial-probe.txt`,
  non-PNG `evidence/` path, missing `models/` key, direct S3 URL — all 403; delete probe);
  then runner cleanup (delete `~/kilnwatch-proof`, 5 destroy / 1 change, delete
  `imports/integration-1/operator-source.tgz`). The Lambda log group
  `/aws/lambda/kilnwatch-api` is now Terraform-managed with 14-day retention (2C).
- **Phase 3 outputs** (values only in ignored `.local/integration-2b/outputs.json`):
  `api_base_url`, `cognito_user_pool_id`, `cognito_app_client_id`, `cognito_issuer`,
  `evidence_base_url` (absent until CloudFront exists).

## Integration 2C — public read API (2026-10-10)

- **Live:** `GET /public/kilns` (near a point, or a district list) and
  `GET /public/kilns/{id}`, no login, flagged kilns only (SQL), allowlisted fields. Stage
  throttling: public 10/s burst 20, default 50/s burst 100. Contract:
  `App/docs/api-contract.md`; evidence: `local-verification.md` (Integration 2C).
- **Deploy used `-target`** (Lambda, public detail route, stage, Lambda log group with an
  `import` block, removed afterwards) because a full apply would retry CloudFront. The
  untargeted plan now shows only the 2 CloudFront resources.
- **CloudFront: pending** AWS account verification. When verified: untargeted plan
  (expect 2 to add) and apply, then §7 publication + receipt re-import (0/0; URLs then
  appear in protected and public detail), the denial probe and runner removal as listed
  above. The opt-in Swift test `localRealDetectionContractDecodesThroughExistingClient`
  expects null URLs; after publication, decode a body with URLs through the default
  suite or update that expectation.


## Evidence CDN in the second account (prompt 16c, 2026-10-10)

- **Why:** the main account still can't create CloudFront until AWS verifies it, and that
  could take days. The user's second account (the one already serving Bedrock, owner agreed
  until the hackathon ends) hosts the evidence distribution in the meantime. The user treats
  it as the CDN home until further notice.
- **How it works:** the PNGs stay in the main account's **private** data bucket (SSE-S3, public
  access blocks on). `aws_cloudfront_distribution.evidence_cdn[0]` and its OAC
  `aws_cloudfront_origin_access_control.evidence_cdn[0]` live in the second account through the
  aliased provider `aws.cdn` (same `hashicorp/aws`, lock unchanged). The provider uses
  `profile = var.cdn_profile`, a `~/.aws/config` profile outside the repo whose
  `credential_process` runs `aws configure export-credentials --profile <second-account-profile>
  --format process`, so there are no stored keys. `aws_s3_bucket_policy.evidence` (main account)
  allows only `s3:GetObject` on `evidence/*.png` for the `cloudfront.amazonaws.com` principal with
  `AWS:SourceArn` equal to that one distribution. `local.evidence_distribution` picks whichever
  distribution exists; the bucket policy and the `evidence_base_url` output both use it.
- **Switch:** `evidence_cdn_account = "main" | "second"` (default `main`) and `cdn_profile` are set
  only in the ignored `terraform.tfvars`. The main-account OAC stays in state either way.
- **Applied:** a targeted plan on the two `evidence_cdn[0]` addresses plus the bucket policy was
  3 add / 0 change / 0 destroy, and the apply added exactly those 3. The registry runner was
  **kept** for the rules-engine apply (prompt 09 Part B step 5 skipped).
- **Then:** §7 publication with the new `evidence_base_url`, receipt upload, a receipt re-import on
  the runner through SSM `send-command` (exact-key downloads, 0 new candidates and observations),
  and the denial probe. Results are in `local-verification.md`.
- **Switch-back** (once AWS verifies the main account, and only with the user's go): set
  `evidence_cdn_account = "main"`, then run a targeted plan and apply on
  `aws_cloudfront_distribution.evidence[0]` and `aws_s3_bucket_policy.evidence`. A dry plan showed
  2 to add, with the policy recreated for the new ARN. Re-run `verify_publication.py` against the
  new `evidence_base_url`, upload the receipt and re-import on the runner. Then run a targeted
  destroy of the second-account `evidence_cdn[0]` resources, which are now removed by count.
  CloudFront disables a distribution before it can delete it, so that step takes several minutes.
- **After the hackathon:** remove the second-account distribution and OAC (targeted, with the
  user's go) and delete the Bedrock role in that account (Phase 4A, `local-verification.md`).
