# Rules engine (v1, local)

Deterministic siting checks: for each kiln footprint, the geodesic distance from the footprint edge to the nearest reference feature, compared with a versioned, cited threshold. No AI and no network during assessment; registry writes go only through `registry.cli apply-assessment`.

```
# Kilns with registry IDs: the public API (live), or the verified import file
PYTHONPATH=AWS python -m rules.cli fetch  --kilns hapur_kilns.geojson --layers .local/rules/hapur_osm.geojson \
    --population .local/rules/hapur_hrsl.tif
PYTHONPATH=AWS python -m rules.cli assess --kilns hapur_kilns.geojson --district Hapur \
    --artifact-manifest Model/results/checkpoint-manifest.json --acquired-at 2026-10-05T05:41:03.148Z \
    --layers .local/rules/hapur_osm.geojson --population .local/rules/hapur_hrsl.tif --out .local/rules/hapur_assessment.json
#   or: --kilns 'https://<api>/public/kilns?district=Hapur&limit=200' --scanned-bbox 77.73 28.68 77.83 28.78

# Registry: dry run anywhere; the write needs the private runner and an assessor login
PYTHONPATH=AWS python -m registry.cli validate-assessment --assessment .local/rules/hapur_assessment.json
PYTHONPATH=AWS python -m registry.cli migrate            # applies 002_assessment.sql
PYTHONPATH=AWS python -m registry.cli apply-assessment --assessment hapur_assessment.json

PYTHONPATH=AWS python -m unittest discover -s AWS/tests -p test_rules.py
```

- `rules_v1.json` holds the thresholds, citations and verification level for each rule. UP's 2026 amendment sets habitation at 800 m and kiln spacing at 1 km, which settles the earlier conflict in the concept.
- `osm.py` fetches OSM features once per area from Overpass. The extract is ODbL and git-ignored.
- `engine.py` is pure computation. It gives each rule one of these statuses:

| Status | Meaning |
|---|---|
| `within_threshold` | A mapped feature is closer than the threshold. This goes into `violations`. |
| `beyond_threshold` | The layer is complete enough that no feature means clear. Used for railways, national highways and other kilns. |
| `inconclusive` | No mapped feature inside the threshold, but OSM coverage is too sparse to conclude clear. Used for habitation, schools and orchards. |
| `not_evaluated` | No usable data. Applies to UP-MUN-5K (no boundary layer), to C-TECH-10K (type unverified), and wherever the threshold ring leaves the searched area. |
| `not_applicable` | A state rule outside its state. |

`exposure.py` adds `exposure` to each kiln: the people, children under 5 and adults over 60 living within 800 m of the footprint edge.
- **Source:** Meta/CIESIN HRSL v1.5.2 (CC BY 4.0). The tiles are pinned rather than the moving "latest" mosaic, and clipped once into a local GeoTIFF.
- **Method:** a ~30 m cell counts when its centre lies inside the ring. A rasterised-buffer cross-check agreed to within 0.14% on all 39 Hapur kilns.
- **Age groups:** HRSL's modelled splits of the same estimate, not separate counts.
- **Missing values:** a kiln whose ring leaves the clipped grid gets no exposure, never a zero.

Every flag is a siting signal pending inspection. Siting criteria govern the establishment of kilns, so whether a rule applies to a given existing kiln is decided on site.

## Writing results to the registry
- `migrations/002_assessment.sql` adds a `kilnwatch_assessor` role. It can update only `candidates.assessment`, so status, review state and observations are out of reach.
- `apply-assessment` validates the whole batch first, then writes it in one transaction. It replaces only the rule keys (`violations`, `rules_assessment`, `rules_results`, `rules_version`, `rules_inputs`), so other assessment keys survive. An unknown or temporary kiln ID rolls back everything.
- When a batch carries `exposure`, it replaces the stored exposure, with `exposure_inputs` recording the source, file hash and radius. A batch without it leaves the stored exposure alone.
- Readers see `violations`, `rules_assessment` and `exposure`. `rules_results` (every rule's status and nearest feature) stays internal.
- Real IDs:
  - For the Hapur run, the old `hapur_kilns.geojson` plus the verified manifest and the exact scene time rebuild the IDs. These matched all 5 kilns recorded from the live public API, in ID, footprint, type and score.
  - The public API path returns only `flagged` kilns, so once inspectors record verdicts, read from the registry instead.
- `Violation.evidenceUrl` is optional in KilnWatchCore, so flags without an image decode.

Still to do on AWS (AWS teammate):
- Run `migrate`.
- Create an assessor login with its secret.
- Run `apply-assessment` from the private runner.
- The PostGIS role test (`test_assessor_writes_rule_keys_only`) has not run yet. Run it on a local PostGIS first.
