"""Authenticated district-scoped registry reads, behind the HTTP API JWT authorizer."""
import json
import logging
import os
import re
from registry.contract import DISTRICT, ID, STATUSES
from registry.db import connect_from_env
from registry.store import Registry

log = logging.getLogger(__name__)


def response(status, body):
    return {'statusCode':status, 'headers':{'content-type':'application/json','cache-control':'no-store'},
            'body':json.dumps(body,allow_nan=False)}


def error(status, code, message):
    return response(status, {'error':{'code':code,'message':message}})


def identity(event):
    claims=event.get('requestContext',{}).get('authorizer',{}).get('jwt',{}).get('claims')
    if not isinstance(claims,dict) or not claims.get('sub'):
        return None,error(401,'unauthorized','A valid inspector identity is required.')
    client=os.environ.get('COGNITO_CLIENT_ID')
    if not client or claims.get('token_use')!='id' or claims.get('aud')!=client:
        return None,error(403,'forbidden_identity','This identity cannot read the registry.')
    groups=claims.get('cognito:groups',[])
    if isinstance(groups,str):
        try: groups=json.loads(groups)
        except ValueError: groups=[g.strip().strip("'\"") for g in groups.strip('[]').split(',')]
    district=claims.get('custom:district','')
    if not isinstance(groups,list) or 'inspector' not in groups or not isinstance(district,str) or not DISTRICT.fullmatch(district):
        return None,error(403,'forbidden_identity','Inspector role and district are required.')
    return district,None


def handle(event, registry_factory):
    method=event.get('requestContext',{}).get('http',{}).get('method')
    path=event.get('rawPath','')
    if method=='GET' and path=='/health':
        return response(200,{'status':'ok','service':'kilnwatch-api','registry_readiness':'not_checked'})
    if method=='GET' and path=='/public/kilns':
        return error(503,'publication_unavailable','Public registry publication is not available.')
    district,denied=identity(event)
    if denied: return denied
    if method=='POST' and path=='/jobs':
        return error(501,'not_implemented','Inference jobs are not implemented.')
    if method!='GET' or (path!='/kilns' and not path.startswith('/kilns/')):
        return error(404,'not_found','Endpoint not found.')
    query=event.get('queryStringParameters') or {}
    if path=='/kilns':
        requested=query.get('district','')
        status=query.get('status')
        cursor=query.get('cursor','')
        limit_text=query.get('limit','100')
        if (set(query)-{'district','status','cursor','limit'} or not isinstance(requested,str) or not DISTRICT.fullmatch(requested)
            or (status is not None and status not in STATUSES) or (cursor and not ID.fullmatch(cursor))
            or not re.fullmatch(r'[0-9]{1,3}',limit_text) or not 1<=int(limit_text)<=200):
            return error(400,'invalid_filter','District, status, cursor or limit is invalid.')
        if requested!=district:
            return error(403,'forbidden_district','This district is outside your read permissions.')
    else:
        kiln_id=path.removeprefix('/kilns/')
        if not ID.fullmatch(kiln_id) or query:
            return error(400,'invalid_id','Kiln ID or query is invalid.')
    try:
        with registry_factory() as registry:
            if path=='/kilns':
                return response(200,registry.list(district,status,cursor,int(limit_text)))
            record=registry.detail(kiln_id,district)
            return response(200,record) if record else error(404,'not_found','Kiln not found in your district.')
    except Exception as exc:
        # Never log connection strings, secret values or SQL text.
        log.error('Registry read failed: %s',type(exc).__name__)
        return error(503,'registry_unavailable','The registry is temporarily unavailable.')


def handler(event, context):
    from contextlib import contextmanager
    @contextmanager
    def registry():
        connection=connect_from_env()
        try: yield Registry(connection)
        finally: connection.close()
    return handle(event,registry)
