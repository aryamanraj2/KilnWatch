# Prompt 43b: deploy inspection requests (amends 43 §5)

Same chat as 43, the lead only. **No sub-agents** for this step. Don't stage, commit or push. The repo is public.

The orchestrator reviewed 43's local work: AWS 238 run (OK, 22 skipped without PostGIS), core 103, portal 92 unit tests, root build clean, leak scan 0, screenshots fine. You stopped correctly: 43 left out the invocation permission. **This prompt adds it to the scope.**

**The user gave the go by running this prompt.** The scope is exactly 43 §5, with this expected plan instead of 43's:

- **2 to add:** `aws_apigatewayv2_route.requests[0]` and `aws_lambda_permission.requests[0]` (source ARN limited to `POST /requests`; the existing verdicts permission is unchanged);
- **3 in-place changes:** the verdicts Lambda code, the API Lambda code, the stage (`POST /requests` throttle 1/s, burst 2);
- **0 to destroy.** Anything else in the plan: stop and report.

Then, in order, exactly as 43 §5 says:
1. Re-check both `aws login` sessions (masked). If either fails, stop and ask the user to sign in again.
2. Runner: migration 004 via SSM, the read-only checks (tables, exact grants, candidate checksum unchanged) and the rolled-back test. The rollback test must switch back to the admin login before `reset-requests`, as your report says.
3. `enable_requests = true` in the ignored tfvars; one targeted plan saved to `.local/requests/requests.tfplan`; read it against the list above; apply the saved plan; compare the live `CodeSha256` with the ZIP hashes in your report (rebuild the ZIPs first if any source changed).
4. Live checks 43 §5.3, including **one** real request plus its duplicate, and the CORS preflight from the portal origin.
5. The portal re-upload and invalidation (43 §5.4), the iOS live read (43 §5.5), then `reset-requests` for that kiln and confirm the public count is 0 (43 §5.6).
6. Mark the contract section live with the date. Update `AWS/docs/inspection-requests-report.md` with a short "Deploy (43b)" section: the plan and apply summaries, hashes, live checks, upload and clean-up. No identifiers anywhere.

Leak-check the changed files again at the end (expect 0) and `git diff --quiet AWS/.terraform.lock.hcl`.
