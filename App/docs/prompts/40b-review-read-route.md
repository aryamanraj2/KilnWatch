# Prompt 40b: read-only review queue route (for the iOS Review tab)

You are the builder for **one small backend step**. Work sequentially in this one chat. No sub-agents. Don't commit, push or stage. The repo is public.

**Context:** prompt 40 is live. Change triage wrote **45 pending items** (24 `new_candidate`, 17 `no_longer_detected`, 4 `low_confidence`) to the `review-queue` DynamoDB table. Nothing can read them except the AWS CLI. The next iOS prompt (23) adds a **Review tab** to the inspector app; it needs one public, read-only route. No approve/reject: nothing in this step can change the queue or the registry.

**The user gave the go by running this prompt.** The scope is exactly:
1. **Code:** a `GET /public/review` path in the assistant Lambda (`AWS/assistant/handler.py`, with the serializer next to the triage code in `AWS/triage/`), tests, and the cosmetic fix from 40's report (the run summary's `current_run` must be the run name, not the feature count).
2. **Terraform** (inside the existing `local.change_triage` gate in `AWS/assistant.tf` and the stage in `AWS/api.tf`):
   - the route `GET /public/review` on the existing assistant integration;
   - one more `aws_lambda_permission` for exactly `GET/public/review` (keep the Ask permission as it is);
   - the route in the stage's **public** throttle group (10/s, burst 20) next to `/public/kilns`;
   - the assistant role gains `dynamodb:Scan` on the review table only. Nothing else on the role changes.
3. **One** targeted plan and apply: the new route, the new permission, the stage (in place), the role policy (in place) and the Lambda (code). Expect 2 added, 3 changed, 0 destroyed. Anything else, stop.
4. Read-only live checks. **Zero** `POST /ask`, zero Bedrock calls, zero triage invokes, zero writes to the table.

**Out of scope:** any write path (approve, reject, delete, update), `PutItem` changes, RDS, other routes and their throttles, the `/ask` behaviour and cap, CORS (GET is already allowed for the portal and localhost), the CDN, the website, `App/` (iOS is prompt 23), the provider lock (`hashicorp/aws 6.68.0`), `destroy` and untargeted applies. If something needs one of these, stop and report.

## Read first

- `AGENTS.md`; `App/docs/prompts/41-orchestrator-handover.md` §1 and §8; `App/docs/prompts/40-change-triage.md`; the "Change triage (40)" sections of `App/docs/api-contract.md` and `AWS/docs/local-verification.md`; `AWS/assistant/handler.py`, `AWS/triage/`, `AWS/assistant.tf`, and the stage in `AWS/api.tf`.

## Rules

- **Never write or print** account IDs, ARNs, the API URL or ID, table or bucket names, CloudFront domains, the RDS host or emails. Read them from `.local/` and the tfvars without printing. New private values go to `.local/triage/` only.
- **Product language:** these are **candidates pending review**, never findings. The response carries the group key and the stored reason verbatim; it adds no new prose except the fixed labels below.

## Step 1: the route

- **Dispatch:** in `handle`, an API Gateway event with method `GET` and `rawPath == "/public/review"` goes to the review reader. Everything else keeps today's behaviour exactly (`POST /ask`, the internal triage invoke). Any query string → **400** `invalid_filter`. It never touches the Ask daily counter.
- **Read:** one paginated `Scan` of the table (at most 500 items; if more, return the first 500 sorted and set `truncated: true`). A **module-level memo of 60 s** so repeated requests in a warm Lambda don't scan again. DynamoDB failure → **503** `review_unavailable` (`retryable: true`), never an empty list.
- **Response 200** (`content-type: application/json`, `cache-control: public, max-age=60`; errors `no-store`):

```json
{
  "baseline": {"run": "m0-before", "scene": "S2A_T43RGM_20231205T053206_L2A", "date": "2023-12-05"},
  "current": {"label": "registry", "scene": "S2B_T43RGM_20261005T053448_L2A", "date": "2026-10-05"},
  "counts": {"new_candidate": 24, "no_longer_detected": 17, "possible_zigzag_conversion": 0, "low_confidence": 4},
  "truncated": false,
  "items": [
    {
      "item_id": "…",
      "group": "new_candidate",
      "state": "pending",
      "kiln_id": "KW-…",
      "reason": "verbatim stored reason",
      "centroid": {"lat": 28.7, "lon": 77.7},
      "baseline": {"type": "FCBK", "score": 0.52} ,
      "current": {"type": "FCBK", "score": 0.36},
      "iou": 0.76,
      "evidence": {"before": "https://…", "after": "https://…"},
      "created_at": "2026-10-11T…Z"
    }
  ]
}
```

  - `kiln_id`, `baseline`, `current`, `iou` and `evidence` are `null` when the item doesn't have them (e.g. `no_longer_detected` has no `kiln_id`, no `current` and no evidence). Scores are rounded to 3 decimals; coordinates to 5.
  - **Allowlist, not passthrough:** only the fields above. Never the model ID, the raw facts blob, internal timings or anything not listed. Evidence URLs only when they are on the evidence CDN host already stored by 40.
  - Order: group in the order `new_candidate`, `no_longer_detected`, `possible_zigzag_conversion`, `low_confidence`; then `kiln_id` (nulls last); then `item_id`.
  - `counts` always has all four keys (0 when empty).
  - The baseline/current scene and date come from the stored items (all items of one run share them). If items from more than one baseline run exist, return only the latest run and note it in the report.

## Step 2: tests (no network)

The GET dispatch (and that `POST /public/review`, a query string, or a `GET /ask` are rejected as today), the allowlist (an extra stored field never appears), null handling per group, ordering, the four `counts` keys, the 60 s memo, the 503 path, the 500-item truncation, and the `current_run` fix. Run the whole suite: `PYTHONPATH=AWS .venv-integration/bin/python -m unittest discover -s AWS/tests -v`.

## Step 3: deploy and check

1. `fmt`, `validate`, package the assistant as before, then **one** targeted plan saved to `.local/triage/review-route.tfplan`. Read it: 2 to add, 3 to change, 0 to destroy, nothing else. Apply.
2. **Live checks** (read-only, report results, never the URL):
   - `GET /public/review`: 200, 45 items, counts 24/17/0/4, every item `state = pending`, the allowlist holds (no other keys), `cache-control` as above.
   - `GET /public/review?x=1`: 400. `POST /public/review`: 404 or 405 from the gateway (no route).
   - With `Origin:` set to the hosted portal origin (from `.local/portal/outputs.json`, not printed) and to `http://localhost:5173`: `access-control-allow-origin` echoes each.
   - `POST /ask` still behaves as before: **don't send one**; instead confirm with the unit tests and that its route and permission are unchanged in the plan.
   - The table still has 45 items (a count-only scan), and the public kiln reads still show 38 flagged / 39 with `include=inspected`.

## Step 4: docs and report

- `App/docs/api-contract.md`: a "Review queue read (40b)" section with the route, the exact response shape above, the errors, caching, throttle, and the line "Read-only. Approving or rejecting items needs reviewer sign-in and is not built." This is the contract iOS prompt 23 builds against.
- `AWS/docs/local-verification.md`: a short "Review route (40b)" entry and the rollback (remove the route with a targeted apply, needs a go).
- **Report:** the plan/apply summaries, tests, the live check table, one example item from each non-empty group (verbatim JSON, URLs replaced with `<evidence-cdn>`), the leak check (changed tracked files against every identifier in `.local` and the tfvars: expect 0; `git diff --quiet AWS/.terraform.lock.hcl`), and open limits (public read without sign-in; the queue is a demo snapshot until triage is wired into Step Functions).
