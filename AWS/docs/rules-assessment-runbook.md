# Rules and exposure results: deploy runbook (AWS teammate)

**Status (2026-10-10): done.** `002_assessment.sql` is applied and the 39 Hapur assessments are written (prompt 31; see `local-verification.md`, "R1"). On macOS, build the §2 archive with `COPYFILE_DISABLE=1 tar --no-xattrs …`, or AppleDouble `._*.sql` files break `migrate`.

This runbook puts the rules engine's results for the 39 Hapur kilns into the live registry: siting flags with measured distances, and the population within 800 m. It uses the same private path as the first import (`first-record-runbook.md` §6): workstation → private `imports/` prefix → SSM runner → RDS.

**What changes on AWS:**
- One migration (`002_assessment.sql`).
- One update to `candidates.assessment` for each of the 39 kilns.

**What doesn't change:**
- No Terraform change and no Lambda redeploy. The API already serializes `violations`, `rules_assessment` and `exposure` from that column.
- No change to kiln status, review state, observations or evidence.

**You need:**
- `main` at `f7efbde` or later.
- `hapur_assessment.json`, sent to you directly. It's git-ignored, so put it at `.local/rules/hapur_assessment.json`.
- The `kilnwatch` profile and the values in `.local/integration-2b/outputs.json`.
- The registry runner Online (it is still running from Integration 2B).

## 1. Check the input on your workstation

From the repository root:

```sh
PYTHONPATH=AWS python -m registry.cli validate-assessment --assessment .local/rules/hapur_assessment.json
```

Expect `{"dry_run": true, "kilns": 39, "rules_version": "kilnwatch-rules-v1", "flags": 52}`. Stop if it differs.

## 2. Package and upload

```sh
mkdir -p .local/rules-v1
tar --exclude=__pycache__ -czf .local/rules-v1/operator-source.tgz \
  AWS/registry AWS/migrations AWS/scripts AWS/lambda/requirements.txt AWS/requirements-operator.txt
P='s3://<data-bucket>/imports/rules-v1'
aws s3 cp .local/rules-v1/operator-source.tgz "$P/operator-source.tgz" --profile kilnwatch
aws s3 cp .local/rules/hapur_assessment.json "$P/hapur_assessment.json" --profile kilnwatch
```

The runner can only `GetObject` under `imports/*`, so both files go there. Never upload the OSM or HRSL extracts; the runner doesn't need them.

## 3. Run on the runner (SSM, as in §6)

Send this as an `AWS-RunShellScript` command, then read the output with `get-command-invocation`:

```sh
dnf install -y python3.12 python3.12-pip
export HOME=/root; mkdir -p ~/kilnwatch-rules && cd ~/kilnwatch-rules
P='s3://<data-bucket>/imports/rules-v1'
aws s3 cp "$P/operator-source.tgz" input/operator-source.tgz
aws s3 cp "$P/hapur_assessment.json" input/hapur_assessment.json
tar -xzf input/operator-source.tgz
python3.12 -m venv .venv
.venv/bin/python -m pip install -r AWS/requirements-operator.txt
curl --fail --silent --show-error \
  https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -o rds-ca.pem
export AWS_REGION=ap-south-1 AWS_DEFAULT_REGION=ap-south-1
export DB_HOST='<private-rds-endpoint>' DB_PORT=5432 DB_NAME=kilnwatch
export DB_CA_BUNDLE="$PWD/rds-ca.pem" DB_SECRET='<registry-admin-secret-arn>'
PYTHONPATH=AWS .venv/bin/python -m registry.cli migrate
PYTHONPATH=AWS .venv/bin/python -m registry.cli validate-assessment --assessment input/hapur_assessment.json
PYTHONPATH=AWS .venv/bin/python -m registry.cli apply-assessment --assessment input/hapur_assessment.json
```

**Expected output:**
- `migrate` prints `{"migrations":"applied"}`. It skips `001` by checksum and applies `002`. A checksum error means `001` was edited; stop.
- `apply-assessment` prints `{"assessed": 39, "rules_version": "kilnwatch-rules-v1"}`.
  - It validates first, then writes all 39 in one transaction.
  - An unknown kiln ID rolls everything back and prints an error. Nothing is half-written.
  - Running it again is safe: it writes the same values.

This uses the admin secret, as the first import did. A dedicated assessor login is not needed for this one-off run; see §6.

## 4. Verify

**From the runner, as admin, in a transaction that is rolled back:**

```sh
PYTHONPATH=AWS .venv/bin/python -c "from registry.db import connect_from_env as c; n=c(); k=n.cursor(); \
  k.execute(\"SELECT COUNT(*), COUNT(*) FILTER (WHERE jsonb_array_length(assessment->'violations')>0), COUNT(*) FILTER (WHERE assessment ? 'exposure') FROM kilnwatch.candidates WHERE district='Hapur'\"); \
  print(k.fetchone()); n.rollback()"
```

Expect `[39, 36, 39]`: 39 kilns, 36 with at least one flag, and 39 with exposure.

**From your workstation, with the public API and no login.** Responses are cached for 60 s.

```sh
curl -s 'https://<api-host>/public/kilns/KW-6b3b38da681850e5af46b024f3d3f78e' | python -m json.tool
```

Expect:
- `"rules_assessment": "partially_evaluated"`
- one violation: `C-HAB-800`, `measured_distance_m: 497`, `threshold_m: 800`, `evidence_url: null`
- `"exposure": {"people": 4225, "children_under_five": 430, "adults_over_sixty": 294}`

`status` must still be `flagged`. The response must not contain `rules_results`, `rules_inputs` or `exposure_inputs`; those stay internal.

## 5. Clean up

- On the runner: `rm -rf ~/kilnwatch-rules`.
- On your workstation: `aws s3 rm 's3://<data-bucket>/imports/rules-v1/' --recursive --profile kilnwatch`.
- Runner removal itself still follows `first-record-runbook.md` ("Deployed state"), after CloudFront publication.
- The later §7 receipt re-import does not touch `assessment`, so these results survive it.

## 6. Later: a dedicated assessor login (not needed now)

`002_assessment.sql` creates the NOLOGIN role `kilnwatch_assessor`. It can update only `candidates.assessment`.

When rules run automatically on each new scene, give that job its own login instead of the admin secret:
1. Create a login role `IN ROLE kilnwatch_assessor`.
2. Store its password in a new Secrets Manager secret. Follow the pattern of `scripts/bootstrap_reader.py`, including the `log_statement` check.
3. Point `DB_SECRET` at that secret.

Before relying on it, run `test_assessor_writes_rule_keys_only` against a local PostGIS (`KILNWATCH_TEST_DB_PORT`). It has not run yet.

## Rollback

To return every Hapur kiln to "not evaluated", run this as admin on the runner, then commit:

```sql
UPDATE kilnwatch.candidates
SET assessment = assessment - 'violations' - 'rules_assessment' - 'rules_results' - 'rules_version'
                            - 'rules_inputs' - 'exposure' - 'exposure_inputs'
WHERE district = 'Hapur';
```

The migration does not need to be undone; an unused role is harmless.
