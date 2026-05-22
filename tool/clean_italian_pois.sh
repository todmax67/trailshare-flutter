#!/usr/bin/env bash
# Pulizia POI OSM: prende pois_italy.json (output di
# fetch_italian_pois.sh) e produce pois_italy_clean.json scartando
# i record con nomi garbage.
#
# Filtri:
#   - name length >= 3
#   - name non solo cifre (es. "11", "07/05/2015")
#   - name non solo simboli/punteggiatura (es. "+ +", "!", ". .")
#   - name non solo cifre + separatori data (date senza nome)
#   - name non sequenza di "x" / "..." / "test"
#   - lat/lng presenti e validi
#
# Output:
#   {
#     "version": 1,
#     "fetched_at": ...,
#     "stats": {...},
#     "pois": [...puliti...]
#   }
#
# Uso:   ./tool/clean_italian_pois.sh
# Deps:  jq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INPUT_FILE="$REPO_ROOT/assets/data/pois_italy.json"
OUTPUT_FILE="$REPO_ROOT/assets/data/pois_italy_clean.json"

if [ ! -f "$INPUT_FILE" ]; then
  echo "❌ Input non trovato: $INPUT_FILE" >&2
  echo "   Esegui prima ./tool/fetch_italian_pois.sh" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq non trovato." >&2; exit 1
fi

INPUT_COUNT=$(jq '.stats.total // (.pois | length)' "$INPUT_FILE")
echo "📥 Input: $INPUT_COUNT POI" >&2

# Filtri jq:
#   - name normalizzato (trim, lowercase per match)
#   - regex per detectare garbage
jq '
  def is_garbage_name:
    . as $n
    | $n | length < 3
      or test("^[\\s\\.\\+\\-\\*/\\\\!?,;:|]+$")          # solo simboli
      or test("^[0-9]+$")                                  # solo cifre
      or test("^\\s*\\d{1,2}[-/.\\s]\\d{1,2}[-/.\\s]\\d{2,4}\\s*$")  # date
      or test("^x+$"; "i")                                 # "xxx"
      or test("^test$"; "i")                               # "test"
      or test("^\\.+$")                                    # solo punti
      or test("^-+$")                                      # solo trattini
      or test("^\\?+$");                                   # solo ?

  {
    version: 1,
    fetched_at: .fetched_at,
    source: .source,
    license: .license,
    pois: (
      .pois
      | map(select(.lat != null and .lng != null
                   and .lat >= 35 and .lat <= 48
                   and .lng >= 6 and .lng <= 19))
      | map(select((.name | is_garbage_name) | not))
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
' "$INPUT_FILE" > "$OUTPUT_FILE"

OUTPUT_COUNT=$(jq '.stats.total' "$OUTPUT_FILE")
DROPPED=$((INPUT_COUNT - OUTPUT_COUNT))
SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)

echo "" >&2
echo "✅ Salvati $OUTPUT_COUNT POI puliti in $OUTPUT_FILE ($SIZE)" >&2
echo "🗑  Scartati per garbage: $DROPPED" >&2
echo "" >&2
echo "📊 Stats per categoria (post-pulizia):" >&2
jq -r '.stats | to_entries | map(select(.key != "total")) | sort_by(-.value) | .[] | "   \(.key): \(.value)"' "$OUTPUT_FILE" >&2
echo "" >&2
echo "🔍 Sample (primi 2 per categoria):" >&2
jq -r '.pois | group_by(.type) | map(.[0:2]) | flatten | .[] | "   [\(.type)] \(.name) — \(.lat),\(.lng) ele:\(.ele // "?")"' "$OUTPUT_FILE" >&2
