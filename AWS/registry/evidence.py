"""Validate evidence files and attach metadata without inventing publication URLs."""
import hashlib
import json
import math
from pathlib import Path
import struct
from urllib.parse import urlparse
from .contract import HASH, canonical, number, timestamp


def attach(records, manifest_path, input_hash, receipt_path=None):
    path = Path(manifest_path)
    raw = path.read_bytes()
    manifest = json.loads(raw)
    if manifest['schema_version'] != 1 or manifest['input_sha256'] != input_hash:
        raise ValueError('evidence belongs to a different detection export')
    record_map = {r['observation_id']: r for r in records}
    if len({e['observation_id'] for e in manifest['entries']}) != len(manifest['entries']):
        raise ValueError('duplicate evidence entry')
    receipt = json.loads(Path(receipt_path).read_text()) if receipt_path else None
    if receipt and (receipt['manifest_sha256'] != hashlib.sha256(raw).hexdigest() or receipt['verified'] is not True):
        raise ValueError('publication receipt does not match manifest')
    base = receipt.get('base_url') if receipt else None
    if base:
        u = urlparse(base)
        if u.scheme != 'https' or not u.hostname or u.path not in ('','/') or u.query or u.fragment or u.username:
            raise ValueError('invalid distribution URL')
    published = {o['object_key']: o['sha256'] for o in receipt['objects']} if receipt else {}
    for entry in manifest['entries']:
        key = entry['observation_id']
        if key not in record_map:
            raise ValueError('evidence has no matching observation')
        record = record_map[key]['payload']
        if entry['model_sha256'] != record['provenance']['model_sha256']:
            raise ValueError('evidence/model mismatch')
        after = entry.get('after')
        if after is None:
            raise ValueError('evidence entry requires after, before may be unavailable')
        for side in ('before','after'):
            source = entry.get(side)
            if source is None: continue
            meta = dict(source)
            relative = Path(meta.pop('local_path'))
            local = (path.parent/relative).resolve()
            if relative.is_absolute() or not local.is_relative_to(path.parent.resolve()):
                raise ValueError('evidence path escapes manifest directory')
            data = local.read_bytes()
            if data[:8] != b'\x89PNG\r\n\x1a\n' or struct.unpack('>II', data[16:24]) != (256,256):
                raise ValueError('evidence must be a 256 x 256 PNG')
            sha = hashlib.sha256(data).hexdigest()
            if meta['sha256'] != sha or meta['object_key'] != 'evidence/'+sha+'.png':
                raise ValueError('evidence checksum/key mismatch')
            if meta['patch_px'] != 256 or meta['gsd_m'] != 10 or not meta['attribution'].startswith('Contains modified Copernicus Sentinel data '):
                raise ValueError('size/resolution/attribution missing')
            if meta.get('published_url') is not None:
                raise ValueError('manifest cannot assert a published URL')
            t = meta['geotransform']
            if len(t) != 6 or t[1:] != [10,0,t[3],0,-10] or not all(math.isfinite(v) for v in t):
                raise ValueError('invalid 10m north-up grid')
            number(meta['nodata_fraction'],0,0.01)
            acquired = timestamp(meta['acquired_at'])
            if side == 'after':
                if meta['scene_id'] != record['provenance']['scene_id'] or acquired != record['last_seen']:
                    raise ValueError('after scene/acquisition mismatch')
                pixels = meta['footprint_px']
                if len(pixels) != 4:
                    raise ValueError('four footprint pixel corners required')
                from pyproj import Transformer
                transformer = Transformer.from_crs('EPSG:4326', meta['crs'], always_xy=True)
                for coordinate, pixel in zip(record['footprint']['polygon'], pixels):
                    if len(pixel) != 2: raise ValueError('pixel axis pair required')
                    x,y = transformer.transform(coordinate['longitude'],coordinate['latitude'])
                    expected = ((x-t[0])/10,(t[3]-y)/10)
                    for v,e in zip(pixel,expected):
                        number(v,0,256)
                        if abs(v-e)>0.01: raise ValueError('footprint pixel placement differs from geometry')
            else:
                if meta['scene_id'] == after['scene_id'] or acquired >= timestamp(after['acquired_at']):
                    raise ValueError('before must be a distinct earlier scene')
                if meta['crs'] != after['crs'] or t != after['geotransform'] or meta['rendering'] != after['rendering'] or meta['footprint_px'] is not None:
                    raise ValueError('historical grid/rendering/unknown-outline mismatch')
            if receipt:
                if published.get(meta['object_key']) != sha:
                    raise ValueError('missing verified publication object')
                meta['published_url'] = base.rstrip('/')+'/'+meta['object_key']
                record['evidence'][side] = meta['published_url']
            record['evidence'][side+'_metadata'] = meta
    return hashlib.sha256(raw).hexdigest()
