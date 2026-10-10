"""Deterministic siting checks: footprint-edge distances to reference features.
No network, database or model dependencies; the same inputs always give the same output."""
import json
from pathlib import Path

import numpy as np
from pyproj import Geod, Transformer
import shapely
from shapely import STRtree
from shapely.geometry import Polygon, box, shape
from shapely.ops import nearest_points

RULES = Path(__file__).with_name('rules_v1.json')
WORK_CRS = 'EPSG:32643'      # UTM 43N, as detect_scene.py; final distances are geodesic anyway
SEARCH_MARGIN_M = 1000       # beyond the threshold, report the nearest feature up to this far
GEOD = Geod(ellps='WGS84')
_to_work = Transformer.from_crs('EPSG:4326', WORK_CRS, always_xy=True).transform
_to_ll = Transformer.from_crs(WORK_CRS, 'EPSG:4326', always_xy=True).transform


def transform(fn, geom):
    return shapely.transform(geom, lambda xy: np.column_stack(fn(xy[:, 0], xy[:, 1])))


def load_rules(path=RULES):
    return json.loads(Path(path).read_text())


def threshold(rule, state):
    for o in rule.get('overrides', []):
        if o['state'] == state:
            return o['threshold_m']
    return rule['threshold_m']


def kiln_polygon(kiln):
    """Registry footprint (four corner objects) -> lon/lat Polygon."""
    return Polygon([(c['longitude'], c['latitude']) for c in kiln['footprint']['polygon']])


class Layer:
    """Reference features of one kind, indexed in metres. `coverage` is the lon/lat
    area the features were fetched for; outside it, absence proves nothing."""

    def __init__(self, features, coverage):
        self.features = features
        self.work = [transform(_to_work, shape(f['geometry'])) for f in features]
        self.tree = STRtree(self.work)
        self.coverage = transform(_to_work, coverage)

    def nearest(self, geom, max_m, skip=()):
        """Index of the closest feature within max_m metres (ties: lowest index), or None."""
        hits = [(geom.distance(self.work[i]), int(i))
                for i in self.tree.query(geom, predicate='dwithin', distance=max_m) if int(i) not in skip]
        return min(hits)[1] if hits else None


def geodesic(a, b):
    (lon1, lat1), (lon2, lat2) = _to_ll(a.x, a.y), _to_ll(b.x, b.y)
    return GEOD.inv(lon1, lat1, lon2, lat2)[2], (lon2, lat2)


def result(rule, status, limit=None, **extra):
    r = {'rule_id': rule['id'], 'check': rule['check'], 'status': status, 'threshold_m': limit,
         'verification': rule['verification'], 'source': rule['source']}
    r.update(extra)
    return r


def check(rule, state, kiln_work, layers, skip=()):
    if rule.get('states') and state not in rule['states']:
        return result(rule, 'not_applicable', reason=f'rule applies only in {", ".join(rule["states"])}')
    if rule['kind'] != 'distance' or rule['layer'] not in layers:
        return result(rule, 'not_evaluated', reason=rule.get('not_evaluated_reason', 'reference layer unavailable'))
    limit = threshold(rule, state)
    layer = layers[rule['layer']]
    search = limit + SEARCH_MARGIN_M
    i = layer.nearest(kiln_work, search, skip)
    # Clear only if the feature layer is complete enough that absence means something.
    clear = 'beyond_threshold' if rule.get('absence_conclusive', True) else 'inconclusive'
    if i is not None:
        on_kiln, on_feature = nearest_points(kiln_work, layer.work[i])
        metres, (lon, lat) = geodesic(on_kiln, on_feature)
        if kiln_work.intersects(layer.work[i]):
            metres = 0.0
        f = layer.features[i]
        return result(rule, 'within_threshold' if metres < limit else clear, limit,
                      measured_distance_m=round(metres), measured_to={'latitude': round(lat, 6), 'longitude': round(lon, 6)},
                      feature={k: f[k] for k in ('ref', 'name', 'kind') if f.get(k)},
                      **({} if metres < limit or clear != 'inconclusive' else {'reason': 'nearest mapped feature; unmapped ones may be closer'}))
    # Nothing found: only meaningful if the whole threshold ring was searched.
    if not layer.coverage.contains(kiln_work.buffer(limit)):
        return result(rule, 'not_evaluated', limit, reason='threshold ring extends outside the searched area')
    reach = search if layer.coverage.contains(kiln_work.buffer(search)) else limit
    return result(rule, clear, limit, measured_distance_m=None, reason=f'no mapped feature within {reach} m')


def assess(kilns, layers, state, rules=None, scanned=None):
    """kilns: registry records. layers: name -> Layer. scanned: lon/lat area searched
    for kilns, which bounds what the kiln-spacing rule can conclude."""
    rules = rules or load_rules()
    polys = [kiln_polygon(k) for k in kilns]
    layers = dict(layers)
    if scanned is not None:
        kiln_features = [{'ref': k['kiln_id'], 'kind': 'satellite candidate', 'geometry': p.__geo_interface__}
                         for k, p in zip(kilns, polys)]
        layers['kilns'] = Layer(kiln_features, scanned)
    out = []
    for n, (kiln, poly) in enumerate(zip(kilns, polys)):
        work = transform(_to_work, poly)
        results = [check(rule, state, work, layers, skip={n} if rule.get('layer') == 'kilns' else ())
                   for rule in rules['rules']]
        violations = [{'rule_id': r['rule_id'], 'measured_distance_m': r['measured_distance_m'],
                       'threshold_m': r['threshold_m'], 'source': r['source'], 'evidence_url': None,
                       'measured_to': r['measured_to']} for r in results if r['status'] == 'within_threshold']
        complete = all(r['status'] not in ('not_evaluated', 'inconclusive') for r in results)
        out.append({'kiln_id': kiln['kiln_id'], 'rules_version': rules['version'], 'state': state,
                    'rules_assessment': 'evaluated' if complete else 'partially_evaluated',
                    'measured_from': 'footprint_edge', 'violations': violations, 'rules_results': results})
    return out


def coverage_of(meta):
    w, s, e, n = meta['bbox']
    return box(w, s, e, n)
