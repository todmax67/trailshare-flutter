#!/usr/bin/env python3
"""Misura il posizionamento di TrailShare nella ricerca del Play Store.

Il gemello di `aso_rank.py`, che copre solo Apple. Fino al 2026-08-17 di Play
non sapevamo niente: il brief del lunedì lo dichiarava ogni settimana come
"non guardato", perché Google non ha un'API di ricerca pubblica come iTunes.

Non serve: la pagina dei risultati porta i pacchetti nell'ordine di
posizionamento dentro l'HTML, e leggerli basta. È una misura, non una stima.

## Cosa NON è

- **Non è il numero che vede l'utente.** Play personalizza i risultati per
  dispositivo, cronologia e paese; e il filtro "Questo dispositivo" cambia
  ancora le carte. Questa è la classifica *impersonale*, quella che serve a
  confrontare due settimane fra loro.
- **Non arriva in fondo.** L'HTML iniziale porta i primi 10-30 risultati, il
  resto si carica scorrendo. "fuori" significa "oltre quelli letti", non
  "inesistente" — ed è il motivo per cui la colonna dei letti è stampata.

Uso:
    python3 scripts/play_rank.py
    python3 scripts/play_rank.py --termini "rifugi,bivacchi"
    python3 scripts/play_rank.py --json           # per il brief automatico
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from datetime import date

PKG = "com.trailshare.app"
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
      "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36")

# Gli stessi termini di aso_keywords.md, così i due store si confrontano.
TERMINI = [
    "sentieri", "rifugi", "bivacchi", "malghe", "ciaspole", "orobie",
    "ferrate", "escursioni", "trekking", "mappe offline",
    "sentieri montagna", "rifugi alpini", "trailshare",
]

_ID = re.compile(r"/store/apps/details\?id=([A-Za-z0-9_.]+)")


def classifica(termine: str) -> list[str]:
    """I pacchetti nell'ordine in cui Play li presenta, deduplicati."""
    url = ("https://play.google.com/store/search"
           f"?q={termine.replace(' ', '%20')}&c=apps&hl=it&gl=IT")
    try:
        html = subprocess.run(
            ["/usr/bin/curl", "-s", "--max-time", "30", "-A", UA, url],
            capture_output=True, text=True, timeout=45).stdout
    except subprocess.TimeoutExpired:
        return []
    visti: list[str] = []
    for m in _ID.finditer(html):
        p = m.group(1)
        if p not in visti:
            visti.append(p)
    return visti


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--termini", help="elenco separato da virgole")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--pausa", type=float, default=1.5,
                    help="secondi fra una ricerca e l'altra")
    args = ap.parse_args()

    termini = ([t.strip() for t in args.termini.split(",") if t.strip()]
               if args.termini else TERMINI)

    esiti = []
    for t in termini:
        ids = classifica(t)
        pos = ids.index(PKG) + 1 if PKG in ids else None
        esiti.append({"termine": t, "posizione": pos, "letti": len(ids),
                      "primi": ids[:3]})
        time.sleep(args.pausa)

    if args.json:
        print(json.dumps({"data": date.today().isoformat(),
                          "store": "play", "paese": "IT",
                          "esiti": esiti}, ensure_ascii=False, indent=2))
        return 0

    print(f"\nPlay Store IT — {date.today().isoformat()}\n")
    print(f"  {'termine':22} {'posizione':>10}  {'letti':>6}   chi sta davanti")
    print("  " + "-" * 78)
    for e in esiti:
        pos = f"{e['posizione']}°" if e["posizione"] else "fuori"
        primi = ", ".join(p.split(".")[-1][:14] for p in e["primi"])
        print(f"  {e['termine']:22} {pos:>10}  {e['letti']:>6}   {primi}")

    dentro = [e for e in esiti if e["posizione"]]
    print(f"\n  In classifica su {len(dentro)} termini di {len(esiti)}.")
    if not any(e["posizione"] for e in esiti if e["termine"] != "trailshare"):
        print("  Su nessun termine generico. Se invece 'trailshare' esce primo,")
        print("  l'app È indicizzata: è un problema di posizionamento, non di")
        print("  presenza — due cose che si curano in modo molto diverso.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
