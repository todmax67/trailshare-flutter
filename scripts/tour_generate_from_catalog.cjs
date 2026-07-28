// Genera tour IN BOZZA dai cammini gia' presenti nel catalogo.
//
// Le tappe sono sentieri di `public_trails` con il numero nel nome; ordinate
// danno la sequenza, e da li' distanze, dislivelli, tempi, difficolta'
// rilevate e il rifugio a fine tappa. Il modello Tour ora le accetta grazie
// a `stageSources` (trackId -> 'public_trail').
//
// SCRIVE SOLO BOZZE PRIVATE, in users/{uid}/tours con isPublic: false.
// Non tocca `community_tours`, quindi niente arriva agli utenti finche' non
// sei tu a pubblicare dall'app. La ragione non e' prudenza tecnica: uno
// scheletro generato NON e' un tour curato, e mettere quattordici schede
// costruite dalla macchina accanto alle sei scritte a mano — con settemila
// caratteri e sette foto — svaluterebbe proprio quelle che valgono.
//
// Quello che la macchina puo' dare: sequenza, numeri, rifugi, difficolta'.
// Quello che deve metterci una persona: le foto, il periodo migliore,
// l'attrezzatura, il racconto.
//
// Uso:
//   node scripts/tour_generate_from_catalog.cjs --dry "Alta Via della Valmalenco"
//   node scripts/tour_generate_from_catalog.cjs "Alta Via della Valmalenco"
//   node scripts/tour_generate_from_catalog.cjs --dry --pulite   (le 14 coerenti)
const admin = require('../functions/node_modules/firebase-admin');
const sa = require('../functions/serviceAccountKey.json');

admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const argv = process.argv.slice(2);
const DRY = argv.includes('--dry');
const PULITE = argv.includes('--pulite');
const CERCA = argv.filter((a) => !a.startsWith('--'))[0];

/// L'account redazionale. Firma ogni tour generato, ed e' lo stesso che gia'
/// firma quattro dei sei tour scritti a mano.
const REDAZIONE_UID = '1sw845iay7XZnTWzX6IcEYsLIgd2';
const REDAZIONE_NOME = 'TrailShareTeam';

const TAPPA = /^(.*?)[\s\-–—]*\b(tappa|tappe|stage|etappe|étape|etape)\b\s*\.?\s*(\d+)(?:[.\-](\d+(?:-\d+)?))?\s*([a-zA-Z]?)/i;
const PREFISSI = /\b(rifugio|rifugi|rif\.?|capanna|baita|bivacco|refuge|refuges|huette|hutte|hütte|berghaus|chalet|gite|gîte|albergo|ostello)\b/gi;
const RANGO = { t: 0, e: 1, ee: 2, eea: 3 };
const ETICHETTA = { t: 'T', e: 'E', ee: 'EE', eea: 'EEA' };

const normalizza = (n) => String(n || '')
  .normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()
  .replace(PREFISSI, ' ').replace(/[^a-z0-9 ]+/g, ' ').replace(/\s+/g, ' ').trim();

function km(lat1, lon1, lat2, lon2) {
  const R = 6371, r = (x) => x * Math.PI / 180;
  const dLat = r(lat2 - lat1), dLon = r(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2
    + Math.cos(r(lat1)) * Math.cos(r(lat2)) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/// Le tre forme di coordinate che convivono nei documenti.
function arrivoDi(x) {
  const p = x.endPoint;
  const la = p && (p.latitude ?? p.lat);
  const ln = p && (p.longitude ?? p.lng ?? p.lon);
  return la != null && ln != null ? [Number(la), Number(ln)] : null;
}

/// Il rifugio di fine tappa: prima il nome dichiarato in `to`, poi la
/// vicinanza. Il nome va confermato dalla posizione o ci si aggancia un
/// omonimo dall'altra parte delle Alpi.
function rifugioDiTappa(t, rifugi) {
  const fine = arrivoDi(t);
  if (t.to) {
    for (const pezzo of String(t.to).split(/[;/]/)) {
      const cercato = normalizza(pezzo);
      if (cercato.length < 3) continue;
      const cand = rifugi.filter((r) => {
        const n = normalizza(r.nome);
        return n === cercato || n.includes(cercato) || cercato.includes(n);
      });
      if (!cand.length) continue;
      const ord = fine
        ? cand.map((r) => ({ ...r, d: km(fine[0], fine[1], r.lat, r.lng) })).sort((a, b) => a.d - b.d)
        : cand.map((r) => ({ ...r, d: 99 }));
      if (ord[0].d <= 5) return ord[0];
    }
  }
  if (!fine) return null;
  const vicino = rifugi.map((r) => ({ ...r, d: km(fine[0], fine[1], r.lat, r.lng) }))
    .filter((r) => r.d <= 3).sort((a, b) => a.d - b.d)[0];
  return vicino || null;
}

(async () => {
  const bSnap = await db.collection('businesses').where('type', '==', 'rifugio').get();
  const rifugi = [];
  bSnap.forEach((d) => {
    const x = d.data(), L = x.location || {};
    const la = L.latitude ?? L.lat, ln = L.longitude ?? L.lng;
    if (la != null && ln != null) rifugi.push({ id: d.id, nome: x.name, lat: Number(la), lng: Number(ln) });
  });

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

  // Le 14 che il censimento ha giudicato complete e coerenti.
  const PULITE_ELENCO = [
    'Sentiero delle Orobie Orientali', 'Alta Via del Lario', 'Da Rifugio a Rifugio',
    'Alta Via della Valmalenco', 'Alta via dei Parchi', 'Gran Via delle Orobie',
    "Alta Via dell'Adamello", 'Luchs Trail', 'Sentiero delle Orobie Occidentali',
    'Itinerario Naturalistico Antonio Curò', "Alta Via n. 2 della Valle d'Aosta",
    "Alta Via n. 1 della Valle d'Aosta", 'Itinerario Garda Brenta', 'Tour du Mont-Blanc CCW',
  ];
  let bersagli;
  if (PULITE) bersagli = PULITE_ELENCO.filter((k) => fam[k]);
  else if (CERCA) {
    const q = CERCA.toLowerCase();
    const esatta = Object.keys(fam).find((k) => k.toLowerCase() === q);
    bersagli = esatta ? [esatta] : Object.keys(fam).filter((k) => k.toLowerCase().includes(q)).slice(0, 1);
  } else { console.error('Serve un nome o --pulite.'); process.exit(1); }
  if (!bersagli.length) { console.error('Nessuna famiglia trovata.'); process.exit(1); }

  console.log(DRY ? '=== SIMULAZIONE ===\n' : '=== SCRITTURA BOZZE ===\n');

  for (const nome of bersagli) {
    const tutte = fam[nome].sort((a, b) => a.n - b.n || a.suffisso.localeCompare(b.suffisso));
    const tappe = tutte.filter((t) => !t.suffisso);   // le varianti non sono giorni
    if (tappe.length < 2) { console.log(`· ${nome}: meno di 2 tappe, salto`); continue; }

    // Un tour per cammino, non uno per esecuzione: se c'e' gia', si salta.
    const esistenti = await db.collection('users').doc(REDAZIONE_UID)
      .collection('tours').where('title', '==', nome).limit(1).get();
    if (!esistenti.empty) { console.log(`· ${nome}: bozza gia' presente, salto`); continue; }

    const trackIds = [], stageSources = {}, stageAccommodations = {};
    let totKm = 0, totGain = 0, totOre = 0, peggiore = -1, conRif = 0;
    const conteggioGradi = {};
    let n = 90, s = -90, e = -180, w = 180;

    for (const t of tappe) {
      trackIds.push(t.id);
      stageSources[t.id] = 'public_trail';
      totKm += (t.distance || 0) / 1000;
      totGain += t.elevationGain || 0;
      totOre += t.oreStimate || 0;
      const g = String(t.difficulty || '').toLowerCase();
      if (t.difficultySource && RANGO[g] !== undefined) {
        conteggioGradi[g] = (conteggioGradi[g] || 0) + 1;
        if (RANGO[g] > peggiore) peggiore = RANGO[g];
      }
      const rif = rifugioDiTappa(t, rifugi);
      if (rif) { stageAccommodations[t.id] = rif.id; conRif++; }
      for (const p of (t.simplifiedPoints || [])) {
        const la = Array.isArray(p) ? p[0] : p?.lat, ln = Array.isArray(p) ? p[1] : p?.lng;
        if (la == null || ln == null) continue;
        if (la > s) s = la; if (la < n) n = la;
        if (ln > e) e = ln; if (ln < w) w = ln;
      }
    }

    const doc = {
      ownerId: REDAZIONE_UID,
      ownerName: REDAZIONE_NOME,
      title: nome,
      type: 'consecutive',
      trackIds,
      stageSources,
      ...(Object.keys(stageAccommodations).length ? { stageAccommodations } : {}),
      // Solo se RILEVATA su almeno una tappa: un grado dedotto da lunghezza e
      // dislivello qui sarebbe la stessa bugia che abbiamo tolto dai sentieri.
      //
      // Il grado del tour e' il MASSIMO fra le tappe, perche' quella tappa
      // esiste e non si aggira. Ma da solo inganna nell'altro verso: l'Alta
      // via dei Parchi ha 8 tappe su 10 in E e una in EEA, e chiamarla "tour
      // EEA" fa credere che servano imbrago e set per dieci giorni invece che
      // per uno. Percio' accanto al grado si salva su quante tappe vale —
      // e' la stessa distinzione fra "e' una ferrata" e "ne comprende un
      // tratto" che usiamo sui sentieri.
      ...(peggiore >= 0 ? {
        difficultyGrade: ETICHETTA[Object.keys(RANGO)[peggiore]],
        difficultyStages: conteggioGradi[Object.keys(RANGO)[peggiore]] || 0,
        difficultyBreakdown: conteggioGradi,
      } : {}),
      totalDistance: totKm * 1000,
      totalElevationGain: totGain,
      totalDurationSeconds: Math.round(totOre * 3600),
      daysCount: tappe.length,
      ...(s > -90 ? { bounds: { n: s, s: n, e, w } } : {}),
      isPublic: false,          // BOZZA: non arriva a nessuno
      generatedFromCatalog: true,
      createdAt: admin.firestore.Timestamp.now(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    console.log(`${DRY ? '·' : '✓'} ${nome}`);
    console.log(`    ${tappe.length} tappe · ${totKm.toFixed(0)} km · D+ ${Math.round(totGain)} m · ` +
      `${totOre.toFixed(0)} h · rifugi ${conRif}/${tappe.length}`);
    console.log(`    grado ${doc.difficultyGrade || 'non determinabile'}` +
      (doc.difficultyStages ? ` su ${doc.difficultyStages} tappa/e di ${tappe.length}` : '') +
      (peggiore >= 0 ? `   (${Object.entries(conteggioGradi).map(([k, v2]) => `${k.toUpperCase()}:${v2}`).join(' ')})` : ''));
    if (!DRY) {
      await db.collection('users').doc(REDAZIONE_UID).collection('tours').add(doc);
    }
  }

  console.log(DRY
    ? '\nNessuna scrittura. Per creare le bozze, togliere --dry.'
    : '\nBozze create in users/{redazione}/tours con isPublic: false.\n'
      + 'Non sono visibili a nessuno: si pubblicano dall\'app, dopo averle rifinite.');
  process.exit(0);
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
