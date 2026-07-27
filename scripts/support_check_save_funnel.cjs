// SUPPORT — READ-ONLY: legge il funnel di salvataggio tracce scritto da
// SaveDiagnosticsService nella collection `save_diagnostics`.
//
// Risponde alla domanda che nel ticket del 2026-07-26 non sapevamo affrontare:
// quanti salvataggi restano solo locali o falliscono, su quali piattaforme e
// versioni?
//
// Uso:
//   node scripts/support_check_save_funnel.cjs [giorni] [email|uid]
// Esempi:
//   node scripts/support_check_save_funnel.cjs 7
//   node scripts/support_check_save_funnel.cjs 30 utente@example.com
//
// Ricorda NODE_PATH: firebase-admin è installato solo in functions/.
//   NODE_PATH=$PWD/functions/node_modules node scripts/support_check_save_funnel.cjs 7

const admin = require('firebase-admin');
const sa = require('../functions/serviceAccountKey.json');
admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();
db.settings({ preferRest: true });

const days = Number(process.argv[2] || 7);
const who = process.argv[3];

const pct = (n, tot) => (tot ? ((n / tot) * 100).toFixed(1) + '%' : '—');

(async () => {
  let uid;
  if (who) {
    const u = who.includes('@')
      ? await admin.auth().getUserByEmail(who)
      : await admin.auth().getUser(who);
    uid = u.uid;
    console.log(`Filtro utente: ${u.email} (${uid})\n`);
  }

  let q = db.collection('save_diagnostics');
  if (uid) q = q.where('userId', '==', uid);
  const snap = await q.get();

  const since = Date.now() - days * 86400000;
  const events = [];
  snap.forEach((d) => {
    const e = d.data();
    // `atClient` è sempre presente; `at` è null per i doc ancora in coda
    // offline — cioè proprio i casi che ci interessano di più.
    const t = Date.parse(e.atClient || '') || e.at?.toDate?.().getTime();
    if (!t || t < since) return;
    events.push({ ...e, _t: t });
  });

  if (!events.length) {
    console.log(
      `Nessun evento negli ultimi ${days} giorni.\n` +
      `Se la build con SaveDiagnosticsService non è ancora sugli store, è normale.`
    );
    process.exit(0);
  }

  events.sort((a, b) => a._t - b._t);

  const byEvent = new Map();
  const byPlatform = new Map();
  const byVersion = new Map();
  const failures = [];
  const localOnly = [];

  for (const e of events) {
    byEvent.set(e.event, (byEvent.get(e.event) || 0) + 1);
    const pk = `${e.platform || '?'}`;
    byPlatform.set(pk, (byPlatform.get(pk) || 0) + 1);
    byVersion.set(e.appVersion || '?', (byVersion.get(e.appVersion || '?') || 0) + 1);
    if (e.event === 'failed') failures.push(e);
    if (e.event === 'localOnly') localOnly.push(e);
  }

  const started = byEvent.get('started') || 0;
  const confirmed = byEvent.get('confirmedServer') || 0;
  const local = byEvent.get('localOnly') || 0;
  const failed = byEvent.get('failed') || 0;

  console.log(`═══ FUNNEL SALVATAGGIO (ultimi ${days} gg, ${events.length} eventi) ═══\n`);
  console.log(`tentativi (started)      : ${started}`);
  console.log(`confermati dal server    : ${confirmed}  ${pct(confirmed, started)}`);
  console.log(`solo locali (in coda)    : ${local}  ${pct(local, started)}`);
  console.log(`falliti                  : ${failed}  ${pct(failed, started)}`);

  const orphans = started - confirmed - local - failed;
  if (orphans > 0) {
    console.log(
      `\n⚠️  ${orphans} tentativi senza esito registrato: l'app è stata uccisa ` +
      `durante il salvataggio, oppure l'evento di esito è rimasto offline.`
    );
  }

  console.log('\n— per piattaforma —');
  [...byPlatform.entries()].sort((a, b) => b[1] - a[1])
    .forEach(([k, v]) => console.log(`  ${k}: ${v}`));
  console.log('\n— per versione app —');
  [...byVersion.entries()].sort((a, b) => b[1] - a[1])
    .forEach(([k, v]) => console.log(`  ${k}: ${v}`));

  if (failures.length) {
    console.log(`\n═══ FALLIMENTI (${failures.length}) ═══`);
    failures.slice(-20).forEach((e) => {
      console.log(
        `• ${e.atClient} uid=${e.userId} ${e.platform}/${e.appVersion} ` +
        `punti=${e.pointsCount ?? '?'} online=${e.online}\n  errore: ${e.error || '—'}`
      );
    });
  }

  if (localOnly.length) {
    console.log(`\n═══ SOLO LOCALI (${localOnly.length}) ═══`);
    console.log('(la traccia è sul telefono e sincronizza da sola: non è una perdita,');
    console.log(' ma è lo stato in cui l\'utente può non vederla nelle liste)');
    localOnly.slice(-20).forEach((e) => {
      console.log(
        `• ${e.atClient} uid=${e.userId} ${e.platform}/${e.appVersion} ` +
        `punti=${e.pointsCount ?? '?'} online=${e.online} track=${e.trackId || '—'}`
      );
    });
  }

  process.exit(0);
})().catch((e) => {
  console.error('Errore:', e);
  process.exit(1);
});
