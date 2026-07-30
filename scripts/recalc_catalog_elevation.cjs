// Ricalcola dislivello, difficoltà e tempi di TUTTO il catalogo con
// l'algoritmo che l'app usa per ogni altra traccia.
//
// PERCHE'
// L'importer del catalogo aveva una formula propria che confrontava solo punti
// ADIACENTI e scartava i passi sotto i 3 m invece di accumularli. Risultato:
// il dislivello dipendeva dalla DENSITA' di campionamento invece che dal
// terreno (su una traccia fitta una salita costante di 2 m per punto contava
// zero, mentre il rumore del DEM sopra i 3 m veniva sommato), e lo stesso
// percorso mostrava numeri diversi se importato in catalogo o registrato
// dall'utente. Il codice e' già stato corretto per i NUOVI import; questo
// script allinea gli esistenti.
//
// COSA TOCCA, E PERCHE' TUTTO INSIEME
// elevationGain alimenta `gainPerKm` in DifficultyCalculator e la DIN 33466 di
// `oreStimate`, che a sua volta decide `piuGiorni` e `giorniStimati`.
// Aggiornare solo il dislivello lascerebbe difficoltà e tempi calcolati su un
// valore che non esiste piu': i cinque campi si muovono in blocco.
//
// COSA NON TOCCA
//  - Le geometrie: solo lettura. Le quote sono quelle già in `coordinatesJson`.
//  - I sentieri con quote assenti o tutte a zero: saltati, non inventiamo nulla
//    (sono i 236 fuori area alpina, vedi scripts/backfill_trail_elevations.cjs).
//  - `difficulty` dichiarata dalla fonte OSM (T/E/EE/EEA): e' un dato altrui.
//
// IMPATTO ATTESO (misurato su 355 schede con le classi Dart reali):
// 66% grado invariato, 30% sale di un grado, 4% scende. E' visibile agli
// utenti — un sentiero "Facile" può diventare "Moderato". Va fatto come
// operazione dichiarata.
//
// Uso:
//   node scripts/recalc_catalog_elevation.cjs                 (dry-run)
//   node scripts/recalc_catalog_elevation.cjs --apply
//   node scripts/recalc_catalog_elevation.cjs --apply --limit 50
const path = require('path');
const admin = require(path.join(__dirname, '../functions/node_modules/firebase-admin'));
const sa = require(path.join(__dirname, '../functions/serviceAccountKey.json'));
const ep = require(path.join(__dirname, '../functions/elevation_processor'));
const { compute } = require(path.join(__dirname, '../functions/difficulty_calculator'));

admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const argv = process.argv.slice(2);
const APPLY = argv.includes('--apply');
const opt = (n, d) => { const i = argv.indexOf('--' + n); return i >= 0 ? argv[i + 1] : d; };
const LIMIT = Number(opt('limit', Infinity));
const ORE_GIORNATA = Number(opt('ore', 8));    // oltre = non fattibile in giornata
const ORE_PER_GIORNO = Number(opt('orgg', 6));

/// Passo per attività [km/h in piano, m/h in salita]. Identico a
/// scripts/trail_effort_backfill.cjs: se divergesse, i tempi ballerebbero fra
/// i due script.
const PASSO = {
  trekking: [4, 400], walking: [4, 400], escursionismo: [4, 400],
  running: [8, 600], trailRunning: [8, 600],
  cycling: [15, 600], gravelBiking: [13, 600],
  eBike: [16, 750], eMountainBike: [13, 750], mountainBiking: [11, 600],
  skiTouring: [3.5, 350], snowshoeing: [3, 300],
  nordicSkiing: [8, 400], alpineSkiing: [10, 500], snowboarding: [10, 500],
};

/// DIN 33466 / SAC: il maggiore fra tempo orizzontale e verticale, più metà
/// del minore.
function oreDiPercorrenza(km, gain, attivita) {
  const [vOriz, vVert] = PASSO[attivita] || PASSO.trekking;
  const orizz = km / vOriz;
  const vert = (gain || 0) / vVert;
  return Math.max(orizz, vert) + Math.min(orizz, vert) / 2;
}

const ORD = ['t1', 't2', 't3', 't4', 't5'];

(async () => {
  console.log(APPLY ? '*** APPLY: scrive su Firestore ***' : '=== DRY-RUN: nessuna scrittura ===');
  console.log(`soglie: giornata ${ORE_GIORNATA}h, ore/giorno ${ORE_PER_GIORNO}\n`);

  // Le geometrie si leggono A BLOCCHI e si scartano subito dopo l'uso.
  // Caricarle tutte in una Map costava oltre 1,1 GB: su questo progetto la
  // memoria satura dai `coordinatesJson` (fino a 900 KB l'uno, 16 mila doc) e'
  // un problema noto, non un'ipotesi.
  const GEO_CHUNK = 150;

  /// Quote di un blocco di id: { id -> [quota|null, ...] }. Salta chi non ha
  /// nemmeno una quota reale (tutte nulle o tutte a zero): non c'e' niente da
  /// cui calcolare e non le inventiamo.
  async function quotePerIds(ids) {
    const out = new Map();
    for (let i = 0; i < ids.length; i += GEO_CHUNK) {
      const fetta = ids.slice(i, i + GEO_CHUNK);
      const refs = fetta.map(id => db.collection('public_trail_geometries').doc(id));
      const snaps = await db.getAll(...refs);
      for (const s of snaps) {
        if (!s.exists) continue;
        const cj = s.data().coordinatesJson;
        if (typeof cj !== 'string' || !cj) continue;
        let arr;
        try { arr = JSON.parse(cj); } catch { continue; }
        if (!Array.isArray(arr) || arr.length < 2) continue;
        const eles = arr.map(c => (Array.isArray(c) && c.length > 2 ? c[2] : null));
        if (!eles.some(v => v !== null && v !== 0)) continue;
        out.set(s.id, eles);
      }
    }
    return out;
  }

  console.log('Lettura schede (solo i campi che servono)...');
  const trails = await db.collection('public_trails')
      .select('name', 'distance', 'activityType', 'elevationGain',
              'computedDifficulty', 'piuGiorni')
      .get();
  console.log(`  schede: ${trails.size}\n`);

  const st = {
    aggiornati: 0, invariati: 0, senzaQuote: 0, senzaDistanza: 0, errori: 0,
    gradoSu: 0, gradoGiu: 0, gradoUguale: 0,
    diventatiPiuGiorni: 0, nonPiuMultiGiorno: 0,
  };
  const transizioni = {};
  const esempi = [];
  let deltaGainTot = 0, nGain = 0;

  let batch = db.batch(), inBatch = 0;
  const flush = async () => {
    if (!APPLY || inBatch === 0) { inBatch = 0; batch = db.batch(); return; }
    await batch.commit();
    batch = db.batch();
    inBatch = 0;
  };

  let visti = 0;
  // Si procede a blocchi: per ogni blocco si leggono le geometrie, si elabora,
  // e la memoria torna libera prima del blocco successivo.
  for (let b = 0; b < trails.docs.length && visti < LIMIT; b += GEO_CHUNK) {
    const blocco = trails.docs.slice(b, b + GEO_CHUNK);
    const quote = await quotePerIds(blocco.map(d => d.id));

    for (const doc of blocco) {
    if (visti >= LIMIT) break;
    const x = doc.data();
    const eles = quote.get(doc.id);
    if (!eles) { st.senzaQuote++; continue; }
    const km = (x.distance || 0) / 1000;
    if (!km || km < 0.1) { st.senzaDistanza++; continue; }
    visti++;

    try {
      const r = ep.process(eles, x.activityType);
      if (!r) { st.senzaQuote++; continue; }

      const gain = Math.round(r.elevationGain);
      const loss = Math.round(r.elevationLoss);
      const min = Math.round(r.minElevation);
      const max = Math.round(r.maxElevation);

      const gainVecchio = Number(x.elevationGain);
      if (Number.isFinite(gainVecchio)) { deltaGainTot += gain - gainVecchio; nGain++; }

      const ore = oreDiPercorrenza(km, gain, x.activityType);
      const upd = {
        elevationGain: gain,
        elevationLoss: loss,
        minAltitude: min,
        maxAltitude: max,
        oreStimate: Math.round(ore * 10) / 10,
        elevationRecalcAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      const gradoVecchio = x.computedDifficulty || (x.piuGiorni ? '(multi)' : null);
      let gradoNuovo;
      if (ore > ORE_GIORNATA) {
        // Su un cammino di piu' giorni un livello T1-T5 non direbbe nulla:
        // saturerebbe a T5 per la sola lunghezza. Si scrive che serve piu' di
        // una giornata e quanti giorni, e si toglie il livello.
        upd.piuGiorni = true;
        upd.giorniStimati = Math.ceil(ore / ORE_PER_GIORNO);
        upd.computedDifficulty = admin.firestore.FieldValue.delete();
        gradoNuovo = '(multi)';
        if (gradoVecchio !== '(multi)') st.diventatiPiuGiorni++;
      } else {
        const d = compute({ distance: x.distance, elevationGain: gain, elevationLoss: loss }, x.activityType);
        if (!d) { st.senzaDistanza++; continue; }
        upd.computedDifficulty = d.key;
        upd.piuGiorni = false;
        upd.giorniStimati = admin.firestore.FieldValue.delete();
        gradoNuovo = d.key;
        if (gradoVecchio === '(multi)') st.nonPiuMultiGiorno++;
      }

      const iV = ORD.indexOf(gradoVecchio), iN = ORD.indexOf(gradoNuovo);
      if (gradoVecchio === gradoNuovo) st.gradoUguale++;
      else if (iV >= 0 && iN >= 0) { iN > iV ? st.gradoSu++ : st.gradoGiu++; }
      if (gradoVecchio !== gradoNuovo) {
        const k = `${gradoVecchio || '(nessuno)'} -> ${gradoNuovo}`;
        transizioni[k] = (transizioni[k] || 0) + 1;
      }

      const cambiato = gain !== gainVecchio || gradoVecchio !== gradoNuovo;
      if (!cambiato) { st.invariati++; continue; }

      if (esempi.length < 12) {
        esempi.push({
          nome: String(x.name || '').slice(0, 30), km: km.toFixed(1),
          gVecchio: Number.isFinite(gainVecchio) ? gainVecchio : '-', gNuovo: gain,
          dVecchio: gradoVecchio || '-', dNuovo: gradoNuovo, ore: ore.toFixed(1),
        });
      }

      if (APPLY) {
        batch.update(doc.ref, upd);
        if (++inBatch >= 400) await flush();
      }
      st.aggiornati++;
      if (st.aggiornati % 1000 === 0) console.log(`  ...${st.aggiornati} aggiornati`);
    } catch (e) {
      st.errori++;
      if (st.errori <= 5) console.log(`  ${doc.id}: ERRORE ${e.message}`);
    }
    }
    // Il batch si chiude a fine blocco: cosi' un'interruzione lascia scritto
    // tutto quello che era stato elaborato, non un blocco a metà.
    await flush();
    quote.clear();
  }
  await flush();

  console.log('\nEsempi:');
  console.log('sentiero                          km   D+ prima  D+ dopo   grado');
  esempi.forEach(e => console.log(
    `${e.nome.padEnd(32)} ${e.km.padStart(5)} ${String(e.gVecchio).padStart(9)} ${String(e.gNuovo).padStart(8)}   ${e.dVecchio} → ${e.dNuovo}  (${e.ore}h)`));

  console.log(`\n=== ${APPLY ? 'SCRITTO' : 'SIMULATO'} ===`);
  console.log(`schede aggiornate:        ${st.aggiornati}`);
  console.log(`invariate:                ${st.invariati}`);
  console.log(`saltate (quote assenti):  ${st.senzaQuote}`);
  console.log(`saltate (distanza):       ${st.senzaDistanza}`);
  console.log(`errori:                   ${st.errori}`);
  if (nGain) console.log(`variazione media D+:      ${deltaGainTot / nGain >= 0 ? '+' : ''}${Math.round(deltaGainTot / nGain)} m per scheda`);
  console.log(`\ngrado invariato: ${st.gradoUguale}   più alto: ${st.gradoSu}   più basso: ${st.gradoGiu}`);
  console.log(`diventati multi-giorno: ${st.diventatiPiuGiorni}   non più multi-giorno: ${st.nonPiuMultiGiorno}`);

  const tr = Object.entries(transizioni).sort((a, b) => b[1] - a[1]);
  if (tr.length) {
    console.log(`\ntransizioni di grado:`);
    tr.slice(0, 14).forEach(([k, v]) => console.log(`  ${k.padEnd(24)} ${v}`));
    if (tr.length > 14) console.log(`  ...e altre ${tr.length - 14} combinazioni`);
  }

  if (!APPLY) console.log(`\nNiente scritto. Rilancia con --apply.`);
  process.exit(0);
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
