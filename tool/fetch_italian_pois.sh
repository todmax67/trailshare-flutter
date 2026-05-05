#!/usr/bin/env bash
# PoC OSM POI ingestion per TrailShare Pro AR Photo Mode v2 / Trail
# Conditions AI / Offline maps. Scarica i POI outdoor rilevanti dall'Italia
# via Overpass API e li salva in un JSON compatto.
#
# Modello: fetch_italian_peaks.sh (stessa strategia 8-chunk + failover).
#
# Categorie raccolte (focus outdoor IT):
#   - tourism=alpine_hut         rifugi alpini gestiti
#   - tourism=wilderness_hut     bivacchi non gestiti
#   - amenity=shelter            ripari (filtro shelter_type per escludere bus)
#   - natural=spring             sorgenti naturali
#   - amenity=drinking_water     fontane potabili
#   - tourism=viewpoint          punti panoramici
#   - historic=wayside_cross     croci di vetta/sentiero
#   - tourism=picnic_site        aree picnic
#   - man_made=cairn             ometti di pietra (alpinistici)
#
# Output schema:
#   {
#     "version": 1,
#     "fetched_at": "ISO 8601",
#     "source": "openstreetmap.org via overpass-turbo",
#     "license": "ODbL 1.0",
#     "stats": { "<type>": N, ..., "total": N },
#     "pois": [
#       {"id":"n12345","type":"alpine_hut","name":"Rifugio X","lat":45.1,"lng":9.1,"ele":1234,"ref":null},
#       ...
#     ]
#   }
#
# POI senza name → SCARTATI (non utili per UX).
# POI con name > 80 char → SCARTATI (probabilmente errori).
#
# Uso:   ./tool/fetch_italian_pois.sh
# Deps:  curl, jq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_FILE="$REPO_ROOT/assets/data/pois_italy.json"
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

# Stessi chunk geografici di fetch_italian_peaks per coerenza.
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

fetch_chunk() {
  local query="$1"
  local out_file="$2"
  local attempt=0
  while [ $attempt -lt 2 ]; do
    for URL in "${OVERPASS_URLS[@]}"; do
      if curl -sf --max-time 180 \
          -X POST \
          --data-urlencode "data=$query" \
          -o "$out_file" \
          "$URL"; then
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

# Query Overpass: tutte le categorie POI in una singola chiamata per chunk.
# Filtro shelter: escludo public_transport=yes (fermate bus/tram).
build_query() {
  local s=$1 w=$2 n=$3 e=$4
  cat <<EOF
[out:json][timeout:90];
(
  node["tourism"="alpine_hut"]($s,$w,$n,$e);
  node["tourism"="wilderness_hut"]($s,$w,$n,$e);
  node["amenity"="shelter"]["shelter_type"!="public_transport"]($s,$w,$n,$e);
  node["natural"="spring"]($s,$w,$n,$e);
  node["amenity"="drinking_water"]($s,$w,$n,$e);
  node["tourism"="viewpoint"]($s,$w,$n,$e);
  node["historic"="wayside_cross"]($s,$w,$n,$e);
  node["tourism"="picnic_site"]($s,$w,$n,$e);
  node["man_made"="cairn"]($s,$w,$n,$e);
);
out;
EOF
}

for chunk in "${CHUNKS[@]}"; do
  IFS='|' read -r LABEL S W N E <<< "$chunk"
  echo "🌍 Chunk \"$LABEL\" bbox($S,$W,$N,$E) ..." >&2
  QUERY=$(build_query "$S" "$W" "$N" "$E")
  OUT="$TMP_DIR/chunk.json"
  if fetch_chunk "$QUERY" "$OUT"; then
    COUNT=$(jq '.elements | length' "$OUT")
    echo "   → $COUNT elementi" >&2
    jq -s '{elements: ((.[0].elements // []) + (.[1].elements // []))}' \
       "$ALL_RAW" "$OUT" > "$TMP_DIR/merged.json"
    mv "$TMP_DIR/merged.json" "$ALL_RAW"
  else
    echo "   ⚠️  Fallito, salto chunk" >&2
  fi
  sleep 2
done

RAW_COUNT=$(jq '.elements | length' "$ALL_RAW")
echo "📦 Totali grezzi (con duplicati ai bordi): $RAW_COUNT" >&2

NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# Funzione per derivare il "type" semplificato dai tag OSM.
# Output finale: alpine_hut | wilderness_hut | shelter | spring |
# drinking_water | viewpoint | wayside_cross | picnic_site | cairn
jq -c --arg fetched "$NOW" '
  def derive_type:
    if .tags.tourism == "alpine_hut" then "alpine_hut"
    elif .tags.tourism == "wilderness_hut" then "wilderness_hut"
    elif .tags.amenity == "shelter" then "shelter"
    elif .tags.natural == "spring" then "spring"
    elif .tags.amenity == "drinking_water" then "drinking_water"
    elif .tags.tourism == "viewpoint" then "viewpoint"
    elif .tags.historic == "wayside_cross" then "wayside_cross"
    elif .tags.tourism == "picnic_site" then "picnic_site"
    elif .tags.man_made == "cairn" then "cairn"
    else "other"
    end;

  {
    version: 1,
    fetched_at: $fetched,
    source: "openstreetmap.org via overpass-turbo",
    license: "ODbL 1.0",
    pois: (
      .elements
      | unique_by(.id)
      | map(. + {derived_type: derive_type})
      | map(select(.derived_type != "other"))
      | map(select(.tags.name != null
                   and (.tags.name | length) > 0
                   and (.tags.name | length) <= 80))
      | map({
          id: ("n" + (.id | tostring)),
          type: .derived_type,
          name: .tags.name,
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
          ref: (.tags.ref // null),
          operator: (.tags.operator // null),
          website: (.tags.website // .tags["contact:website"] // null)
        })
      | sort_by(.type, .name)
    )
  }
  | (.stats = (
      .pois
      | group_by(.type)
      | map({(.[0].type): length})
      | add
      | . + {total: (([.[]] | add) // 0)}
    ))
' "$ALL_RAW" > "$OUTPUT_FILE"

# Drinking_water spesso non ha name → li scartiamo nel filtro sopra ma molti
# vanno persi. Stampiamo conteggio + dimensione.
FINAL_COUNT=$(jq '.stats.total' "$OUTPUT_FILE")
SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)

echo "" >&2
echo "✅ Salvati $FINAL_COUNT POI in $OUTPUT_FILE ($SIZE)" >&2
echo "" >&2
echo "📊 Stats per categoria:" >&2
jq -r '.stats | to_entries | map(select(.key != "total")) | sort_by(-.value) | .[] | "   \(.key): \(.value)"' "$OUTPUT_FILE" >&2
echo "" >&2
echo "🔍 Sample (primo POI per categoria):" >&2
jq -r '.pois | group_by(.type) | map(.[0]) | .[] | "   [\(.type)] \(.name) — \(.lat),\(.lng) ele:\(.ele // "?")"' "$OUTPUT_FILE" >&2
