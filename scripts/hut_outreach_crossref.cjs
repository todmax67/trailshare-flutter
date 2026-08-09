// Incrocia la lista di outreach dei rifugi con le schede business gia' esistenti.
//
// Perche' serve: contattare un gestore la cui scheda esiste gia' — magari
// generata da noi e mai rivendicata — e' una conversazione diversa dal
// contattare uno che sulla mappa non c'e' proprio. Nel primo caso il messaggio
// e' "la tua pagina e' gia' online, prendine il controllo"; nel secondo e'
// "esisti sulla nostra mappa?". Mandare il testo sbagliato brucia il contatto.
//
// Le regole di accoppiamento NON sono inventate qui: sono le stesse di
// lib/core/utils/poi_business_dedup.dart — nome identico dopo normalizzazione,
// entro 60 metri — che sono gia' state misurate sull'intero catalogo (2.949
// schede su 6.496 hanno un POI OSM omonimo entro quella soglia). Usarne di
// diverse darebbe due verita' diverse per lo stesso fatto.
//
// Non scrive NULLA su Firestore: legge e basta.
//
// Uso:
//   node scripts/hut_outreach_crossref.cjs <lista.csv> [--out <file.csv>]

// Deve stare PRIMA di firebase-admin. Su questa macchina il resolver di sistema
// (getaddrinfo) ogni tanto risponde ENOTFOUND per firestore.googleapis.com,
// mentre le query dirette ai server DNS funzionano: `host` trova l'IPv4 e la
// cache di sistema ha solo l'IPv6, che qui non e' instradabile. gRPC passa da
// dns.lookup, quindi in caso di fallimento lo si dirotta su dns.resolve4.
// Svuotare la cache vorrebbe sudo; questo no.
const dns = require('dns');
const _lookup = dns.lookup;
dns.lookup = function (hostname, options, callback) {
  if (typeof options === 'function') { callback = options; options = {}; }
  return _lookup(hostname, options, (err, address, family) => {
    if (!err) return callback(err, address, family);
    dns.resolve4(hostname, (err2, addrs) => {
      if (err2 || !addrs || !addrs.length) return callback(err);
      if (options && options.all) {
        return callback(null, addrs.map((a) => ({ address: a, family: 4 })));
      }
      callback(null, addrs[0], 4);
    });
  });
};

const admin = require('../functions/node_modules/firebase-admin');
const sa = require('../functions/serviceAccountKey.json');
const fs = require('fs');
const path = require('path');

admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

// Identiche a poi_business_dedup.dart.
const MAX_METERS = 60;
const normalize = (s) => (s || '').toLowerCase().trim().replace(/\s+/g, ' ');

function haversine(lat1, lng1, lat2, lng2) {
  const R = 6371000;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

// --- CSV minimale, quanto basta per il formato che produciamo noi ----------

function parseCsv(text) {
  const rows = [];
  let row = [], field = '', inQuotes = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inQuotes) {
      if (c === '"' && text[i + 1] === '"') { field += '"'; i++; }
      else if (c === '"') inQuotes = false;
      else field += c;
    } else if (c === '"') inQuotes = true;
    else if (c === ',') { row.push(field); field = ''; }
    else if (c === '\n') { row.push(field); rows.push(row); row = []; field = ''; }
    else if (c !== '\r') field += c;
  }
  if (field || row.length) { row.push(field); rows.push(row); }
  const header = rows.shift();
  return rows
    .filter((r) => r.length === header.length)
    .map((r) => Object.fromEntries(header.map((h, i) => [h, r[i]])));
}

function toCsv(rows) {
  const header = Object.keys(rows[0]);
  const esc = (v) => {
    const s = v === undefined || v === null ? '' : String(v);
    return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  return [header.join(','), ...rows.map((r) => header.map((h) => esc(r[h])).join(','))]
    .join('\n') + '\n';
}

(async () => {
  const inPath = process.argv[2];
  if (!inPath || !fs.existsSync(inPath)) {
    console.error('uso: node scripts/hut_outreach_crossref.cjs <lista.csv> [--out <file>]');
    process.exit(1);
  }
  const outIdx = process.argv.indexOf('--out');
  const outPath = outIdx > 0 ? process.argv[outIdx + 1]
    : inPath.replace(/\.csv$/, '_incrociato.csv');

  const list = parseCsv(fs.readFileSync(inPath, 'utf8'));
  console.log(`contatti in lista: ${list.length}`);

  console.log('leggo le schede business…');
  const snap = await db.collection('businesses').get();
  const businesses = [];
  snap.forEach((d) => {
    const b = d.data();
    // Le coordinate stanno in location.lat / location.lng, non in campi di
    // primo livello ne' in un GeoPoint.
    const lat = b.location?.lat;
    const lng = b.location?.lng;
    if (typeof lat !== 'number' || typeof lng !== 'number') return;
    businesses.push({
      id: d.id,
      name: b.name || '',
      norm: normalize(b.name || ''),
      lat, lng,
      tier: b.tier || '',
      status: b.status || '',
      type: b.type || '',
      ownerId: b.ownerId || '',
      claimedAt: b.claimedAt || null,
      pendingSelfManagement: b.pendingSelfManagement === true,
    });
  });
  console.log(`schede con coordinate: ${businesses.length} su ${snap.size}`);

  // Utile saperlo: e' il campo su cui si decide chi contattare.
  const perTier = {};
  for (const b of businesses) perTier[b.tier || '(vuoto)'] =
    (perTier[b.tier || '(vuoto)'] || 0) + 1;
  console.log('   per tier: ' + Object.entries(perTier)
    .sort((a, b) => b[1] - a[1])
    .map(([k, v]) => `${k}=${v}`).join('  '));

  // Indice grossolano per cella di ~0,01° (~1,1 km): confrontare 1.269 × 6.496
  // per intero sarebbe inutilmente lento.
  const grid = new Map();
  const cell = (lat, lng) => `${Math.round(lat * 100)}:${Math.round(lng * 100)}`;
  for (const b of businesses) {
    for (let dLat = -1; dLat <= 1; dLat++) {
      for (let dLng = -1; dLng <= 1; dLng++) {
        const k = `${Math.round(b.lat * 100) + dLat}:${Math.round(b.lng * 100) + dLng}`;
        if (!grid.has(k)) grid.set(k, []);
        grid.get(k).push(b);
      }
    }
  }

  const tally = {};
  const out = list.map((r) => {
    const lat = parseFloat(r.lat), lng = parseFloat(r.lng);
    const nome = normalize(r.nome);
    let match = null, dist = null;

    for (const b of grid.get(cell(lat, lng)) || []) {
      if (b.norm !== nome) continue;
      const d = haversine(lat, lng, b.lat, b.lng);
      if (d <= MAX_METERS && (dist === null || d < dist)) { match = b; dist = d; }
    }

    // Lo stato lo dice `tier`, non `ownerId`: le schede generate da noi hanno
    // comunque un ownerId di servizio, e leggerlo come "rivendicata" faceva
    // risultare mille rifugi gia' clienti — su un'app con poco piu' di cento
    // utenti registrati.
    let stato;
    if (!match) {
      stato = 'nessuna scheda';
    } else if (match.tier === 'unclaimed') {
      stato = 'scheda non rivendicata';
    } else {
      stato = `scheda attiva (${match.tier || 'tier ignoto'})`;
    }
    tally[stato] = (tally[stato] || 0) + 1;

    return {
      stato_scheda: stato,
      ...r,
      scheda_id: match?.id || '',
      scheda_tier: match?.tier || '',
      scheda_richiesta_gestione: match?.pendingSelfManagement ? 'si' : '',
      scheda_distanza_m: dist === null ? '' : dist.toFixed(0),
    };
  });

  // Chi ha gia' un proprietario non va contattato a freddo: e' gia' cliente o
  // gia' dentro. Resta nel file, ma in fondo e marcato.
  // Prima chi ha gia' una pagina da riprendersi (il pitch piu' facile), poi chi
  // non c'e' proprio, in fondo chi e' gia' attivo e non va contattato a freddo.
  const rango = (s) => s === 'scheda non rivendicata' ? 0
    : s === 'nessuna scheda' ? 1 : 2;
  out.sort((a, b) =>
    (rango(a.stato_scheda) - rango(b.stato_scheda)) ||
    a.priorita.localeCompare(b.priorita) ||
    a.nome.localeCompare(b.nome));

  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, toCsv(out), 'utf8');

  console.log('\n--- incrocio ---');
  for (const [k, v] of Object.entries(tally).sort((a, b) => b[1] - a[1])) {
    console.log(`   ${String(v).padStart(5)}  ${k}`);
  }

  const nonRiv = out.filter((r) => r.stato_scheda === 'scheda non rivendicata');
  const conEmail = nonRiv.filter((r) => r.email).length;
  console.log(`\n   delle non rivendicate, con email: ${conEmail}`);
  console.log(`\nscritto ${outPath}`);
  console.log('NON committarlo: contiene recapiti di persone reali.');
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
