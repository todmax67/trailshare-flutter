#!/usr/bin/env node
/**
 * Genera i QR dei link tracciabili elencati in `growth_links.json`.
 *
 * Uno per etichetta, in PNG (per la stampa) e SVG (per il ridimensionamento
 * senza perdita, es. un adesivo grande sul vetro del rifugio).
 *
 * Livello di correzione errori alto (H): i QR di questa serie finiscono su
 * card appoggiate al bancone di un rifugio, dove si sporcano, si piegano e si
 * consumano agli angoli. Con H il codice resta leggibile anche con quasi un
 * terzo della superficie rovinata; costa solo qualche modulo in piu'.
 *
 *   node scripts/make_qr.cjs            # tutte le etichette
 *   node scripts/make_qr.cjs qr_arlaud  # una sola
 */

const fs = require('fs');
const path = require('path');

let QRCode;
try {
  QRCode = require('qrcode');
} catch (e) {
  console.error(
    'Manca la dipendenza `qrcode`. Installala una volta sola con:\n' +
      '  cd scripts && npm install',
  );
  process.exit(1);
}

const REGISTRY = path.join(__dirname, 'growth_links.json');
const OUT_DIR = path.join(__dirname, '..', 'adv', 'qr');

async function main() {
  const registry = JSON.parse(fs.readFileSync(REGISTRY, 'utf8'));
  const base = registry.base.replace(/\/+$/, '');

  const only = process.argv.slice(2);
  const links = only.length
    ? registry.links.filter((l) => only.includes(l.label))
    : registry.links;

  if (!links.length) {
    console.error(
      `Nessuna etichetta corrispondente a: ${only.join(', ')}\n` +
        `Disponibili: ${registry.links.map((l) => l.label).join(', ')}`,
    );
    process.exit(1);
  }

  fs.mkdirSync(OUT_DIR, { recursive: true });

  for (const link of links) {
    // Stessa whitelist della pagina /r: un'etichetta con caratteri strani
    // produrrebbe un QR che punta a un URL diverso da quello atteso, e sulla
    // carta stampata l'errore non si corregge piu'.
    if (!/^[a-z0-9_-]+$/.test(link.label)) {
      console.error(`✗ ${link.label}: etichetta non valida, solo a-z 0-9 _ -`);
      continue;
    }

    const url = `${base}/${link.label}`;
    const opts = { errorCorrectionLevel: 'H', margin: 2 };

    await QRCode.toFile(path.join(OUT_DIR, `${link.label}.png`), url, {
      ...opts,
      width: 1200, // ~10 cm a 300 dpi: la dimensione di una card da banco
    });
    await QRCode.toFile(path.join(OUT_DIR, `${link.label}.svg`), url, {
      ...opts,
      type: 'svg',
    });

    console.log(`✓ ${link.label.padEnd(14)} → ${url}`);
    if (link.note) console.log(`  ${link.note}`);
  }

  console.log(`\nFile in ${path.relative(process.cwd(), OUT_DIR)}/`);
  console.log(
    'Prima di stampare: inquadra il QR e verifica che apra lo store giusto.',
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
