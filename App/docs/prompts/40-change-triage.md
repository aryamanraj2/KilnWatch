# Prompt 40: change triage, Agent 2 (concept p.10)

You are the builder for **one backend step**. Work sequentially in this one chat. No sub-agents. Don't commit, push or stage. The repo is public.

**Run only after prompt 38 has finished and been reviewed**, with both detector runs in S3: `detections/m0-after/` (5 Oct 2026) and `detections/m0-before/` (5 Dec 2023). Same Terraform state as 37/38: if a plan reports a state lock, stop; never force-unlock.

## Goal

The concept's Agent 2: when a scene has been processed, compare its detections with the registry, sort every difference into one of **four groups**, and queue each item for human review with a plain-language reason and its before/after evidence. **Nothing changes a kiln's status.** The only write any part of this step can make is `queue_for_review`.

For the demo, the comparison is **the 2023 run (baseline) against today's registry (39 Hapur candidates, 2026 scene)**: "what changed since December 2023".

**The user gave the go by running this prompt.** The scope is exactly:
1. **New code:** `AWS/triage/` (the deterministic diff and the agent step) and its tests; a thin entry in the assistant Lambda for an **internal** invocation (no new API route).
2. **Terraform** (gated by `enable_change_triage`, default `false`): one DynamoDB table `review-queue` (on-demand, PITR off, no stream); the assistant role gains `s3:GetObject` on `detections/*` and `dynamodb:PutItem` on that table only (with `attribute_not_exists` used in code for idempotency). Nothing else on the role changes.
3. **One** targeted plan and apply for exactly those resources plus the assistant Lambda (code update). Expect 1 table added and in-place changes to the role policy and the Lambda. Anything else, stop.
4. **One** live triage run (`baseline_run = m0-before`, `current = registry`), plus at most **one** re-run if the first fails before writing. Bedrock use for this run: at most **80** model calls.

**Out of scope:** RDS (no migration, no write, no runner), any change to `status` or `review_state`, the public API routes, `/ask` behaviour and its daily cap, the route Lambda, the CDN, Step Functions wiring (manual invocation only; note it as the next step), a review console or any UI, the provider lock (`hashicorp/aws 6.68.0`), `destroy` and untargeted applies. If something needs one of these, stop and report.

## Read first

- `AGENTS.md`; `App/docs/concept.txt` p.10 (Agent 2, guardrails), p.11 (pipeline step 5) and p.14 (review console).
- `App/docs/prompts/41-orchestrator-handover.md` §1, §4 and §8; `AWS/assistant/` (core, tools, validator, handler) and `AWS/assistant.tf`.
- 38's report section in `AWS/docs/local-verification.md` ("M0"), and the GeoJSON shape of `detections/<run>/kilns.geojson` and `run.json`.

## Rules

- **Never write or print** account IDs, ARNs, the API URL, CloudFront domains, bucket or table names, the RDS host or emails. Read them from `.local/` and the tfvars without printing. New private values go to `.local/triage/` only.
- **Product language:** every item is a **candidate for review**, never a finding. Never "illegal", "violation", "violating", "unlawful". A detection missing in 2023 is "not detected in the Dec 2023 scene", never "built after 2023" (10 m pixels miss small kilns; haze and cloud happen). A missing 2026 detection is "no longer detected", never "closed" or "demolished". Model scores are not accuracy.
- **Fix the data shape, not prompt lines** (handover §8): the four groups, the matching and every number come from deterministic code. The model only writes the reason sentence from facts it is given.

## Step 1: deterministic diff (`AWS/triage/diff.py`, pure Python, no network)

- **Inputs:** the baseline run's features (`m0-before`), the current registry kilns (read through the public API with `include=inspected`, so all 39 are included regardless of status), and the current run's features (`m0-after`) for detector scores.
- **Matching:** one-to-one by footprint IoU (≥ 0.3) with a centroid-distance fallback (≤ 30 m) for slivers. Use a dependency that is already in the Lambda package, or a small exact polygon-overlap function with tests. No new heavy dependency.
- **The four groups** (every difference lands in exactly one; a match with nothing notable produces no item):
  1. `new_candidate`: in the registry, no match in the baseline. Reason facts: "not detected in the Dec 2023 scene".
  2. `no_longer_detected`: in the baseline, no match in the registry.
  3. `possible_zigzag_conversion`: matched, baseline type FCBK or CFCBK and current type Zigzag.
  4. `low_confidence`: matched or new, with a current detector score below **0.5** (a named constant; report how many sit near it). Only if not already in group 1–3 (state the precedence in code: 3, then 1, then 4).
- **Item facts** (the only things the agent sees): `item_id` (stable hash of run + group + footprint), group, `kiln_id` when the registry has one, both scene IDs and dates, the baseline and current type and score, the matched IoU or "none", the centroid, and evidence: the registry's `evidence.before/after` URLs when present, otherwise the scene IDs and footprint only (say "no published image" in the facts).
- **Tests:** each group, precedence, idempotent `item_id`, no item for an unchanged match, empty inputs, and a recorded real-shape sample (sanitized).

## Step 2: Agent 2 step (`AWS/triage/agent.py`, inside the assistant Lambda)

- Entry: the assistant handler accepts an **internal** event `{"action": "triage", "baseline_run": "m0-before", "current": "registry"}` only when invoked directly (no `requestContext` from API Gateway). API Gateway events behave exactly as before; add a test that `POST /ask` with that body is rejected as today.
- For each item, one Bedrock call (same model and second-account path as Ask, reasoning off) writes **one or two plain sentences** of reason from the item facts. Then `queue_for_review(item, reason)` is the **only** tool and the only write: a conditional `PutItem` (idempotent on `item_id`) with the facts, the reason, `state = "pending"`, `created_at`, and the model ID.
- **Validator** (reuse the Ask validator's pieces): every `KW-…` ID and scene ID in the reason must be in the item's facts; banned stems; no status words ("confirmed", "compliant", "closed", "not a kiln", "approved"); no claims of construction or demolition dates. Regenerate once, then a deterministic template reason (mark `reason_source = "template"`).
- Caps: at most 80 items per invocation (stop and report if the diff has more), the Lambda's existing timeout respected (process in one invocation if it fits, otherwise accept a `start_after` cursor). Logs: counts and timings only. This does **not** count against the public `/ask` daily cap; keep it separate.
- **Tests (mocked Bedrock and DynamoDB):** the internal-event gate, the single write path, idempotency, validator rejections, template fallback, the 80-item cap.

## Step 3: deploy and run

1. `fmt`, `validate`, package the assistant Lambda as before, then **one** targeted plan saved to `.local/triage/triage.tfplan`. Read it: 1 table added, role policy and Lambda in place. Anything else, stop. Apply.
2. Invoke once (`aws lambda invoke`, the internal event). Save the response to `.local/triage/run.json`.
3. **Check** with read-only calls: the item count per group equals the diff's count; a re-invoke is **not** needed to prove idempotency (the unit test covers it). Read back all items (scan, counts and fields, no names printed) and confirm `state = pending` on every item.
4. **Prove nothing else changed:** the public API still returns 38 flagged (39 with `include=inspected`, 1 confirmed) and every `status` is unchanged.

## Step 4: docs and report

- `App/docs/api-contract.md`: a short "Change triage (40)" section: the four groups and their wording, the item shape, "internal only, no public route", and that the registry changes only on a reviewer's approval (not built yet).
- `AWS/docs/local-verification.md`: a "Change triage (40)" entry with the counts, cost and rollback (`enable_change_triage = false`, targeted apply, needs a go).
- **Report:** the diff counts per group, with **five example items** (group, facts summary and the agent's reason, verbatim), how many reasons came from the model vs the template, Bedrock calls and cost, the plan/apply summaries, tests (`PYTHONPATH=AWS .venv-integration/bin/python -m unittest discover -s AWS/tests -v`: counts), the leak check (changed tracked files against every identifier in `.local` and the tfvars: expect 0; `git diff --quiet AWS/.terraform.lock.hcl`), and open limits: no review console or approval path yet, manual invocation (Step Functions wiring next), 10 m pixels and seasonal haze limit what "not detected" means.
