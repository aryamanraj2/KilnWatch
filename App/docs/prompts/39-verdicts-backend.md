# Prompt 39 (V1): verdicts backend, public for the demo (no sign-in)

You are the builder for **one backend step**. Work sequentially in this one chat. No sub-agents. Don't commit, push or stage. The repo is public.

**Goal:** close the loop:

> satellite flag → rules and exposure → route → **inspector records a verdict on site** → the registry status changes → the app shows the outcome.

The user decided: **no sign-in and no auth for now.** `POST /verdicts` is therefore a **public** route, like `/ask` and `/routes/plan`. It's protected only by validation, a daily cap, an on/off switch and an operator reset. Build to the request and response shapes of `App/docs/api-contract.md` "POST /verdicts" (the body, `Idempotency-Key`, 201/200/409 and `photo_uploads`). **Ignore** its `Authorization` header and district-scope lines for now, and say so in the contract. The iOS side (prompt 22) follows this.

**The user gave the go by running this prompt.** The scope is exactly:

1. **Code:**
   - migration `AWS/migrations/003_verdicts.sql`;
   - a new `AWS/verdicts/` Lambda package (handler + store) and tests;
   - `AWS/verdicts.tf`, gated by `enable_verdicts` (default `false`);
   - the public read change in `AWS/registry/` and `AWS/lambda/api_handler.py` (§3);
   - a small operator command `registry.cli reset-verdict`.
2. **The runner (SSM), which is still up:**
   - apply migration 003;
   - create the DB login `kilnwatch_verdicts` and write its password **only** into the new Secrets Manager secret, following the runbook pattern used for the reader login (`AWS/docs/first-record-runbook.md`, the `kilnwatch_api` login);
   - read-only and rolled-back checks.
3. **Plan and apply:** **one** targeted plan and apply for:
   - the new verdict resources (Lambda, role, policy, log group, empty secret, integration, `POST /verdicts` route **without** an authorizer, and its stage throttle);
   - the code update of `aws_lambda_function.api`.

   Expect additions, plus in-place changes to the API Lambda and the stage only. Anything else, stop.
4. **Live checks that change no kiln** (§5).

**Out of scope:**
- Cognito and any sign-in;
- iOS code;
- the Ask and route Lambdas (they must keep seeing flagged kilns only);
- CORS, the CDN and the provider lock (`hashicorp/aws 6.68.0`);
- `destroy` and untargeted applies;
- **any real verdict that changes a kiln's status.** The first real one is recorded from the app in prompt 22.

## Rules

- **Never write or print** account IDs, ARNs, the API URL or ID, bucket names, the RDS host, the runner ID, passwords or emails. Read them from `.local/integration-2b/outputs.json` and the tfvars without printing them. Private values go to `.local/v1/` only.
- **Product:**
  - `confirmed` means the inspector confirmed the siting concern on site. It's still never "illegal".
  - Agents (Ask) can never record verdicts; there's no tool for it and there must never be one.
- **On macOS,** archives use `COPYFILE_DISABLE=1 tar --no-xattrs`.
- **Credentials:** the `kilnwatch` profile; Terraform `.local/tools/terraform/terraform`. Sign-ins happen only in the user's terminal.

## Step 1: database (`003_verdicts.sql`, transactional, idempotent like 001 and 002)

- **`kilnwatch.verdicts`:**
  - `verdict_id uuid PRIMARY KEY`, `kiln_id` (FK to candidates), `outcome` (check: `confirmed|compliant|not_a_kiln|closed`), `note` (≤ 2000 characters);
  - `recorded_at timestamptz` (device time), `received_at timestamptz DEFAULT now()`;
  - `body_sha256 text` (for the idempotency compare);
  - `photos jsonb` (id, latitude, longitude, horizontal_accuracy_m, taken_at, object_key).
- **`kilnwatch.verdict_days`:** `(day date PRIMARY KEY, count int)`, the daily cap counted in RDS. The verdict Lambda runs in the VPC, which has no DynamoDB path; **don't add VPC endpoints.**
- **The role `kilnwatch_verdict_writer` (NOLOGIN):**
  - `SELECT` on candidates;
  - `SELECT, INSERT` on verdicts;
  - `SELECT, INSERT, UPDATE` on verdict_days;
  - `UPDATE (status, review_state)` on candidates.

  Nothing else. The login `kilnwatch_verdicts` is granted that role.
- **The reader:** `GRANT SELECT (kiln_id, outcome, recorded_at) ON kilnwatch.verdicts TO kilnwatch_reader`. Only those columns, never the note or photos.
- Keep `review_state` values consistent with 001 (for example `reviewed` after a verdict). Check the importer never overwrites status or review_state.

## Step 2: verdict Lambda (`AWS/verdicts/`, Python 3.12, in the VPC like the API Lambda)

- **No auth.** It ignores any `Authorization` header and never requires one.
- **Request validation:** follow the contract exactly.
  - Body ≤ 16 KB. Unknown keys → 400.
  - `id` is a UUID equal to the `Idempotency-Key` header, compared case-insensitively.
  - `kiln_id` is a full ID that exists; `outcome` comes from the enum.
  - At most **8** photos, each with a UUID, finite coordinates in range, accuracy ≥ 0 and an ISO time.
  - `note` ≤ 2000 characters; `recorded_at` is an ISO time no later than now + 10 min.
- **Daily cap:** **30 verdicts per UTC day**, counted atomically in `verdict_days` **inside the same transaction**, before the insert. A replay (same `id`) doesn't count. When the cap is reached → **429** `daily_cap_reached`.
- **Idempotency:**
  - A new `id` → insert and apply, return **201**.
  - The same `id` with the same `body_sha256` → **200** with fresh upload URLs.
  - The same `id` with a different body → **409** `idempotency_conflict`.
- **Status apply:** set `candidates.status = outcome` and `review_state` **only if** this verdict's `recorded_at` is the latest for that kiln. A late older verdict is stored but doesn't override. Unknown kiln → 404.
- **Photos:**
  - `photo_uploads` holds a presigned S3 **PUT** for each photo:
    - key `verdicts/<verdict_id>/<photo_id>.jpg` in the existing private data bucket;
    - signed for `Content-Type: image/jpeg`, expiry 15 min.
  - **Simplification:** the Lambda has no S3 network path, so it can't check which photos arrived. A replay returns fresh URLs for **every** photo; re-uploading overwrites the same key. Note it in the contract.
  - IAM: `s3:PutObject` on `verdicts/*` only, plus the verdict secret, plus logs and the VPC ENI basics. Nothing else.
- **Errors:** nested `{"error": {"code", "message", "retryable"}}` like `/ask`.
  - DB failure → `503 registry_unavailable` (retryable).
  - Logs hold counts, outcome and latency only: no kiln ID, coordinates or note.
- **Stage throttle** on `POST /verdicts`: 1 request/s, burst 2, like `/ask`.
- **Operator reset** (`registry.cli reset-verdict --kiln <id> --confirm`): for demo rehearsals. It sets the kiln back to `flagged` / `pending` and keeps the verdict rows as history. It's run on the runner and needs a go each time. **Don't run it for real in this step**, only inside the rolled-back test in §5.

## Step 3: show the outcome in the public read (opt-in only)

Today the public SQL is hard-coded `WHERE c.status='flagged'`. After a verdict, the kiln would vanish from the app. Add an **opt-in** query parameter `include=inspected` to `GET /public/kilns` (both shapes) and `GET /public/kilns/{id}`:

- **Without it:** byte-for-byte the current behaviour, flagged only. Ask, the route planner and the portal don't pass it, so they're unaffected. Keep the existing tests green, and add one that proves the default is unchanged.
- **With it:** all candidates, each with a new public key `inspection: {"outcome", "recorded_at"}` from the latest verdict (`null` while flagged). Never the note, photos, IDs or review internals. Keep the allowlist approach in `public_view`.
- **Validation:** `include` accepts exactly `inspected`. Anything else → 400, as unknown keys are today.
- **Caching:** the same `max-age=60`. Note in the contract that an outcome can take up to 60 s to show.

## Step 4: tests

- every validation branch;
- 201, 200 replay and 409;
- the cap (30, replay not counted, 429);
- the late-verdict ordering;
- 404;
- presign key and content type;
- no auth needed, and an `Authorization` header is ignored;
- log privacy;
- the public default unchanged;
- `include=inspected` shape and allowlist;
- the migration grants (an opt-in PostGIS test like 002's);
- the full suite (last: 153 run, 143 pass, 10 skipped). Report the counts.

## Step 5: deploy and live checks (no kiln changes)

1. **Runner:**
   - apply migration 003, create the login, store its secret;
   - read-only checks: tables exist, the grants are exact, and the 39 `flagged/pending` candidates are unchanged (the candidate-row checksum matches before and after).
2. **Rolled-back write test on the runner:** in one transaction, as `kilnwatch_verdicts`:
   - run the store's insert, cap and apply for one kiln;
   - assert the status changed and the counter went up;
   - run `reset-verdict` inside the same transaction and assert the kiln is back;
   - **roll back.**

   Show the checksum unchanged and `verdict_days` empty.
3. **Terraform:** one targeted plan, saved to `.local/v1/v1.tfplan`. Read it, then apply it. Check that the live `CodeSha256` values match the ZIPs.
4. **Live, writing nothing:**
   - `POST /verdicts` with a bad body → 400;
   - an unknown full kiln ID → 404 (the cap counts only successful inserts; make sure a 404 isn't counted);
   - a mismatched `Idempotency-Key` → 400.
5. **Public read:**
   - `/public/kilns?district=Hapur` → 39, with **no** `inspection` key (the default is unchanged);
   - with `&include=inspected` → 39, every `inspection` null;
   - `include=bogus` → 400.
6. **Ask and route are unaffected:** don't call them; the default read is proven unchanged above.

## Step 6: docs and report

- `App/docs/api-contract.md`:
  - "POST /verdicts" says live (2026-10-11), **public for the demo, no auth**; the cap; the replay simplification; the photo limits; `reset-verdict`;
  - "Auth" says sign-in is deferred by the user;
  - the public read section documents `include=inspected` and `inspection`.
- `AWS/docs/local-verification.md`: a "V1: verdicts (39)" entry with no identifiers.
- The runbook: a short section on the verdict login, the reset command and the kill switch (`enable_verdicts = false`, a targeted apply, needs a go).

**Report:**
- the diff summary and test counts;
- the migration and checks;
- the plan and apply summaries and hashes;
- the live checks;
- the leak check:
  - grep the changed files for every identifier from `.local` (expect 0);
  - `git diff --quiet AWS/.terraform.lock.hcl`;
- open limits:
  - **anyone with the API URL can record a verdict, within the cap of 30 a day**;
  - replay re-uploads all photos;
  - the runner is needed for resets.
