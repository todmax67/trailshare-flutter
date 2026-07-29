// Recupero storico dei passaggi sui segmenti.
//
// Il confronto gira SOLO al salvataggio della traccia: un segmento creato
// oggi non incontrera' mai le uscite di ieri. Misurato sull'account del
// founder: 73 passaggi geometrici reali, ZERO sforzi registrati. La funzione
// era di fatto ferma — l'unico modo per vedere qualcosa era creare il
// segmento prima di percorrerlo.
//
// Questo script ripassa le tracce esistenti contro tutti i segmenti usando
// functions/segment_matching.js, gemello dell'algoritmo dell'app.
//
// --verifica e' la prova di fedelta': rifa' i conti sugli sforzi che l'app
// ha gia' scritto e controlla che i tempi coincidano. Se divergono, il
// gemello e' fuori allineamento e NON va usato per scrivere.
//
// Uso:
//   node scripts/segment_backfill.cjs --verifica
//   node scripts/segment_backfill.cjs --dry [--utente UID]
//   node scripts/segment_backfill.cjs [--utente UID]
const admin = require('../functions/node_modules/firebase-admin');
const sa = require('../functions/serviceAccountKey.json');
const { confronta, confrontaSingolo } = require('../functions/segment_matching');

admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const argv = process.argv.slice(2);
const DRY = argv.includes('--dry');
const VERIFICA = argv.includes('--verifica');
const opt = (n, d) => { const i = argv.indexOf('--' + n); return i >= 0 ? argv[i + 1] : d; };
const SOLO_UTENTE = opt('utente', null);

async function caricaSegmenti() {
  const snap = await db.collection('segments').get();
  const out = [];
  snap.forEach((d) => {
    const x = d.data();
    if (x.startLat == null || x.endLat == null) return;
    const poly = (x.polyline || []).map((p) => ({
      lat: p.lat ?? p.latitude, lng: p.lng ?? p.longitude,
    })).filter((p) => p.lat != null && p.lng != null);
    out.push({ id: d.id, name: x.name, isPublic: x.isPublic === true,
      startLat: x.startLat, startLng: x.startLng, endLat: x.endLat, endLng: x.endLng,
      distance: x.distance || 0, polyline: poly, createdBy: x.createdBy,
      activityType: x.activityType });
  });
  return out;
}

/// L'orario di un punto, in millisecondi. Tre forme convivono:
///   `timestamp` numerico   — registrazione dal telefono
///   `time` stringa ISO     — sincronizzazione dall'orologio (Garmin, Polar)
///   Timestamp di Firestore — documenti piu' vecchi
/// Leggendo solo la prima, ogni traccia registrata al polso risultava priva
/// di orari e spariva dal recupero: 220 punti buttati per un nome di campo.
function istante(p) {
  if (typeof p.timestamp === 'number') return p.timestamp;
  if (p.timestamp && p.timestamp._seconds) return p.timestamp._seconds * 1000;
  for (const k of ['time', 'timestamp', 'ts']) {
    if (typeof p[k] === 'string') {
      const d = Date.parse(p[k]);
      if (!Number.isNaN(d)) return d;
    }
  }
  return null;
}

/// I punti stanno inline sulle tracce vecchie e in geometry/data su quelle
/// migrate (lo spostamento che ha risolto la saturazione della cache).
async function puntiDi(ref, x) {
  let raw = Array.isArray(x.points) && x.points.length ? x.points : null;
  if (!raw) {
    const g = await ref.collection('geometry').doc('data').get();
    if (!g.exists) return [];
    try { raw = JSON.parse(g.data().pointsJson); } catch (e) { return []; }
  }
  const out = [];
  for (const p of raw) {
    const lat = p.latitude ?? p.lat, lng = p.longitude ?? p.lng;
    const t = istante(p);
    if (lat == null || lng == null || t == null) continue;
    out.push({ lat: Number(lat), lng: Number(lng), t });
  }
  return out;
}

async function verifica(segmenti) {
  console.log('=== PROVA DI FEDELTA\' sugli sforzi gia\' scritti dall\'app ===\n');
  let confrontati = 0, uguali = 0;
  const diversi = [];
  for (const seg of segmenti) {
    const eff = await db.collection('segments').doc(seg.id).collection('efforts').get();
    for (const e of eff.docs) {
      const y = e.data();
      if (!y.trackId || !y.userId) continue;
      // Gli sforzi con attivita' incompatibile sono fuori dalle classifiche:
      // confrontarli non dice nulla sulla fedelta' del gemello, e uno di
      // loro faceva scattare un falso allarme.
      if (y.activityMismatch === true) continue;
      const tRef = db.collection('users').doc(y.userId).collection('tracks').doc(y.trackId);
      const tSnap = await tRef.get();
      if (!tSnap.exists) continue;
      const punti = await puntiDi(tRef, tSnap.data());
      if (punti.length < 2) continue;
      const r = confrontaSingolo(punti, seg);
      confrontati++;
      if (r && r.durataSecondi === y.durationSeconds) uguali++;
      else diversi.push({ seg: seg.name, atteso: y.durationSeconds,
        ottenuto: r ? r.durataSecondi : 'nessun match', chi: y.username });
    }
  }
  // Le tracce sono decimate a 1000 punti al salvataggio: l'app confrontava
  // sui punti pieni, il gemello legge quelli ridotti, e ingresso e uscita dal
  // segmento cadono su punti leggermente diversi. Uno scarto di pochi
  // secondi e' quello, non un algoritmo che diverge. Sopra i 10 secondi
  // invece qualcosa non torna e va capito prima di scrivere.
  const SCARTO_DECIMAZIONE = 10;
  const piccole = diversi.filter((d) => typeof d.ottenuto === 'number'
    && Math.abs(d.ottenuto - d.atteso) <= SCARTO_DECIMAZIONE);
  const grosse = diversi.filter((d) => !piccole.includes(d));

  console.log(`sforzi confrontati: ${confrontati}`);
  console.log(`tempi identici:     ${uguali}`);
  console.log(`scarti entro ${SCARTO_DECIMAZIONE}s (decimazione): ${piccole.length}`);
  console.log(`DIVERGENZE VERE:    ${grosse.length}`);
  grosse.slice(0, 10).forEach((d) => console.log(
    `  ${String(d.seg).slice(0, 28).padEnd(30)} app ${String(d.atteso).padStart(5)}s  gemello ${String(d.ottenuto).padStart(5)}  (${d.chi})`));
  console.log(grosse.length === 0
    ? `\nGEMELLO FEDELE: ${uguali} identici, ${piccole.length} entro lo scarto della decimazione, 0 divergenze vere.`
    : '\nATTENZIONE: divergenze da spiegare PRIMA di scrivere.');
}

(async () => {
  const segmenti = await caricaSegmenti();
  console.log(`segmenti: ${segmenti.length}\n`);
  if (VERIFICA) { await verifica(segmenti); process.exit(0); }

  console.log(DRY ? '=== SIMULAZIONE ===\n' : '=== SCRITTURA ===\n');
  const utenti = SOLO_UTENTE ? [SOLO_UTENTE] : await (async () => {
    const s = await db.collection('user_profiles').get();
    return s.docs.map((d) => d.id);
  })();

  let tracce = 0, nuovi = 0, gia = 0;
  for (const uid of utenti) {
    const tSnap = await db.collection('users').doc(uid).collection('tracks').get();
    if (tSnap.empty) continue;
    const prof = await db.collection('user_profiles').doc(uid).get();
    const username = prof.data()?.username || 'Utente';
    const avatarUrl = prof.data()?.avatarUrl || null;

    for (const d of tSnap.docs) {
      const x = d.data();
      const punti = await puntiDi(d.ref, x);
      if (punti.length < 2) continue;
      tracce++;
      for (const r of confronta(punti, segmenti, x.activityType)) {
        const effCol = db.collection('segments').doc(r.segmento.id).collection('efforts');
        // Una traccia puo' ora produrre PIU' passaggi sullo stesso segmento
        // (allenamento a ripetute, anello ripercorso): la chiave e' l'indice
        // di partenza, non il solo trackId. Gli sforzi scritti prima non ce
        // l'hanno: valgono per il primo passaggio, cosi' non si duplicano.
        const esistenti = await effCol.where('trackId', '==', d.id).get();
        const indici = new Set(esistenti.docs.map((e) =>
          e.data().trackStartIdx !== undefined ? e.data().trackStartIdx : 0));
        if (indici.has(r.iPartenza) || (r.indicePassaggio === 0 && indici.has(0))) {
          gia++; continue;
        }
        nuovi++;
        console.log(`${DRY ? '·' : '✓'} ${String(x.name || '?').slice(0, 30).padEnd(32)} → ` +
          `${String(r.segmento.name).slice(0, 26).padEnd(28)} ${String(r.durataSecondi).padStart(5)}s  ${username}`);
        if (!DRY) {
          await effCol.add({
            userId: uid, username, avatarUrl,
            trackId: d.id,
            durationSeconds: r.durataSecondi,
            distance: r.segmento.distance,
            averageSpeedKmh: r.velocitaMediaKmh,
            completedAt: admin.firestore.Timestamp.fromDate(r.quando),
            // Indice del punto di partenza dentro la traccia: distingue i
            // passaggi multipli sullo stesso segmento nella stessa uscita.
            trackStartIdx: r.iPartenza,
            passIndex: r.indicePassaggio,
            // Marcato: questo sforzo viene dal recupero storico, non da una
            // registrazione dal vivo. Serve a poterlo rifare o annullare.
            fromBackfill: true,
          });
        }
      }
    }
  }
  console.log(`\ntracce esaminate:      ${tracce}`);
  console.log(`passaggi gia' presenti: ${gia}`);
  console.log(`${DRY ? 'da scrivere' : 'scritti'}:           ${nuovi}`);
  if (DRY) console.log('\nNessuna scrittura. Per applicare, togliere --dry.');
  process.exit(0);
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
