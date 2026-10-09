# Integration 1 first-record deployment runbook — REVIEW ONLY

Prepared 2026-10-09 on main. **AWS is not deployed. No commands that mutate AWS,
publish objects, migrate/import RDS, train, commit or push were executed.**
Phase 3 remains on hold. A later explicit deployment request authorizes live writes.
The commands below are a concrete review sequence, not an instruction to deploy now.

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

1. Account ID, named AWS profile, us-west-2 availability, deployment operator and
   state owner. Use private encrypted state with locking; agree backend configuration
   and credentials separately. No state, plans, tokens or local `.tfvars` in Git.
2. Approve district `Hapur` for this AOI. The importer receives an administrative
   district assignment; it does not establish district boundaries. Re-import with a
   different district is rejected. Multi-district identities are deferred.
3. Review RDS 17/PostGIS support, instance/storage, Secrets Manager interface endpoint
   in two private subnets, CloudFront, logs and optional runner costs. No monthly total
   is claimed. Keep backups/deletion protection appropriate before retaining real data;
   the foundation still skips final snapshots and has deletion protection disabled.
4. Approve public publication of only the selected Copernicus satellite PNGs. Model,
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
export AWS_PROFILE='<approved-profile>' AWS_REGION=us-west-2
aws sts get-caller-identity
cd AWS
cp terraform.tfvars.example terraform.tfvars
# Set approved names/region/runner choice in the ignored file.
terraform init  # use the agreed encrypted/locked backend config; do not upgrade providers
terraform fmt -check -recursive
terraform validate
terraform plan -out=first-record.tfplan
terraform show first-record.tfplan
```

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
aws s3 cp .local/integration-1/ "s3://<data-bucket>/imports/integration-1/" --recursive
aws ssm start-session --target '<registry-runner-id>'
```

On the approved SSM runner, using its instance role (no copied AWS access keys):

```sh
sudo dnf install -y python3.12 python3.12-pip
mkdir -p ~/kilnwatch-proof && cd ~/kilnwatch-proof
aws s3 cp 's3://<data-bucket>/imports/integration-1/' input/ --recursive
tar -xzf input/operator-source.tgz
python3.12 -m venv .venv
.venv/bin/python -m pip install -r AWS/requirements-operator.txt
curl --fail --silent --show-error \
  https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -o rds-ca.pem
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
existing role, and never prints credentials; reconcile DB/secret if a commit fails
between secret publication and DB commit. Rotation needs its own reviewed procedure.

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
