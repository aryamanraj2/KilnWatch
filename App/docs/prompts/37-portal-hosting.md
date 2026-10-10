# Prompt 37: host the resident portal on AWS (second-account CloudFront)

You are the builder for **one infrastructure step**. Run it **after prompt 36** (the portal on the live API) has passed orchestrator review. Work sequentially in this one chat. No sub-agents. Don't commit, push or stage. The repo is public.

**Goal:** the resident portal (`Web/ResidentPortal`, a static Vite build) is served over HTTPS from AWS and talks to the live public API and `/ask` from its hosted origin. The user chose AWS hosting through the **second account**. The main account still can't create CloudFront, which is why the evidence CDN lives there too (`AWS/bridge.tf`, prompt 16c). Reuse that proven pattern: **a private bucket in the main account, and a CloudFront distribution with an OAC in the second account through the `aws.cdn` provider.**

**The user gave the go by running this prompt.** The scope is exactly:
1. a new `AWS/portal.tf` and its variables and outputs, gated by `enable_portal_hosting` (default `false`), plus the CORS line in `AWS/api.tf`;
2. **one** targeted plan and apply for exactly the new portal resources and `aws_apigatewayv2_api.http` (CORS). Expect only additions plus 1 in-place change to the API; anything else, stop;
3. uploading the portal's production build to the new portal bucket, and invalidating `/*` when you re-upload;
4. ignored config: `enable_portal_hosting = true` in `AWS/terraform.tfvars`, and `Web/ResidentPortal/.env.production.local`;
5. at most **2** live `POST /ask` from the hosted site.

**Out of scope:** the evidence CDN, the data bucket and its policy, IAM users/roles, Lambdas, the provider lock (`hashicorp/aws 6.68.0`, never change it), `terraform destroy`, untargeted applies, custom domains and certificates, and portal code changes beyond build config. If something needs one of these, stop and report.

## Rules

- **Never write or print** either account ID, any ARN, the API URL or ID, any CloudFront domain or ID, any bucket name or the RDS host. Read them from `.local/integration-2b/outputs.json`, `.local/phase-4/cdn/outputs.json` and the tfvars into variables without printing them. Save new outputs (the portal URL, distribution ID, bucket) **only** to `.local/portal/outputs.json`. Use placeholders in docs.
- **Credentials:** Terraform binary `.local/tools/terraform/terraform`; main-account credentials via `aws configure export-credentials --profile kilnwatch --format env`; the `aws.cdn` provider uses the `cdn_profile` already in the tfvars. Sign-ins happen only in the user's own terminal.
- **On macOS,** archives use `COPYFILE_DISABLE=1 tar --no-xattrs` (not expected here).

## Step 0: preflight (read-only, stop on any failure)

1. Confirm that prompt 36 is in the working tree and that `npm run build` passes in `Web/ResidentPortal`.
2. Confirm the `cdn_profile` can **read** CloudFront in the second account (`cloudfront list-distributions`, `list-functions`, `list-origin-access-controls`), printing counts only. If `list-functions` is denied, the SPA rewrite can't use a CloudFront Function: stop and report, and the user will ask the second account's owner.
3. **Cost note** for the report: S3 storage of a few MB, and CloudFront within the free tier at demo traffic. Expect about $0 a month. Say so.

## Step 1: Terraform (`AWS/portal.tf`, all `count = var.enable_portal_hosting ? 1 : 0`)

- **Main account:**
  - `aws_s3_bucket` with `bucket_prefix = "${var.project_name}-portal-"`, all public access blocked, SSE-S3, ownership enforced and versioning off.
  - A bucket policy that lets **only** the portal distribution `s3:GetObject` on `*`, conditioned on `AWS:SourceArn` (same shape as `aws_s3_bucket_policy.evidence`).
- **Second account (`provider = aws.cdn`):**
  - **An OAC** for the portal.
  - **A CloudFront Function** (`cloudfront-js-2.0`, viewer request) that rewrites a URI with **no file extension** to `/index.html`, so `/kilns/<id>`, `/rules/<id>`, `/about`, `/privacy`, `/complaint` and the new Ask route work on refresh. A missing `/assets/x.js` must stay an error, never HTML.
  - **The distribution:**
    - `default_root_object = "index.html"`, `redirect-to-https`, GET/HEAD only, compression on, `PriceClass_200`, default certificate;
    - the managed caching policy `Managed-CachingOptimized` and the managed `Managed-SecurityHeadersPolicy`, both looked up by name with data sources;
    - no custom error page that turns 403/404 into HTML.
- **CORS** (`AWS/api.tf`): `allow_origins` becomes the de-duplicated list of `http://localhost:5173` (kept for local dev), `var.frontend_origin` when set, and `https://<portal distribution domain>` when hosting is on. Methods and headers stay unchanged.
- **Outputs** `portal_url`, `portal_bucket` and `portal_distribution_id`, all `sensitive = true`.
- **Plan and apply:** `terraform fmt` and `validate`. Make one plan targeted at the new portal resources and `aws_apigatewayv2_api.http`, saved to `.local/portal/portal.tfplan`. Read it: only additions (bucket and its settings, policy, OAC, function, distribution) plus **1 in-place change** on the API's CORS. Anything replaced or destroyed, or any other resource touched: stop. Apply the saved plan. Write the outputs to `.local/portal/outputs.json`.

## Step 2: build and upload

1. Write the ignored `Web/ResidentPortal/.env.production.local` with `VITE_DATA_MODE=live`, the API base URL and the evidence CDN host, the same values as 36's `.env.local`. Confirm it's ignored with `git check-ignore`. Then run `npm run build`.

   The built JavaScript will contain the API URL; any public web app must. It never goes into git: `dist/` is ignored. Confirm with `git check-ignore dist`.
2. Upload `dist/`:
   - `assets/*` with `cache-control: public, max-age=31536000, immutable`;
   - `index.html` and the other root files with `cache-control: no-cache`;
   - correct content types (`aws s3 sync` with `--delete`, run in two passes for the two cache headers).
3. Invalidate `/*` only when re-uploading.

## Step 3: live checks (hosted HTTPS URL; report results, never the URL)

1. `/` loads and the search near 28.7306, 77.7759 shows the real kilns. **The browser console has no CORS errors.**
2. A direct load and a refresh of `/kilns/KW-6b3b38da681850e5af46b024f3d3f78e` show C-HAB-800 at 497 m against 800 m, 4,225 people, and before/after images with the attribution.
3. A missing asset path (for example `/assets/nope.js`) does **not** return `index.html`.
4. Direct S3 access to the portal bucket gives 403. A request with `Origin: <portal origin>` to `/public/kilns?...` returns `access-control-allow-origin` equal to the portal origin. `http://localhost:5173` still works.
5. Ask from the hosted site (at most 2): "How many kilns are flagged in Hapur?" and one question from a kiln page. Report the status, the fallback flag and the latency.
6. The response headers include HSTS and nosniff.

## Step 4: docs and report

- `Web/ResidentPortal/docs/hosting-proposal.md`: replace the Amplify text with "Hosted: S3 (main account, private) + CloudFront (second account, OAC)", the deploy commands with placeholders, and how to roll back (`enable_portal_hosting = false`, targeted apply, needs a go).
- `AWS/docs/local-verification.md`: a short "Portal hosting (37)" entry, with no identifiers.

**Report:**
- the preflight;
- the plan and apply summaries;
- the upload counts;
- the live check table;
- the leak check:
  - grep the changed tracked files for every identifier from the `.local` files and the new outputs (expect 0);
  - `git diff --quiet AWS/.terraform.lock.hcl`;
  - `.env.production.local` and `dist/` are ignored;
- open limits:
  - **the Ask cap (100 a day) and route cap are shared with anyone who finds the site**, so share the link only for the demo;
  - no custom domain;
  - no CSP yet.
