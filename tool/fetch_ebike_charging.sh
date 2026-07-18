#!/usr/bin/env bash
# Harvest punti di ricarica e-bike (Italia) da OpenStreetMap via Overpass
# e MERGE nell'asset esistente assets/data/pois_italy_clean.json come
# type "ebike_charging".
#
# Sorella di fetch_italian_pois.sh, ma con due differenze deliberate:
#   - query singola (≈1.2k elementi, niente chunking 8-bbox);
#   - i POI SENZA nome NON vengono scartati: le colonnine raramente hanno
#     un name su OSM → fallback "Ricarica e-bike" (o l'operator se c'è).
#
# Tag OSM: amenity=charging_station + bicycle=yes (nodi e way; per le way
# si usa il centroide "out center").
#
# Uso:   ./tool/fetch_ebike_charging.sh
# Deps:  curl, python3

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLEAN_FILE="$REPO_ROOT/assets/data/pois_italy_clean.json"
TMP_JSON="$(mktemp)"
trap 'rm -f "$TMP_JSON"' EXIT

OVERPASS_URLS=(
  "https://overpass-api.de/api/interpreter"
  "https://overpass.kumi.systems/api/interpreter"
)

QUERY='[out:json][timeout:120];
area["ISO3166-1"="IT"][admin_level=2]->.it;
(
  node["amenity"="charging_station"]["bicycle"="yes"](area.it);
  way["amenity"="charging_station"]["bicycle"="yes"](area.it);
);
out center tags;'

ok=0
for url in "${OVERPASS_URLS[@]}"; do
  echo "→ Overpass: $url"
  if curl -s --max-time 180 "$url" --data-urlencode "data=$QUERY" -o "$TMP_JSON" \
     && python3 -c "import json;d=json.load(open('$TMP_JSON'));assert d.get('elements')" 2>/dev/null; then
    ok=1; break
  fi
  echo "  fallito, provo il prossimo…"
done
[ "$ok" = 1 ] || { echo "❌ Overpass non raggiungibile"; exit 1; }

python3 - "$TMP_JSON" "$CLEAN_FILE" << 'EOF'
import json, sys
from datetime import datetime, timezone

raw = json.load(open(sys.argv[1]))
clean_path = sys.argv[2]
clean = json.load(open(clean_path))

pois = []
seen = set()
for e in raw.get('elements', []):
    tags = e.get('tags', {})
    prefix = 'n' if e['type'] == 'node' else 'w'
    pid = f"{prefix}{e['id']}"
    if pid in seen:
        continue
    seen.add(pid)
    lat = e.get('lat') or (e.get('center') or {}).get('lat')
    lng = e.get('lon') or (e.get('center') or {}).get('lon')
    if lat is None or lng is None:
        continue
    name = (tags.get('name') or tags.get('operator') or 'Ricarica e-bike').strip()
    if len(name) > 80:
        name = 'Ricarica e-bike'
    pois.append({
        'id': pid,
        'type': 'ebike_charging',
        'name': name,
        'lat': round(float(lat), 6),
        'lng': round(float(lng), 6),
        'ele': None,
        'ref': tags.get('ref'),
        'operator': tags.get('operator'),
        'website': tags.get('website') or tags.get('contact:website'),
    })

# Merge: rimuovi eventuali ebike_charging di run precedenti, poi appendi.
before = len(clean['pois'])
clean['pois'] = [p for p in clean['pois'] if p.get('type') != 'ebike_charging']
clean['pois'].extend(pois)
clean['stats']['ebike_charging'] = len(pois)
clean['stats']['total'] = len(clean['pois'])
clean['fetched_at'] = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

json.dump(clean, open(clean_path, 'w'), ensure_ascii=False, separators=(',', ':'))
print(f"✅ ebike_charging: {len(pois)} POI (asset: {before} → {clean['stats']['total']})")
EOF