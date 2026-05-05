#!/usr/bin/env bash
# Fetch dedicato SOLO ai rifugi/bivacchi/ripari da OSM (alpine_hut +
# wilderness_hut + shelter). Categorie a bassa densità (~3-4k tot in
# IT) ma alta utilità per outdoor — vanno garantite complete.
#
# Strategia: query Overpass MIRATA (solo 3 tag) su chunk ampi. Con
# payload leggero non triggera timeout silenti. Output → file separato
# che poi va mergato nel pois_italy.json principale.
#
# Uso:   ./tool/fetch_italian_huts.sh
# Output: assets/data/huts_italy.json
# Deps:  curl, jq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_FILE="$REPO_ROOT/assets/data/huts_italy.json"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

OVERPASS_URLS=(
  "https://overpass-api.de/api/interpreter"
  "https://overpass.kumi.systems/api/interpreter"
  "https://overpass.openstreetmap.ru/api/interpreter"
)

# Chunks più ampi del fetch generico — il payload dei soli huts è
# leggero quindi possiamo permetterci aree più estese.
declare -a CHUNKS=(
  "Alpi-NW|44.0|6.4|47.2|9.5"
  "Alpi-Centrali|45.0|9.5|47.2|11.5"
  "Alpi-NE|45.5|11.0|47.2|14.0"
  "App-Settentrionali|42.0|8.0|45.5|13.5"
  "App-Centrali|39.0|11.0|43.0|17.5"
  "Sicilia-Sardegna|35.5|6.0|41.0|17.5"
)

fetch_chunk() {
  local query="$1"
  local out_file="$2"
  for URL in "${OVERPASS_URLS[@]}"; do
    if curl -sf --max-time 240 \
        -X POST \
        --data-urlencode "data=$query" \
        -o "$out_file" \
        "$URL"; then
      if jq -e . "$out_file" >/dev/null 2>&1 && \
         ! jq -e '.remark // empty | test("timeout"; "i")' "$out_file" >/dev/null 2>&1; then
        return 0
      fi
    fi
    sleep 3
  done
  return 1
}

ALL_RAW="$TMP_DIR/all_raw.json"
echo '{"elements":[]}' > "$ALL_RAW"

for chunk in "${CHUNKS[@]}"; do
  IFS='|' read -r LABEL S W N E <<< "$chunk"
  echo "🏠 Chunk huts \"$LABEL\" bbox($S,$W,$N,$E) ..." >&2
  # nwr (node+way+relation) + "out center": molti rifugi noti
  # (Curò, Tagliaferri, ecc.) sono mappati come building polygon
  # (way) non come node singolo. "out center" ci dà il centroide
  # per ways/relations, mantenendo lat/lon per i nodes nativi.
  QUERY="[out:json][timeout:240];(nwr[\"tourism\"=\"alpine_hut\"]($S,$W,$N,$E);nwr[\"tourism\"=\"wilderness_hut\"]($S,$W,$N,$E);nwr[\"amenity\"=\"shelter\"][\"shelter_type\"!=\"public_transport\"]($S,$W,$N,$E););out center;"
  OUT="$TMP_DIR/chunk.json"
  if fetch_chunk "$QUERY" "$OUT"; then
    COUNT=$(jq '.elements | length' "$OUT")
    echo "   → $COUNT huts" >&2
    jq -s '{elements: ((.[0].elements // []) + (.[1].elements // []))}' \
       "$ALL_RAW" "$OUT" > "$TMP_DIR/merged.json"
    mv "$TMP_DIR/merged.json" "$ALL_RAW"
  else
    echo "   ❌ FALLITO" >&2
  fi
  sleep 2
done

NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

jq -c --arg fetched "$NOW" '
  def derive_type:
    if .tags.tourism == "alpine_hut" then "alpine_hut"
    elif .tags.tourism == "wilderness_hut" then "wilderness_hut"
    elif .tags.amenity == "shelter" then "shelter"
    else "other"
    end;

  # Per nodes: lat/lon nativo. Per ways/relations: .center.{lat,lon}.
  # ID prefix per distinguere fonte (n=node, w=way, r=relation).
  def derive_lat:
    if .lat != null then .lat
    elif .center != null then .center.lat
    else null end;
  def derive_lon:
    if .lon != null then .lon
    elif .center != null then .center.lon
    else null end;
  def id_prefix:
    if .type == "node" then "n"
    elif .type == "way" then "w"
    else "r" end;

  {
    version: 1,
    fetched_at: $fetched,
    source: "openstreetmap.org via overpass (huts-only nwr query)",
    license: "ODbL 1.0",
    pois: (
      .elements
      | map(. + {derived_type: derive_type, _lat: derive_lat, _lon: derive_lon, _idp: id_prefix})
      | map(select(.derived_type != "other"))
      | map(select(._lat != null and ._lon != null))
      | unique_by(.id)
      | map(select(.tags.name != null
                   and (.tags.name | length) > 0
                   and (.tags.name | length) <= 80))
      | map({
          id: (._idp + (.id | tostring)),
          type: .derived_type,
          name: .tags.name,
          lat: (._lat * 100000 | round / 100000),
          lng: (._lon * 100000 | round / 100000),
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
      | . + {total: ([.[]] | add // 0)}
    ))
' "$ALL_RAW" > "$OUTPUT_FILE"

TOTAL=$(jq '.stats.total' "$OUTPUT_FILE")
SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
echo "" >&2
echo "✅ Salvati $TOTAL huts in $OUTPUT_FILE ($SIZE)" >&2
echo "" >&2
echo "📊 Stats:" >&2
jq -r '.stats | to_entries | map(select(.key != "total")) | sort_by(-.value) | .[] | "   \(.key): \(.value)"' "$OUTPUT_FILE" >&2
