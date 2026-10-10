import copy
import unittest

from pyproj import Geod
from shapely.geometry import box, mapping

from registry.contract import assessment_patches, public_view, serialize
from rules import engine, osm

GEOD = Geod(ellps='WGS84')
LAT, LON = 28.73, 77.78                      # Hapur
AREA = box(77.70, 28.65, 77.86, 28.81)       # well beyond every threshold ring


def offset(lon, lat, east_m=0, north_m=0):
    lon, lat, _ = GEOD.fwd(lon, lat, 90, east_m)
    lon, lat, _ = GEOD.fwd(lon, lat, 0, north_m)
    return lon, lat


def kiln(kiln_id, lon=LON, lat=LAT, half_m=40):
    corners = [offset(lon, lat, dx, dy) for dx, dy in ((-half_m, -half_m), (half_m, -half_m), (half_m, half_m), (-half_m, half_m))]
    return {'kiln_id': kiln_id, 'footprint': {'polygon': [{'longitude': x, 'latitude': y} for x, y in corners],
                                              'centroid': {'longitude': lon, 'latitude': lat}}}


def point(east_m, north_m=0, ref='osm:node/1'):
    lon, lat = offset(LON, LAT, east_m, north_m)
    return {'ref': ref, 'kind': 'test', 'geometry': {'type': 'Point', 'coordinates': [lon, lat]}}


def layers(**features):
    return {name: engine.Layer(fs, AREA) for name, fs in features.items()}


def by_rule(assessment):
    return {r['rule_id']: r for r in assessment['rules_results']}


class DistanceTests(unittest.TestCase):
    def test_school_inside_and_outside_threshold(self):
        # Footprint edge is 40 m east of the centre, so the school is 900 m / 1,100 m from the edge.
        near = engine.assess([kiln('KW-1')], layers(schools=[point(940)]), 'UP')[0]
        far = engine.assess([kiln('KW-1')], layers(schools=[point(1140)]), 'UP')[0]
        r = by_rule(near)['UP-SCH-1K']
        self.assertEqual(r['status'], 'within_threshold')
        self.assertAlmostEqual(r['measured_distance_m'], 900, delta=1)
        self.assertEqual(r['threshold_m'], 1000)
        self.assertEqual(by_rule(far)['UP-SCH-1K']['status'], 'inconclusive')   # schools are sparsely mapped
        self.assertAlmostEqual(by_rule(far)['UP-SCH-1K']['measured_distance_m'], 1100, delta=1)
        self.assertEqual([v['rule_id'] for v in near['violations']], ['UP-SCH-1K'])
        self.assertEqual([v['rule_id'] for v in far['violations']], [])

    def test_violation_matches_record_contract(self):
        v = engine.assess([kiln('KW-1')], layers(railways=[point(140)]), 'UP')[0]['violations'][0]
        self.assertEqual(set(v), {'rule_id', 'measured_distance_m', 'threshold_m', 'source', 'evidence_url', 'measured_to'})
        self.assertEqual(v['threshold_m'], 200)
        lon, lat = offset(LON, LAT, 140)
        self.assertAlmostEqual(v['measured_to']['longitude'], lon, places=5)
        self.assertAlmostEqual(v['measured_to']['latitude'], lat, places=5)

    def test_nearest_of_several_and_overlap_is_zero(self):
        r = by_rule(engine.assess([kiln('KW-1')], layers(habitation=[point(700, ref='a'), point(0, 340, ref='b')]), 'UP')[0])
        self.assertEqual(r['C-HAB-800']['feature']['ref'], 'b')
        self.assertAlmostEqual(r['C-HAB-800']['measured_distance_m'], 300, delta=1)
        inside = {'ref': 'c', 'kind': 'test', 'geometry': mapping(box(LON - 0.01, LAT - 0.01, LON + 0.01, LAT + 0.01))}
        r = by_rule(engine.assess([kiln('KW-1')], layers(habitation=[inside]), 'UP')[0])
        self.assertEqual(r['C-HAB-800']['measured_distance_m'], 0)

    def test_empty_layer_is_clear_only_when_ring_was_searched(self):
        r = by_rule(engine.assess([kiln('KW-1')], layers(railways=[]), 'UP')[0])
        self.assertEqual(r['UP-RAIL-200']['status'], 'beyond_threshold')
        self.assertIsNone(r['UP-RAIL-200']['measured_distance_m'])
        edge = kiln('KW-2', *offset(77.70, LAT, 100))       # 100 m inside the searched area
        r = by_rule(engine.assess([edge], layers(railways=[]), 'UP')[0])
        self.assertEqual(r['UP-RAIL-200']['status'], 'not_evaluated')

    def test_sparse_layers_never_conclude_clear(self):
        r = by_rule(engine.assess([kiln('KW-1')], layers(orchards=[], habitation=[point(1200)]), 'UP')[0])
        self.assertEqual(r['C-ORCH-800']['status'], 'inconclusive')
        self.assertEqual((r['C-HAB-800']['status'], r['C-HAB-800']['measured_distance_m']), ('inconclusive', 1160))

    def test_missing_layer_and_unverifiable_rules_are_not_evaluated(self):
        a = engine.assess([kiln('KW-1')], {}, 'UP')[0]
        r = by_rule(a)
        self.assertEqual(r['C-HAB-800']['status'], 'not_evaluated')
        self.assertEqual(r['C-TECH-10K']['status'], 'not_evaluated')
        self.assertEqual(r['UP-MUN-5K']['status'], 'not_evaluated')
        self.assertEqual(a['rules_assessment'], 'partially_evaluated')
        self.assertEqual(a['violations'], [])

    def test_state_rules_and_overrides(self):
        r = by_rule(engine.assess([kiln('KW-1')], layers(schools=[point(500)]), 'HR')[0])
        self.assertEqual(r['UP-SCH-1K']['status'], 'not_applicable')
        rules = engine.load_rules()
        hab = next(x for x in rules['rules'] if x['id'] == 'C-HAB-800')
        hab['overrides'] = [{'state': 'XX', 'threshold_m': 1000}]
        r = by_rule(engine.assess([kiln('KW-1')], layers(habitation=[point(940)]), 'XX', rules)[0])
        self.assertEqual((r['C-HAB-800']['threshold_m'], r['C-HAB-800']['status']), (1000, 'within_threshold'))
        r = by_rule(engine.assess([kiln('KW-1')], layers(habitation=[point(940)]), 'UP', rules)[0])
        self.assertEqual((r['C-HAB-800']['threshold_m'], r['C-HAB-800']['status']), (800, 'inconclusive'))


class KilnSpacingTests(unittest.TestCase):
    def test_pair_flags_each_other_but_not_itself(self):
        a, b = kiln('KW-A'), kiln('KW-B', *offset(LON, LAT, 780))   # 700 m edge to edge
        out = engine.assess([a, b], {}, 'UP', scanned=AREA)
        for mine, other in zip(out, ('KW-B', 'KW-A')):
            r = by_rule(mine)['C-KILN-1K']
            self.assertEqual(r['status'], 'within_threshold')
            self.assertEqual(r['feature']['ref'], other)
            self.assertAlmostEqual(r['measured_distance_m'], 700, delta=1)

    def test_lone_kiln_near_scan_edge_is_not_evaluated(self):
        lone = kiln('KW-A', *offset(77.70, LAT, 500))
        self.assertEqual(by_rule(engine.assess([lone], {}, 'UP', scanned=AREA)[0])['C-KILN-1K']['status'], 'not_evaluated')
        self.assertEqual(by_rule(engine.assess([kiln('KW-A')], {}, 'UP', scanned=AREA)[0])['C-KILN-1K']['status'], 'beyond_threshold')

    def test_without_scan_area_spacing_is_not_evaluated(self):
        self.assertEqual(by_rule(engine.assess([kiln('KW-A')], {}, 'UP')[0])['C-KILN-1K']['status'], 'not_evaluated')


class OsmTests(unittest.TestCase):
    def element(self, tags, kind='way', closed=True):
        pts = [(77.78, 28.73), (77.781, 28.73), (77.781, 28.731), (77.78, 28.731)]
        if closed: pts.append(pts[0])
        el = {'type': kind, 'id': 7, 'tags': tags}
        if kind == 'node': el.update(lon=77.78, lat=28.73)
        else: el['geometry'] = [{'lon': x, 'lat': y} for x, y in pts]
        return el

    def layers_of(self, *elements):
        fc = osm.layers_from({'elements': list(elements), 'osm3s': {'timestamp_osm_base': '2026-10-10T00:00:00Z'}}, [77.7, 28.6, 77.9, 28.8])
        return [(f['properties']['layer'], f['geometry']['type']) for f in fc['features']]

    def test_classification(self):
        self.assertEqual(self.layers_of(self.element({'building': 'yes'})), [('habitation', 'Polygon')])
        self.assertEqual(self.layers_of(self.element({'building': 'industrial'})), [])
        self.assertEqual(self.layers_of(self.element({'building': 'school', 'amenity': 'school'})), [('schools', 'Polygon')])
        self.assertEqual(self.layers_of(self.element({'place': 'village'}, 'node')), [('habitation', 'Point')])
        self.assertEqual(self.layers_of(self.element({'railway': 'rail'}, closed=False)), [('railways', 'LineString')])
        self.assertEqual(self.layers_of(self.element({'railway': 'rail', 'service': 'siding'}, closed=False)), [])
        self.assertEqual(self.layers_of(self.element({'highway': 'trunk', 'ref': 'NH 9'}, closed=False)), [('national_highways', 'LineString')])
        self.assertEqual(self.layers_of(self.element({'highway': 'primary', 'ref': 'SH 18'}, closed=False)), [])

    def test_relation_outer_ring_becomes_polygon(self):
        ring = [{'lon': x, 'lat': y} for x, y in [(77.78, 28.73), (77.79, 28.73), (77.79, 28.74), (77.78, 28.73)]]
        rel = {'type': 'relation', 'id': 9, 'tags': {'landuse': 'orchard'}, 'members': [{'role': 'outer', 'geometry': ring}]}
        self.assertEqual(self.layers_of(rel), [('orchards', 'MultiPolygon')])


class RegistryWriteTests(unittest.TestCase):
    """The registry side: what apply-assessment accepts and what readers then see."""
    def body(self, ids=('KW-' + 'a' * 32,)):
        kilns = [kiln(i, *offset(LON, LAT, 3000 * n)) for n, i in enumerate(ids)]
        out = engine.assess(kilns, layers(railways=[point(140)], schools=[]), 'UP')
        return {'rules_version': 'kilnwatch-rules-v1', 'assessed_at': '2026-10-10T06:00:00+00:00',
                'inputs': {'kilns_sha256': 'k', 'layers_sha256': 'l', 'osm_base': '2026-10-10T05:38:35Z'}, 'assessments': out}

    def test_patch_carries_only_rule_keys(self):
        (kiln_id, patch), = assessment_patches(self.body())
        self.assertEqual(kiln_id, 'KW-' + 'a' * 32)
        self.assertEqual(set(patch), {'violations', 'rules_assessment', 'rules_results', 'rules_version', 'rules_inputs'})
        self.assertEqual(patch['rules_inputs']['assessed_at'], '2026-10-10T06:00:00Z')

    def test_rejects_local_ids_duplicates_and_inconsistent_flags(self):
        for ids in (('local-0000',), ('KW-' + 'a' * 32, 'KW-' + 'a' * 32)):
            with self.assertRaises(ValueError):
                assessment_patches(self.body(ids))
        b = self.body(); b['assessments'][0]['violations'] = []
        with self.assertRaises(ValueError):
            assessment_patches(b)
        b = self.body(); b['assessments'][0]['violations'][0]['evidence_url'] = 'http://insecure.invalid/x.png'
        with self.assertRaises(ValueError):
            assessment_patches(b)
        b = self.body(); b['assessments'][0]['violations'][0]['note'] = 'extra'
        with self.assertRaises(ValueError):
            assessment_patches(b)

    def test_readers_see_flags_but_not_internal_results(self):
        (_, patch), = assessment_patches(self.body())
        payload = {'kiln_id': 'KW-' + 'a' * 32, 'violations': [], 'rules_assessment': 'not_evaluated',
                   'exposure': None, 'type_verification': 'unverified', 'evidence': {'before': None, 'after': None}}
        record = serialize(copy.deepcopy(payload), assessment=patch)
        self.assertEqual(record['rules_assessment'], 'partially_evaluated')
        self.assertEqual([v['rule_id'] for v in record['violations']], ['UP-RAIL-200'])
        self.assertIsNone(record['violations'][0]['evidence_url'])
        self.assertNotIn('rules_results', record)
        self.assertEqual(public_view(record)['violations'], record['violations'])


if __name__ == '__main__':
    unittest.main()
