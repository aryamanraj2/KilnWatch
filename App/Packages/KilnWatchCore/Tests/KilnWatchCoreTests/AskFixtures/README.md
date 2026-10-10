# Ask fixtures

The normal answer and nested/gateway error bodies are sanitized recordings from the existing ignored Phase 4 fixtures. They represent responses at recording time, not current registry facts. `fallback.synthetic.json` is a synthetic validator fallback, not a live fallback observation. Full kiln IDs (including the shortened trace label) are remapped to synthetic full-format IDs consistently. Host-like values and infrastructure identifiers are removed. No test reaches a live service.
