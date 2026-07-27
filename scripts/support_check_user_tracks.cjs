// SUPPORT — verifica READ-ONLY delle tracce di un utente.
//
// Serve per rispondere ai ticket tipo "ho salvato il trek ma non lo trovo":
// dice se i documenti esistono sul SERVER, e in particolare se ci sono doc
// senza `createdAt` (invisibili alle query dell'app, che ordinano tutte per
// createdAt desc) o sessioni LiveTrack con il path recuperabile.
//
// Uso:
//   node scripts/support_check_user_tracks.cjs <email|uid> [giorni]
// Esempi:
//   node scripts/support_check_user_tracks.cjs utente@example.com
//   node scripts/support_check_user_tracks.cjs Abc123Uid 7
//
// NON scrive nulla. Nessun campo sensibile stampato oltre a quelli necessari.

const admin = require('firebase-admin');
const sa = require('../functions/serviceAccountKey.json');
admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const arg = process.argv[2];
const days = Number(process.argv[3] || 7);
if (!arg) {
  console.error('Uso: node scripts/support_check_user_tracks.cjs <email|uid> [giorni]');
  process.exit(1);
}

const fmt = (v) => {
  if (!v) return '—';
  if (typeof v === 'string') return v;
  if (v.toDate) return v.toDate().toISOString();
  return String(v);
};
const km = (m) => (typeof m === 'number' ? (m / 1000).toFixed(2) + ' km' : '—');

(async () => {
  // 1. Risolvi l'utente
  let user;
  try {
    user = arg.includes('@')
      ? await admin.auth().getUserByEmail(arg)
      : await admin.auth().getUser(arg);
  } catch (e) {
    console.error(`❌ Utente non trovato in Auth: ${arg} (${e.code || e.message})`);
    process.exit(2);
  }

  console.log('═══ UTENTE ═══');
  console.log(`uid        : ${user.uid}`);
  console.log(`email      : ${user.email} (verificata: ${user.emailVerified})`);
  console.log(`creato il  : ${user.metadata.creationTime}`);
  console.log(`ultimo login: ${user.metadata.lastSignInTime}`);
  console.log(`provider   : ${user.providerData.map((p) => p.providerId).join(', ')}`);

  // NB: il profilo utente sta in `user_profiles/{uid}`. Il doc `users/{uid}` è
  // solo il contenitore delle sub-collection (tracks, integrations) e in
  // Firestore può legittimamente non esistere: la sua assenza NON è un errore.
  const profile = await db.collection('user_profiles').doc(user.uid).get();
  if (profile.exists) {
    const p = profile.data();
    console.log(`username   : ${p.username || '—'}`);
    console.log(`regione    : ${p.regionId || p.region || '—'}`);
    console.log(`push token : ${p.fcmToken ? 'sì' : 'no'}`);
  } else {
    console.log('⚠️  profilo user_profiles/{uid} assente');
  }
  const userDoc = await db.collection('users').doc(user.uid).get();
  if (userDoc.exists) {
    const u = userDoc.data();
    console.log(`piano      : ${u.subscriptionTier || u.plan || '—'}`);
    console.log(`XP         : ${u.xp ?? '—'}`);
  }

  // 2. TUTTE le tracce (nessun orderBy: così vediamo anche i doc che le
  //    query dell'app escluderebbero perché senza createdAt)
  const snap = await db.collection('users').doc(user.uid).collection('tracks').get();
  console.log(`\n═══ TRACCE (${snap.size} totali sul server) ═══`);

  const rows = [];
  snap.forEach((d) => {
    const t = d.data();
    rows.push({
      id: d.id,
      name: t.name || '(senza nome)',
      createdAt: t.createdAt || null,
      recordedAt: t.recordedAt || null,
      activity: t.activityType || '—',
      distance: t.distance,
      points: t.pointsCount ?? (Array.isArray(t.points) ? t.points.length : null),
      hasGeometryDoc: t.hasGeometryDoc === true,
      isPublic: t.isPublic === true,
    });
  });

  const keyOf = (r) => fmt(r.createdAt) !== '—' ? fmt(r.createdAt) : fmt(r.recordedAt);
  rows.sort((a, b) => String(keyOf(b)).localeCompare(String(keyOf(a))));

  const cutoff = Date.now() - days * 86400000;
  const recent = rows.filter((r) => {
    const k = keyOf(r);
    return k !== '—' && Date.parse(k) >= cutoff;
  });

  console.log(`\n— Ultimi ${days} giorni: ${recent.length} tracce —`);
  for (const r of recent.length ? recent : rows.slice(0, 10)) {
    console.log(
      `• ${r.id}  ${keyOf(r)}\n` +
      `  nome="${r.name}" attività=${r.activity} ${km(r.distance)} punti=${r.points ?? '?'} ` +
      `geometry=${r.hasGeometryDoc ? 'sì' : 'NO'} pubblica=${r.isPublic ? 'sì' : 'no'}\n` +
      `  createdAt=${fmt(r.createdAt)} recordedAt=${fmt(r.recordedAt)}`
    );
  }
  if (!recent.length && rows.length) {
    console.log(`(nessuna traccia negli ultimi ${days} giorni: sopra le 10 più recenti in assoluto)`);
  }

  // 3. Anomalie che rendono una traccia "invisibile" nell'app
  const noCreatedAt = rows.filter((r) => !r.createdAt);
  const noGeometry = rows.filter((r) => !r.hasGeometryDoc && !r.points);
  console.log('\n═══ ANOMALIE ═══');
  console.log(`senza createdAt (invisibili alle liste dell'app): ${noCreatedAt.length}`);
  noCreatedAt.forEach((r) => console.log(`  → ${r.id} "${r.name}" recordedAt=${fmt(r.recordedAt)}`));
  console.log(`senza geometria/punti (traccia vuota): ${noGeometry.length}`);
  noGeometry.forEach((r) => console.log(`  → ${r.id} "${r.name}" ${keyOf(r)}`));

  // 4. Sessioni LiveTrack: se attive durante il trek, il path è sul server
  //    ed è recuperabile anche se la traccia non è stata salvata.
  const live = await db.collection('live_sessions').where('userId', '==', user.uid).get();
  console.log(`\n═══ SESSIONI LIVETRACK (${live.size}) ═══`);
  const liveRows = [];
  live.forEach((d) => {
    const s = d.data();
    liveRows.push({
      id: d.id,
      start: s.startTime,
      last: s.lastUpdate,
      end: s.endTime,
      active: s.isActive === true,
      pathLen: Array.isArray(s.path) ? s.path.length : 0,
    });
  });
  liveRows.sort((a, b) => String(fmt(b.start)).localeCompare(String(fmt(a.start))));
  for (const s of liveRows.slice(0, 10)) {
    console.log(
      `• ${s.id} start=${fmt(s.start)} lastUpdate=${fmt(s.last)} end=${fmt(s.end)} ` +
      `attiva=${s.active} punti_path=${s.pathLen}`
    );
  }
  if (liveRows.some((s) => s.pathLen > 0)) {
    console.log('\n💡 Un path LiveTrack con punti > 0 è ricostruibile in GPX da inviare all\'utente.');
  }

  process.exit(0);
})().catch((e) => {
  console.error('Errore:', e);
  process.exit(1);
});
