"""Explicitly synthetic inputs. Never real kiln evidence."""
import copy
from contextlib import contextmanager
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'lambda'))
from registry.contract import convert, serialize, digest
from api_handler import handle


def collection():
    return {'type':'FeatureCollection','kilnwatch':{
        'model_sha256':'a'*64,'model_version':'synthetic-unit-test',
        'confidence_semantics':'predicted_class_score_shared',
        'scenes':[{'id':'SYNTHETIC-AFTER','acquired_at':'2026-10-05T05:41:03.148Z'}]},
        'features':[{'type':'Feature','geometry':{'type':'Polygon','coordinates':[
            [[77.78,28.73],[77.781,28.73],[77.781,28.731],[77.78,28.731],[77.78,28.73]]]},
            'properties':{'type':'FCBK','type_confidence':0.95,'detection_confidence':0.95,
                          'scene_id':'SYNTHETIC-AFTER','scene_date':'2026-10-05',
                          'acquired_at':'2026-10-05T05:41:03.148Z','centroid':[77.7805,28.7305]}}]}


def records():
    return convert(collection(),'Hapur','b'*64,'2026-10-09T15:00:00Z')


def event(path='/kilns',query=None,claims=True):
    return {'rawPath':path,'queryStringParameters':{'district':'Hapur'} if query is None and path=='/kilns' else query,
            'requestContext':{'http':{'method':'GET'},'authorizer':{'jwt':{'claims':{
                'sub':'synthetic-sub','token_use':'id','aud':'synthetic-client',
                'cognito:groups':'["inspector"]','custom:district':'Hapur'}}} if claims else {}}}


class MemoryRegistry:
    """API-only test double. Not database persistence proof."""
    def __init__(self, source=None):
        self.rows=[serialize(r['payload']) for r in (source or records())]
    def list(self,district,status=None,cursor='',limit=100):
        rows=sorted([r for r in self.rows if r['district']==district and (status is None or r['status']==status) and r['kiln_id']>cursor],key=lambda r:r['kiln_id'])
        return {'kilns':rows[:limit],'next_cursor':rows[limit-1]['kiln_id'] if len(rows)>limit else None}
    def detail(self,kiln_id,district):
        return next((r for r in self.rows if r['kiln_id']==kiln_id and r['district']==district),None)
    def public_near(self,lat,lon,radius_m):
        # Distance is SQL-only (PostGIS test); the double returns flagged rows at a fixed distance.
        return {'kilns':[{**r,'distance_m':0} for r in self.rows if r['status']=='flagged'],'next_cursor':None}
    def public_list(self,district,cursor='',limit=100):return self.list(district,'flagged',cursor,limit)
    def public_detail(self,kiln_id):
        return next((r for r in self.rows if r['kiln_id']==kiln_id and r['status']=='flagged'),None)
    @contextmanager
    def factory(self): yield self
