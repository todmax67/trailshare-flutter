// SUPPORT — READ-ONLY: quante tracce vengono salvate al giorno, su tutti gli
// utenti? Serve a distinguere un problema individuale da una regressione
// sistemica (es. dopo una release sugli store).
//
// Uso: node scripts/support_check_save_health.cjs [giorni]

const admin = require('firebase-admin');
const sa = require('../functions/serviceAccountKey.json');
admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();
// Script one-shot: REST invece di gRPC. Più tollerante su reti/DNS domestici
// (il resolver interno di gRPC ignora dns.setServers e su alcuni router non
// risolve firestore.googleapis.com).
db.settings({ preferRest: true });

const days = Number(process.argv[2] || 21);

(async () => {
  const since = Date.now() - days * 86400000;
  // NB: il `where('createdAt', ...)` su collectionGroup richiederebbe un indice
  // dedicato. Per una diagnosi una tantum scansioniamo e filtriamo in memoria,
  // leggendo solo i campi necessari.
  const snap = await db
    .collectionGroup('tracks')
    .select('createdAt', 'isPlanned', 'userId')
    .get();

  const perDay = new Map();
  let planned = 0;
  let noCreatedAt = 0;
  snap.forEach((d) => {
    const t = d.data();
    if (t.isPlanned === true) {
      planned++;
      return; // i percorsi pianificati non sono registrazioni
    }
    if (!t.createdAt || !t.createdAt.toDate) {
      noCreatedAt++;
      return;
    }
    const ts = t.createdAt.toDate();
    if (ts.getTime() < since) return;
    const day = ts.toISOString().slice(0, 10);
    perDay.set(day, (perDay.get(day) || 0) + 1);
  });
  console.log(`(scansionate ${snap.size} tracce in totale; ${noCreatedAt} senza createdAt)`);

  console.log(`═══ TRACCE REGISTRATE PER GIORNO (ultimi ${days} gg) ═══`);
  console.log(`(esclusi ${planned} percorsi pianificati)\n`);
  const keys = [...perDay.keys()].sort();
  for (const k of keys) {
    const n = perDay.get(k);
    console.log(`${k}  ${String(n).padStart(3)}  ${'█'.repeat(n)}`);
  }

  const counts = keys.map((k) => perDay.get(k));
  const avg = counts.length ? counts.reduce((a, b) => a + b, 0) / counts.length : 0;
  console.log(`\nmedia/giorno: ${avg.toFixed(1)}`);
  const last3 = keys.slice(-3).map((k) => `${k}=${perDay.get(k)}`).join('  ');
  console.log(`ultimi 3 giorni: ${last3 || '— nessuna traccia —'}`);

  // Sessioni LiveTrack recenti (indicatore indipendente di attività reale)
  const live = await db
    .collection('live_sessions')
    .where('startTime', '>=', admin.firestore.Timestamp.fromDate(new Date(Date.now() - 5 * 86400000)))
    .get();
  console.log(`\n═══ SESSIONI LIVETRACK ultimi 5 gg: ${live.size} ═══`);
  live.forEach((d) => {
    const s = d.data();
    console.log(
      `• ${d.id} uid=${s.userId} start=${s.startTime?.toDate?.().toISOString() || '—'} ` +
      `punti=${Array.isArray(s.path) ? s.path.length : 0} attiva=${s.isActive === true}`
    );
  });

  process.exit(0);
})().catch((e) => {
  console.error('Errore:', e);
  process.exit(1);
});
