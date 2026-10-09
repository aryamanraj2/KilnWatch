# KilnWatch AWS foundation and Integration 1 bridge

**Source prepared; AWS is not deployed.** The iOS app/core live in `App/`; the
model scripts live in `Model/`. Integration 1 adds a local evidence/import path,
PostgreSQL/PostGIS migrations and authenticated registry reads. It does not start
training, inference automation, agents, route planning or verdict submission.

Read [the first-record runbook](docs/first-record-runbook.md) before any deployment.
It contains prerequisites, account/state decisions, private database access,
operator commands and the separate deployment authorization gate. Verified local
results and unrun checks are in [local-verification.md](docs/local-verification.md).

## Local preparation (repository root)

```sh
python3 -m venv .venv-integration
.venv-integration/bin/python -m pip install -r Model/requirements-integration.txt -r AWS/requirements-operator.txt
.venv-integration/bin/python AWS/scripts/package_api.py
PYTHONPATH=AWS .venv-integration/bin/python -m unittest discover -s AWS/tests -v
PYTHONPATH=AWS .venv-integration/bin/python AWS/tests/generate_contract.py
```

The Lambda archive must exist before Terraform validation/plan. It packages pinned
pure-Python pg8000 dependencies for Python 3.12/x86_64, registry read modules and
an RDS CA bundle; the old single-file archive is removed. Terraform/AWS CLI and a
local PostGIS/Docker runtime were unavailable in the builder's environment, so
cloud, Terraform and actual database integration checks remain unrun.

`registry.cli validate` performs a complete dry run without opening a database.
`registry.cli migrate` and `import` are explicit write operations for the future
approved private runner. Core schema has runs, candidates, observations, evidence
and migration checksums; no assessment engine or review/verdict product is added.
The shared [app contract](../App/docs/api-contract.md) uses optional exposure/images,
unassessed rules and explicit unverified baseline type. Missing facts are never zero.

## Prepared deployment behavior

- Private encrypted/versioned S3 with public access blocked; CloudFront OAC can read
  only content-addressed satellite `evidence/*.png`, not models/imports/field photos.
  URLs remain null until a read-only publication checksum proof supplies a receipt.
- Private RDS PostgreSQL 17/PostGIS, forced TLS, separate SELECT-only runtime secret.
  Lambda cannot read the master secret, start Step Functions or read/write S3.
- Private Secrets Manager interface endpoint and restricted Lambda egress to that
  endpoint and PostgreSQL. The handler needs no S3 network path.
- Optional temporary SSM EC2 runner for the reviewed migration/import path. Off by
  default; no inbound ports. Approve its outbound network, credentials and cost
  separately. RDS is never opened to the internet.
- HTTP API root paths `GET /kilns?district=Hapur[&status=flagged]` and `GET /kilns/{id}`.
  Nested Lambda errors; pages default 100/max 200, with `next_cursor`. The core client
  follows pages. The API checks the Cognito-authorized ID token's subject, client,
  token type, inspector group and immutable admin-provisioned district. Missing
  permissions deny access; unknown/other-district details are hidden with 404.
- `/public/kilns` stays unavailable (503), `/jobs` remains 501, `/health` reports the
  process only. Routes/rules/verdicts/agents are deferred; no fabricated Today route.
- Admin-only account provisioning and an inspector group are prepared. Managed
  login/PKCE, multi-district policy and Verified Permissions remain future work.

Use `AWS/terraform.tfvars.example` for redacted configuration. Select the account,
profile, region and encrypted locked state owner before `terraform init`/plan.
No plan/apply was executed. Do not upgrade the existing provider lock unnecessarily.
Keep local tfvars/state/plan, model weights, raw imagery/exports and tokens out of Git.

AgentCore, SageMaker training, Amplify and the optional long-running ECS service
remain disabled by default. Existing ECS/Step Functions scaffolding is unfinished;
its image/input contracts are not implemented. Do not launch it for this bridge.
The model script's optional artifact upload uses `models/<run>/...`; local detection
is `python Model/scripts/detect_scene.py`, not the old root `scripts/` path.

Prototype RDS deletion protection remains disabled and final snapshots skipped.
Review these before retaining important data. No monthly price estimate is claimed.
