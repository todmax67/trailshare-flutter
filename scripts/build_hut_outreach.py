#!/usr/bin/env python3
"""Estrae la lista dei rifugi da contattare, da OpenStreetMap.

Serve al lato B2B: i gestori sono l'unica fonte possibile delle aperture (vedi
docs/rifugi_aperture.md — OSM ne copre l'8%), e questo e' l'elenco di chi si
puo' raggiungere.

**Il CSV non va nel repo.** Sono recapiti di persone reali: un file cosi' dentro
git resta nella cronologia per sempre anche dopo un `git rm`. Di default finisce
in /Volumes/Lexar/outreach/, fuori dal progetto.

Due vincoli da conoscere prima di usarlo:

- **ODbL.** I dati vengono da OpenStreetMap. Se ne deriva materiale pubblico va
  attribuito ("© contributori OpenStreetMap"); l'uso interno per contattare
  qualcuno non fa scattare la clausola di condivisione allo stesso modo.
- **Contatti B2B.** Sono recapiti aziendali pubblicati dagli stessi gestori, e
  il legittimo interesse copre il primo contatto commerciale — a condizione che
  la mail dica chi siamo, dove abbiamo preso il recapito e come farsi togliere,
  e che chi si toglie non venga ricontattato. Alcuni numeri sono cellulari
  privati di gestori individuali: trattarli come dati personali.

Uso:
    python3 scripts/build_hut_outreach.py
    python3 scripts/build_hut_outreach.py --out <file.csv>
    python3 scripts/build_hut_outreach.py --regione lombardia
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import subprocess
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DEFAULT_PBF = Path('/Volumes/Lexar/osm_data/italy-latest.osm.pbf')
DEFAULT_OUT = Path('/Volumes/Lexar/outreach')
REGIONS_DART = REPO / 'lib' / 'core' / 'constants' / 'geo_regions.dart'
OPENINGS = REPO / 'assets' / 'data' / 'hut_openings.json'

PHONE = ('phone', 'contact:phone', 'contact:mobile')
EMAIL = ('email', 'contact:email')
SITE = ('website', 'contact:website', 'url')

# Le sezioni CAI e le societa' alpine gestiscono decine di rifugi a testa:
# contattare l'organizzazione vale piu' che contattare i singoli.
ORG = re.compile(r'\b(CAI|Club Alpino|SAT|Societ[aà] degli Alpinisti|'
                 r'Club Alpin|Alpenverein|AVS|Parco|Comune)\b', re.IGNORECASE)

_REGION_RE = re.compile(
    r"GeoRegion\(code:\s*'([^']+)',\s*countryCode:\s*'([^']+)',\s*"
    r"nameIt:\s*'([^']*)'.*?latMin:\s*([-\d.]+),\s*latMax:\s*([-\d.]+),\s*"
    r"lngMin:\s*([-\d.]+),\s*lngMax:\s*([-\d.]+)",
    re.DOTALL)


def load_regions():
    """Riusa le regioni definite dall'app invece di inventarne altre."""
    src = REGIONS_DART.read_text(encoding='utf-8')
    out = []
    for m in _REGION_RE.finditer(src):
        code, cc, name, la, lA, lo, lO = m.groups()
        la, lA, lo, lO = float(la), float(lA), float(lo), float(lO)
        if la == 0 and lA == 0:
            continue  # sentinella
        out.append((code, cc, name, la, lA, lo, lO))
    return out


def region_of(regions, lat, lng):
    for code, cc, name, la, lA, lo, lO in regions:
        if la <= lat <= lA and lo <= lng <= lO:
            return code, cc, name
    return '', '', ''


def first(props, keys):
    for k in keys:
        v = props.get(k)
        if v:
            return str(v).strip()
    return ''


def decode_osm_id(osm_id: str) -> str:
    """Vedi build_hut_openings.py: osmium chiama 'a<way*2>' gli oggetti chiusi."""
    if not osm_id.startswith('a'):
        return osm_id
    n = int(osm_id[1:])
    return f'w{n // 2}' if n % 2 == 0 else f'r{(n - 1) // 2}'


def run_osmium(pbf: Path, workdir: Path) -> Path:
    filtered = workdir / 'huts_out.osm.pbf'
    exported = workdir / 'huts_out.geojsonseq'
    print(f'estraggo da {pbf.name}…')
    subprocess.run(
        ['osmium', 'tags-filter', str(pbf),
         'n/tourism=alpine_hut,wilderness_hut',
         'w/tourism=alpine_hut,wilderness_hut',
         '-o', str(filtered), '--overwrite'],
        check=True, capture_output=True)
    subprocess.run(
        ['osmium', 'export', str(filtered), '-f', 'geojsonseq',
         '--add-unique-id=type_id', '-a', 'timestamp',
         '-o', str(exported), '--overwrite'],
        check=True, capture_output=True)
    return exported


def centroid(geom):
    """Un punto rappresentativo, che serve solo ad assegnare la regione.

    Vanno gestiti tutti e tre i tipi che osmium produce davvero: Point,
    **LineString** e MultiPolygon. Polygon non compare mai. Dimenticare
    LineString buttava via 1.021 righe su 2.290 senza dire niente.
    """
    if not geom:
        return None, None
    t, c = geom.get('type'), geom.get('coordinates')
    if t == 'Point':
        return c[1], c[0]
    if t == 'LineString':
        pts = c
    elif t == 'Polygon':
        pts = c[0]
    elif t == 'MultiPolygon':
        pts = c[0][0]
    elif t == 'MultiLineString':
        pts = c[0]
    else:
        return None, None
    if not pts:
        return None, None
    return sum(p[1] for p in pts) / len(pts), sum(p[0] for p in pts) / len(pts)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--pbf', type=Path, default=DEFAULT_PBF)
    ap.add_argument('--out', type=Path, default=None)
    ap.add_argument('--regione', default=None,
                    help='filtra per codice regione (es. lombardia)')
    args = ap.parse_args()

    if not args.pbf.exists():
        print(f'estratto non trovato: {args.pbf}', file=sys.stderr)
        return 1

    regions = load_regions()
    print(f'regioni caricate da geo_regions.dart: {len(regions)}')

    gia_note = set()
    if OPENINGS.exists():
        doc = json.loads(OPENINGS.read_text(encoding='utf-8'))
        gia_note = {k for k, v in doc.get('openings', {}).items()
                    if v.get('periods')}
    print(f'rifugi per cui abbiamo gia\' un periodo: {len(gia_note)}')

    workdir = DEFAULT_OUT / '.tmp'
    workdir.mkdir(parents=True, exist_ok=True)
    exported = run_osmium(args.pbf, workdir)

    best: dict[str, tuple] = {}
    for line in open(exported, encoding='utf-8'):
        line = line.strip().lstrip('\x1e')
        if not line:
            continue
        f = json.loads(line)
        key = decode_osm_id(f.get('id', ''))
        p = f.get('properties', {})
        prev = best.get(key)
        score = (1 if first(p, EMAIL + PHONE) else 0, p.get('@timestamp') or 0)
        if prev is None or score > prev[0]:
            best[key] = (score, p, f.get('geometry'))

    rows = []
    for key, (_, p, geom) in best.items():
        tel, mail, site = first(p, PHONE), first(p, EMAIL), first(p, SITE)
        if not (tel or mail or site):
            continue

        lat, lng = centroid(geom)
        if lat is None:
            continue
        rcode, ccode, rname = region_of(regions, lat, lng)
        if args.regione and rcode != args.regione:
            continue

        gestito = p.get('tourism') == 'alpine_hut'
        operator = p.get('operator', '')
        is_org = bool(ORG.search(operator)) if operator else False
        ha_aperture = key in gia_note

        if not gestito:
            prio = 'D · bivacco (di solito una sezione CAI, pitch diverso)'
        elif mail and not ha_aperture:
            prio = 'A · email, e delle aperture non sappiamo niente'
        elif mail:
            prio = 'B · email, aperture da confermare'
        else:
            prio = 'C · solo telefono o sito'

        ts = p.get('@timestamp')
        rows.append({
            'priorita': prio,
            'nome': p.get('name', ''),
            'tipo': 'rifugio' if gestito else 'bivacco',
            'regione': rname,
            'paese': ccode,
            'quota_m': p.get('ele', ''),
            'gestore': operator,
            'gestore_e_organizzazione': 'si' if is_org else '',
            'email': mail,
            'telefono': tel,
            'sito': site,
            'aperture_gia_note': 'si' if ha_aperture else '',
            'osm_id': key,
            'osm_ultima_modifica': (
                datetime.fromtimestamp(ts, tz=timezone.utc).date().isoformat()
                if ts else ''),
            'lat': f'{lat:.5f}',
            'lng': f'{lng:.5f}',
        })

    rows.sort(key=lambda r: (r['priorita'], r['regione'], r['nome']))

    out = args.out or (DEFAULT_OUT /
                       f'rifugi_contatti_{datetime.now().date().isoformat()}.csv')
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, 'w', encoding='utf-8', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)

    print(f'\n--- {len(rows)} contatti ---')
    for k, v in Counter(r['priorita'] for r in rows).most_common():
        print(f'   {v:5}  {k}')

    print('\n--- prime regioni ---')
    for k, v in Counter(r['regione'] for r in rows
                        if r['tipo'] == 'rifugio').most_common(8):
        print(f'   {v:5}  {k or "(fuori dalle regioni note)"}')

    print('\n--- organizzazioni che ne gestiscono piu\' d\'uno ---')
    orgs = Counter(r['gestore'] for r in rows
                   if r['gestore_e_organizzazione'] == 'si')
    for k, v in orgs.most_common(6):
        print(f'   {v:5}  {k[:50]}')

    print(f'\nscritto {out}')
    print('NON committarlo: contiene recapiti di persone reali.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
