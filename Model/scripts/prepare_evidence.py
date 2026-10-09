"""Cut aligned 256px Sentinel-2 evidence; no uploads, no training normalization.
Run from the repository root with the Integration 1 environment.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import sys

os.environ.setdefault('AWS_NO_SIGN_REQUEST','YES')
os.environ.setdefault('GDAL_DISABLE_READDIR_ON_OPEN','EMPTY_DIR')
os.environ.setdefault('CPL_VSIL_CURL_ALLOWED_EXTENSIONS','.tif')
import numpy as np
from PIL import Image
import rasterio
from rasterio.windows import Window
from pyproj import Transformer
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'AWS'))
from registry.contract import convert, timestamp

SIZE = 256
RENDERING = 'rgb_reflectance_fixed_0_0.3_gamma_1.0_v1'


def patch(item, record, out, target=None, historical=False):
    """Require the native after grid on every band/date; refuse misaligned imagery."""
    arrays=[]; masks=[]; sources=[]
    center=record['footprint']['centroid']
    for name in ('red','green','blue'):
        asset=item['assets'][name]
        radiometry=asset['raster:bands'][0]
        scale,offset=radiometry['scale'],radiometry['offset']
        with rasterio.open(asset['href']) as src:
            if src.crs is None or src.transform.b != 0 or src.transform.d != 0 or src.transform.a != 10 or src.transform.e != -10:
                raise ValueError('requires north-up native 10m scene')
            if not arrays and target is None:
                to_utm=Transformer.from_crs('EPSG:4326',src.crs,always_xy=True)
                cx,cy=to_utm.transform(center['longitude'],center['latitude'])
                col,row=(~src.transform)*(cx,cy)
                window=Window(int(np.floor(col))-SIZE//2,int(np.floor(row))-SIZE//2,SIZE,SIZE)
                grid=src.window_transform(window); crs=src.crs.to_string()
            elif not arrays:
                grid,crs=target
                if src.crs.to_string() != crs: raise ValueError('historical CRS differs')
                col,row=(~src.transform)*(grid.c,grid.f)
                if abs(col-round(col))>1e-7 or abs(row-round(row))>1e-7:
                    raise ValueError('historical pixel grid differs')
                window=Window(round(col),round(row),SIZE,SIZE)
            if window.col_off < 0 or window.row_off < 0 or window.col_off+SIZE>src.width or window.row_off+SIZE>src.height:
                raise ValueError('patch extends beyond scene; select a covering tile')
            if src.crs.to_string()!=crs or not src.window_transform(window).almost_equals(grid):
                raise ValueError('band/date grid differs')
            raw=src.read(1,window=window)
            mask=src.read_masks(1,window=window)>0
            if 'nodata' in radiometry: mask &= raw != radiometry['nodata']
            arrays.append(np.round(np.clip((raw.astype('float32')*scale+offset)/0.3,0,1)*255).astype('uint8'))
            masks.append(mask)
            sources.append({'band':name,'href':asset['href'],'scale':scale,'offset':offset})
    valid=np.logical_and.reduce(masks)
    nodata=float((~valid).mean())
    if nodata>0.01: raise ValueError(f'patch nodata {nodata:.3f} exceeds 1%')
    rgb=np.dstack(arrays); rgb[~valid]=0
    rgba=np.dstack((rgb,valid.astype('uint8')*255))
    out.mkdir(parents=True,exist_ok=True)
    temp=out/'patch.png'; Image.fromarray(rgba).save(temp,format='PNG',compress_level=9)
    sha=hashlib.sha256(temp.read_bytes()).hexdigest(); image=out/(sha+'.png'); temp.replace(image)
    transformer=Transformer.from_crs('EPSG:4326',crs,always_xy=True)
    def pixels(c):
        x,y=transformer.transform(c['longitude'],c['latitude'])
        col,row=(~grid)*(x,y)
        return [round(col,6),round(row,6)]
    acquired=timestamp(item['properties']['datetime'])
    meta={'local_path':image.name,'sha256':sha,'object_key':'evidence/'+sha+'.png',
          'scene_id':item['id'],'acquired_at':acquired,'patch_px':SIZE,'gsd_m':10,
          'crs':crs,'geotransform':list(grid.to_gdal()),'centroid_px':pixels(center),
          'footprint_px':None if historical else [pixels(c) for c in record['footprint']['polygon']],
          'attribution':'Contains modified Copernicus Sentinel data '+acquired[:4],
          'nodata_fraction':nodata,'rendering':RENDERING,'source_assets':sources,
          'grid_code':item['properties'].get('grid:code'),'scene_cloud_pct':item['properties'].get('eo:cloud_cover')}
    if not historical and any(not 0<=v<=SIZE for p in meta['footprint_px'] for v in p):
        raise ValueError('footprint does not fit evidence patch')
    return meta,(grid,crs)


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--detections',type=Path,required=True)
    ap.add_argument('--scenes',type=Path,required=True)
    ap.add_argument('--before-scene',type=Path,help='one saved historical STAC item; omit for unavailable before')
    ap.add_argument('--district',required=True)
    ap.add_argument('--index',type=int,default=0,help='one sorted observation for the initial proof')
    ap.add_argument('--out',type=Path,required=True)
    a=ap.parse_args()
    raw=a.detections.read_bytes(); sha=hashlib.sha256(raw).hexdigest()
    records=convert(json.loads(raw),a.district,sha,datetime.now(timezone.utc).isoformat())
    selected=records[a.index]; record=selected['payload']
    items=json.loads(a.scenes.read_text())['features']
    after=next(i for i in items if i['id']==record['provenance']['scene_id'])
    if timestamp(after['properties']['datetime'])!=record['last_seen']: raise ValueError('STAC time differs from detection')
    after_meta,grid=patch(after,record,a.out)
    before_meta=None
    if a.before_scene:
        before=json.loads(a.before_scene.read_text())
        if before['properties']['grid:code']!=after['properties']['grid:code'] or timestamp(before['properties']['datetime'])>=record['last_seen']:
            raise ValueError('historical scene must be earlier and on the same MGRS tile')
        before_meta,_=patch(before,record,a.out,target=grid,historical=True)
    manifest={'schema_version':1,'input_sha256':sha,'publication_state':'local_unpublished',
              'entries':[{'observation_id':selected['observation_id'],'model_sha256':record['provenance']['model_sha256'],
                          'before':before_meta,'after':after_meta}]}
    (a.out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps({'kiln_id':record['kiln_id'],'before_available':before_meta is not None,'manifest':str(a.out/'manifest.json')}))


if __name__=='__main__': main()
