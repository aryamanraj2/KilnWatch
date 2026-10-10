import copy
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch as mock_patch
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'Model'/'scripts'))
from fixtures import collection, records, event, MemoryRegistry, handle
from registry.contract import convert, serialize, observation_key, timestamp, public_view
from registry.store import persist
from registry.evidence import attach
from prepare_evidence import patch


class ConversionTests(unittest.TestCase):
    def convert(self,c): return convert(c,'Hapur','b'*64,'2026-10-09T15:00:00Z')
    def test_axis_timestamp_and_unknown_facts(self):
        p=records()[0]['payload']
        self.assertEqual(p['footprint']['polygon'][0],{'latitude':28.73,'longitude':77.78})
        self.assertEqual(len(p['footprint']['polygon']),4)
        self.assertEqual(p['last_seen'],'2026-10-05T05:41:03.148000Z')
        self.assertIsNone(p['exposure']);self.assertEqual(p['rules_assessment'],'not_evaluated')
        self.assertEqual(p['violations'],[]);self.assertEqual(p['type_verification'],'unverified')
        self.assertEqual(serialize(p)['status'],'flagged');self.assertIsNone(p['evidence']['before'])
    def test_unknown_type_preserved(self):
        c=collection();c['features'][0]['properties']['type']='Hoffmann'
        self.assertEqual(self.convert(c)[0]['payload']['type'],'Hoffmann')
    def test_date_only_not_invented(self):
        with self.assertRaises(ValueError): timestamp('2026-10-05')
        c=collection();c['kilnwatch']['scenes'][0]['acquired_at']='2026-10-05'
        with self.assertRaises(ValueError): self.convert(c)
    def test_date_from_source_and_mismatch(self):
        c=collection();del c['features'][0]['properties']['acquired_at']
        self.assertEqual(self.convert(c)[0]['payload']['last_seen'],records()[0]['payload']['last_seen'])
        c['features'][0]['properties']['scene_date']='2026-10-04'
        with self.assertRaises(ValueError):self.convert(c)
    def test_bad_geometry_and_confidences(self):
        for modify in [lambda f:f['geometry'].update(type='Point'),
                       lambda f:f['geometry']['coordinates'][0].pop(),
                       lambda f:f['geometry']['coordinates'][0][1].__setitem__(0,181),
                       lambda f:f['properties'].__setitem__('type_confidence',float('nan')),
                       lambda f:f['properties'].__setitem__('detection_confidence',1.1),
                       lambda f:f['properties'].__setitem__('centroid',[77,28])]:
            with self.subTest(modify=modify):
                c=collection();modify(c['features'][0])
                with self.assertRaises(ValueError): self.convert(c)
    def test_crossing_ring_rejected(self):
        c=collection();r=c['features'][0]['geometry']['coordinates'][0];r[1],r[2]=r[2],r[1]
        with self.assertRaises(ValueError):self.convert(c)
    def test_retry_reordering_and_rotated_ring(self):
        c=collection();f=copy.deepcopy(c['features'][0]);f['properties']['scene_id']='SYNTHETIC-B'
        c['kilnwatch']['scenes'].append({'id':'SYNTHETIC-B','acquired_at':'2026-10-05T05:41:03.148Z'})
        c['features'].append(f);a=self.convert(c);c['features'].reverse();b=self.convert(c)
        self.assertEqual(a,b)
        r=c['features'][0]['geometry']['coordinates'][0][:-1];r=r[1:]+r[:1];c['features'][0]['geometry']['coordinates']=[r+[r[0]]]
        self.assertEqual([x['observation_id'] for x in a],[x['observation_id'] for x in self.convert(c)])
    def test_human_decisions_serializer(self):
        p=serialize(records()[0]['payload'],'compliant','approved',{'rules_assessment':'evaluated','type_verification':'verified'})
        self.assertEqual(p['status'],'compliant');self.assertEqual(p['type_verification'],'verified')


class SpyCursor:
    rowcount=1
    def __init__(self,fail=False):self.sql=[];self.fail=fail
    def execute(self,sql,args=None):
        self.sql.append((sql,args))
        if self.fail and 'INSERT INTO kilnwatch.observations' in sql:raise RuntimeError('synthetic DB write failure')
    def fetchone(self):return ('Hapur',)
    def close(self):pass
class SpyConnection:
    def __init__(self,fail=False):self.cur=SpyCursor(fail);self.committed=False;self.rolled_back=False
    def cursor(self):return self.cur
    def commit(self):self.committed=True
    def rollback(self):self.rolled_back=True
class TransactionUnitTests(unittest.TestCase):
    def test_commit_and_no_human_state_update(self):
        conn=SpyConnection();result=persist(conn,records(),'b'*64,'a'*64)
        self.assertTrue(conn.committed);self.assertEqual(result['observations_inserted'],1)
        updates=[s for s,a in conn.cur.sql if s.startswith('UPDATE kilnwatch.candidates')]
        self.assertTrue(updates);self.assertTrue(all('status' not in s and 'assessment' not in s and 'review_state' not in s for s in updates))
    def test_write_failure_rolls_back(self):
        conn=SpyConnection(True)
        with self.assertRaises(RuntimeError):persist(conn,records(),'b'*64,'a'*64)
        self.assertTrue(conn.rolled_back);self.assertFalse(conn.committed)
    def test_whole_batch_validates_before_persistence(self):
        c=collection();bad=copy.deepcopy(c['features'][0]);bad['properties']['type_confidence']=-1;c['features'].append(bad)
        with self.assertRaises(ValueError):convert(c,'Hapur','b'*64,'2026-10-09T15:00:00Z')


@mock_patch.dict(os.environ,{'COGNITO_CLIENT_ID':'synthetic-client'})
class APITests(unittest.TestCase):
    def setUp(self):self.repo=MemoryRegistry()
    def test_list_detail_and_filtered_empty(self):
        result=handle(event(),self.repo.factory);body=json.loads(result['body'])
        self.assertEqual(result['statusCode'],200);self.assertIn('kilns',body);self.assertNotIn('items',body)
        kiln=body['kilns'][0];detail=handle(event('/kilns/'+kiln['kiln_id']),self.repo.factory)
        self.assertEqual(json.loads(detail['body']),kiln)
        self.assertEqual(json.loads(handle(event(query={'district':'Hapur','status':'confirmed'}),self.repo.factory)['body'])['kilns'],[])
    def test_missing_id_and_other_district_hidden(self):
        self.assertEqual(handle(event('/kilns/KW-0000'),self.repo.factory)['statusCode'],404)
        e=event('/kilns/'+self.repo.rows[0]['kiln_id']);e['requestContext']['authorizer']['jwt']['claims']['custom:district']='Meerut'
        self.assertEqual(handle(e,self.repo.factory)['statusCode'],404)
    def test_auth_fail_closed(self):
        self.assertEqual(handle(event(claims=False),self.repo.factory)['statusCode'],401)
        for name in ('sub','aud','token_use','cognito:groups','custom:district'):
            e=event();del e['requestContext']['authorizer']['jwt']['claims'][name]
            self.assertIn(handle(e,self.repo.factory)['statusCode'],(401,403))
        e=event();e['requestContext']['authorizer']['jwt']['claims']['token_use']='access'
        self.assertEqual(handle(e,self.repo.factory)['statusCode'],403)
        e=event();e['requestContext']['authorizer']['jwt']['claims']['cognito:groups']='[not-inspector]'
        self.assertEqual(handle(e,self.repo.factory)['statusCode'],403)
    def test_gateway_group_string(self):
        e=event();e['requestContext']['authorizer']['jwt']['claims']['cognito:groups']='[inspector]'
        self.assertEqual(handle(e,self.repo.factory)['statusCode'],200)
    def test_district_and_filter_denials(self):
        for q,code in [({'district':'Meerut'},403),({'district':'Hapur','status':'bad'},400),({'district':'Hapur','limit':'201'},400),({'district':'Hapur','cursor':'x'},400),({},400)]:
            self.assertEqual(handle(event(query=q),self.repo.factory)['statusCode'],code)
    def test_database_failure_not_empty(self):
        def failed():raise RuntimeError('password=do-not-expose')
        result=handle(event(),failed)
        self.assertEqual(result['statusCode'],503);self.assertNotIn('password',result['body']);self.assertIn('error',json.loads(result['body']))
    def test_pagination(self):
        self.repo.rows.append(copy.deepcopy(self.repo.rows[0]));self.repo.rows[-1]['kiln_id']='KW-'+'f'*32
        body=json.loads(handle(event(query={'district':'Hapur','limit':'1'}),self.repo.factory)['body'])
        self.assertIsNotNone(body['next_cursor']);self.assertEqual(len(body['kilns']),1)
        last=json.loads(handle(event(query={'district':'Hapur','limit':'1','cursor':body['next_cursor']}),self.repo.factory)['body'])
        self.assertEqual(len(last['kilns']),1);self.assertIsNone(last['next_cursor'])


class PublicAPITests(unittest.TestCase):
    """No-login resident reads: no claims, flagged only, allowlisted fields."""
    def setUp(self):self.repo=MemoryRegistry()
    def get(self,path='/public/kilns',query=None):
        e=event(path,query,claims=False);return handle(e,self.repo.factory)
    def test_allowlist_drops_internal_fields_and_keeps_swift_fields(self):
        p=records()[0]['payload'];p['evidence']['after_metadata']={'sha256':'d'*64,'scene_id':'SYNTHETIC-AFTER'};p['internal_note']='x'
        view=public_view(serialize(p,'flagged','pending',{'rules_assessment':'not_evaluated'}))
        for key in ('review_state','provenance','assessment','internal_note'):self.assertNotIn(key,view)
        for key in ('kiln_id','footprint','type','type_confidence','detection_confidence','first_seen','last_seen','violations',
                    'exposure','status','evidence','district','rules_assessment','type_verification'):self.assertIn(key,view)
        self.assertEqual(view['evidence']['after_metadata']['sha256'],'d'*64)
    def test_near_list_and_detail_need_no_claims(self):
        kiln_id=self.repo.rows[0]['kiln_id']
        for path,query in [('/public/kilns',{'lat':'28.73','lon':'77.78'}),('/public/kilns',{'lat':'-28','lon':'77.78','radius_m':'5000'}),
                           ('/public/kilns',{'district':'Hapur','limit':'1'}),('/public/kilns/'+kiln_id,None)]:
            with self.subTest(query=query):
                result=self.get(path,query);body=result['body']
                self.assertEqual(result['statusCode'],200);self.assertEqual(result['headers']['cache-control'],'public, max-age=60')
                self.assertIn(kiln_id,body);self.assertNotIn('review_state',body);self.assertNotIn('provenance',body)
        self.assertEqual(handle(event(claims=False),self.repo.factory)['statusCode'],401)
    def test_invalid_queries(self):
        for q in [{},{'lat':'28.73'},{'lat':'28.73','lon':'77.78','district':'Hapur'},{'district':'Hapur','status':'flagged'},
                  {'lat':'28.73','lon':'77.78','status':'flagged'},{'lat':'999','lon':'77.78'},{'lat':'28.73','lon':'-181'},
                  {'lat':'nan','lon':'77.78'},{'lat':'inf','lon':'77.78'},{'lat':'1e1','lon':'77.78'},{'lat':'28.73','lon':'77.78','radius_m':'99'},
                  {'lat':'28.73','lon':'77.78','radius_m':'5001'},{'lat':'28.73','lon':'77.78','radius_m':'99999'},{'lat':'28.73','lon':'77.78','radius_m':'2000.5'},
                  {'district':'Hapur','limit':'0'},{'district':'Hapur','limit':'201'},{'district':'Hapur','cursor':'x'},{'district':'1'},{'other':'x'}]:
            with self.subTest(q=q):
                result=self.get(query=q);self.assertEqual(result['statusCode'],400)
                self.assertEqual(result['headers']['cache-control'],'no-store');self.assertIn('code',json.loads(result['body'])['error'])
        self.assertEqual(self.get('/public/kilns/KW-x')['statusCode'],400)
        self.assertEqual(self.get('/public/kilns/'+self.repo.rows[0]['kiln_id'],{'x':'1'})['statusCode'],400)
    def test_non_flagged_hidden_like_unknown(self):
        unknown=self.get('/public/kilns/KW-'+'0'*32)
        self.repo.rows[0]['status']='confirmed';hidden=self.get('/public/kilns/'+self.repo.rows[0]['kiln_id'])
        self.assertEqual(unknown['statusCode'],404);self.assertEqual((hidden['statusCode'],hidden['body']),(404,unknown['body']))
        self.assertEqual(json.loads(self.get(query={'district':'Hapur'})['body'])['kilns'],[])
    def test_database_failure_is_503(self):
        def failed():raise RuntimeError('password=do-not-expose')
        for path,query in [('/public/kilns',{'lat':'28.73','lon':'77.78'}),('/public/kilns',{'district':'Hapur'}),('/public/kilns/'+self.repo.rows[0]['kiln_id'],None)]:
            result=handle(event(path,query,claims=False),failed)
            self.assertEqual(result['statusCode'],503);self.assertNotIn('password',result['body']);self.assertEqual(result['headers']['cache-control'],'no-store')


def synthetic_scene(directory,scene_id,acquired,shift=0,nodata=False):
    import numpy as np
    import rasterio
    from rasterio.transform import from_origin
    assets={}
    for i,name in enumerate(('red','green','blue')):
        path=directory/(scene_id+'-'+name+'.tif')
        data=np.full((512,512),1800+i*100,dtype='uint16')
        if nodata:data[:]=0
        with rasterio.open(path,'w',driver='GTiff',width=512,height=512,count=1,dtype='uint16',
                           crs='EPSG:32643',transform=from_origin(769000+shift,3184000,10,10),nodata=0) as dst:dst.write(data,1)
        assets[name]={'href':str(path),'raster:bands':[{'scale':0.0001,'offset':-0.1,'nodata':0}]}
    return {'id':scene_id,'properties':{'datetime':acquired,'grid:code':'SYNTHETIC-GRID'},'assets':assets}


class EvidenceTests(unittest.TestCase):
    def test_dimensions_grid_checksum_and_unavailable_before(self):
        from PIL import Image
        with tempfile.TemporaryDirectory() as d:
            directory=Path(d);record=records()[0]['payload'];scene=synthetic_scene(directory,'SYNTHETIC-AFTER',record['last_seen'])
            meta,grid=patch(scene,record,directory/'images')
            self.assertEqual(Image.open(directory/'images'/meta['local_path']).size,(256,256))
            self.assertEqual(meta['sha256'],hashlib.sha256((directory/'images'/meta['local_path']).read_bytes()).hexdigest())
            before=synthetic_scene(directory,'SYNTHETIC-BEFORE','2023-12-05T05:40:56.807Z')
            bmeta,_=patch(before,record,directory/'images',grid,True)
            self.assertEqual(bmeta['geotransform'],meta['geotransform']);self.assertIsNone(bmeta['footprint_px'])
            manifest={'schema_version':1,'input_sha256':'b'*64,'entries':[{'observation_id':records()[0]['observation_id'],'model_sha256':'a'*64,'before':None,'after':meta}]}
            file=directory/'images'/'manifest.json';file.write_text(json.dumps(manifest));result=records();attach(result,file,'b'*64)
            self.assertIsNone(result[0]['payload']['evidence']['before']);self.assertIsNone(result[0]['payload']['evidence']['after'])
            self.assertEqual(len(result[0]['payload']['evidence']['after_metadata']['footprint_px']),4)
            manifest['entries'][0]['after']['sha256']='c'*64;file.write_text(json.dumps(manifest))
            with self.assertRaises(ValueError):attach(records(),file,'b'*64)
    def test_nodata_and_grid_mismatch_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            directory=Path(d);record=records()[0]['payload'];scene=synthetic_scene(directory,'A',record['last_seen'])
            _,grid=patch(scene,record,directory/'images')
            shifted=synthetic_scene(directory,'B','2023-12-05T05:40:56Z',shift=1)
            with self.assertRaises(ValueError):patch(shifted,record,directory/'images',grid,True)
            empty=synthetic_scene(directory,'C',record['last_seen'],nodata=True)
            with self.assertRaises(ValueError):patch(empty,record,directory/'images')


class ReadCursor:
    def __init__(self):self.last='';self.closed=False
    def execute(self,sql,args):self.last=sql
    def fetchall(self):
        if self.last.startswith('SELECT side,metadata'):return []
        from datetime import datetime,timezone
        p=records()[0]['payload'];d=datetime(2026,10,5,5,41,3,148000,tzinfo=timezone.utc)
        return [(p['kiln_id'],'confirmed','approved',{},d,d,p,records()[0]['observation_id'])]
    def close(self):self.closed=True
class PersistedReadUnitTests(unittest.TestCase):
    def test_pg8000_cursor_without_context_manager_and_human_status(self):
        from registry.store import Registry
        class Conn:
            def __init__(self):self.cur=ReadCursor()
            def cursor(self):return self.cur
        conn=Conn();body=Registry(conn).list('Hapur')
        self.assertTrue(conn.cur.closed);self.assertEqual(body['kilns'][0]['status'],'confirmed')
        self.assertEqual(body['kilns'][0]['review_state'],'approved')
        self.assertIsNone(body['kilns'][0]['evidence']['after'])


if __name__=='__main__':unittest.main()
