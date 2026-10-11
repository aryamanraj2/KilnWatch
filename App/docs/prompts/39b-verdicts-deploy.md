# Prompt 39b: deploy the verdicts backend (continuation of 39, same chat)

Prompt 39's code passed orchestrator review: 176 run, 160 pass and 16 opt-in skips; the default public read is byte-for-byte unchanged. Deployment stopped for two good reasons, and this widens the go to cover them:

1. **The existing Secrets Manager endpoint policy** (`aws_vpc_endpoint.secrets` in `AWS/bridge.tf`) only allows the reader and master secrets.
2. **The runner role policy** only allows `PutSecretValue` on the reader secret.

**The user gave the go by running this.** Everything in prompt 39 still applies, plus exactly this:

- **Code edits**, both added only `if enable_verdicts`, the same pattern as the runner conditional that already exists:
  - in the endpoint policy, add the verdict secret to the `GetSecretValue` resources and to the runner-only `PutSecretValue` statement;
  - in the runner's role policy, add `PutSecretValue` on the verdict secret only.
- **Two targeted applies** in this order:
  1. **Apply A:** the empty `aws_secretsmanager_secret.verdicts[0]`, plus in-place changes to `aws_vpc_endpoint.secrets` and the runner's role policy. Expect 1 add and 2 in-place changes; anything else, stop.
  2. **Runner (SSM):** migration 003, the `kilnwatch_verdicts` login, its password written only into the new secret, and the checks and rolled-back write test from 39 §5.
  3. **Apply B:** the verdict Lambda, role, policy, log group, integration and route, the stage throttle change, and the `aws_lambda_function.api` code update. Expect additions plus in-place changes to the stage and the API Lambda only; anything else, stop. Then check that the live `CodeSha256` values match your ZIP hashes (verdict `be4cca0e…`, API `2b571ca6…`, or the new ones if you rebuild).
- **Then:** the live checks from 39 §5.4–5.5, which write no verdict. Update the docs from "prepared" to "live".

**Credentials:** the user refreshes them in their own terminal with `aws login --profile kilnwatch` before you start. If a call says the session expired, stop and ask them to run it again.

**Leave alone, and don't revert:** the comment and description edits in other `AWS/*.tf` files, and the deleted `AWS/backend.hcl.example` / `AWS/terraform.tfvars.example`. They come from another session, and the user decides about them. Don't stage anything.

Report as in 39, plus both plan summaries.
