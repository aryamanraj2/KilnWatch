`*.recorded.json` are sanitized copies of bodies recorded from the live `POST /routes/plan` (P1) on 2026-10-10, before this phase.

- `plan-people.recorded.json`: the default people plan for Hapur, 8 stops, 8 legs, 4 notes. Stop 1 has `rules_flagged: []`.
- `plan-start.recorded.json`: a plan with an explicit start, 5 stops, 5 legs, 3 notes.
- `plan-invalid.recorded.json`: the 400 `invalid_request` error body.

Real registry IDs are remapped consistently across both plans (stops, `legs[].to_kiln_id`, `kilns`) to full-format synthetic IDs `KW-d1` plus 26 zeros and `0001` to `0008`. `route_id` is replaced with a synthetic value, and the recorded error `message` is replaced with neutral text. Numbers, notes, access notes, statuses and geometry are kept as recorded. The bodies contained no hosts or URLs; evidence is null as recorded. The app's DEBUG stub uses a copy of the people plan (`App/KilnWatch/Mock/P1Plan.recorded.json`), labelled Sample data. These resources never authorize live POSTs.
