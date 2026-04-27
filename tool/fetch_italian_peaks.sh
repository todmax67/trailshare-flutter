#!/usr/bin/env bash
# Scarica TUTTE le cime italiane da OpenStreetMap via Overpass API e
# le salva in formato compatto in assets/data/peaks_italy.json.
#
# Strategia: 6 chunk geografici (Italia spezzata in regioni) per
# evitare timeout del singolo "area Italia". Ogni chunk è una bbox
# che Overpass può servire in <60s.
#
# Output schema:
#   {
#     "version": 1,
#     "fetched_at": "ISO 8601",
#     "count": N,
#     "peaks": [
#       {"id":"n12345","name":"Monte X","lat":45.1,"lng":9.1,"ele":1234,"type":"peak"},
#       ...
#     ]
#   }
#
# Cime senza name o senza ele numerico → SCARTATE.
#
# Uso:   ./tool/fetch_italian_peaks.sh
# Deps:  curl, jq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_FILE="$REPO_ROOT/assets/data/peaks_italy.json"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if ! command -v curl >/dev/null 2>&1; then
  echo "❌ curl non trovato." >&2; exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq non trovato. brew install jq" >&2; exit 1
fi

OVERPASS_URLS=(
  "https://overpass-api.de/api/interpreter"
  "https://overpass.kumi.systems/api/interpreter"
  "https://overpass.openstreetmap.ru/api/interpreter"
)

# Bounding box: south, west, north, east. Coperture sovrapposte per
# essere sicuri di non perdere cime ai bordi (verranno deduplicate
# tramite id OSM dopo il merge).
# Format: label|south|west|north|east  (pipe-separated per supportare spazi nei label)
# Alpi-NW spezzato in 2 sotto-chunk per evitare timeout (zona densissima).
declare -a CHUNKS=(
  "Alpi-NW-Aosta|45.5|6.4|47.2|8.5"
  "Alpi-NW-Pie-Lig|44.0|6.4|45.5|9.5"
  "Alpi-Centro|45.0|8.5|47.2|11.0"
  "Alpi-NE|45.0|10.5|47.2|14.0"
  "App-Centro-Nord|42.5|9.0|45.5|13.5"
  "Liguria-Toscana|42.0|8.0|44.5|12.0"
  "App-Centro-Sud|39.0|12.0|43.0|17.5"
  "Sicilia-Sardegna-Calabria|35.5|6.0|41.0|17.5"
)

# Altitudine minima per essere inclusi: 800m. Sotto questo valore le
# "cime" OSM sono spesso colline locali poco rilevanti per AR a distanza.
# Casi speciali (Vesuvio 1281, Etna 3357, Stromboli 924, Vulture 1326) sono
# coperti perché >800m. Cime costiere sotto restano nei volcanoes.
MIN_ELE=800
# Sanity check: la cima piu alta in Italia e il Monte Bianco a ~4810m.
# Tutto sopra questo valore e quasi sicuramente errore OSM (ele in cm,
# typo, etc.) e va scartato.
MAX_ELE=5000

fetch_chunk() {
  local query="$1"
  local out_file="$2"
  local attempt=0
  while [ $attempt -lt 2 ]; do
    for URL in "${OVERPASS_URLS[@]}"; do
      if curl -sf --max-time 150 \
          -X POST \
          --data-urlencode "data=$query" \
          -o "$out_file" \
          "$URL"; then
        # Verifica che non sia un HTML di errore + non abbia "remark" timeout
        if jq -e . "$out_file" >/dev/null 2>&1 && \
           ! jq -e '.remark // empty | test("timeout"; "i")' "$out_file" >/dev/null 2>&1; then
          return 0
        fi
      fi
    done
    attempt=$((attempt + 1))
    sleep 5
  done
  return 1
}

ALL_RAW="$TMP_DIR/all_raw.json"
echo '{"elements":[]}' > "$ALL_RAW"

for chunk in "${CHUNKS[@]}"; do
  IFS='|' read -r LABEL S W N E <<< "$chunk"
  echo "🌍 Chunk \"$LABEL\" bbox($S,$W,$N,$E) ..." >&2
  QUERY="[out:json][timeout:60];(node[\"natural\"=\"peak\"]($S,$W,$N,$E);node[\"natural\"=\"volcano\"]($S,$W,$N,$E););out;"
  OUT="$TMP_DIR/chunk.json"
  if fetch_chunk "$QUERY" "$OUT"; then
    COUNT=$(jq '.elements | length' "$OUT")
    echo "   → $COUNT elementi" >&2
    # Merge nelle elements globali
    jq -s '{elements: ((.[0].elements // []) + (.[1].elements // []))}' \
       "$ALL_RAW" "$OUT" > "$TMP_DIR/merged.json"
    mv "$TMP_DIR/merged.json" "$ALL_RAW"
  else
    echo "   ⚠️  Fallito, salto chunk" >&2
  fi
  # Politeness delay tra chunk per non stressare Overpass
  sleep 2
done

RAW_COUNT=$(jq '.elements | length' "$ALL_RAW")
echo "📦 Totali grezzi (con duplicati ai bordi): $RAW_COUNT" >&2

NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# Deduplica per id, filtra solo con name + ele numerico, ordina per ele desc.
jq -c --arg fetched "$NOW" '
  {
    version: 1,
    fetched_at: $fetched,
    source: "openstreetmap.org via overpass-turbo",
    license: "ODbL 1.0",
    peaks: (
      .elements
      | unique_by(.id)
      | map(select(.tags.name != null
                   and (.tags.name | length) > 0
                   and (.tags.name | length) <= 60))
      | map({
          id: ("n" + (.id | tostring)),
          name: .tags.name,
          # Round lat/lng a 5 decimali (precisione ~1m), ele a int.
          lat: (.lat * 100000 | round / 100000),
          lng: (.lon * 100000 | round / 100000),
          ele: (
            if .tags.ele == null then null
            else (.tags.ele
                  | gsub("[^0-9.\\-]"; "")
                  | tonumber? // null
                  | (if . == null then null else (. | round) end))
            end
          ),
          type: (if .tags.natural == "volcano" then "volcano" else "peak" end)
        })
      | map(select(.ele != null and .ele >= '$MIN_ELE' and .ele <= '$MAX_ELE'))
      | sort_by(-.ele)
    )
  }
  | (.count = (.peaks | length))
' "$ALL_RAW" > "$OUTPUT_FILE"

FINAL_COUNT=$(jq '.count' "$OUTPUT_FILE")
SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)

echo "✅ Salvate $FINAL_COUNT cime in $OUTPUT_FILE ($SIZE)" >&2
