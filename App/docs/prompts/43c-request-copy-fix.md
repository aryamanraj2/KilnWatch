# Prompt 43c: portal request copy fix + re-upload

Same chat as 43/43b. **No sub-agents.** Don't stage, commit or push. The repo is public.

The orchestrator reviewed 43b live: aggregates are 0 on all 39 kilns, the portal serves the new build. Two portal issues show up in the demo (the first live request shows a count of 1):

1. **Plurals** in `Web/ResidentPortal/src/features/requests/InspectionRequest.tsx`:
   - line ~19: "1 inspection requests · not verified" → "1 inspection request · not verified" for 1;
   - lines ~47–48: "1 residents have asked…" → "1 resident has asked for an inspection of this kiln." for 1.
   - English only needs the singular forms; the Hindi strings are fine as they are. Check any other count string in the portal (area list, record) the same way. Add a unit test for count 1 and 12.
2. **The sticky bar's "Request an inspection"** (`RecordPages.tsx` action bar) still invites a second request after this browser has sent one. When this browser has already sent a request for the kiln, the bar's button reads "View your request" (Hindi: "अपना अनुरोध देखें") and scrolls to the card; otherwise unchanged.

**The user gave the go by running this prompt** for exactly: the two code fixes, `npm run typecheck`, `npm test`, `npm run build`, the mocked `test:e2e:live` on Chromium, then **one** portal re-upload (37's procedure: production build with the ignored `.env.production.local`, two-pass `s3 sync`, invalidate `/*`). Check both `aws login` sessions first (masked); if either fails, stop and ask. **No POST to the live API** (read-only page check at 390 px after the upload). No other AWS change.

Never print identifiers. Report: diff summary, test counts, upload/invalidation summary, one 390 px screenshot of the record page (read-only), leak check of the changed files (expect 0). Append a short "43c" section to `AWS/docs/inspection-requests-report.md`.
