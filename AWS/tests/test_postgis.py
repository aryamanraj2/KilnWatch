from contextlib import closing
"""Real persistence tests: opt in with KILNWATCH_TEST_DB_PORT for a disposable LOCAL PostGIS.
Never points at RDS. Only the dedicated disposable database named kilnwatch_test is allowed.
"""
import copy
import os
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parent))
from fixtures import records, collection
from registry.cli import migrate
from registry.contract import convert
from registry.store import Registry,persist


@unittest.skipUnless(os.getenv('KILNWATCH_TEST_DB_PORT'),'Disposable local PostgreSQL/PostGIS unavailable; persistence proof unrun')
class PostGISTests(unittest.TestCase):
    def setUp(self):
        import pg8000.dbapi
        self.conn=pg8000.dbapi.connect(host='127.0.0.1',port=int(os.environ['KILNWATCH_TEST_DB_PORT']),database='kilnwatch_test',user='postgres',password=os.environ['KILNWATCH_TEST_DB_PASSWORD'],ssl_context=False)
        migrate(self.conn);migrate(self.conn)
        with closing(self.conn.cursor()) as c:c.execute('TRUNCATE kilnwatch.import_runs, kilnwatch.candidates, kilnwatch.observations, kilnwatch.run_observations, kilnwatch.evidence CASCADE')
        self.conn.commit()
    def tearDown(self):self.conn.close()
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
        r=records();bad=copy.deepcopy(r[0]);bad['observation_id']='c'*64;bad['payload']['kiln_id']='KW-'+'c'*32
        bad['geometry']={'type':'Polygon','coordinates':[[[0,0],[1,1],[1,0],[0,1],[0,0]]]}
        with self.assertRaises(Exception):persist(self.conn,r+[bad],'b'*64,'a'*64)
        with closing(self.conn.cursor()) as cur:
            for table in ('import_runs','candidates','observations','run_observations'):
                cur.execute('SELECT COUNT(*) FROM kilnwatch.'+table);self.assertEqual(cur.fetchone()[0],0)
