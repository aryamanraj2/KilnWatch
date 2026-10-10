"""P1 route planner, pure Python: selection, nearest-neighbour + 2-opt ordering, budget trimming and the route contract.
The Amazon Location client is passed in, so tests need neither AWS nor the network. Same input, same plan."""
import hashlib
import json
import math
import time
from datetime import datetime, timedelta, timezone

IST = timezone(timedelta(hours=5, minutes=30))
SERVICE_MIN = 35
MAX_KILNS = 8            # 9 origins x 8 destinations = 72 cells: Unbounded allows at most 15 origins and 100 cells
MAX_LEG_POINTS = 200
ACCESS_NOTE = 'Kiln centroid, not a verified entrance · confirm on site'
DEFAULT_START = 'Default start: centre of the selected kilns.'
NOTES = ['ETAs are estimates from road travel times without live traffic, plus 35 minutes on site per stop.',
         'Access points are kiln centroids, not verified entrances.',
         'Every kiln is flagged by satellite, pending inspection. A siting flag is a signal to check on site.']
CHECKS = {'C-HAB-800': 'Distance to the nearest home', 'C-KILN-1K': 'Distance to the nearest kiln',
          'UP-NH-300': 'Distance to the national highway', 'UP-RAIL-200': 'Distance to the railway'}
ALWAYS = ['Kiln type: fixed chimney or zigzag', 'Is the kiln firing?']


class NoKilns(Exception):
    pass


class RoutingUnavailable(Exception):
    pass


# ---- solver: node 0 is the start; d[i][j] is driving seconds; the path is open (no return to the start) ----

def path_cost(d, path):
    return sum(d[a][b] for a, b in zip([0] + path, path))


def order(d, nodes):
    """Nearest neighbour from the start (ties to the lower index), then 2-opt reversals until none helps."""
    left, path, at = sorted(nodes), [], 0
    while left:
        at = min(left, key=lambda j: (d[at][j], j))
        path.append(at); left.remove(at)
    improved = True
    while improved:
        improved = False
        for i in range(len(path) - 1):
            for j in range(i + 1, len(path)):
                candidate = path[:i] + path[i:j + 1][::-1] + path[j + 1:]
                if path_cost(d, candidate) < path_cost(d, path):
                    path, improved = candidate, True
    return path


def fit(d, ranked, max_stops, budget_s):
    """ranked: nodes, highest priority first. Drop the lowest-priority stop until driving plus service fits."""
    keep = ranked[:max_stops]
    while keep:
        path = order(d, keep)
        if path_cost(d, path) + SERVICE_MIN * 60 * len(path) <= budget_s:
            return path
        keep = keep[:-1]
    return []


# ---- planner ----

def people(kiln):
    return kiln['exposure']['people']


def select(request, kilns):
    """The candidates (at most max_stops, highest priority first) and the counts left out. Raises NoKilns."""
    left_out = {}
    if request['kiln_ids'] is not None:
        wanted = set(request['kiln_ids'])
        kilns = [k for k in kilns if k['kiln_id'] in wanted]
        left_out['not_found'] = len(wanted) - len(kilns)
    # The sheet needs a people count, so a kiln without an exposure estimate is left out, never ranked as zero.
    usable = [k for k in kilns if isinstance(k.get('exposure'), dict) and isinstance(k['exposure'].get('people'), int)]
    left_out['no_exposure'] = len(kilns) - len(usable)
    if request['priority'] == 'flags':
        usable.sort(key=lambda k: (-len(k.get('violations') or []), -people(k), k['kiln_id']))
    else:
        usable.sort(key=lambda k: (-people(k), k['kiln_id']))
    if not usable:
        raise NoKilns()
    return usable[:min(request['max_stops'], MAX_KILNS)], left_out


def centroid(kiln):
    c = kiln['footprint']['centroid']
    return [round(c['longitude'], 6), round(c['latitude'], 6)]


def matrix(geo, start, points, metrics):
    """Driving seconds: rows are the start and every kiln, columns every kiln. Failed cells are None."""
    started = time.monotonic()
    try:
        reply = geo.calculate_route_matrix(
            Origins=[{'Position': p} for p in [start] + points], Destinations=[{'Position': p} for p in points],
            TravelMode='Car', RoutingBoundary={'Unbounded': True}, Traffic={'Usage': 'IgnoreTrafficData'})
        rows = [[cell.get('Duration') if 'Error' not in cell else None for cell in row] for row in reply['RouteMatrix']]
    except Exception:
        raise RoutingUnavailable() from None   # never echo provider text
    finally:
        metrics['location_ms'] = metrics.get('location_ms', 0) + int((time.monotonic() - started) * 1000)
    metrics['matrix_cells'] = (len(points) + 1) * len(points)
    if len(rows) != len(points) + 1 or any(len(r) != len(points) for r in rows):
        raise RoutingUnavailable()
    # d[i][j] with node 0 the start and node j the j-th kiln; nothing ever drives back to the start.
    return [[0] + row for row in rows]


def simplify(line):
    # ponytail: every n-th vertex plus the last, not Douglas-Peucker; fine for a ~200 point preview line.
    step = math.ceil(len(line) / MAX_LEG_POINTS) if len(line) > MAX_LEG_POINTS else 1
    points = line[::step]
    if points[-1] != line[-1]: points.append(line[-1])
    return [[round(x, 6), round(y, 6)] for x, y in points]


def road_legs(geo, start, points, kiln_ids, metrics):
    """One CalculateRoutes call over the final order, or None if it fails (the contract allows no legs)."""
    started = time.monotonic()
    try:
        reply = geo.calculate_routes(
            Origin=start, Destination=points[-1], Waypoints=[{'Position': p} for p in points[:-1]],
            TravelMode='Car', LegGeometryFormat='Simple', LegAdditionalFeatures=['Summary'],
            Traffic={'Usage': 'IgnoreTrafficData'})
        legs = reply['Routes'][0]['Legs']
        if len(legs) != len(points): return None
        out = []
        for kiln_id, leg in zip(kiln_ids, legs):
            overview = leg['VehicleLegDetails']['Summary']['Overview']
            line = leg['Geometry']['LineString']
            if len(line) < 2: return None
            out.append({'to_kiln_id': kiln_id, 'distance_m': overview['Distance'], 'duration_s': overview['Duration'],
                        'geometry': {'type': 'LineString', 'coordinates': simplify(line)}})
        return out
    except Exception:
        return None
    finally:
        metrics['location_ms'] = metrics.get('location_ms', 0) + int((time.monotonic() - started) * 1000)


def sheet(kiln):
    flagged = [v['rule_id'] for v in kiln.get('violations') or []]
    labels = {c.get('rule_id'): c.get('check') for c in kiln.get('rule_checks') or []}
    checks = [CHECKS.get(r) or labels.get(r) for r in flagged]
    return {'rules_flagged': flagged, 'people_exposed': people(kiln),
            'on_site_checks': list(dict.fromkeys(c for c in checks if c)) + ALWAYS}


def stamp(moment, zone=IST):
    return moment.astimezone(zone).isoformat(timespec='seconds')


def plan(request, candidates, left_out, geo, now, metrics):
    """The route contract plus `notes`. Raises RoutingUnavailable when the matrix fails."""
    points = [centroid(k) for k in candidates]
    start = request['start']
    notes = []
    if start is None:
        start = [round(sum(p[0] for p in points) / len(points), 6), round(sum(p[1] for p in points) / len(points), 6)]
        notes.append(DEFAULT_START)
    else:
        start = [round(start['lon'], 6), round(start['lat'], 6)]
    d = matrix(geo, start, points, metrics)
    reachable = [j for j in range(1, len(points) + 1)
                 if d[0][j] is not None and all(d[i][j] is not None and d[j][i] is not None for i in range(1, len(points) + 1))]
    if not reachable: raise RoutingUnavailable()
    path = fit(d, reachable, request['max_stops'], request['budget_min'] * 60)
    stops = [candidates[j - 1] for j in path]
    legs = road_legs(geo, start, [points[j - 1] for j in path], [k['kiln_id'] for k in stops], metrics) if stops else None

    depart, t, body_stops = request['depart'], 0.0, []
    for n, (j, kiln) in enumerate(zip(path, stops)):
        t += legs[n]['duration_s'] if legs else d[([0] + path)[n]][j]
        eta = depart + timedelta(seconds=round(t / 60) * 60)
        lon, lat = points[j - 1]
        body_stops.append({'order': n + 1, 'kiln_id': kiln['kiln_id'], 'eta': stamp(eta), 'service_min': SERVICE_MIN,
                           'access': {'lat': lat, 'lon': lon, 'note': ACCESS_NOTE}, 'sheet': sheet(kiln)})
        t += SERVICE_MIN * 60

    if left_out.get('not_found'): notes.append(f"{left_out['not_found']} requested kiln IDs were not found among the flagged kilns of {request['district']}.")
    if left_out.get('no_exposure'): notes.append(f"{left_out['no_exposure']} kilns without an exposure estimate were left out, because the inspection sheet needs a people count.")
    if len(reachable) < len(points): notes.append(f'{len(points) - len(reachable)} kilns had no road route and were left out.')
    if 0 < len(path) < len(reachable): notes.append(f'{len(reachable) - len(path)} lower-priority kilns were left out to fit the {request["budget_min"]} minute budget.')
    if not path: notes.append(f'No stop fits the {request["budget_min"]} minute budget from this start.')
    if stops and legs is None: notes.append('Road legs are unavailable for this plan; ETAs use the matrix travel times.')

    inputs = {k: request[k] for k in ('district', 'budget_min', 'max_stops', 'priority', 'kiln_ids')}
    inputs.update(start=start, depart=stamp(depart, timezone.utc))
    digest = hashlib.sha256(json.dumps(inputs, sort_keys=True).encode()).hexdigest()[:8]
    body = {'district': request['district'],
            'generated_at': now.astimezone(timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z'),
            'route_id': f"plan-{depart.astimezone(IST).date()}-{request['district'].lower().replace(' ', '-')}-{digest}",
            'depart': stamp(depart), 'budget_min': request['budget_min'], 'stops': body_stops,
            **({'legs': legs} if legs is not None else {}),
            'kilns': stops, 'notes': notes + NOTES}
    metrics.update(stops=len(body_stops), legs=legs is not None)
    return body


def default_depart(now):
    """Tomorrow 09:00 Asia/Kolkata."""
    day = now.astimezone(IST).date() + timedelta(days=1)
    return datetime(day.year, day.month, day.day, 9, tzinfo=IST)
