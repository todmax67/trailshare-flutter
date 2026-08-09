#!/usr/bin/env python3
"""Costruisce assets/data/hut_openings.json dai dati OSM.

Produce il seed delle aperture per rifugi e bivacchi, nel formato che
`HutOpening.fromMap` sa leggere (lib/data/models/hut_opening.dart).

Due sorgenti di verita' diverse, ed e' il punto del file:

- **bivacchi** (`wilderness_hut`): non gestiti, sempre accessibili. La risposta
  viene dalla categoria, non dai dati. Sono ~2.662 punti su 6.468.
- **rifugi gestiti** (`alpine_hut`): serve `opening_hours`, e ce l'ha l'8%.

`updatedAt` non e' la data di questa importazione ma il **timestamp OSM
dell'ultima modifica dell'oggetto**: e' l'unico modo di sapere davvero quanto e'
vecchio il dato, ed e' cio' che permette alla UI di dichiararlo.

Uso:
    python3 scripts/build_hut_openings.py                 # Italia
    python3 scripts/build_hut_openings.py --pbf <file>
    python3 scripts/build_hut_openings.py --dry-run       # non scrive niente

Richiede `osmium` (brew install osmium-tool) e un estratto Geofabrik.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from calendar import monthrange
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DEFAULT_PBF = Path('/Volumes/Lexar/osm_data/italy-latest.osm.pbf')
OUT = REPO / 'assets' / 'data' / 'hut_openings.json'
POIS = REPO / 'assets' / 'data' / 'pois_italy_clean.json'

MONTHS = {m: i for i, m in enumerate(
    ['jan', 'feb', 'mar', 'apr', 'may', 'jun',
     'jul', 'aug', 'sep', 'oct', 'nov', 'dec'], start=1)}

# "2024 Apr 23-Nov 06", "Jun-Oct", "Jun 25-Sep 15". Il giorno e' opzionale su
# entrambi i lati; l'anno solo in testa.
_YEAR = re.compile(r'^\s*(\d{4})\b')
_RANGE = re.compile(
    r'\b(' + '|'.join(MONTHS) + r')\.?\s*(\d{1,2})?\s*-\s*'
    r'(' + '|'.join(MONTHS) + r')\.?\s*(\d{1,2})?',
    re.IGNORECASE)


def parse_opening_hours(raw: str):
    """Traduce un valore OSM `opening_hours` nel nostro modello.

    Ritorna (periods, esito) dove esito e' una delle etichette usate nel
    riepilogo. Non tenta di essere un parser completo della sintassi
    opening_hours: prende la finestra stagionale e butta via gli orari del
    giorno, che per un rifugio non servono a decidere se e' aperto in agosto.
    """
    s = (raw or '').strip()
    if not s:
        return [], 'vuoto'

    low = s.lower()

    if low in ('closed', 'off'):
        return [], 'dichiarato chiuso'

    if low.startswith('24/7'):
        # Un rifugio "sempre aperto" e' quasi sempre un bivacco mal taggato:
        # lo si segnala, la decisione la prende il chiamante sul tipo OSM.
        return [], 'sempre aperto'

    year = None
    m = _YEAR.match(s)
    if m:
        year = int(m.group(1))
        s = s[m.end():]

    r = _RANGE.search(s)
    if not r:
        # Resta roba tipo "Su" o "Sa,Su": e' un orario settimanale senza
        # stagione, che sulla domanda "e' aperto ad agosto?" non dice nulla.
        return [], 'solo settimanale'

    fm = MONTHS[r.group(1).lower()]
    fd = int(r.group(2)) if r.group(2) else 1
    tm = MONTHS[r.group(3).lower()]
    td = int(r.group(4)) if r.group(4) else monthrange(2001, tm)[1]

    # Difesa da giorni impossibili scritti a mano (31 novembre).
    fd = min(max(fd, 1), monthrange(2001, fm)[1])
    td = min(max(td, 1), monthrange(2001, tm)[1])

    period = {'from': {'m': fm, 'd': fd}, 'to': {'m': tm, 'd': td}}
    if year is not None:
        period['year'] = year

    return [period], ('dichiarata' if year else 'tipica')


def decode_osm_id(osm_id: str) -> str:
    """Riporta gli id di tipo *area* alla forma usata dal dataset dell'app.

    `osmium export` chiama `a<n>` gli oggetti chiusi trattati come poligoni,
    dove n = id_way * 2 per le way e id_relation * 2 + 1 per le relazioni. Il
    dataset dell'app viene da Overpass e usa `w<id>` / `r<id>`.

    Senza questa conversione il join perde 2.723 rifugi su 6.468 — il 42% —
    e sembra che manchino i dati mentre manca solo l'incastro delle chiavi.
    """
    if not osm_id.startswith('a'):
        return osm_id
    n = int(osm_id[1:])
    return f'w{n // 2}' if n % 2 == 0 else f'r{(n - 1) // 2}'


def run_osmium(pbf: Path, workdir: Path) -> Path:
    filtered = workdir / 'huts.osm.pbf'
    exported = workdir / 'huts.geojsonseq'
    print(f'estraggo rifugi e bivacchi da {pbf.name}…')
    subprocess.run(
        ['osmium', 'tags-filter', str(pbf),
         'n/tourism=alpine_hut,wilderness_hut',
         'w/tourism=alpine_hut,wilderness_hut',
         '-o', str(filtered), '--overwrite'],
        check=True, capture_output=True)
    subprocess.run(
        ['osmium', 'export', str(filtered), '-f', 'geojsonseq',
         '--add-unique-id=type_id', '-a', 'timestamp,version',
         '-o', str(exported), '--overwrite'],
        check=True, capture_output=True)
    return exported


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--pbf', type=Path, default=DEFAULT_PBF)
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()

    if not args.pbf.exists():
        print(f'estratto non trovato: {args.pbf}', file=sys.stderr)
        print('scaricalo da https://download.geofabrik.de/europe/italy.html',
              file=sys.stderr)
        return 1

    workdir = OUT.parent / '.osm_tmp'
    workdir.mkdir(parents=True, exist_ok=True)
    exported = run_osmium(args.pbf, workdir)

    # Solo i POI che l'app conosce davvero: importare aperture per punti che
    # non compaiono da nessuna parte non serve a nessuno.
    # pois_italy_clean.json e' un oggetto con metadati piu' la lista in 'pois'.
    poi_doc = json.load(open(POIS, encoding='utf-8'))
    poi_list = poi_doc['pois'] if isinstance(poi_doc, dict) else poi_doc
    known = {p['id'] for p in poi_list
             if p.get('type') in ('alpine_hut', 'wilderness_hut')}
    print(f'POI rifugio/bivacco nel dataset dell\'app: {len(known)}')

    out: dict[str, dict] = {}
    esiti = Counter()
    fuori_dataset = 0
    eta = []

    # osmium puo' emettere lo stesso oggetto due volte (una come way, una come
    # area): si tiene la variante piu' informativa, cioe' quella che ha
    # opening_hours, e a parita' la modificata piu' di recente.
    best: dict[str, dict] = {}
    for line in open(exported, encoding='utf-8'):
        line = line.strip().lstrip('\x1e')
        if not line:
            continue
        feat = json.loads(line)
        key = decode_osm_id(feat.get('id', ''))
        if key not in known:
            fuori_dataset += 1
            continue
        p = feat.get('properties', {})
        prev = best.get(key)
        if prev is None:
            best[key] = p
            continue
        score = (1 if p.get('opening_hours') else 0, p.get('@timestamp') or 0)
        prev_score = (1 if prev.get('opening_hours') else 0,
                      prev.get('@timestamp') or 0)
        if score > prev_score:
            best[key] = p

    for osm_id, props in best.items():
        kind_tag = props.get('tourism')

        ts = props.get('@timestamp')
        updated = (datetime.fromtimestamp(ts, tz=timezone.utc).isoformat()
                   if ts else None)
        if ts:
            eta.append((datetime.now(tz=timezone.utc)
                        - datetime.fromtimestamp(ts, tz=timezone.utc)).days)

        if kind_tag == 'wilderness_hut':
            # La categoria e' la risposta: nessun dato, nessuna scadenza.
            out[osm_id] = {'kind': 'bivacco'}
            esiti['bivacco (per categoria)'] += 1
            continue

        periods, esito = parse_opening_hours(props.get('opening_hours', ''))
        esiti[esito] += 1

        if not periods:
            # Senza periodi non si scrive niente: l'assenza di una voce e' gia'
            # "ignoto", e un file piu' piccolo e' un file piu' onesto.
            continue

        out[osm_id] = {
            'kind': 'gestito',
            'periods': periods,
            'source': 'osm',
            **({'updatedAt': updated} if updated else {}),
        }

    print(f'\nignorati perche\' non nel dataset dell\'app: {fuori_dataset}')
    print('\n--- esito del parsing ---')
    for k, v in esiti.most_common():
        print(f'   {k:26} {v:5}')

    gestiti = {k: v for k, v in out.items() if v['kind'] == 'gestito'}
    bivacchi = {k: v for k, v in out.items() if v['kind'] == 'bivacco'}
    print(f'\n--- risultato ---')
    print(f'   bivacchi risolti per categoria   {len(bivacchi):5}')
    print(f'   rifugi con un periodo vero       {len(gestiti):5}')

    if gestiti:
        scaduti = sum(1 for v in gestiti.values()
                      if any(p.get('year', 9999) < datetime.now().year
                             for p in v['periods']))
        print(f'   di cui gia\' scaduti              {scaduti:5}'
              '   (mostrati come "solo stagioni passate")')

    if eta:
        eta.sort()
        print(f'\n   eta\' del dato OSM: mediana {eta[len(eta)//2]//365} anni, '
              f'il piu\' vecchio {max(eta)//365} anni')

    if args.dry_run:
        print('\n--dry-run: non scrivo niente.')
        return 0

    payload = {
        'generatedAt': datetime.now(tz=timezone.utc).date().isoformat(),
        'source': args.pbf.name,
        'note': 'Generato da scripts/build_hut_openings.py. Non modificare a mano.',
        'openings': out,
    }
    OUT.write_text(json.dumps(payload, ensure_ascii=False, separators=(',', ':')),
                   encoding='utf-8')
    print(f'\nscritto {OUT.relative_to(REPO)} '
          f'({OUT.stat().st_size/1024:.0f} KB, {len(out)} voci)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
