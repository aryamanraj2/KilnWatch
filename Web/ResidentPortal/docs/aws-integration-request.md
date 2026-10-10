# Integration inputs — not sent

R1 uses synthetic local data and requires none of these services to run. This checklist is for owner review before later phases; no teammate was contacted automatically. The [public contract](public-api-contract.md) is a proposal.

## AWS teammate

1. **Latest state:** confirm the public environment/base URL and latest verification report. The last repository report says 73/75 resources in `ap-south-1`, 39 private Hapur candidates, and `/public/kilns` returning 503. This portal did not inspect the account.
2. **Publication:** name the publication owner; agree which records/fields/images are anonymous. Implement the server-side public projection/filter, not a frontend-only filter. Prove that private and nonexistent IDs are indistinguishable and that anonymous endpoints cannot mutate data.
3. **Nearby search:** agree center/radius, maximum area/page size, canonical distance basis, sort/cursor/revision semantics, coverage/completeness and freshness. The R1 adapter is centroid-based; proposed footprint-based live calculations need explicit parser/label changes.
4. **Details/rules/exposure:** provide public detail/rule routes, authoritative citations, applicability/version, actual assessments and exposure provenance. Missing facts may remain explicitly unavailable; please do not fill missing assessments with fixture values.
5. **Evidence:** confirm the CloudFront account-verification outcome, actual publication/receipt re-import, approved HTTPS hosts, per-image metadata and CORS. The selected pair's approval does not establish approval to expose all private candidates. Supply denial proof for private object paths.
6. **Maps/geocoding:** approve provider/coverage/attribution/terms, a restricted browser key if needed, allowed origins/expiry/quotas and budget. R1 uses no tile/geocoder service. Search-provider disclosure must reflect the chosen provider.
7. **Resident assistant (R3):** supply server-side registry/rule tools, citation validation, actual request/event schema, Hindi/English behavior, network and IAM path, timeouts, abuse/rate limits and cost controls. Confirm VPC reachability; IAM alone is insufficient. The browser receives no Bedrock/AgentCore credentials.
8. **Hosting (R4):** confirm Amplify monorepo root/runtime, domain/HTTPS, preview versus production environments, asset-safe SPA rewrites, exact API/image/font/map/worker origins, CSP/CORS/security headers and source-map policy. Reconcile existing infrastructure `VITE_API_BASE_URL` with the proposed resident variables; no AWS configuration was changed here.
9. **Incremental cost and release proof:** review portal hosting, map/geocoding, public reads and assistant usage separately from the earlier foundation cost estimate. Supply actual anonymous acceptance evidence and a release owner.

Ready-to-review proposal files: [public API](public-api-contract.md), [hosting](hosting-proposal.md), [README configuration](../README.md).

## ML team mate

1. Saved training-run/notebook version identity and the linkage from weights to reported metrics. No new checkpoint or retraining is requested.
2. Approved public model/version terminology and confidence interpretation, including known FCBK/Zigzag confusion. AP must not be presented as general or field accuracy.
3. Interpretation of the existing before/after pair: acquisition dates, grid/alignment/cloud/season limits, what differences support, and whether any actual historical outline exists.
4. Additional generated evidence, if any, and candidate association. One pair is not 39 pairs. The AWS teammate still controls anonymous publication.

## Other release inputs

Faithful independent Hindi copy review and verified/owner-reviewed official filing contacts. The local draft composer remains usable without either a filing link or an AI service. These are release limitations, not excuses to stop building the sample journey.

## Stop boundary

No R2 connection until the user gives the go and the public backend is approved/ready. R3 and R4 each have their own go; deployment requires explicit authorization. Keep missing inputs distinct from implementation defects and failed tests.
