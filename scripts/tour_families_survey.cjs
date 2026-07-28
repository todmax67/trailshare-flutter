// Censimento delle famiglie di tappe nel catalogo, per capire cosa deve
// reggere il modello Tour prima di scriverlo.
//
// Non basta sapere quante tappe ci sono: serve sapere se la SEQUENZA e'
// coerente. In un cammino l'arrivo della tappa N e' la partenza della N+1;
// dove non lo e', o mancano tappe o l'ordine non e' quello. Un modello
// costruito su sequenze rotte nasce storto.
//
// Controlla per ogni famiglia:
//   - tappe principali e varianti (lettere, decimali, niente)
//   - buchi nella numerazione e numeri ripetuti
//   - continuita' arrivo->partenza fra tappe consecutive
//   - copertura di difficolta' rilevata, rifugio a fine tappa, descrizione
//
// Uso:
//   node scripts/tour_families_survey.cjs
//   node scripts/tour_families_survey.cjs --min 5
const admin = require('../functions/node_modules/firebase-admin');
const sa = require('../functions/serviceAccountKey.json');

admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const argv = process.argv.slice(2);
const opt = (n, d) => { const i = argv.indexOf('--' + n); return i >= 0 ? argv[i + 1] : d; };
const MIN_TAPPE = Number(opt('min', 3));

const TAPPA = /^(.*?)[\s\-–—]*\b(tappa|tappe|stage|etappe|étape|etape)\b\s*\.?\s*(\d+)(?:[.\-](\d+(?:-\d+)?))?\s*([a-zA-Z]?)/i;
const PREFISSI = /\b(rifugio|rifugi|rif\.?|capanna|baita|bivacco|refuge|refuges|huette|hutte|hütte|berghaus|chalet|gite|gîte|albergo|ostello)\b/gi;

function normalizza(nome) {
  return String(nome || '')
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .toLowerCase().replace(PREFISSI, ' ')
    .replace(/[^a-z0-9 ]+/g, ' ').replace(/\s+/g, ' ').trim();
}

/// Due luoghi sono "lo stesso posto" se il nome normalizzato coincide o se
/// uno contiene l'altro: "Rifugio Bosio-Galli" e "Rif. Bosio Galli" sono
/// lo stesso rifugio scritto da due mani diverse.
function stessoLuogo(a, b) {
  const x = normalizza(a), y = normalizza(b);
  if (!x || !y || x.length < 3 || y.length < 3) return false;
  return x === y || x.includes(y) || y.includes(x);
}

function arrivoDi(x) {
  const p = x.endPoint;
  const la = p && (p.latitude ?? p.lat);
  const ln = p && (p.longitude ?? p.lng ?? p.lon);
  return la != null && ln != null ? [Number(la), Number(ln)] : null;
}

function km(lat1, lon1, lat2, lon2) {
  const R = 6371, r = (x) => x * Math.PI / 180;
  const dLat = r(lat2 - lat1), dLon = r(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2
    + Math.cos(r(lat1)) * Math.cos(r(lat2)) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

(async () => {
  const bSnap = await db.collection('businesses').where('type', '==', 'rifugio').get();
  const rifugi = [];
  bSnap.forEach((d) => {
    const x = d.data(), L = x.location || {};
    const la = L.latitude ?? L.lat, ln = L.longitude ?? L.lng;
    if (la != null && ln != null) rifugi.push({ nome: x.name, lat: Number(la), lng: Number(ln) });
  });

  const snap = await db.collection('public_trails').get();
  const fam = {};
  snap.forEach((d) => {
    const x = d.data();
    const m = String(x.name || '').match(TAPPA);
    if (!m) return;
    const capo = m[1].trim().replace(/[-–—:]+$/, '').trim();
    if (capo.length < 3) return;
    (fam[capo] = fam[capo] || []).push({ ...x,
      n: Number(m[3]), suffisso: (m[4] ? '.' + m[4] : '') + (m[5] || '') });
  });

  const righe = [];
  for (const [nome, tutte] of Object.entries(fam)) {
    const tappe = tutte.filter((t) => !t.suffisso).sort((a, b) => a.n - b.n);
    const varianti = tutte.filter((t) => t.suffisso);
    if (tappe.length < MIN_TAPPE) continue;

    // buchi e ripetizioni nella numerazione
    const numeri = tappe.map((t) => t.n);
    const unici = [...new Set(numeri)];
    const ripetuti = numeri.length - unici.length;
    const atteso = Math.max(...unici) - Math.min(...unici) + 1;
    const buchi = atteso - unici.length;

    // continuita': l'arrivo della N e' la partenza della N+1?
    let continue_ = 0, verificabili = 0;
    for (let i = 0; i < tappe.length - 1; i++) {
      const a = tappe[i], b = tappe[i + 1];
      if (!a.to || !b.from) continue;
      verificabili++;
      if (String(a.to).split(/[;/]/).some((p) => stessoLuogo(p, b.from))) continue_++;
    }

    let conRif = 0;
    for (const t of tappe) {
      const fine = arrivoDi(t);
      const perNome = t.to && rifugi.some((r) => String(t.to).split(/[;/]/).some((p) => stessoLuogo(p, r.nome)));
      const vicino = fine && rifugi.some((r) => km(fine[0], fine[1], r.lat, r.lng) <= 3);
      if (perNome || vicino) conRif++;
    }

    righe.push({
      nome, tappe: tappe.length, varianti: varianti.length,
      kmTot: tappe.reduce((s, t) => s + (t.distance || 0) / 1000, 0),
      rilevate: tappe.filter((t) => t.difficultySource).length,
      descritte: tappe.filter((t) => t.description).length,
      conRif, buchi, ripetuti,
      cont: verificabili ? continue_ / verificabili : null,
      verificabili,
    });
  }

  righe.sort((a, b) => (b.rilevate / b.tappe + b.conRif / b.tappe) - (a.rilevate / a.tappe + a.conRif / a.tappe));

  const pc = (a, b) => b ? `${Math.round(100 * a / b)}%`.padStart(4) : '   —';
  console.log(`famiglie con almeno ${MIN_TAPPE} tappe principali: ${righe.length}\n`);
  console.log('itinerario'.padEnd(38) + 'tappe var    km  grado rifugi testi  contin.  anomalie');
  console.log('─'.repeat(104));
  for (const r of righe) {
    const anomalie = [
      r.buchi > 0 ? `${r.buchi} buchi` : null,
      r.ripetuti > 0 ? `${r.ripetuti} ripetute` : null,
      r.cont !== null && r.cont < 0.5 ? 'sequenza incerta' : null,
      r.verificabili === 0 ? 'da/a assenti' : null,
    ].filter(Boolean).join(', ');
    console.log(
      r.nome.slice(0, 36).padEnd(38) +
      String(r.tappe).padStart(5) + String(r.varianti).padStart(4) +
      r.kmTot.toFixed(0).padStart(6) +
      pc(r.rilevate, r.tappe) + pc(r.conRif, r.tappe) + pc(r.descritte, r.tappe) +
      (r.cont === null ? '     —' : `${Math.round(100 * r.cont)}%`.padStart(8)) +
      '  ' + anomalie);
  }

  const perfette = righe.filter((r) => r.buchi === 0 && r.ripetuti === 0
    && r.cont !== null && r.cont >= 0.8 && r.conRif / r.tappe >= 0.7 && r.descritte === r.tappe);
  console.log(`\ncomplete e coerenti (niente buchi, sequenza >=80%, rifugi >=70%, tutte descritte): ${perfette.length}`);
  perfette.forEach((r) => console.log(`  ${r.nome} — ${r.tappe} tappe, ${r.kmTot.toFixed(0)} km`));
  process.exit(0);
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
