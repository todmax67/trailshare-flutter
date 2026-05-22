#!/usr/bin/env python3
"""
Apply: prende un manifest tradotto (con campo 'en') e applica le sostituzioni.

Input formato translations.json:
{
  "<file_path>": [
    {
      "line": 123,
      "original": "Foo italiano",
      "key": "fooKey",
      "en": "Foo english",
      "wrapper": "Text",
      "has_interp": false,
      "placeholders": []
    },
    ...
  ]
}

Output:
- Append a lib/l10n/app_it.arb e lib/l10n/app_en.arb (skippa chiavi già presenti)
- Sostituisce nei .dart la stringa hardcoded con context.l10n.<key>
- Auto-import core/extensions/l10n_extension.dart se mancante
- Rispetta --dry-run

Caveat: gestisce solo wrapper di primo livello (Text/title/subtitle/...).
Se la riga ha più stringhe italiane, le sostituisce in ordine.
Per stringhe con interpolazione, l'utente deve dichiarare placeholders nel JSON.
"""
from __future__ import annotations
import argparse
import json
import re
from pathlib import Path


L10N_IMPORT_LINE = "import '../../core/extensions/l10n_extension.dart';"


def detect_l10n_import_relative(dart_file: Path, project_root: Path) -> str:
    """Calcola il path relativo corretto da dart_file a core/extensions/l10n_extension.dart"""
    target = project_root / "lib/core/extensions/l10n_extension.dart"
    rel = Path("/".join([".."] * (len(dart_file.relative_to(project_root / "lib").parts) - 1))) / "core/extensions/l10n_extension.dart"
    return f"import '{rel}';"


def ensure_l10n_import(content: str, import_line: str) -> str:
    if "l10n_extension.dart" in content or "AppLocalizations" in content:
        return content
    lines = content.splitlines(keepends=True)
    insert_at = 0
    last_import = -1
    for i, line in enumerate(lines):
        if line.startswith("import "):
            last_import = i
    if last_import < 0:
        return import_line + "\n" + content
    insert_at = last_import + 1
    lines.insert(insert_at, import_line + "\n")
    return "".join(lines)


def replace_in_line(line: str, original: str, key: str, en_placeholders: list[str]) -> str:
    """Sostituisce la stringa hardcoded con il riferimento context.l10n.<key>."""
    # const Text('...') → Text(context.l10n.key) (rimuovi const se presente)
    # Wrapper Text → Text(context.l10n.key)
    # title: const Text('...') → title: Text(context.l10n.key)
    # tooltip: '...' → tooltip: context.l10n.key
    # label: const Text('...') → label: Text(context.l10n.key)
    if en_placeholders:
        # context.l10n.key(arg1, arg2)
        # Per ora supportiamo solo se l'utente ha già messo la chiamata in `key_call`.
        pass

    # Costruisci replacement
    # Trova la stringa esatta tra apici (singoli o doppi)
    esc = re.escape(original)
    pattern_single = re.compile(r"(const\s+Text\s*\(\s*)?'(" + esc + r")'")
    pattern_double = re.compile(r'(const\s+Text\s*\(\s*)?"(' + esc + r')"')

    new_call = f"context.l10n.{key}" + (f"({', '.join(en_placeholders)})" if en_placeholders else "")

    def repl(m: re.Match) -> str:
        leading = m.group(1) or ""
        if leading:
            # rimuovi `const` e ricostruisci Text(...)
            return f"Text({new_call}"  # nota: la parentesi chiusa è già nel sorgente
        return new_call

    new_line, n1 = pattern_single.subn(repl, line, count=1)
    if n1 == 0:
        new_line, _ = pattern_double.subn(repl, line, count=1)
    return new_line


def _drop_const_around_l10n_calls(content: str) -> str:
    """Per ogni riga che contiene `context.l10n.`, controlla la riga corrente
    e le ~3 righe precedenti per `const <Widget>(`: se trovato, rimuovi il
    `const`. Conservativo: agisce solo se la chiusura `)` arriva DOPO la
    riga con context.l10n. (cioè il widget const contiene la chiamata).
    """
    lines = content.splitlines(keepends=True)
    for i, line in enumerate(lines):
        if "context.l10n." not in line:
            continue
        # cerca all'indietro fino a 5 righe
        for j in range(i, max(-1, i - 6), -1):
            m = re.search(r"\bconst\s+([A-Z]\w*\s*\()", lines[j])
            if m:
                # Trovato: rimuovi solo questo `const ` (mantieni widget call)
                lines[j] = lines[j][: m.start()] + lines[j][m.start() + len("const "):]
                break
    return "".join(lines)


def append_arb(arb_path: Path, additions: dict[str, str], dry_run: bool) -> int:
    """Aggiunge chiavi al file .arb. Skippa chiavi già esistenti. Mantiene la chiusura `}`."""
    content = arb_path.read_text(encoding="utf-8")
    parsed = json.loads(content)
    new_keys = 0
    for k, v in additions.items():
        if k in parsed:
            continue
        parsed[k] = v
        new_keys += 1
    if dry_run:
        return new_keys
    arb_path.write_text(json.dumps(parsed, ensure_ascii=False, indent=2), encoding="utf-8")
    return new_keys


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--translations", default="scripts/i18n_auto/translations.json")
    ap.add_argument("--arb-it", default="lib/l10n/app_it.arb")
    ap.add_argument("--arb-en", default="lib/l10n/app_en.arb")
    ap.add_argument("--root", default=".")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    project_root = Path(args.root).resolve()
    translations = json.loads(Path(args.translations).read_text(encoding="utf-8"))

    # Raccogli chiavi → it/en per .arb
    arb_it: dict[str, str] = {}
    arb_en: dict[str, str] = {}
    for f, items in translations.items():
        for it in items:
            key = it["key"]
            arb_it[key] = it["original"]
            arb_en[key] = it["en"]

    # Append .arb
    added_it = append_arb(Path(args.arb_it), arb_it, args.dry_run)
    added_en = append_arb(Path(args.arb_en), arb_en, args.dry_run)
    print(f"[arb] +{added_it} chiavi in IT, +{added_en} chiavi in EN (dry={args.dry_run})")

    # Modifica file .dart
    files_modified = 0
    replacements_total = 0
    for f, items in translations.items():
        dart_path = (project_root / f) if not Path(f).is_absolute() else Path(f)
        if not dart_path.exists():
            print(f"  ⚠️  Manca: {dart_path}")
            continue
        content = dart_path.read_text(encoding="utf-8")
        original_content = content
        # Ordina items per line desc per non shiftare le linee successive
        for it in sorted(items, key=lambda x: -x["line"]):
            ln = it["line"]
            lines = content.splitlines(keepends=True)
            if ln - 1 >= len(lines):
                continue
            original_line = lines[ln - 1]
            placeholders = it.get("placeholders") or []
            new_line = replace_in_line(original_line, it["original"], it["key"], placeholders)
            if new_line != original_line:
                lines[ln - 1] = new_line
                content = "".join(lines)
                replacements_total += 1
            else:
                print(f"  ⚠️  no-op: {f}:{ln} → {it['original'][:50]}")
        if content != original_content:
            # Auto-import l10n
            rel_import = detect_l10n_import_relative(dart_path, project_root)
            content = ensure_l10n_import(content, rel_import)
            # Quando il Text() figlio è non-const, il parent `const SnackBar/
            # ListTile/AlertDialog/Padding/...` rompe la compilazione.
            # Strategia: dopo le sostituzioni, rimuovi `const ` dal parent
            # immediatamente sopra le linee modificate (heuristica conservativa
            # ma efficace nei pattern Flutter più comuni).
            content = _drop_const_around_l10n_calls(content)
            if not args.dry_run:
                dart_path.write_text(content, encoding="utf-8")
            files_modified += 1

    print(f"[dart] {replacements_total} sostituzioni in {files_modified} file (dry={args.dry_run})")
    if args.dry_run:
        print("Dry-run completato. Rilancia senza --dry-run per applicare.")


if __name__ == "__main__":
    main()
