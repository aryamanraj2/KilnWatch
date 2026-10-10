"""python -m registry.cli {validate,import,migrate,validate-assessment,apply-assessment};
writes require explicit import/migrate/apply-assessment."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
from .contract import assessment_patches, convert, serialize
from .evidence import attach
from .store import apply_assessments, persist
from .db import connect_from_env


def prepare(path, district, evidence=None, receipt=None, imported_at=None):
    raw=Path(path).read_bytes(); sha=hashlib.sha256(raw).hexdigest()
    collection=json.loads(raw)
    records=convert(collection,district,sha,imported_at or datetime.now(timezone.utc).isoformat())
    evidence_sha=attach(records,evidence,sha,receipt) if evidence else None
    if receipt and not evidence: raise ValueError('receipt requires evidence')
    return records,sha,collection['kilnwatch']['model_sha256'],evidence_sha


def migrate(connection):
    cursor=connection.cursor()
    try:
        cursor.execute('SELECT pg_advisory_xact_lock(614092701)')
        cursor.execute('CREATE TABLE IF NOT EXISTS public.kilnwatch_schema_migrations (version text PRIMARY KEY, sha256 text NOT NULL, applied_at timestamptz NOT NULL DEFAULT now())')
        for path in sorted((Path(__file__).resolve().parents[1]/'migrations').glob('*.sql')):
            sha=hashlib.sha256(path.read_bytes()).hexdigest()
            cursor.execute('SELECT sha256 FROM public.kilnwatch_schema_migrations WHERE version=%s',(path.name,))
            row=cursor.fetchone()
            if row:
                if row[0]!=sha: raise ValueError('applied migration checksum changed')
                continue
            cursor.execute(path.read_text())
            cursor.execute('INSERT INTO public.kilnwatch_schema_migrations(version,sha256) VALUES (%s,%s)',(path.name,sha))
        connection.commit()
    except Exception:
        connection.rollback(); raise
    finally: cursor.close()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command',choices=['validate','import','migrate','validate-assessment','apply-assessment'])
    parser.add_argument('--detections',type=Path)
    parser.add_argument('--district')
    parser.add_argument('--evidence',type=Path)
    parser.add_argument('--publication-receipt',type=Path)
    parser.add_argument('--preview',type=Path)
    parser.add_argument('--assessment',type=Path,help='rules engine output (python -m rules.cli assess)')
    args=parser.parse_args()
    try:
        if args.command=='migrate':
            connection=connect_from_env()
            try: migrate(connection)
            finally: connection.close()
            print('{"migrations":"applied"}'); return
        if args.command.endswith('-assessment'):
            if not args.assessment: raise ValueError('--assessment required')
            body=json.loads(args.assessment.read_text())
            if args.command=='validate-assessment':
                patches=assessment_patches(body)
                print(json.dumps({'dry_run':True,'kilns':len(patches),'rules_version':body['rules_version'],
                                  'flags':sum(len(p['violations']) for _,p in patches)})); return
            connection=connect_from_env()
            try: print(json.dumps(apply_assessments(connection,body)))
            finally: connection.close()
            return
        if not args.detections or not args.district: raise ValueError('--detections and --district required')
        records,sha,model,evidence=prepare(args.detections,args.district,args.evidence,args.publication_receipt)
        if args.preview: args.preview.write_text(json.dumps({'kilns':[serialize(r['payload']) for r in records]},indent=2)+'\n')
        if args.command=='validate':
            print(json.dumps({'dry_run':True,'records':len(records),'input_sha256':sha,'evidence_sha256':evidence})); return
        connection=connect_from_env()
        try: print(json.dumps(persist(connection,records,sha,model,evidence)))
        finally: connection.close()
    except (ValueError,KeyError,TypeError,IndexError) as e:
        parser.error('invalid import: '+str(e))


if __name__=='__main__': main()
