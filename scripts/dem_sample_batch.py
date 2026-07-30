#!/usr/bin/env python3
"""Campiona le quote di MOLTI sentieri in una sola passata.

Il primo tentativo faceva uno spawn Python per sentiero (421 in totale): ogni
avvio rifaceva import numpy e memmap dei tile da zero, e su disco esterno non
finiva. Qui i tile si aprono una volta e restano in cache per tutti i sentieri.

Input  (file JSON):  {"<trailId>": [[lon, lat], ...], ...}
Output (file JSON):  {"<trailId>": [quota|null, ...], ...}

Uso:
    python3 dem_sample_batch.py in.json out.json /Volumes/Lexar/dem_data
"""
import json
import sys
import time

from dem_sampler import DemSampler


def main():
    in_path, out_path = sys.argv[1], sys.argv[2]
    dem_dir = sys.argv[3] if len(sys.argv) > 3 else "/Volumes/Lexar/dem_data"

    with open(in_path) as f:
        trails = json.load(f)

    sampler = DemSampler(dem_dir)
    out = {}
    tot_punti = sum(len(v) for v in trails.values())
    fatti = 0
    t0 = time.time()

    for i, (tid, coords) in enumerate(trails.items(), 1):
        out[tid] = [
            None if v is None else round(v, 1)
            for v in sampler.sample_many(coords)
        ]
        fatti += len(coords)
        if i % 25 == 0 or i == len(trails):
            el = time.time() - t0
            vel = fatti / el if el else 0
            print(
                "  %d/%d sentieri, %d/%d punti (%.0f pt/s, %.0fs)"
                % (i, len(trails), fatti, tot_punti, vel, el),
                flush=True,
            )

    with open(out_path, "w") as f:
        json.dump(out, f)
    print("scritto %s in %.0fs" % (out_path, time.time() - t0), flush=True)


if __name__ == "__main__":
    main()
