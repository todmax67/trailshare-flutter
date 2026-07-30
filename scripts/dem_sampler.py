#!/usr/bin/env python3
"""Campiona quote da tile SRTM .hgt locali, con interpolazione bilineare.

I .hgt sono int16 big-endian, griglia NxN (3601 = 1 arcsec ~30m), riga 0 = bordo
NORD del tile. Nessuna libreria GIS necessaria: bastano numpy e un po' di
aritmetica. Serve al backfill delle geometrie del catalogo che hanno le quote a
zero (vedi scripts/backfill_trail_elevations.cjs).

Uso:
    echo '[[10.77,46.01],[10.78,46.02]]' | python3 dem_sampler.py /Volumes/Lexar/dem_data
Stampa un array JSON di quote (null dove il tile manca o il DEM è void).
"""
import json
import os
import sys

import numpy as np

VOID = -32768  # valore "no data" SRTM


class DemSampler:
    def __init__(self, dem_dir):
        self.dem_dir = dem_dir
        self._cache = {}
        self._missing = set()

    @staticmethod
    def tile_name(lon, lat):
        la, lo = int(np.floor(lat)), int(np.floor(lon))
        return "%s%02d%s%03d" % (
            "N" if la >= 0 else "S", abs(la),
            "E" if lo >= 0 else "W", abs(lo),
        )

    def _tile(self, name):
        if name in self._cache:
            return self._cache[name]
        if name in self._missing:
            return None
        path = os.path.join(self.dem_dir, name + ".hgt")
        if not os.path.exists(path):
            self._missing.add(name)
            return None
        size = os.path.getsize(path)
        n = int(round((size / 2) ** 0.5))
        if n * n * 2 != size:
            self._missing.add(name)
            return None
        # memmap: i tile pesano 25 MB ciascuno, non li teniamo tutti in RAM
        grid = np.memmap(path, dtype=">i2", mode="r").reshape(n, n)
        self._cache[name] = (grid, n)
        return self._cache[name]

    def sample(self, lon, lat):
        """Quota in metri, o None se non disponibile."""
        got = self._tile(self.tile_name(lon, lat))
        if got is None:
            return None
        grid, n = got
        lat0, lon0 = np.floor(lat), np.floor(lon)
        # frazione dentro il tile; riga 0 = nord, quindi la latitudine si inverte
        y = (1.0 - (lat - lat0)) * (n - 1)
        x = (lon - lon0) * (n - 1)
        r0, c0 = int(np.floor(y)), int(np.floor(x))
        r1, c1 = min(r0 + 1, n - 1), min(c0 + 1, n - 1)
        if not (0 <= r0 < n and 0 <= c0 < n):
            return None
        fy, fx = y - r0, x - c0
        q = [float(grid[r0, c0]), float(grid[r0, c1]),
             float(grid[r1, c0]), float(grid[r1, c1])]
        if any(v == VOID for v in q):
            # bordo di un buco: ripiega sul nearest valido, meglio che nulla
            valid = [v for v in q if v != VOID]
            return sum(valid) / len(valid) if valid else None
        top = q[0] * (1 - fx) + q[1] * fx
        bot = q[2] * (1 - fx) + q[3] * fx
        return top * (1 - fy) + bot * fy

    def sample_many(self, coords):
        """coords: [[lon, lat], ...] -> [quota|None, ...]"""
        return [self.sample(c[0], c[1]) for c in coords]


def main():
    dem_dir = sys.argv[1] if len(sys.argv) > 1 else "/Volumes/Lexar/dem_data"
    coords = json.load(sys.stdin)
    out = DemSampler(dem_dir).sample_many(coords)
    json.dump([None if v is None else round(v, 1) for v in out], sys.stdout)


if __name__ == "__main__":
    main()
