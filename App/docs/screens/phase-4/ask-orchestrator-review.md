# Prompt 18 — orchestrator review

Reviewed on 10 October 2026. No blocking findings in the iOS changes.

Independently inspected the tracked diff and new Swift sources, test resources, UI harness source and builder report against prompt 18. Request validation, stateless POST construction, error distinctions, explicit retry, cancellation and stale-response handling are covered by local tests. Live responses preserve server steps, full citations, fallback and disclaimer. Live detail prefill does not submit automatically. Sample responses remain separate.

## Independent verification

- Core suite rerun: 53 tests, one opt-in live check skipped, no failures or compiler warnings.
- Prescribed root Simulator build rerun: succeeded, no compiler warnings or errors.
- Scoped diff whitespace check: passed.
- Visually inspected all 18 Ask screenshots, including live answer/detail, local errors, offline recovery, fallback, waiting, prefill, long input, light/dark, AX3/AX5 and scripted Reduce Motion evidence.
- Regenerated screenshot OCR and reran the reviewed leak scanner: 40 builder-owned files, including 18 screenshots; zero matches. Raw logs remain ignored. Scan inputs came from existing local configuration/fixtures, with no AWS reads.

The builder's temporary UI harness was reviewed but not rerun by the orchestrator. Screenshot inspection supports layout findings; it does not establish spoken VoiceOver behavior.

## Limits and next gate

The builder reports one confirmed app request and conservative usage of 2/8 attempts. The live citation opened live detail. The orchestrator made no live requests. A selected-kiln contextual POST has local construction/prefill coverage but was not exercised live.

Build and screenshots use the installed iOS 27 Simulator/toolchain. Minimum deployment remains iOS 26.1; physical iOS 26.6 and spoken VoiceOver checks remain unverified. The fixed footer occupies substantial space at AX5, particularly with the DEBUG test label; tightening it can be considered during the later polish phase.

Recommendation: accept prompt 18's implementation. Prompt 19 remains gated on the user's R1-live confirmation; prompt 20 remains gated on P1. This review does not authorize staging, committing, pushing, deployment or AWS writes. Unrelated AWS-lane changes were left untouched.
