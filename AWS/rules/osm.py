"""OpenStreetMap reference layers for the siting rules, fetched once per area from the
Overpass API and saved as GeoJSON (ODbL: keep attribution, never commit the extract)."""
from datetime import datetime, timezone
import hashlib
import json
import re
import urllib.parse
import urllib.request

from shapely.geometry import LineString, MultiPolygon, Point, Polygon, mapping
from shapely.ops import polygonize, unary_union

OVERPASS = 'https://overpass-api.de/api/interpreter'
PLACES = '^(city|town|village|hamlet|suburb|neighbourhood|quarter|isolated_dwelling)$'
NH_REF = re.compile(r'(^|;)\s*(NH|NE)[\s-]?\d', re.I)
# Buildings explicitly tagged as something people do not live in. Untagged
# building=yes, most of rural India, counts as habitation.
NOT_DWELLING = {'industrial', 'warehouse', 'commercial', 'retail', 'office', 'school', 'college', 'university',
                'hospital', 'temple', 'mosque', 'church', 'religious', 'shrine', 'government', 'public', 'civic',
                'train_station', 'transportation', 'farm_auxiliary', 'barn', 'cowshed', 'stable', 'greenhouse',
                'shed', 'garage', 'garages', 'carport', 'roof', 'construction', 'ruins', 'kiln', 'chimney',
                'cinema', 'movie theater', 'service', 'transformer_tower', 'water_tower', 'storage_tank', 'silo', 'toilets', 'parking'}


def query(bbox):
    w, s, e, n = bbox
    b = f'({s},{w},{n},{e})'
    return f'''[out:json][timeout:300];
(
  way["building"]{b};
  nwr["landuse"="residential"]{b};
  node["place"~"{PLACES}"]{b};
  nwr["amenity"="school"]{b};
  nwr["landuse"="orchard"]{b};
  way["railway"="rail"]{b};
  way["highway"]["ref"]{b};
);
out geom;'''


def fetch(bbox, url=OVERPASS):
    q = query(bbox)
    req = urllib.request.Request(url, data=urllib.parse.urlencode({'data': q}).encode(),
                                 headers={'User-Agent': 'KilnWatch-rules/1 (siting checks)'})
    with urllib.request.urlopen(req, timeout=360) as r:
        data = json.load(r)
    return layers_from(data, bbox, hashlib.sha256(q.encode()).hexdigest())


def geometry(el):
    """Overpass `out geom` element -> shapely geometry, or None."""
    if el['type'] == 'node':
        return Point(el['lon'], el['lat'])
    if el['type'] == 'way':
        pts = [(p['lon'], p['lat']) for p in el.get('geometry', []) if p]
        if len(pts) < 2:
            return None
        closed = len(pts) >= 4 and pts[0] == pts[-1]
        area = closed and not {'railway', 'highway'} & el.get('tags', {}).keys()
        return Polygon(pts) if area else LineString(pts)
    lines = [LineString([(p['lon'], p['lat']) for p in m['geometry']])
             for m in el.get('members', []) if m.get('role') in ('outer', '') and len(m.get('geometry') or []) >= 2]
    if not lines:
        return None
    polys = list(polygonize(unary_union(lines)))
    return MultiPolygon(polys) if polys else unary_union(lines)


def kinds(tags):
    """Which rule layers an element belongs to, with a short description."""
    out = []
    building = tags.get('building')
    if building and building not in NOT_DWELLING and tags.get('man_made') not in ('kiln', 'chimney'):
        out.append(('habitation', f'building={building}'))
    if tags.get('landuse') == 'residential':
        out.append(('habitation', 'landuse=residential'))
    if 'place' in tags and re.match(PLACES, tags['place']):
        out.append(('habitation', f'place={tags["place"]}'))
    if tags.get('amenity') == 'school':
        out.append(('schools', 'amenity=school'))
    if tags.get('landuse') == 'orchard':
        out.append(('orchards', 'landuse=orchard'))
    if tags.get('railway') == 'rail' and not tags.get('service'):
        out.append(('railways', 'railway=rail'))
    if tags.get('highway') and NH_REF.search(tags.get('ref', '')):
        out.append(('national_highways', f'highway={tags["highway"]} ref={tags["ref"]}'))
    return out


def layers_from(data, bbox, query_sha256=None):
    features = []
    for el in data['elements']:
        tags = el.get('tags', {})
        found = kinds(tags)
        if not found:
            continue
        geom = geometry(el)
        if geom is None or geom.is_empty:
            continue
        for layer, kind in found:
            features.append({'type': 'Feature', 'geometry': mapping(geom),
                             'properties': {'layer': layer, 'ref': f'osm:{el["type"]}/{el["id"]}', 'kind': kind,
                                            **({'name': tags['name']} if tags.get('name') else {})}})
    meta = {'source': 'OpenStreetMap via Overpass API', 'licence': 'ODbL 1.0, (c) OpenStreetMap contributors',
            'osm_base': data.get('osm3s', {}).get('timestamp_osm_base'),
            'fetched_at': datetime.now(timezone.utc).isoformat(timespec='seconds'),
            'bbox': list(bbox), 'query_sha256': query_sha256}
    return {'type': 'FeatureCollection', 'features': features, 'kilnwatch': meta}
