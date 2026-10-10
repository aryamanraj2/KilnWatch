# Prompt 33 (E1): before/after evidence images for all Hapur kilns

You are the builder for **one backend data step** of KilnWatch. Today only 1 of the 39 Hapur kilns (`KW-6b3b38…`) has published before/after satellite images. Cut, review, publish and attach them for the other 38, with the **same** scripts, grid, checks and attribution as that first pair.

You build and run. You do not orchestrate. Work sequentially in this one chat. No sub-agents. Do not commit, push or stage.

## The go (scope)

The user gave the go by running this prompt. It covers **exactly** this:
1. Reading Sentinel-2 image windows over the network (Earth Search STAC and the AWS Open Data Sentinel-2 bucket), for the 2026-10-05 after scene and the saved 2023-12-05 before scene. This is the same source as the first pair. **No detection or inference run.**
2. A small tracked wrapper script (Step 2) and local outputs under `.local/e1/`.
3. Uploading the reviewed PNGs to the data bucket's `evidence/` prefix with `AWS/scripts/upload_evidence.py` (conditional, content-hashed keys), then `AWS/scripts/verify_publication.py` against the evidence CDN.
4. Uploading the import inputs to `imports/e1/` and removing them at the end.
5. SSM `send-command` on the registry runner: the evidence re-import with the publication receipt, plus read-only verification queries.

**Out of scope:** Terraform, IAM, the bucket policy, CloudFront settings, the tfvars, the rules engine, Ask, the route Lambda, and removing the runner. If anything needs one of those: stop and report.

**Stop and report before any upload if:**
- fewer than 30 kilns get a valid after image;
- any PNG fails the checks below or looks wrong in review;
- the re-import dry run would create new kilns or change anything except evidence.

## Rules

- **The repo is public.** Never write into tracked files, or print, either account ID, any ARN, the API URL or ID, the CloudFront domain or ID, the bucket name, the RDS host, the runner ID or emails. Read them from `.local/integration-2b/outputs.json`, `.local/phase-4/cdn/outputs.json` and the ignored tfvars into shell variables. Use placeholders in docs.
- **Product language.** Images are evidence for inspection, not proof. A kiln is "flagged by satellite, pending inspection". Never "illegal". Keep the Copernicus attribution exactly as the preparer writes it.
- **Credentials:** the `kilnwatch` profile. Sign-ins only in the user's own terminal. Request approval for the network and AWS commands.
- **On macOS,** build any archive with `COPYFILE_DISABLE=1 tar --no-xattrs …`. AppleDouble `._*` files broke `migrate` in R1.

## Files

You may touch only:
- **new:** `AWS/scripts/prepare_all_evidence.py`, plus a test for it in `AWS/tests/`;
- `AWS/docs/local-verification.md`, `AWS/docs/first-record-runbook.md` (a short "all kilns" note in §2/§7 only), and `App/docs/api-contract.md` (the evidence status line only);
- anything under the ignored `.local/`.

**Do not edit `Model/`** (the ML teammate owns it), the registry code, or anything in `App/` except the contract line.

## Step 0: read first

1. `AGENTS.md`, then `App/docs/plan-final-stretch.md` §2 "E1".
2. `AWS/docs/first-record-runbook.md` §2 (local evidence), §6 (the runner and SSM) and §7 (publish, verify and re-import with the receipt).
3. `App/docs/prompts/16c-cloudfront-second-account.md`: how the first pair was published and re-imported.
4. `Model/scripts/prepare_evidence.py` (`--index` picks one sorted observation; it writes one-entry `manifest.json`), `AWS/registry/evidence.py` (`attach` accepts many entries and checks each one), `AWS/scripts/upload_evidence.py`, `AWS/scripts/verify_publication.py`, and `AWS/registry/cli.py` (the import with `--evidence` and `--publication-receipt`).
5. The inputs that already exist on this Mac: `.local/integration-1/hapur.geojson`, `hapur.scenes.json`, `before-scene.json`, and `evidence/manifest.json` (the first pair). **Use the same `hapur.geojson`**: the manifest's `input_sha256` must equal the hash of the detections the registry was imported from.

## Step 1: check the inputs

- The SHA-256 of `.local/integration-1/hapur.geojson` equals the first manifest's `input_sha256`. If not, stop.
- 39 observations convert; for each index 0–38, note its kiln ID.

## Step 2: cut all pairs (a wrapper, no `Model/` change)

`AWS/scripts/prepare_all_evidence.py`:
- Runs `Model/scripts/prepare_evidence.py` once per index (0–38) into a per-index temporary folder, with the same `--scenes`, `--before-scene` and `--district Hapur`.
- Collects each one-entry manifest into **one** `manifest.json` in `.local/e1/evidence/`, with all the PNGs alongside, and `local_path` relative to it.
- A kiln the preparer refuses (out of bounds, >1% nodata, grid mismatch) is **skipped and listed with the reason**, never patched or substituted. A missing before image stays `null` (the preparer allows it); a missing after image means the kiln is skipped.
- Validate the merged manifest with the existing registry check:
  ```sh
  PYTHONPATH=AWS .venv-integration/bin/python -m registry.cli validate \
    --detections .local/integration-1/hapur.geojson --district Hapur \
    --evidence .local/e1/evidence/manifest.json --preview .local/e1/registry-preview.json
  ```
- **The `KW-6b3b38…` pair** must come out byte-identical to the published one (same SHA-256s). If not, stop and report: the cut is not reproducible.
- **Test:** the merge logic (relative paths, duplicate observation rejected, a skipped kiln listed, the input hash carried through), with no network.

## Step 3: review (before any upload)

- Make a contact sheet, `.local/e1/contact-sheet.png`: every kiln's before and after side by side, labelled with a short kiln ID. **Look at it yourself.**
- For each kiln, report: after OK, before OK or `null`, nodata fraction, and anything odd (cloud, blank, a black edge, a clearly different place).
- Stop if anything looks wrong. Otherwise tell the user the path, so they can glance at it too, and continue.

## Step 4: publish and verify

1. `upload_evidence.py --manifest .local/e1/evidence/manifest.json --bucket "$BUCKET" --publish-reviewed-evidence`. The keys are content hashes, so the existing `KW-6b3b38…` objects are verified, not rewritten.
2. `verify_publication.py --manifest … --base-url "https://$CDN" --out .local/e1/publication-receipt.json`: HTTPS, `image/png`, matching checksums for every object.
3. A denial probe: one direct S3 URL and one non-PNG path through the CDN are both still denied.

## Step 5: re-import on the runner (SSM)

Follow runbook §6/§7, as 16c did, downloading each file by key from `imports/e1/`: the operator source archive, `hapur.geojson`, the merged manifest, every PNG it references, and the receipt.

1. **Before:** read-only counts (rolled back): candidates; `status`/`review_state`; kilns with violations and with exposure (expect 39 / 36 / 39 from R1); and kilns with evidence URLs (expect 1).
2. **Validate first,** then the import with `--evidence` and `--publication-receipt`. Expect **0 new** kilns and observations; only evidence metadata changes.
3. **After:** the same counts. Everything is identical except the evidence count, which goes from 1 to the number published. **R1's rules and exposure must be unchanged.** If they changed, stop and report; don't fix anything.
4. Clean up: the runner work folder and `imports/e1/` (0 keys left). The runner stays running.

## Step 6: live check

- **Public API:** the Hapur list. Count kilns with both `evidence.before` and `evidence.after`, with after only, and with none. For 3 random kilns, `curl` both URLs: 200, `image/png`, and SHA-256 equal to the manifest.
- **Ask, at most 2 questions** (read the counter first):
  - "Which flagged kilns in Hapur have satellite images?": the count matches;
  - "Show me the evidence for KW-<another kiln>": dates and the exact attribution.
- Save the list response (no hosts) to `.local/phase-4/live/e1/` for the iOS team.

## Step 7: documents

- **`AWS/docs/local-verification.md`:** an "E1: evidence for all Hapur kilns" entry (counts, skipped kilns and reasons, the receipt summary, the before/after counts, the live checks), with no identifiers.
- **`AWS/docs/first-record-runbook.md`:** one short note that `prepare_all_evidence.py` does all observations.
- **`App/docs/api-contract.md`:** update only the line that says evidence is published for one kiln.

## Report

1. The input hash check, and the per-kiln table (kiln, before, after, nodata, notes), with skipped kilns and reasons.
2. The reproducibility check for `KW-6b3b38…`.
3. The contact-sheet path and your review.
4. The upload and verify results, and the denial probe.
5. The SSM outputs (no identifiers), and the before/after counts proving that only evidence changed.
6. The live check, and the Ask answers.
7. The diff summary and test counts (the full suite: last run 141 run, 131 pass, 10 skipped).
8. **Leak check:** grep every changed tracked file for the identifiers read from the `.local` files (without printing them): expect 0. `git diff --quiet AWS/.terraform.lock.hcl`. Only the allowed files touched.
9. **A short note the user can forward** to the iOS orchestrator and the AWS teammate: how many kilns now have images.
