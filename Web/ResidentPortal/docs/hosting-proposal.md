# Resident portal hosting

**Hosted: S3 (main account, private) + CloudFront (second account, OAC).** Live since prompt 37 (2026-10-11).

The main account still can't create CloudFront, so the portal reuses the evidence CDN pattern from `AWS/bridge.tf`. Everything is in `AWS/portal.tf`, behind `enable_portal_hosting` (default `false`):

- a private bucket in the main account (`bucket_prefix = "<project>-portal-"`) with all public access blocked, SSE-S3, ownership enforced and versioning off. Its policy allows `s3:GetObject` only to the portal distribution, through an `AWS:SourceArn` condition;
- in the second account (`aws.cdn` provider), an OAC, a CloudFront Function and the distribution. The distribution uses `redirect-to-https`, GET/HEAD only, compression, `PriceClass_200` and the default certificate, with the managed `Managed-CachingOptimized` and `Managed-SecurityHeadersPolicy` policies;
- the SPA rewrite: a viewer-request function sends any path without a file extension (`/kilns/<id>`, `/rules/<id>`, `/ask`, `/about`, `/privacy`, `/complaint`) to `/index.html`. There is no custom error page, so a missing `/assets/*.js` stays a 403 from S3 and never turns into HTML;
- API CORS (`AWS/api.tf`): `http://localhost:5173`, `frontend_origin` when set, and `https://<portal-distribution>.cloudfront.net`.

Outputs `portal_url`, `portal_bucket` and `portal_distribution_id` are sensitive. Keep them only in the ignored `.local/portal/outputs.json`, never in git.

## Deploy

Build config lives in the ignored `Web/ResidentPortal/.env.production.local`. It sets `VITE_DATA_MODE=live`, the public API base URL and the evidence image host, and never holds credentials. The built JavaScript contains the API URL, as any public web app must; `dist/` is ignored.

```sh
cd Web/ResidentPortal
npm run build

# Hashed assets: cache for a year. Everything else: revalidate.
aws s3 sync dist/assets s3://<portal-bucket>/assets --profile kilnwatch --delete \
  --cache-control "public, max-age=31536000, immutable"
aws s3 sync dist s3://<portal-bucket> --profile kilnwatch --delete --exclude "assets/*" \
  --cache-control "no-cache"

# Only when re-uploading over an existing build:
aws cloudfront create-invalidation --profile <cdn-profile> \
  --distribution-id <portal-distribution-id> --paths "/*"
```

## Roll back (needs a go)

1. Empty the bucket: `aws s3 rm s3://<portal-bucket> --recursive --profile kilnwatch`. The bucket has no `force_destroy`.
2. Set `enable_portal_hosting = false` in the ignored `AWS/terraform.tfvars`.
3. Run one targeted plan and apply over the `portal.tf` resources and `aws_apigatewayv2_api.http`. Expect the portal resources destroyed and 1 in-place CORS change back to localhost (plus `frontend_origin` if set). CloudFront disables the distribution before deleting it, which takes several minutes.

## Open limits

- The Ask cap (100 a day) and the route cap are shared with anyone who finds the site, so share the link only for the demo.
- There is no custom domain; it uses the default `*.cloudfront.net` certificate.
- There is no CSP yet. The managed security headers policy sends HSTS, `nosniff`, `X-Frame-Options`, `Referrer-Policy` and XSS protection. A CSP must cover self-hosted scripts and styles, the API and evidence hosts in `connect-src`/`img-src`, and the React style attributes the map and comparator use, without allowing every origin.
- Source maps are disabled in the production build. Personal locations, drafts and complaint content must never enter deployment metadata, URLs or logs.
