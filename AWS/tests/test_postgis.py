from contextlib import closing
"""Real persistence tests: opt in with KILNWATCH_TEST_DB_PORT for a disposable LOCAL PostGIS.
Never points at RDS. Only the dedicated disposable database named kilnwatch_test is allowed.
"""
import copy
import importlib.util
import json
import os
from pathlib import Path
import sys
import types
import unittest
from unittest import mock
sys.path.insert(0,str(Path(__file__).resolve().parent))
from fixtures import records, collection
from registry.cli import migrate
from registry.contract import convert
from registry.store import Registry,persist

TABLES={'import_runs':'run_id','candidates':'status','observations':'scene_id','run_observations':'run_id','evidence':'metadata'}
URL='https://synthetic.invalid/evidence/'


def connect(user='postgres',password=None):
    import pg8000.dbapi
    return pg8000.dbapi.connect(host='127.0.0.1',port=int(os.environ['KILNWATCH_TEST_DB_PORT']),database='kilnwatch_test',
                                user=user,password=password or os.environ['KILNWATCH_TEST_DB_PASSWORD'],ssl_context=False)


def many(n,district,shift=0):
    """n synthetic non-overlapping kilns, 0.01 degree apart."""
    c=collection();f0=c['features'][0];c['features']=[]
    for i in range(n):
        f=copy.deepcopy(f0);d=(i+shift)*0.01
        f['geometry']['coordinates']=[[[x+d,y] for x,y in f0['geometry']['coordinates'][0]]]
        f['properties']['centroid']=[77.7805+d,28.7305];c['features'].append(f)
    return convert(c,district,'b'*64,'2026-10-09T15:00:00Z')


def with_evidence(r,sha,url=None):
    """Synthetic after-side metadata (and a synthetic receipt URL); never the real evidence pair."""
    r=copy.deepcopy(r);meta={'sha256':sha,'object_key':'evidence/'+sha+'.png','synthetic':True}
    if url:meta['published_url']=url+sha+'.png'
    r[-1]['payload']['evidence']['after_metadata']=meta
    return r


@unittest.skipUnless(os.getenv('KILNWATCH_TEST_DB_PORT'),'Disposable local PostgreSQL/PostGIS unavailable; persistence proof unrun')
class PostGISTests(unittest.TestCase):
    def setUp(self):
        import pg8000.dbapi
        self.conn=connect()
        migrate(self.conn);migrate(self.conn)
        with closing(self.conn.cursor()) as c:c.execute('TRUNCATE kilnwatch.import_runs, kilnwatch.candidates, kilnwatch.observations, kilnwatch.run_observations, kilnwatch.evidence CASCADE')
        self.conn.commit()
    def tearDown(self):
        # Roles are cluster-wide; this only ever runs against the disposable kilnwatch_test cluster.
        self.conn.rollback()
        with closing(self.conn.cursor()) as c:
            for role in ('kilnwatch_api','kilnwatch_test_importer','kilnwatch_test_assessor'):c.execute('DROP ROLE IF EXISTS '+role)
        self.conn.commit();self.conn.close()
    def count(self,table,where=''):
        with closing(self.conn.cursor()) as c:
            c.execute('SELECT COUNT(*) FROM kilnwatch.'+table+where);return c.fetchone()[0]
    def role_exists(self,name):
        with closing(self.conn.cursor()) as c:
            c.execute('SELECT 1 FROM pg_roles WHERE rolname=%s',(name,));return c.fetchone() is not None
    def denied(self,conn,sql):
        import pg8000.dbapi
        with closing(conn.cursor()) as c, self.assertRaises(pg8000.dbapi.DatabaseError) as e:c.execute(sql)
        conn.rollback();self.assertEqual(e.exception.args[0]['C'],'42501',sql)
    def test_retry_reorder_human_state_and_provenance(self):
        c=collection();f=copy.deepcopy(c['features'][0]);f['properties']['scene_id']='SYNTHETIC-B';c['features'].append(f)
        c['kilnwatch']['scenes'].append({'id':'SYNTHETIC-B','acquired_at':'2026-10-05T05:41:03.148Z'})
        r=convert(c,'Hapur','b'*64,'2026-10-09T15:00:00Z');self.assertEqual(persist(self.conn,r,'b'*64,'a'*64)['candidates_inserted'],2)
        with closing(self.conn.cursor()) as cur:cur.execute("UPDATE kilnwatch.candidates SET status='compliant',review_state='approved',assessment='{}'")
        self.conn.commit();c['features'].reverse()
        retry=convert(c,'Hapur','c'*64,'2026-10-09T16:00:00Z');result=persist(self.conn,retry,'c'*64,'a'*64)
        self.assertEqual(result['candidates_inserted'],0);self.assertEqual(result['observations_inserted'],0)
        payload=Registry(self.conn).list('Hapur')['kilns'];self.assertEqual(len(payload),2)
        self.assertTrue(all(p['status']=='compliant' and p['review_state']=='approved' for p in payload))
        with closing(self.conn.cursor()) as cur:
            cur.execute('SELECT COUNT(*) FROM kilnwatch.run_observations');self.assertEqual(cur.fetchone()[0],4)
            cur.execute('SELECT ST_SRID(footprint),ST_IsValid(footprint) FROM kilnwatch.observations');self.assertTrue(all(row==(4326,True) or list(row)==[4326,True] for row in cur.fetchall()))
    def test_mid_transaction_failure_rolls_back_every_table(self):
        r=with_evidence(records(),'d'*64);bad=copy.deepcopy(r[0]);bad['observation_id']='c'*64;bad['payload']['kiln_id']='KW-'+'c'*32
        bad['geometry']={'type':'Polygon','coordinates':[[[0,0],[1,1],[1,0],[0,1],[0,0]]]}
        with self.assertRaises(Exception):persist(self.conn,r+[bad],'b'*64,'a'*64)
        with closing(self.conn.cursor()) as cur:
            for table in TABLES:
                cur.execute('SELECT COUNT(*) FROM kilnwatch.'+table);self.assertEqual(cur.fetchone()[0],0)
    def test_evidence_republication_guard(self):
        r=records()
        persist(self.conn,with_evidence(r,'d'*64),'b'*64,'a'*64)       # first insert, unpublished
        persist(self.conn,with_evidence(r,'e'*64),'b'*64,'a'*64)       # unpublished -> unpublished may change bytes
        persist(self.conn,with_evidence(r,'d'*64,URL),'b'*64,'a'*64)   # synthetic receipt publishes
        persist(self.conn,with_evidence(r,'d'*64),'b'*64,'a'*64)       # replay without receipt keeps the URL
        kiln=Registry(self.conn).list('Hapur')['kilns'][0]
        self.assertEqual(kiln['evidence']['after'],URL+'d'*64+'.png')
        self.assertEqual(kiln['evidence']['after_metadata']['published_url'],kiln['evidence']['after'])
        with self.assertRaises(ValueError):
            persist(self.conn,many(1,'Hapur',shift=5)+with_evidence(r,'f'*64),'c'*64,'a'*64)
        self.assertEqual(self.count('candidates'),1);self.assertEqual(self.count('import_runs'),1)
        self.assertEqual(self.count('evidence'," WHERE sha256='"+'d'*64+"' AND metadata->>'published_url' IS NOT NULL"),1)
    def test_district_conflict_rolls_back(self):
        persist(self.conn,records(),'b'*64,'a'*64)
        moved=convert(collection(),'Meerut','c'*64,'2026-10-09T16:00:00Z')
        with self.assertRaises(ValueError):persist(self.conn,many(1,'Meerut',shift=3)+moved,'c'*64,'a'*64)
        self.assertEqual(self.count('candidates'),1);self.assertEqual(self.count('candidates'," WHERE district='Hapur'"),1)
        self.assertEqual(self.count('import_runs'),1)
    def test_migration_checksum_tamper_detected(self):
        real=Path.read_bytes
        def tampered(path):return real(path)+(b'\n-- tampered' if path.suffix=='.sql' else b'')
        with mock.patch.object(Path,'read_bytes',tampered),self.assertRaises(ValueError):migrate(self.conn)
        migrate(self.conn)
    def test_persisted_list_filters_pagination_and_detail(self):
        hapur=many(5,'Hapur');meerut=many(2,'Meerut',shift=10)
        persist(self.conn,hapur,'b'*64,'a'*64);persist(self.conn,meerut,'b'*64,'a'*64)
        ids=sorted(r['payload']['kiln_id'] for r in hapur)
        with closing(self.conn.cursor()) as cur:cur.execute("UPDATE kilnwatch.candidates SET status='confirmed' WHERE kiln_id=%s",(ids[1],))
        self.conn.commit();registry=Registry(self.conn);seen=[];cursor=''
        while True:
            page=registry.list('Hapur',cursor=cursor,limit=2);seen+=[k['kiln_id'] for k in page['kilns']]
            if page['next_cursor'] is None:break
            cursor=page['next_cursor']
        self.assertEqual(seen,ids);self.assertIsNone(registry.list('Hapur',limit=5)['next_cursor'])
        self.assertEqual([k['kiln_id'] for k in registry.list('Hapur','confirmed')['kilns']],[ids[1]])
        self.assertEqual(len(registry.list('Hapur','flagged')['kilns']),4);self.assertEqual(len(registry.list('Meerut')['kilns']),2)
        self.assertEqual(registry.detail(ids[1],'Hapur')['status'],'confirmed')
        self.assertIsNone(registry.detail(meerut[0]['payload']['kiln_id'],'Hapur'))
    def test_public_near_flagged_only_paging_and_detail(self):
        # Footprints sit 0.01 degree (~975 m) apart in longitude; the point lies inside kiln 0.
        hapur=many(5,'Hapur');persist(self.conn,hapur,'b'*64,'a'*64);persist(self.conn,many(2,'Meerut',shift=10),'b'*64,'a'*64)
        # convert() orders by observation key, so order IDs west to east.
        ids=[r['payload']['kiln_id'] for r in sorted(hapur,key=lambda r:r['payload']['footprint']['centroid']['longitude'])]
        with closing(self.conn.cursor()) as cur:cur.execute("UPDATE kilnwatch.candidates SET status='confirmed' WHERE kiln_id=%s",(ids[1],))
        self.conn.commit();registry=Registry(self.conn)
        def near(radius):return registry.public_near(28.7305,77.7805,radius)['kilns']
        self.assertEqual([(k['kiln_id'],k['distance_m']) for k in near(100)],[(ids[0],0)])
        wide=near(5000);distances=[k['distance_m'] for k in wide]
        self.assertEqual([k['kiln_id'] for k in wide],[ids[0],ids[2],ids[3],ids[4]])  # ids[1] confirmed, Meerut ~9.7 km
        self.assertEqual(distances,sorted(distances));self.assertTrue(all(0<d<=5000 for d in distances[1:]))
        self.assertTrue(all(k['status']=='flagged' for k in wide))
        self.assertEqual([k['kiln_id'] for k in near(2000)],[ids[0],ids[2]])
        self.assertEqual(registry.public_near(28.7305,77.7805,2000,limit=1)['kilns'][0]['kiln_id'],ids[0])
        self.assertEqual(registry.public_near(28.0,77.0,5000)['kilns'],[])
        seen=[];cursor=''
        while True:
            body=registry.public_list('Hapur',cursor,2);seen+=[k['kiln_id'] for k in body['kilns']]
            if body['next_cursor'] is None:break
            cursor=body['next_cursor']
        self.assertEqual(seen,sorted(set(ids)-{ids[1]}))
        self.assertEqual(registry.public_detail(ids[0])['kiln_id'],ids[0]);self.assertIsNone(registry.public_detail(ids[1]))
        self.assertIsNone(registry.public_detail('KW-'+'0'*32));self.assertNotIn('distance_m',registry.public_detail(ids[0]))
    def test_importer_role_persists_but_cannot_decide(self):
        with closing(self.conn.cursor()) as c:c.execute("CREATE ROLE kilnwatch_test_importer LOGIN PASSWORD 'synthetic-importer' IN ROLE kilnwatch_importer")
        self.conn.commit();importer=connect('kilnwatch_test_importer','synthetic-importer')
        try:
            r=with_evidence(records(),'d'*64)
            self.assertEqual(persist(importer,r,'b'*64,'a'*64)['observations_inserted'],1)
            persist(importer,with_evidence(r,'d'*64,URL),'b'*64,'a'*64);persist(importer,r,'b'*64,'a'*64)
            for sql in ("UPDATE kilnwatch.candidates SET status='confirmed'","UPDATE kilnwatch.candidates SET review_state='approved'",
                        "UPDATE kilnwatch.candidates SET assessment='{}'::jsonb"):self.denied(importer,sql)
        finally:importer.close()
        self.assertEqual(self.count('evidence'," WHERE metadata ? 'published_url'"),1)
    def test_assessor_writes_rule_keys_only(self):
        from registry.store import apply_assessments
        persist(self.conn,records(),'b'*64,'a'*64)
        kiln_id=records()[0]['payload']['kiln_id']
        with closing(self.conn.cursor()) as c:
            c.execute("UPDATE kilnwatch.candidates SET assessment='{\"exposure\":{\"people\":5}}'::jsonb")
            c.execute("CREATE ROLE kilnwatch_test_assessor LOGIN PASSWORD 'synthetic-assessor' IN ROLE kilnwatch_assessor")
        self.conn.commit();assessor=connect('kilnwatch_test_assessor','synthetic-assessor')
        flag={'rule_id':'UP-RAIL-200','measured_distance_m':142,'threshold_m':200,'source':'UP siting rules (2012)',
              'evidence_url':None,'measured_to':{'latitude':28.73,'longitude':77.78}}
        def body(*ids):
            return {'rules_version':'kilnwatch-rules-v1','assessed_at':'2026-10-10T06:00:00Z','inputs':{},
                    'assessments':[{'kiln_id':i,'rules_version':'kilnwatch-rules-v1','rules_assessment':'partially_evaluated',
                                    'violations':[flag],'rules_results':[{'rule_id':'UP-RAIL-200','status':'within_threshold'}]} for i in ids]}
        try:
            self.assertEqual(apply_assessments(assessor,body(kiln_id))['assessed'],1)
            apply_assessments(assessor,body(kiln_id))
            with self.assertRaises(ValueError):apply_assessments(assessor,body(kiln_id,'KW-'+'0'*32))
            for sql in ("UPDATE kilnwatch.candidates SET status='confirmed'","UPDATE kilnwatch.candidates SET review_state='approved'",
                        "UPDATE kilnwatch.candidates SET last_seen=now()","DELETE FROM kilnwatch.candidates"):self.denied(assessor,sql)
        finally:assessor.close()
        record=Registry(self.conn).detail(kiln_id,'Hapur')
        self.assertEqual(record['violations'],[flag]);self.assertEqual(record['rules_assessment'],'partially_evaluated')
        self.assertEqual(record['exposure'],{'people':5});self.assertEqual(record['status'],'flagged')
    def test_bootstrap_recovery_and_reader_is_select_only(self):
        spec=importlib.util.spec_from_file_location('bootstrap_reader',Path(__file__).resolve().parents[1]/'scripts'/'bootstrap_reader.py')
        boot=importlib.util.module_from_spec(spec);spec.loader.exec_module(boot);store={}
        class SecretsManager:  # In-process stub: no network, no AWS.
            def put_secret_value(self,SecretId,SecretString):store[SecretId]=json.loads(SecretString)
        def run(commit):
            conn=connect()
            class Wrapped:
                cursor=conn.cursor;rollback=conn.rollback;close=conn.close
                def commit(self):commit(conn)
            with mock.patch.dict(sys.modules,{'boto3':types.SimpleNamespace(client=lambda name:SecretsManager())}),\
                 mock.patch.dict(os.environ,{'REGISTRY_READER_SECRET':'synthetic-reader'}),mock.patch.object(boot,'connect_from_env',Wrapped):
                boot.main()
            return store['synthetic-reader']['password']
        def fail(conn):raise RuntimeError('synthetic commit failure')
        def landed(conn):conn.commit();raise RuntimeError('synthetic lost commit acknowledgement')
        with self.assertRaises(SystemExit):run(fail)
        self.assertFalse(self.role_exists('kilnwatch_api'));orphan=store['synthetic-reader']['password']
        password=run(lambda conn:conn.commit())  # no row: rerun recovers and overwrites the secret
        self.assertTrue(self.role_exists('kilnwatch_api'));self.assertNotEqual(password,orphan)
        persist(self.conn,records(),'b'*64,'a'*64);reader=connect('kilnwatch_api',password)
        try:
            for table,column in TABLES.items():
                with closing(reader.cursor()) as c:c.execute('SELECT COUNT(*) FROM kilnwatch.'+table);c.fetchone()
                self.denied(reader,'INSERT INTO kilnwatch.'+table+' DEFAULT VALUES')
                self.denied(reader,'UPDATE kilnwatch.'+table+' SET '+column+'='+column)
                self.denied(reader,'DELETE FROM kilnwatch.'+table)
            for column in ('review_state','assessment'):self.denied(reader,'UPDATE kilnwatch.candidates SET '+column+'='+column)
        finally:reader.close()
        with closing(self.conn.cursor()) as c:c.execute('DROP ROLE kilnwatch_api')
        self.conn.commit()
        with self.assertRaises(SystemExit):run(landed)  # a row: commit landed, secret matches
        self.assertTrue(self.role_exists('kilnwatch_api'));connect('kilnwatch_api',store['synthetic-reader']['password']).close()
        with self.assertRaises(SystemExit):run(lambda conn:conn.commit())  # rerun refuses the existing role
