#!/usr/bin/env python3
"""
Scan: estrae stringhe italiane hardcoded da lib/presentation/ in un manifest.

Output: i18n_manifest.json con righe { file, line, original, suggested_key }.
La traduzione EN viene aggiunta in un secondo passaggio (a mano o via AI).

Heuristica italiana: presenza di accenti, congiunzioni/articoli, suffissi
caratteristici (zione, mento, ità). Filtra:
- linee con AppLocalizations / context.l10n / .tr() / S.of (già tradotte)
- commenti // e /* */
- debugPrint, assert, TODO

Pattern matchati (Text/title/subtitle/content/label/tooltip/hintText):
  Text('Foo bar') → estrae "Foo bar"
  title: const Text('Foo') → estrae "Foo"
  ... con interpolazione $var o ${expr} viene flaggata come `has_interp`.
"""
from __future__ import annotations
import argparse
import json
import re
from dataclasses import asdict, dataclass
from pathlib import Path


ITALIAN_HINTS = re.compile(
    r"(à|è|é|ì|ò|ù"
    r"|\bzion[ei]?\b|\bment[oi]?\b|\bità\b|\baggio\b"
    r"|\b(gli|dei|delle|della|dello|alle|alla|allo|il|la|le|un|una"
    r"|non|che|sono|hai|già|più|come|dove|quando|perché)\b"
    r"|sentier|traccia|attività|registr|carica|esporta|importa"
    r"|impostazioni|profilo|amici|cerca|filtra|seleziona|conferma|annulla"
    r"|chiudi|elimina|salva|disponibil|necessari|errore|riuscit|fallit|riprov"
    r"|cariament|salvataggio|nessuno|nessuna|nessun)",
    re.IGNORECASE,
)

# Cattura: ('xxx') o ("xxx") preceduto da Text|title|subtitle|content|label|tooltip|hintText|labelText
STR_PATTERN = re.compile(
    r"""(?<![A-Za-z0-9_])"""                       # non parte di identifier
    r"""(?P<wrapper>Text|title|subtitle|content|label|tooltip|hintText|labelText|helperText|message)"""
    r"""\s*[:(]\s*"""                              # : o (
    r"""(?:const\s+Text\(\s*)?"""                  # eventuale const Text(...)
    r"""(?:'(?P<s1>(?:\\.|[^'\\])*)'"""            # 'string'
    r"""|"(?P<s2>(?:\\.|[^"\\])*)")"""             # oppure "string"
)

SKIP_PATTERNS = (
    "AppLocalizations",
    "context.l10n",
    ".tr()",
    "S.of",
    "debugPrint",
    "assert(",
    "TODO",
    "FIXME",
)


@dataclass
class Match:
    file: str
    line: int
    wrapper: str
    original: str
    has_interp: bool
    suggested_key: str
    context_line: str


def slugify_key(s: str, max_words: int = 4) -> str:
    """Genera una chiave camelCase plausibile da una stringa italiana."""
    # Rimuovi punteggiatura, normalizza
    cleaned = re.sub(r"[^\w\s]", " ", s.lower())
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    words = cleaned.split()[:max_words]
    if not words:
        return "untitledKey"
    # camelCase
    return words[0] + "".join(w.capitalize() for w in words[1:])


def is_comment_line(line: str) -> bool:
    stripped = line.strip()
    return stripped.startswith("//") or stripped.startswith("*") or stripped.startswith("/*")


def scan_file(path: Path) -> list[Match]:
    out: list[Match] = []
    try:
        text = path.read_text(encoding="utf-8")
    except Exception:
        return out
    for lineno, raw_line in enumerate(text.splitlines(), start=1):
        if is_comment_line(raw_line):
            continue
        if any(p in raw_line for p in SKIP_PATTERNS):
            continue
        for m in STR_PATTERN.finditer(raw_line):
            s = m.group("s1") or m.group("s2") or ""
            if not s.strip():
                continue
            if not ITALIAN_HINTS.search(s):
                continue
            has_interp = "$" in s
            out.append(
                Match(
                    file=str(path),
                    line=lineno,
                    wrapper=m.group("wrapper"),
                    original=s,
                    has_interp=has_interp,
                    suggested_key=slugify_key(s),
                    context_line=raw_line.strip(),
                )
            )
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="lib/presentation", help="root dir to scan")
    ap.add_argument("--out", default="scripts/i18n_auto/manifest.json")
    ap.add_argument("--exclude", nargs="*", default=[])
    args = ap.parse_args()

    root = Path(args.root)
    matches: list[Match] = []
    for dart in root.rglob("*.dart"):
        if any(ex in str(dart) for ex in args.exclude):
            continue
        if "generated" in str(dart):
            continue
        matches.extend(scan_file(dart))

    # De-dup esatti (stessa stringa, stesso file) preferendo il più alto in alto
    seen: set[tuple[str, str]] = set()
    deduped: list[Match] = []
    for m in matches:
        k = (m.file, m.original)
        if k in seen:
            continue
        seen.add(k)
        deduped.append(m)

    # Group by file for review
    by_file: dict[str, list[dict]] = {}
    for m in deduped:
        by_file.setdefault(m.file, []).append(asdict(m))
    for f in by_file:
        by_file[f].sort(key=lambda x: x["line"])

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(by_file, ensure_ascii=False, indent=2))
    print(f"Trovate {len(deduped)} stringhe in {len(by_file)} file → {out_path}")
    print("Top 10 file:")
    for f, items in sorted(by_file.items(), key=lambda x: -len(x[1]))[:10]:
        print(f"  {len(items):3d}  {f}")


if __name__ == "__main__":
    main()
