// Scheletro di un tour costruito dalle tappe gia' presenti nel catalogo.
//
// Il catalogo contiene 56 cammini le cui tappe sono sentieri separati con il
// numero nel nome ("Alta Via n. 1 della Valle d'Aosta Tappa 3"). Ordinandole
// si ottiene la sequenza, e da li' tutto il resto: distanze, dislivelli,
// difficolta' rilevate, tempi, e il rifugio a fine tappa.
//
// NON SCRIVE NIENTE. Serve a rispondere a una domanda sola: uno scheletro
// costruito cosi' regge come tour, o e' solo una tabella? Prima di
// estendere il modello Tour (che oggi prende le tappe da `tracks`, non da
// `public_trails`) vale la pena guardarlo.
//
// Uso:
//   node scripts/tour_skeleton_preview.cjs "Alta Via n. 1 della Valle d'Aosta"
//   node scripts/tour_skeleton_preview.cjs --elenco     (le famiglie disponibili)
const admin = require('../functions/node_modules/firebase-admin');
const sa = require('../functions/serviceAccountKey.json');

admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const argv = process.argv.slice(2);
const ELENCO = argv.includes('--elenco');
const CERCA = argv.filter((a) => !a.startsWith('--'))[0];
const RAGGIO_KM = 3;

// Le varianti si scrivono in tre modi a seconda di chi ha mappato:
//   lettere    "Tappa 1A"      (Alta Via della Valmalenco)
//   decimali   "Stage 4.1"     (Tour du Mont-Blanc)
//   niente     "Tappa 4"       (Alta Via n.1 della Valle d'Aosta)
// Il gruppo 3 e' la tappa, il 4 la sotto-numerazione, il 5 la lettera:
// tutto cio' che sta nel 4 o nel 5 e' una variante, non un giorno in piu'.
const TAPPA = /^(.*?)[\s\-–—]*\b(tappa|tappe|stage|etappe|étape|etape)\b\s*\.?\s*(\d+)(?:[.\-](\d+(?:-\d+)?))?\s*([a-zA-Z]?)/i;
const NOME_CAI = { t: 'T — Turistico', e: 'E — Escursionistico',
  ee: 'EE — Escursionisti Esperti', eea: 'EEA — Attrezzata/Alpinistica' };
const RANGO = { t: 0, e: 1, ee: 2, eea: 3 };

function km(lat1, lon1, lat2, lon2) {
  const R = 6371, r = (x) => x * Math.PI / 180;
  const dLat = r(lat2 - lat1), dLon = r(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2
    + Math.cos(r(lat1)) * Math.cos(r(lat2)) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/// Nomi di rifugio confrontabili: via accenti, punteggiatura e i prefissi
/// che cambiano da lingua a lingua ("Rifugio", "Rif.", "Capanna", "Hutte",
/// "Refuge"). Senza questo, "Rif. Antonio ed Elia Longoni" e "Rifugio
/// Longoni" restano due cose diverse.
const PREFISSI = /\b(rifugio|rifugi|rif\.?|capanna|baita|bivacco|refuge|refuges|huette|hutte|hütte|berghaus|chalet|gite|gîte|albergo|ostello)\b/gi;
function normalizza(nome) {
  return String(nome || '')
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(PREFISSI, ' ')
    .replace(/[^a-z0-9 ]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/// Abbina il rifugio partendo dal campo `to` della tappa, che spesso lo
/// nomina gia' ("a Rifugio Bosio-Galli"). E' una fonte migliore della sola
/// vicinanza: risolve gli omonimi a pari distanza, dove la geografia non
/// sa scegliere. Il nome pero' va CONFERMATO dalla posizione, altrimenti si
/// aggancia un "Rifugio Cristina" dall'altra parte delle Alpi.
function perNome(to, rifugi, fine) {
  if (!to) return null;
  for (const pezzo of String(to).split(/[;/]|\bo\b/)) {
    const cercato = normalizza(pezzo);
    if (cercato.length < 3) continue;
    const candidati = rifugi.filter((r) => {
      const n = normalizza(r.nome);
      return n === cercato || n.includes(cercato) || cercato.includes(n);
    });
    if (!candidati.length) continue;
    // fra gli omonimi vince il piu' vicino all'arrivo, e solo se e' vicino.
    const conDist = fine
      ? candidati.map((r) => ({ ...r, d: km(fine[0], fine[1], r.lat, r.lng) }))
        .sort((a, b) => a.d - b.d)
      : candidati.map((r) => ({ ...r, d: null }));
    const scelto = conDist[0];
    if (scelto.d === null || scelto.d <= 5) return { ...scelto, viaNome: true };
  }
  return null;
}

/// Fine della tappa: e' li' che si dorme.
function arrivo(x) {
  // Nei documenti convivono due forme a seconda dell'import: {lat, lon} e
  // {latitude, longitude}. Leggerne una sola dava una longitudine undefined,
  // quindi distanze NaN e "nessun rifugio" anche a quaranta metri.
  const p = x.endPoint;
  const la = p && (p.latitude ?? p.lat);
  const ln = p && (p.longitude ?? p.lng ?? p.lon);
  if (la != null && ln != null) return [Number(la), Number(ln)];
  const sp = x.simplifiedPoints;
  if (Array.isArray(sp) && sp.length) {
    const l = sp[sp.length - 1];
    if (Array.isArray(l)) return [Number(l[0]), Number(l[1])];
    if (l && l.lat != null) return [Number(l.lat), Number(l.lng)];
  }
  return null;
}

(async () => {
  const snap = await db.collection('public_trails').get();
  const fam = {};
  snap.forEach((d) => {
    const x = d.data();
    const m = String(x.name || '').match(TAPPA);
    if (!m) return;
    const capo = m[1].trim().replace(/[-–—:]+$/, '').trim();
    if (capo.length < 3) return;
    (fam[capo] = fam[capo] || []).push({ ...x, id: d.id, n: Number(m[3]),
      suffisso: (m[4] ? '.' + m[4] : '') + (m[5] || '') });
  });

  if (ELENCO || !CERCA) {
    const ok = Object.entries(fam).filter(([, v]) => v.length >= 3)
      .sort((a, b) => b[1].length - a[1].length);
    console.log(`famiglie con almeno 3 tappe: ${ok.length}\n`);
    ok.slice(0, 30).forEach(([k, v]) => {
      const rilevate = v.filter((t) => t.difficultySource).length;
      console.log(`  ${String(v.length).padStart(3)} tappe · rilevate ${String(rilevate).padStart(2)} · ${k}`);
    });
    process.exit(0);
  }

  // Prima l'uguaglianza esatta: "Tour du Mont-Blanc CCW" e "Tour du
  // Mont-Blanc CCW Alt" sono due itinerari diversi, e cercando per
  // contenuto vinceva il secondo.
  const q = CERCA.toLowerCase();
  const esatta = Object.keys(fam).find((k) => k.toLowerCase() === q);
  const parziali = Object.keys(fam).filter((k) => k.toLowerCase().includes(q));
  const chiave = esatta || parziali[0];
  if (!chiave) { console.error(`Nessuna famiglia contiene "${CERCA}". Usa --elenco.`); process.exit(1); }
  if (!esatta && parziali.length > 1) {
    console.log(`⚠ "${CERCA}" corrisponde a ${parziali.length} famiglie, uso la prima:`);
    parziali.forEach((k) => console.log(`    ${k === chiave ? '→' : ' '} ${k} (${fam[k].length} voci)`));
    console.log();
  }
  // Il suffisso letterale NON e' una tappa in piu': 1A e 1B sono varianti o
  // raccordi della tappa 1, non due giorni di cammino. Sommandole si
  // gonfiava l'Alta Via della Valmalenco di 35 km inesistenti — e chi la usa
  // per pianificare se ne accorge in montagna.
  const tutte = fam[chiave].sort((a, b) => a.n - b.n || a.suffisso.localeCompare(b.suffisso));
  const tappe = tutte.filter((t) => !t.suffisso);
  const varianti = tutte.filter((t) => t.suffisso);
  if (!tappe.length) { console.error('Nessuna tappa principale: solo varianti.'); process.exit(1); }

  // Rifugi, per proporre dove si dorme.
  const bSnap = await db.collection('businesses').where('type', '==', 'rifugio').get();
  const rifugi = [];
  bSnap.forEach((d) => {
    const x = d.data(), L = x.location || {};
    const la = L.latitude ?? L.lat, ln = L.longitude ?? L.lng;
    if (la != null && ln != null) rifugi.push({ nome: x.name, lat: Number(la), lng: Number(ln) });
  });

  let totKm = 0, totGain = 0, totOre = 0, peggiore = -1;
  let conRilievo = 0, conRifugio = 0, conNome = 0;

  console.log('═'.repeat(78));
  console.log(chiave.toUpperCase());
  console.log('═'.repeat(78));

  for (let i = 0; i < tappe.length; i++) {
    const t = tappe[i];
    const kmT = (t.distance || 0) / 1000;
    totKm += kmT; totGain += t.elevationGain || 0; totOre += t.oreStimate || 0;
    const g = String(t.difficulty || '').toLowerCase();
    if (t.difficultySource && RANGO[g] !== undefined) {
      conRilievo++;
      if (RANGO[g] > peggiore) peggiore = RANGO[g];
    }

    const fine = arrivo(t);
    let dove = '—';
    // Prima il nome dichiarato nel campo `to`, poi la vicinanza.
    const perN = perNome(t.to, rifugi, fine);
    if (perN) {
      dove = `${perN.nome}${perN.d != null ? ` (${perN.d.toFixed(1)} km)` : ''}  ← dal nome`;
      conRifugio++; conNome++;
    } else if (fine) {
      const v = rifugi.map((r) => ({ ...r, d: km(fine[0], fine[1], r.lat, r.lng) }))
        .filter((r) => r.d <= RAGGIO_KM).sort((a, b) => a.d - b.d)[0];
      if (v) { dove = `${v.nome} (${v.d.toFixed(1)} km)`; conRifugio++; }
    }

    const grado = t.difficultySource ? (t.difficulty || '?').toUpperCase() : '·';
    console.log(`\nTAPPA ${String(t.n).padStart(2)}${t.suffisso}  ${String(t.name).replace(chiave, '').replace(/^[\s\-–—]*/, '').slice(0, 46)}`);
    console.log(`   ${kmT.toFixed(1).padStart(6)} km   D+ ${String(Math.round(t.elevationGain || 0)).padStart(5)} m   ` +
      `${t.oreStimate ? t.oreStimate.toFixed(1).padStart(5) + ' h' : '    — '}   grado ${grado.padEnd(4)}` +
      `${t.difficultySource ? '' : '(non rilevato)'}`);
    if (t.from || t.to) console.log(`   da ${t.from || '?'} a ${t.to || '?'}`);
    console.log(`   dormire: ${dove}`);
    if (t.description) console.log(`   testo: ${String(t.description).slice(0, 96)}…`);

    for (const alt of varianti.filter((v) => v.n === t.n)) {
      console.log(`      variante ${alt.n}${alt.suffisso}: ${((alt.distance || 0) / 1000).toFixed(1)} km · ` +
        `D+ ${Math.round(alt.elevationGain || 0)} m` +
        `${alt.from || alt.to ? `  (${alt.from || '?'} → ${alt.to || '?'})` : ''}`);
    }
  }

  console.log('\n' + '═'.repeat(78));
  console.log('COMPLESSIVO');
  console.log(`  ${tappe.length} tappe · ${totKm.toFixed(0)} km · D+ ${Math.round(totGain)} m · ${totOre.toFixed(0)} ore`);
  if (varianti.length) {
    const kmV = varianti.reduce((a, b) => a + (b.distance || 0) / 1000, 0);
    console.log(`  + ${varianti.length} varianti (${kmV.toFixed(0)} km) tenute FUORI dal totale`);
  }
  console.log(`  difficolta' del tour (la piu' alta fra le tappe rilevate): ` +
    `${peggiore >= 0 ? NOME_CAI[Object.keys(RANGO)[peggiore]] : 'non determinabile'}`);
  console.log(`  tappe con grado rilevato: ${conRilievo}/${tappe.length}`);
  console.log(`  tappe con un rifugio a fine percorso: ${conRifugio}/${tappe.length}` +
    `  (di cui ${conNome} riconosciuti dal nome dichiarato)`);
  console.log(`  tappe con descrizione: ${tappe.filter((t) => t.description).length}/${tappe.length}`);
  console.log('\nNessuna scrittura: e\' un\'anteprima.');
  process.exit(0);
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
