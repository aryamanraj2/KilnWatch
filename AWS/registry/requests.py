"""Allowlisted resident request aggregates shared by reads and public writes."""
CONCERNS = ('smoke_or_ash', 'near_homes', 'near_school_or_hospital', 'other')
AGGREGATE_COLUMNS = '''count(*)::int AS count,
 count(*) FILTER (WHERE distance_band='under_1km')::int AS within_1km,
 jsonb_build_object('smoke_or_ash',count(*) FILTER (WHERE 'smoke_or_ash'=ANY(concerns)),
 'near_homes',count(*) FILTER (WHERE 'near_homes'=ANY(concerns)),
 'near_school_or_hospital',count(*) FILTER (WHERE 'near_school_or_hospital'=ANY(concerns)),
 'other',count(*) FILTER (WHERE 'other'=ANY(concerns))) AS concerns,
 (max(created_at) AT TIME ZONE 'Asia/Kolkata')::date AS last_request_on'''
AGGREGATE_JOIN = ''' LEFT JOIN (SELECT kiln_id,jsonb_build_object(
 'count',count,'within_1km',within_1km,'concerns',concerns,'last_request_on',last_request_on) AS resident_requests
 FROM (SELECT kiln_id,''' + AGGREGATE_COLUMNS + ''' FROM kilnwatch.inspection_requests GROUP BY kiln_id) a
 ) rr ON rr.kiln_id=c.kiln_id'''


def public_requests(value=None):
    """Only aggregate fields, including authoritative zeros for an empty registry group."""
    value = value or {}
    concerns = value.get('concerns') or {}
    return {'count': value.get('count', 0), 'within_1km': value.get('within_1km', 0),
            'concerns': {key: concerns.get(key, 0) for key in CONCERNS},
            'last_request_on': value.get('last_request_on')}


def aggregate(cursor, kiln_id):
    cursor.execute('SELECT ' + AGGREGATE_COLUMNS + ' FROM kilnwatch.inspection_requests WHERE kiln_id=%s', (kiln_id,))
    count, within, concerns, last = cursor.fetchone()
    return public_requests({'count': count, 'within_1km': within, 'concerns': concerns,
                            'last_request_on': last.isoformat() if last else None})
