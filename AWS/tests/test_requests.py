"""Synthetic request validation, transaction, aggregate and privacy checks."""
import base64
from datetime import date, datetime, timezone
import json
import os
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock, patch
from uuid import uuid4
sys.path.insert(0,str(Path(__file__).parent))
from fixtures import MemoryRegistry, event, handle as public_handle, records
from registry.cli import migrate
from registry.requests import CONCERNS, aggregate, public_requests
from registry.contract import public_view
from registry.store import Registry, persist, reset_requests
from verdicts.requests import handle, record, validate
from verdicts.store import VerdictError

KILN='KW-'+'a'*32
CLIENT='a80d2cb8-9e91-4dfd-96fd-a3d6d4c24aa1'
NOW=datetime(2026,10,11,20,tzinfo=timezone.utc)

def body(): return {'kiln_id':KILN,'client_id':CLIENT,'concerns':['smoke_or_ash','near_homes'],'distance_band':'under_1km','lang':'en'}
def request(b=None): return {'routeKey':'POST /requests','headers':{'content-type':'application/json'},'body':json.dumps(body() if b is None else b)}

class ValidationTests(unittest.TestCase):
    def reject(self,e):
        with self.assertRaises(VerdictError) as caught: validate(e)
        self.assertEqual((caught.exception.status,caught.exception.code),(400,'invalid_request'))
    def test_hash_normalizes_uuid_and_never_retains_raw_id(self):
        a=validate(request());b=validate(request(body()|{'client_id':CLIENT.upper()}))
        self.assertEqual(a,b);self.assertNotIn('client_id',a);self.assertEqual(len(a['client_hash']),64)
    def test_each_missing_field(self):
        for key in body():
            b=body();del b[key];self.reject(request(b))
    def test_unknown_key_and_wrong_object_types(self):
        for b in [[],None,'text',1,body()|{'note':'x'},body()|{'client_hash':'a'*64}]:self.reject(request()|{'body':json.dumps(b)})
    def test_full_id_validation(self):
        for v in [None,[],{},1,'KW-0412',KILN.upper(),KILN+'x']:self.reject(request(body()|{'kiln_id':v}))
    def test_uuid_v4_required(self):
        for v in [None,[],1,'','a'*32,'6f9619ff-8b86-d011-b42d-00c04fc964ff','a80d2cb8-9e91-4dfd-76fd-a3d6d4c24aa1']:
            self.reject(request(body()|{'client_id':v}))
    def test_concerns_all_branches(self):
        for v in [None,{},'other',[],[1],[{}],['x'],['other','other'],list(CONCERNS)+['other']]:self.reject(request(body()|{'concerns':v}))
        for v in [['other'],list(CONCERNS)]:self.assertEqual(validate(request(body()|{'concerns':v}))['concerns'],v)
    def test_distance_and_language(self):
        for key,good in [('distance_band',['under_1km','1_to_5km','over_5km','not_said']),('lang',['en','hi'])]:
            for v in [None,{},[],1,'',good[0].upper()]:self.reject(request(body()|{key:v}))
            for v in good:validate(request(body()|{key:v}))
    def test_content_type(self):
        for h in [{},{'content-type':'text/plain'},{'content-type':None}]:self.reject(request()|{'headers':h})
        validate(request()|{'headers':{'Content-Type':'Application/JSON; charset=utf-8'}})
    def test_body_json_duplicates_constants_and_byte_limit(self):
        for raw in [None,1,'','{','{"lang":"en","lang":"hi"}','NaN','Infinity','x'*4097,'\ud800']:
            self.reject(request()|{'body':raw})
        e=request();e['body']+=' '*(4096-len(e['body'].encode()));validate(e)
        self.reject(e|{'body':e['body']+' '})
        self.reject(request()|{'body':json.dumps(body()|{'extra':'界'*1500},ensure_ascii=False)})
    def test_base64_valid_and_invalid(self):
        e=request();e.update(body=base64.b64encode(e['body'].encode()).decode(),isBase64Encoded=True)
        self.assertEqual(validate(e),validate(request()))
        for raw in ['!!','x'*5465,base64.b64encode(b'x'*4097).decode(),base64.b64encode(b'\xff').decode()]:
            self.reject(e|{'body':raw})

class HandlerTests(unittest.TestCase):
    def test_success_duplicate_and_no_auth(self):
        for status in [201,200]:
            c=Mock();data={'kiln_id':KILN,'created':status==201,'resident_requests':public_requests()}
            with patch('verdicts.requests.record',return_value=(status,data)):
                out=handle(request()|{'headers':request()['headers']|{'Authorization':'ignored'}},lambda:c,NOW)
            self.assertEqual(out['statusCode'],status);c.commit.assert_called_once();c.close.assert_called_once()
            self.assertEqual(out['headers']['cache-control'],'no-store')
    def test_errors_and_rollback(self):
        for status,code,retry in [(404,'not_found',False),(429,'daily_cap_reached',True)]:
            c=Mock()
            with patch('verdicts.requests.record',side_effect=VerdictError(status,code,'Synthetic',retry)):
                out=handle(request(),lambda:c)
            self.assertEqual(json.loads(out['body'])['error'],{'code':code,'message':'Synthetic','retryable':retry})
            c.rollback.assert_called_once();c.commit.assert_not_called()
    def test_db_commit_and_cleanup_failures_are_sanitized(self):
        for where in ['connect','record','commit']:
            c=Mock();c.close.side_effect=RuntimeError('private')
            c.rollback.side_effect=RuntimeError('private')
            if where=='commit':c.commit.side_effect=RuntimeError('private')
            with patch('verdicts.requests.record',side_effect=RuntimeError('private') if where=='record' else None,
                       return_value=(201,{'resident_requests':public_requests()})):
                out=handle(request(),lambda:(_ for _ in ()).throw(RuntimeError('private')) if where=='connect' else c)
            self.assertEqual(out['statusCode'],503);self.assertNotIn('private',out['body'])
    def test_validation_does_not_open_db_and_log_keys_are_exact(self):
        factory=Mock()
        with self.assertLogs('verdicts.requests',level='INFO') as logs:out=handle(request({}),factory)
        factory.assert_not_called();self.assertEqual(out['statusCode'],400)
        facts=json.loads(logs.output[0].split(':',2)[2]);self.assertEqual(set(facts),{'count','status_code','latency_ms'})
    def test_success_log_privacy(self):
        with patch('verdicts.requests.record',return_value=(201,{'kiln_id':KILN,'resident_requests':public_requests()})),self.assertLogs('verdicts.requests',level='INFO') as logs:
            handle(request(),lambda:Mock())
        text=' '.join(logs.output)
        for private in [KILN,CLIENT,validate(request())['client_hash'],'under_1km','near_homes']:self.assertNotIn(private,text)
    def test_route_dispatch_keeps_verdict_path(self):
        from verdicts.handler import handler
        with patch('verdicts.requests.handle',return_value='request') as r,patch('verdicts.handler.handle',return_value='verdict') as v:
            self.assertEqual(handler(request(),None),'request');r.assert_called_once();v.assert_not_called()
            self.assertEqual(handler({'routeKey':'POST /verdicts'},None),'verdict');v.assert_called_once()

class TransactionTests(unittest.TestCase):
    def connection(self,rows):
        c=Mock();c.cursor.return_value.fetchone.side_effect=rows;return c
    def test_new_duplicate_missing_and_cap_sql(self):
        agg=(1,1,{'smoke_or_ash':1,'near_homes':1},date(2026,10,12))
        for created in [True,False]:
            c=self.connection([(KILN,),('uuid',) if created else None]+([(1,)] if created else [])+[agg])
            status,out=record(c,validate(request()),NOW)
            self.assertEqual(status,201 if created else 200);self.assertEqual(out['created'],created)
            sql=' '.join(call.args[0] for call in c.cursor.return_value.execute.call_args_list)
            self.assertEqual('request_days' in sql,created);self.assertIn('ON CONFLICT (kiln_id,client_hash) DO NOTHING',sql)
            self.assertNotIn('UPDATE kilnwatch.candidates',sql);c.commit.assert_not_called()
        for rows,code in [([None],'not_found'),([(KILN,),('uuid',),None],'daily_cap_reached')]:
            c=self.connection(rows)
            with self.assertRaises(VerdictError) as caught:record(c,validate(request()),NOW)
            self.assertEqual(caught.exception.code,code)
            if code=='not_found':self.assertNotIn('request_days',str(c.cursor.return_value.execute.call_args_list))
    def test_zero_and_ist_date(self):
        c=Mock();c.fetchone.return_value=(0,0,{k:0 for k in CONCERNS},None)
        self.assertEqual(aggregate(c,KILN),public_requests());self.assertIn("AT TIME ZONE 'Asia/Kolkata'",c.execute.call_args.args[0])
    def test_public_allowlist_and_all_read_shapes(self):
        class Repo(MemoryRegistry):
            def public_list(self,*args,include_inspected=False):return {'kilns':self.rows,'next_cursor':None}
            def public_near(self,*args,include_inspected=False):return self.public_list()
            def public_detail(self,*args,include_inspected=False):return self.rows[0]
        repo=Repo();raw=public_requests()|{'client_hash':'private','lang':'hi','request_id':'private'}
        repo.rows[0]['resident_requests']=raw
        for inspected in [False,True]:
            for path,q in [('/public/kilns',{'district':'Hapur'}),('/public/kilns',{'lat':'28.7','lon':'77.7'}),('/public/kilns/'+repo.rows[0]['kiln_id'],{})]:
                if inspected:q=q|{'include':'inspected'}
                out=json.loads(public_handle(event(path,q,False),repo.factory)['body']);k=out['kilns'][0] if 'kilns' in out else out
                self.assertEqual(k['resident_requests'],public_requests());self.assertNotIn('private',json.dumps(k))
    def test_trim_drops_request_aggregate(self):
        from assistant.tools import trim
        row=MemoryRegistry().rows[0]
        for detail in [False,True]:self.assertEqual(trim(row,detail),trim(row|{'resident_requests':{'count':12}},detail))
    def test_reset_requires_confirmation_full_id_and_uses_operator(self):
        from registry.cli import main
        for argv in [['cli','reset-requests','--kiln',KILN],['cli','reset-requests','--kiln','bad','--confirm']]:
            with patch.object(sys,'argv',argv),patch('registry.cli.connect_from_env') as connect,patch('sys.stderr'):
                with self.assertRaises(SystemExit):main()
                connect.assert_not_called()
        c=self.connection([(KILN,)])
        with patch.object(sys,'argv',['cli','reset-requests','--kiln',KILN,'--confirm']),patch('registry.cli.connect_from_env',return_value=c),patch('builtins.print'):
            main()
        sql=' '.join(call.args[0] for call in c.cursor.return_value.execute.call_args_list)
        self.assertIn('DELETE FROM kilnwatch.inspection_requests',sql);self.assertNotIn('request_days',sql);c.commit.assert_called_once()
        c=self.connection([None])
        with self.assertRaises(ValueError):reset_requests(c,KILN)
        with self.assertRaises(ValueError):reset_requests(c,'bad')

@unittest.skipUnless(os.getenv('KILNWATCH_TEST_DB_PORT'),'Disposable local PostGIS unavailable')
class RequestPostGISTests(unittest.TestCase):
    def connect(self):
        import pg8000.dbapi
        return pg8000.dbapi.connect(host='127.0.0.1',port=int(os.environ['KILNWATCH_TEST_DB_PORT']),database='kilnwatch_test',user='postgres',password=os.environ.get('KILNWATCH_TEST_DB_PASSWORD'),ssl_context=False)
    def setUp(self):
        self.c=self.connect();migrate(self.c);migrate(self.c)
        cur=self.c.cursor();cur.execute('TRUNCATE kilnwatch.import_runs,kilnwatch.candidates,kilnwatch.request_days CASCADE');cur.close();self.c.commit()
        persist(self.c,records(),'b'*64,'a'*64);self.kiln=records()[0]['payload']['kiln_id']
    def tearDown(self):self.c.rollback();self.c.close()
    def value(self,sql):
        cur=self.c.cursor();cur.execute(sql);row=cur.fetchone();cur.close();return row[0]
    def write(self,client=CLIENT):return record(self.c,validate(request(body()|{'kiln_id':self.kiln,'client_id':client})),NOW)
    def test_writer_permissions_and_reader_privacy(self):
        cur=self.c.cursor();cur.execute('SET LOCAL ROLE kilnwatch_request_writer')
        self.assertEqual(self.write()[0],201);self.assertEqual(self.write()[0],200);cur.execute('RESET ROLE')
        self.assertEqual(self.value('SELECT count FROM kilnwatch.request_days'),1)
        cur.execute('SET LOCAL ROLE kilnwatch_reader')
        self.assertEqual(Registry(self.c).public_detail(self.kiln)['resident_requests']['count'],1)
        cur.execute('RESET ROLE');cur.close()
        for col in ['client_hash','lang','request_id']:
            self.assertFalse(self.value(f"SELECT has_column_privilege('kilnwatch_reader','kilnwatch.inspection_requests','{col}','SELECT')"))
        self.assertFalse(self.value("SELECT has_table_privilege('kilnwatch_request_writer','kilnwatch.candidates','UPDATE')"))
        self.assertFalse(self.value("SELECT has_table_privilege('kilnwatch_request_writer','kilnwatch.inspection_requests','DELETE')"))
    def test_duplicate_at_cap_unknown_and_rollback(self):
        self.write();cur=self.c.cursor();cur.execute('UPDATE kilnwatch.request_days SET count=300');cur.close()
        self.assertEqual(self.write()[0],200)
        with self.assertRaises(VerdictError) as caught:self.write(str(uuid4()))
        self.assertEqual(caught.exception.status,429);self.c.rollback()
        self.assertEqual(self.value('SELECT count(*) FROM kilnwatch.inspection_requests'),0)
        with self.assertRaises(VerdictError) as caught:record(self.c,validate(request()),NOW)
        self.assertEqual(caught.exception.status,404);self.c.rollback()
        self.assertEqual(self.value('SELECT count(*) FROM kilnwatch.request_days'),0)
    def test_all_reads_zero_counts_ist_and_reset_status_unchanged(self):
        before=self.value("SELECT md5(string_agg(row_to_json(c)::text,'' ORDER BY kiln_id)) FROM kilnwatch.candidates c")
        r=Registry(self.c)
        self.assertEqual(r.public_detail(self.kiln)['resident_requests'],public_requests())
        self.write()
        for inspected in [False,True]:
            for row in [r.public_detail(self.kiln,inspected),r.public_list('Hapur',include_inspected=inspected)['kilns'][0],r.public_near(28.7305,77.7805,2000,include_inspected=inspected)['kilns'][0]]:
                self.assertEqual(row['resident_requests']['count'],1);self.assertEqual(row['resident_requests']['last_request_on'],'2026-10-12')
        reset_requests(self.c,self.kiln);self.assertEqual(r.public_detail(self.kiln)['resident_requests'],public_requests())
        self.assertEqual(self.value('SELECT count FROM kilnwatch.request_days'),1)
        self.assertEqual(self.value("SELECT md5(string_agg(row_to_json(c)::text,'' ORDER BY kiln_id)) FROM kilnwatch.candidates c"),before)
        self.c.rollback();self.assertEqual(self.value('SELECT count(*) FROM kilnwatch.request_days'),0)
    def test_concurrent_duplicate_consumes_one(self):
        import threading
        results=[];errors=[];barrier=threading.Barrier(2)
        def work():
            c=self.connect()
            try:
                barrier.wait(timeout=5);results.append(record(c,validate(request(body()|{'kiln_id':self.kiln})),NOW)[0]);c.commit()
            except Exception as e:errors.append(type(e).__name__);c.rollback()
            finally:c.close()
        threads=[threading.Thread(target=work) for _ in range(2)]
        for t in threads:t.start()
        for t in threads:t.join(timeout=10)
        self.assertEqual(errors,[]);self.assertEqual(sorted(results),[200,201]);self.assertEqual(self.value('SELECT count FROM kilnwatch.request_days'),1)

    def test_exact_grants_and_existing_login_membership(self):
        cur=self.c.cursor()
        cur.execute("CREATE ROLE kilnwatch_verdicts NOLOGIN")
        cur.execute((Path(__file__).parents[1]/'migrations/004_requests.sql').read_text())
        self.assertTrue(self.value("SELECT pg_has_role('kilnwatch_verdicts','kilnwatch_request_writer','MEMBER')"))
        expected={'candidates':{'SELECT'},'inspection_requests':{'SELECT','INSERT'},'request_days':{'SELECT','INSERT','UPDATE'}}
        for table,privs in expected.items():
            for privilege in ['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']:
                cur.execute('SELECT has_table_privilege(%s,%s,%s)',('kilnwatch_request_writer','kilnwatch.'+table,privilege))
                self.assertEqual(cur.fetchone()[0],privilege in privs)
        cur.execute("SELECT column_name FROM information_schema.column_privileges WHERE grantee='kilnwatch_reader' AND table_name='inspection_requests' AND privilege_type='SELECT'")
        self.assertEqual({r[0] for r in cur.fetchall()},{'kiln_id','concerns','distance_band','created_at'})
        self.assertFalse(self.value("SELECT rolcanlogin FROM pg_roles WHERE rolname='kilnwatch_request_writer'"))
        cur.close()
    def test_concurrent_global_cap_never_exceeds_300(self):
        import threading
        from test_postgis import many
        rows=many(2,'Hapur');persist(self.c,rows,'c'*64,'a'*64)
        cur=self.c.cursor();cur.execute('INSERT INTO kilnwatch.request_days VALUES (%s,299)',(NOW.date(),));cur.close();self.c.commit()
        barrier=threading.Barrier(2);results=[]
        def work(kiln):
            c=self.connect()
            try:
                barrier.wait(timeout=5)
                results.append(record(c,validate(request(body()|{'kiln_id':kiln,'client_id':str(uuid4())})),NOW)[0]);c.commit()
            except VerdictError as e:results.append(e.status);c.rollback()
            finally:c.close()
        ts=[threading.Thread(target=work,args=(r['payload']['kiln_id'],)) for r in rows]
        for t in ts:t.start()
        for t in ts:t.join(timeout=10)
        self.assertEqual(sorted(results),[201,429]);self.assertEqual(self.value('SELECT count FROM kilnwatch.request_days'),300)
        self.assertEqual(self.value('SELECT count(*) FROM kilnwatch.inspection_requests'),1)
