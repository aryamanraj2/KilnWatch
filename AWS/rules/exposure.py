"""People living near each kiln, from Meta / CIESIN High Resolution Settlement Layer (HRSL).
Fetched once per area to a local GeoTIFF (CC BY 4.0, keep under .local/), then summed offline.

A cell counts when its centre lies within RADIUS_M of the kiln footprint edge; cells are
~30 m, so the ring edge is resolved to about half a cell. Age layers are HRSL's modelled
splits of the same estimate, not separate counts."""
import os

import numpy as np
import shapely
from shapely.geometry import box

from . import engine

os.environ.setdefault('AWS_NO_SIGN_REQUEST', 'YES')
os.environ.setdefault('GDAL_DISABLE_READDIR_ON_OPEN', 'EMPTY_DIR')

RADIUS_M = 800                # matches C-HAB-800 and the concept's "people within 800 m"
VERSION = 'HRSL v1.5.2'
BASE = 'https://dataforgood-fb-data.s3.amazonaws.com/hrsl-cogs'
# Pinned tiles (lat 20-30 N, lon 70-80 E) rather than the moving "latest" mosaics.
TILE_BOUNDS = (70.0, 20.0, 80.0, 30.0)
LAYERS = {
    'people': f'{BASE}/hrsl_general/v1.5/cog_globallat_20_lon_70_general-v1.5.2.tif',
    'children_under_five': f'{BASE}/hrsl_children_under_five/v1.5/cog_globallat_20_lon_70_children_under_five-v1.5.2.tif',
    'adults_over_sixty': f'{BASE}/hrsl_elderly_60_plus/v1.5/cog_globallat_20_lon_70_elderly_60_plus-v1.5.2.tif',
}
ATTRIBUTION = 'Population: Meta and CIESIN High Resolution Settlement Layer (HRSL), CC BY 4.0'


def fetch(bbox, out):
    """Clip the three layers to bbox [w, s, e, n] into one 3-band GeoTIFF."""
    import rasterio
    from rasterio.windows import from_bounds
    w, s, e, n = bbox
    if not box(*TILE_BOUNDS).contains(box(w, s, e, n)):
        raise ValueError('area outside the pinned HRSL tile; add the neighbouring tile')
    bands, profile = [], None
    for url in LAYERS.values():
        with rasterio.open('/vsicurl/' + url) as src:
            win = from_bounds(w, s, e, n, src.transform).round_offsets().round_lengths()
            a = src.read(1, window=win, masked=True).filled(0).astype('float32')
            if profile is None:
                profile = {'driver': 'GTiff', 'dtype': 'float32', 'count': len(LAYERS), 'crs': src.crs,
                           'transform': src.window_transform(win), 'width': a.shape[1], 'height': a.shape[0],
                           'compress': 'deflate'}
            elif a.shape != (profile['height'], profile['width']):
                raise ValueError('HRSL layers are not on one grid')
            bands.append(a)
    out.parent.mkdir(parents=True, exist_ok=True)
    with rasterio.open(out, 'w', **profile) as dst:
        for i, (name, a) in enumerate(zip(LAYERS, bands), 1):
            dst.write(a, i)
            dst.set_band_description(i, name)
        dst.update_tags(source=VERSION, attribution=ATTRIBUTION, **{f'url_{k}': v for k, v in LAYERS.items()})
    return {k: round(float(b.sum())) for k, b in zip(LAYERS, bands)}


class Grid:
    """Population cells (lon/lat grid) with their centres projected to metres."""

    def __init__(self, bands, transform):
        self.bands = np.stack(bands)                       # (layer, row, col)
        rows, cols = np.indices(self.bands.shape[1:])
        lon, lat = transform * (cols + 0.5, rows + 0.5)
        x, y = engine._to_work(lon.ravel(), lat.ravel())
        self.centres = shapely.points(x, y)
        h, w = self.bands.shape[1:]
        self.coverage = box(*(transform * (0, h)), *(transform * (w, 0)))
        self.tree = shapely.STRtree(self.centres)

    @classmethod
    def load(cls, path):
        import rasterio
        with rasterio.open(path) as src:
            names = list(src.descriptions)
            if names != list(LAYERS):
                raise ValueError(f'unexpected population bands {names}')
            return cls([src.read(i + 1) for i in range(len(names))], src.transform)

    def counts(self, kiln_work, radius=RADIUS_M):
        """-> {people, children_under_five, adults_over_sixty}, or None if the ring leaves the grid."""
        ring = engine.transform(engine._to_ll, kiln_work.buffer(radius))
        if not self.coverage.contains(ring):
            return None
        idx = self.tree.query(kiln_work, predicate='dwithin', distance=radius)
        flat = self.bands.reshape(len(LAYERS), -1)[:, idx]
        return {name: int(round(float(v))) for name, v in zip(LAYERS, flat.sum(axis=1))}


def assess(kilns, grid, radius=RADIUS_M):
    """-> per kiln exposure dict, or None where the population grid does not cover the ring."""
    return [grid.counts(engine.transform(engine._to_work, engine.kiln_polygon(k)), radius) for k in kilns]
