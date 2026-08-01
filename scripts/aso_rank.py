"""Posizione di TrailShare nella ricerca App Store italiana, per parola chiave.

Uso:  python3 scripts/aso_rank.py rifugi bivacchi "mappe offline"

Stampa posizione, quante app competono su quel termine e chi sta in testa.
Il conteggio totale conta quanto la posizione: un termine con due app in tutto
si occupa, uno con centottanta si conquista. Vedi docs/aso_keywords.md.

Nessuna autenticazione: e' l'API di ricerca pubblica di iTunes.
"""
import json, sys, time, urllib.parse, urllib.request

APP = 6751456265
def rank(term):
    u = ("https://itunes.apple.com/search?term=" + urllib.parse.quote(term)
         + "&country=it&entity=software&limit=200")
    try:
        d = json.load(urllib.request.urlopen(u, timeout=25))
    except Exception as e:
        return None, 0, []
    res = d.get("results", [])
    pos = next((i+1 for i, r in enumerate(res) if r.get("trackId") == APP), None)
    top = [r.get("trackName","")[:26] for r in res[:3]]
    return pos, len(res), top

terms = sys.argv[1:]
for t in terms:
    p, n, top = rank(t)
    label = f"{p}°" if p else ("fuori dai %d" % n if n else "errore")
    print(f"{t:<22} {label:<14} tot={n:<4} top3: {' | '.join(top)}")
    time.sleep(1.2)
