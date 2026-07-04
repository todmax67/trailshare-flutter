#!/usr/bin/env node
/**
 * Backfill: scrive le stats SETTIMANALI denormalizzate su user_profiles
 * (weeklyStatsWeekId / weeklyDistanceCurrent / weeklyElevationCurrent /
 * weeklyTracksCurrent / weeklyXpCurrent), calcolandole dalle tracce della
 * settimana corrente per TUTTI i profili — zeri inclusi: la PRESENZA del
 * campo dice al client che la denormalizzazione è attiva (fast path della
 * classifica); l'assenza su tutti i profili fa scattare il fallback
 * real-time.
 *
 * Eseguire UNA volta, SUBITO DOPO il deploy di onTrackCreate/onTrackUpdate
 * (che da lì in poi mantengono i bucket col reset lazy). Idempotente:
 * RICALCOLA e sovrascrive i soli campi weekly* (niente increment → nessun
 * doppio conteggio se rilanciato o se una traccia arriva durante il run).
 *
 * Predicato attività (canonico, identico al client):
 *   isPlanned !== true && distance > 0
 * Data traccia: recordedAt ?? createdAt con parsing robusto (Timestamp,
 * stringa ISO, epoch ms) — gli stessi formati misti gestiti dal client.
 * XP: floor(dist/100) + floor(ele/10) PER TRACCIA (parità col client e con
 * applyActivityStatsDenorm in functions/index.js).
 *
 *   node scripts/backfill_weekly_stats.cjs           # dry-run
 *   node scripts/backfill_weekly_stats.cjs --apply   # applica
 */
const admin = require('firebase-admin');
const serviceAccount = require('../functions/serviceAccountKey.json');
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

const APPLY = process.argv.includes('--apply');

// Lunedì corrente in ora italiana — stesso algoritmo di
// currentActivityPeriodIds in functions/index.js.
function currentWeek() {
  const rome = new Date(
    new Date().toLocaleString('sv-SE', { timeZone: 'Europe/Rome' }));
  const monday = new Date(rome);
  monday.setDate(rome.getDate() - ((rome.getDay() + 6) % 7));
  const weekId = `${monday.getFullYear()}-` +
    `${String(monday.getMonth() + 1).padStart(2, '0')}-` +
    `${String(monday.getDate()).padStart(2, '0')}`;
  // Istante assoluto di inizio settimana: mezzanotte italiana. +02:00 è
  // l'offset CEST (ora legale) — corretto per luglio 2026; se mai
  // rilanciato in ora solare usare +01:00.
  const weekStart = new Date(`${weekId}T00:00:00+02:00`);
  return { weekId, weekStart };
}

function parseDate(v) {
  if (v == null) return null;
  if (typeof v.toDate === 'function') return v.toDate(); // Timestamp
  if (typeof v === 'string') {
    const d = new Date(v);
    return isNaN(d.getTime()) ? null : d;
  }
  if (typeof v === 'number') return new Date(v);
  return null;
}

(async () => {
  const { weekId, weekStart } = currentWeek();
  console.log(`Settimana corrente: ${weekId} (start ${weekStart.toISOString()})`);

  const profiles = await db.collection('user_profiles').get();
  let processed = 0;
  let withActivity = 0;
  let applied = 0;

  for (const profile of profiles.docs) {
    const uid = profile.id;
    const tracksSnap =
      await db.collection('users').doc(uid).collection('tracks').get();

    let dist = 0, ele = 0, tracks = 0, xp = 0;
    for (const t of tracksSnap.docs) {
      const d = t.data();
      if (d.isPlanned === true) continue;
      const trackDist = d.distance || 0;
      if (trackDist <= 0) continue; // tracce vuote/annullate: non attività
      const when = parseDate(d.recordedAt) || parseDate(d.createdAt);
      if (!when || when < weekStart) continue;
      const trackEle = d.elevationGain || 0;
      dist += trackDist;
      ele += trackEle;
      tracks += 1;
      xp += Math.floor(trackDist / 100) + Math.floor(trackEle / 10);
    }

    processed++;
    if (tracks > 0) withActivity++;
    console.log(`${APPLY ? 'APPLY' : 'DRY-RUN'}: ${uid} → ${tracks} tracce, ` +
      `${(dist / 1000).toFixed(1)} km, +${ele.toFixed(0)} m, ${xp} XP ` +
      `(${tracksSnap.size} doc letti)`);

    if (APPLY) {
      await profile.ref.set({
        weeklyStatsWeekId: weekId,
        weeklyDistanceCurrent: dist,
        weeklyElevationCurrent: ele,
        weeklyTracksCurrent: tracks,
        weeklyXpCurrent: xp,
      }, { merge: true });
      applied++;
    }
  }

  console.log(`\nProfili: ${processed}, con attività questa settimana: ` +
    `${withActivity}, scritti: ${applied}`);
  if (!APPLY) {
    console.log('Dry-run: nessuna scrittura. Rilancia con --apply per applicare.');
  }
  process.exit(0);
})().catch((e) => { console.error('ERR', e); process.exit(1); });
