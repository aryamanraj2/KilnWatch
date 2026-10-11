# KilnWatch — prompt 22: real verdicts, closing the loop (no sign-in)

Run in a **new Claude Code builder chat**, in the existing checkout. Prompt 21/21b (polish) passed review. The verdict backend (39/39b) is **live**. This builder may use Xcode and the Simulator; no other builder may use them at the same time.

**Goal:** the inspector's verdict leaves the phone and changes the registry, and the app shows the outcome. That closes the loop:

> flag → rules and exposure → route → kiln → **verdict + photos → AWS → status shown**

The user decided: **no sign-in and no auth.** `POST /verdicts` is public.

## 1. Scope and authorization

Running this prompt authorizes:
- local iOS edits, `swift test`, the root build, Simulator checks and screenshots;
- public GETs (including `include=inspected`);
- **exactly 1 live `POST /verdicts`** (and its replay, if the app retries it), plus its photo PUTs. This is the **user's go for one real verdict** (§5). It permanently changes one kiln's status until an operator reset.

**Zero** live `POST /routes/plan` and `POST /ask`. No AWS CLI, no backend or contract edits, no sub-agents, no staging or commits. Own `App/` only. Keep testing light: core tests, the root build, the checks listed and one screenshot per item.

Read:
- `AGENTS.md`, `App/docs/DESIGN.md` (binding), the newest `App/docs/HANDOVER.md` sections;
- `App/docs/api-contract.md`: "POST /verdicts" (live, public, cap 30/day, replay returns URLs for every photo) and the public read's `include=inspected` / `inspection`;
- `Features/Verdict/VerdictSheet.swift`, `KilnWatchApp.swift` (`recordVerdict`, `verdictOverrides`, registry loading), KilnWatchCore `KilnWatchAPI.swift` (`submit`, `upload`, `send`), `Offline.swift` (`VerdictOutbox`), `Models.swift` (`Verdict`, `Photo`, `KilnStatus`, `Kiln`), `ForegroundLocation.swift`, `StatusBadge`, `HoldToConfirmButton`.

## 2. What exists and what to change

- **The verdict sheet is a mock today:**
  - its photos are bundled sample images;
  - `recordVerdict` only sets a local override, and is disabled in public mode;
  - `VerdictOutbox` (crash-safe queue, idempotent flush, photo files) exists in core but the app never uses it.
- **`submit` always attaches a bearer token**, so in public mode it would fail with `.token`. Make `POST /verdicts` **unauthenticated** (the same way the public reads skip the token), with no `Authorization` header. `upload` already sends none.
- **The response decodes into `VerdictReceipt`** (`id`, `photo_uploads[{photo_id, upload_url}]`). The upload host is S3: allow only `https` URLs on an `amazonaws.com` host, and never log or display them.

## 3. Capture and queue

- **Photos:**
  - real capture with the system camera (`UIImagePickerController` / camera), falling back to `PhotosPicker` when no camera is available (Simulator);
  - at most **8**; downscale to ≤ 2048 px on the long edge and encode JPEG at about 0.7 quality;
  - strip any EXIF that isn't needed: the app's `Photo` record carries the geotag.
- **Geotag:** from the existing foreground location at capture time (latitude, longitude, horizontal accuracy, time). If there's no fix, say "Location unavailable · photo can't be geotagged" and don't attach it. Never fake coordinates.
- **Note:** optional, ≤ 2000 characters.
- **Outcome rows:** unchanged, from DESIGN.
- **Hold to submit:**
  - `VerdictOutbox.enqueue` (photos written first);
  - then the success or queued feedback (`.success` online, `.warning` offline, as now);
  - then `flush`.
  - The sheet copy "This changes KW-…'s status for everyone." stays.
- **Flush triggers:** right after enqueue, on app foreground, and when connectivity returns. One flush at a time (the actor already guards this). **No timers or polling loops.**
- **Error handling:**

  | Response | Effect | Retry |
  |---|---|---|
  | 400 / 404 / 409 | "rejected" with the reason in plain words (for example "This kiln is no longer in the registry"); keep it in the outbox | the user can **Discard** with a confirmation |
  | 429 `daily_cap_reached` | "Verdict limit reached for today · will send after 05:30 IST" | the next day |
  | 503 / transport | stays queued | the next trigger |

- **Pending state:**
  - a kiln with a queued verdict shows "Verdict pending sync" (quiet, with a symbol) on its row and detail, and the chosen outcome as **pending**, never as recorded;
  - a small "1 verdict waiting to sync" line on Today/Kilns while the outbox isn't empty.
- **Remove the mock override path in public mode.** Fixture/DEBUG mode may keep its labelled sample behaviour.

## 4. Showing outcomes

- The app's registry list and detail requests add `include=inspected`, both shapes. Ask and the route planner are server-side and stay flagged-only; don't change them.
- **Model:** add `inspection: {outcome, recordedAt}?` (optional; old caches and fixtures still decode). `Kiln.status` already carries the outcome.
- **Display:**
  - an inspected kiln shows the `StatusBadge` for its outcome (symbol + word + colour, existing tokens) and "Recorded on site · 11 Oct" (Asia/Kolkata);
  - flagged kilns keep "Flagged by satellite · pending inspection";
  - never "illegal".
- **Kilns list:** a status filter menu that already exists keeps working; all statuses are visible.
- **Today map:** inspected kilns get their status colour and symbol (not the flagged amber).
- **Saved route plan:** a stop whose kiln now has a verdict shows the outcome on its card. The plan itself isn't changed.
- After a successful flush, refresh that kiln's detail once (one GET, not a loop). The public read may lag up to 60 s (cache), so show the local "Recorded · syncing" state until the refreshed read agrees.

## 5. The one live verdict (the user's go)

- **Pick** a Hapur kiln that is **not** in the saved plan's stops and **not** the reference kiln `KW-6b3b38…`. Record its full ID in the report.
- **Set the Simulator location** to that kiln's centroid (`xcrun simctl location … set <lat>,<lon>`), so the photo geotag is real for this test.
- **Outcome `confirmed`**, note "Simulator end-to-end test, not a field inspection", **1 photo** from the Simulator photo library (any image). The photo only goes to the private bucket and is never public; say so in the report.
- **Submit once.** Check:
  - 201;
  - the photo PUT got 200;
  - the outbox is empty;
  - after up to ~60 s, one `GET /public/kilns/<id>?include=inspected` shows `status: confirmed` with `inspection.recorded_at`;
  - the default `GET /public/kilns?district=Hapur` now has **38** kilns. **Say this in the report:** the public flagged count, Ask and route planning now see 38, until an operator reset.
- If anything fails, **don't** send a second new verdict. Report it. A replay of the same ID is fine.

## 6. Tests, build, screenshots, report

- **Core tests (stubs):**
  - `submit` sends no `Authorization` and does send the `Idempotency-Key`;
  - the receipt decode;
  - the upload host allowlist;
  - outbox flush paths for 201, 200 replay, 409, 429, 503 and transport (the verdict stays or leaves as specified);
  - `inspection` decode, and old payloads without it;
  - `include=inspected` on list and detail requests.
  - Last run: 77 passed. Report the new count. The root build must have zero warnings.
- **Screenshots** in `App/docs/screens/phase-6/`:
  - the verdict sheet with a real photo and geotag;
  - the queued/offline state;
  - the rejected state (stub);
  - the kiln detail after the live verdict (outcome + "Recorded on site");
  - the Kilns list showing the mixed statuses;
  - the Today map with the inspected kiln.

  Label live versus stubbed. Inspect each yourself.
- **Leak scan** of changed files and PNGs, as in 20/21. The presigned URL and bucket host must never appear in logs, screenshots or files. Report counts only.
- **Write** `App/docs/screens/phase-6/verdict-loop-report.md`:
  - what changed;
  - tests and build;
  - the live verdict (the kiln ID, statuses, timings, the 38-count effect);
  - screenshots;
  - leak counts;
  - limits (Simulator camera fallback; no sign-in by decision; public cap 30/day; reset needs the runner).
- Add a 3-line note to `App/docs/HANDOVER.md`. Stop for orchestrator review.
