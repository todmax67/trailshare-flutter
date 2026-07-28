// Arricchimento SENTIERI — descrizioni AI dai NOSTRI fatti strutturati
// (public_trails: distanza, D+, quote, ref CAI, da/a, anello, difficoltà)
// + rifugi vicini incrociati dalla base businesses. Nessuna fonte esterna:
// zero rischio invenzioni. Salva aiDraft (pending) per revisione web admin.
// Backfill bonus: location.region del sentiero da point-in-polygon (ISTAT).
//
// Uso:
//   ANTHROPIC_API_KEY=... node scripts/trail_ai_descriptions.cjs --limit 25 [--rifugioroute]
const admin = require('../functions/node_modules/firebase-admin');
const sa = require('../functions/serviceAccountKey.json');
const fs = require('fs');
const path = require('path');
admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const API_KEY = process.env.ANTHROPIC_API_KEY;
if (!API_KEY) { console.error('ANTHROPIC_API_KEY mancante'); process.exit(1); }
const MODEL = 'claude-haiku-4-5-20251001';
const sleep = ms => new Promise(r => setTimeout(r, ms));

const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf('--' + n); return i >= 0 ? args[i + 1] : d; };
const LIMIT = Number(opt('limit', 25));
const ONLY_RIFUGIO_ROUTE = args.includes('--rifugioroute');
// --ferrate: solo vie attrezzate. Serve perche' l'ordinamento privilegia i
// percorsi lunghi e le ferrate, corte, finirebbero in fondo a una coda di
// migliaia di candidati — mentre sono quelle che devono essere sistemate
// per prime.
const ONLY_FERRATE = args.includes('--ferrate');
// --autopublish: scrive direttamente description (descriptionSource
// 'ai_facts') invece della coda di revisione. Da usare SOLO dopo che il
// formato è stato validato dal founder sul pilota.
const AUTOPUBLISH = args.includes('--autopublish');
const CONCURRENCY = Number(opt('concurrency', 6));

// ── Regioni (point-in-polygon, riuso pipeline schede) ─────────────────────
// Il backfill della regione e' un di piu': se i confini non ci sono lo
// script genera lo stesso le descrizioni, che sono il lavoro vero. Il file
// stava in /tmp e le pulizie del disco se lo portano via.
const GEOJSON = [
  path.join(__dirname, '..', 'assets', 'geo', 'it_regions.geojson'),
  '/tmp/it_regions.geojson',
].find(p => fs.existsSync(p));
if (!GEOJSON) {
  console.log('· confini regionali assenti: salto il backfill di location.region');
  console.log('  (per riattivarlo: assets/geo/it_regions.geojson)');
}
const gj = GEOJSON ? JSON.parse(fs.readFileSync(GEOJSON, 'utf8')) : { features: [] };
const regions = gj.features.map(f => {
  const name = String(f.properties.reg_name).split('/')[0].trim();
  const polys = f.geometry.type === 'Polygon' ? [f.geometry.coordinates] : f.geometry.coordinates;
  const withBox = polys.map(poly => {
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (const ring of poly) for (const [x, y] of ring) {
      if (x < minX) minX = x; if (x > maxX) maxX = x;
      if (y < minY) minY = y; if (y > maxY) maxY = y;
    }
    return { poly, box: [minX, minY, maxX, maxY] };
  });
  return { name, polys: withBox };
});
function inPoly(lng, lat, poly) {
  let inside = false;
  for (const ring of poly) {
    for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      const xi = ring[i][0], yi = ring[i][1], xj = ring[j][0], yj = ring[j][1];
      if (((yi > lat) !== (yj > lat)) && (lng < (xj - xi) * (lat - yi) / (yj - yi) + xi)) inside = !inside;
    }
  }
  return inside;
}
function regionOf(lng, lat) {
  for (const r of regions) {
    for (const { poly, box } of r.polys) {
      if (lng < box[0] || lng > box[2] || lat < box[1] || lat > box[3]) continue;
      if (inPoly(lng, lat, poly)) return r.name;
    }
  }
  return null;
}

// Un'etichetta di regione sola non regge sui grandi itinerari: il Sentiero
// Italia non e' piemontese e la Via Alpina non e' dei Grigioni. Prima si
// prendeva la regione del PRIMO punto e la si passava al modello come fatto:
// lui rispettava la consegna di non inventare, ma il fatto era gia' falso.
// Ora: se il tracciato spazia troppo, la regione non si passa affatto.
const SPAN_MAX_KM = 50;   // diagonale del rettangolo che contiene il percorso
const DIST_MAX_KM = 100;  // lunghezza oltre la quale una regione sola non regge

function estensioneKm(pts) {
  if (pts.length < 2) return 0;
  let minLat = Infinity, maxLat = -Infinity, minLng = Infinity, maxLng = -Infinity;
  for (const [la, ln] of pts) {
    if (la < minLat) minLat = la; if (la > maxLat) maxLat = la;
    if (ln < minLng) minLng = ln; if (ln > maxLng) maxLng = ln;
  }
  return haversineKm(minLat, minLng, maxLat, maxLng);
}

/// Le regioni toccate campionando il percorso (inizio, quarti, fine).
/// Vuoto se non abbiamo i confini caricati: in quel caso decide l'estensione.
function regioniLungo(pts) {
  if (!regions.length || !pts.length) return [];
  const viste = [];
  for (const q of [0, 0.25, 0.5, 0.75, 1]) {
    const p = pts[Math.min(pts.length - 1, Math.floor(q * (pts.length - 1)))];
    const r = regionOf(p[1], p[0]);
    if (r && !viste.includes(r)) viste.push(r);
  }
  return viste;
}

/// Quote implausibili: meglio tacere che pubblicare "quota minima -5 m".
const quotaPlausibile = v => v != null && Number.isFinite(v) && v >= 0 && v <= 5000;

/// Nomi che promettono un giro: se il dato dice il contrario, vince il nome.
const NOMI_ANELLO = /\b(rund|ring|circuit|circolare|anello|giro|loop|tour|periplo)/i;

/// Vie attrezzate. Riconoscerle conta piu' di ogni altro fatto: la formula
/// _estimateDifficulty dava "T — turistico" a una ferrata di 200 m con 130
/// di dislivello (corta e ripida = sotto le sue soglie), e le descrizioni
/// arrivavano a scrivere "ideale per escursionisti di ogni livello". Su una
/// via che richiede imbrago e set da ferrata quella frase e' pericolosa.
const NOMI_FERRATA = /\b(ferrata|ferrate|klettersteig|sentiero attrezzato|via attrezzata|sentiero alpinistico attrezzato)/i;

/// Segmenti di servizio di una ferrata: avvicinamento, attacco, uscita,
/// rientro. Portano "ferrata" nel nome ma non sono la via attrezzata, quindi
/// non si puo' affermare ne' che siano attrezzati ne' che siano facili.
const NOMI_FERRATA_SERVIZIO = /\b(approach|zustieg|ausstieg|abstieg|attacco|accesso|avvicinamento|rientro|return|exit|start|uscita|discesa)\b/i;

const eFerrata = (nome) => NOMI_FERRATA.test(String(nome || ''))
  && !NOMI_FERRATA_SERVIZIO.test(String(nome || ''));

function haversineKm(lat1, lon1, lat2, lon2) {
  const R = 6371, toRad = x => x * Math.PI / 180;
  const dLat = toRad(lat2 - lat1), dLon = toRad(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function trailPoints(x) {
  // simplifiedPoints: array di {lat,lng} o [lat,lng]; fallback start/center.
  const pts = [];
  const sp = x.simplifiedPoints;
  if (Array.isArray(sp)) {
    for (const p of sp) {
      if (Array.isArray(p) && p.length >= 2) pts.push([Number(p[0]), Number(p[1])]);
      else if (p && typeof p === 'object' && p.lat != null) pts.push([Number(p.lat), Number(p.lng)]);
    }
  }
  if (!pts.length && x.startLat != null) pts.push([Number(x.startLat), Number(x.startLng)]);
  if (!pts.length && x.center && x.center.lat != null) pts.push([Number(x.center.lat), Number(x.center.lng)]);
  return pts.filter(p => Number.isFinite(p[0]) && Number.isFinite(p[1]));
}

async function generate(trail, nearbyRifugi) {
  const f = [];
  if (trail.ref) f.push(`Numero sentiero: ${trail.ref}`);
  f.push(`Nome: ${trail.name}`);
  if (trail.from) f.push(`Partenza: ${trail.from}`);
  if (trail.to) f.push(`Arrivo/meta: ${trail.to}`);
  f.push(`Lunghezza: ${(trail.distance / 1000).toFixed(1)} km`);
  if (trail.elevationGain != null) f.push(`Dislivello positivo: ${Math.round(trail.elevationGain)} m`);
  if (quotaPlausibile(trail.maxAltitude)) f.push(`Quota massima: ${Math.round(trail.maxAltitude)} m`);
  if (quotaPlausibile(trail.minAltitude)) f.push(`Quota minima: ${Math.round(trail.minAltitude)} m`);
  // "Anello: sì" si verifica da solo (primo e ultimo punto a meno di 100 m).
  // "Anello: no" no: sulle relazioni OSM aggregate l'ordine dei punti e'
  // arbitrario, e lo Steirischer LANDESRUNDwanderweg risultava non-anello.
  // Se il nome promette un giro, o il percorso e' lungo abbastanza da essere
  // una relazione composta, il dato non si passa.
  if (trail.isCircular === true) {
    f.push('Anello: sì');
  } else if (trail.isCircular === false
    && !NOMI_ANELLO.test(String(trail.name || ''))
    && (trail.distance / 1000) <= DIST_MAX_KM) {
    f.push('Anello: no');
  }

  // La difficolta' non e' rilevata sul terreno: _estimateDifficulty la deduce
  // da lunghezza e dislivello, e QUALUNQUE percorso oltre 1200 m di D+
  // complessivo diventa EE. Su un cammino lungo e in pendenza dolce (la Via
  // del Sale: 12 m/km) e' un allarme falso, e un'etichetta di rischio
  // sbagliata in montagna e' peggio che nessuna etichetta.
  const km = (trail.distance || 0) / 1000;
  const pendenza = km > 0 && trail.elevationGain != null ? trail.elevationGain / km : null;
  const eeGonfiata = trail.difficulty === 'EE' && km > 20 && pendenza !== null && pendenza < 40;

  // Su una via attrezzata la difficolta' salvata e' spesso "T" o "facile",
  // perche' dedotta da lunghezza e dislivello: corta e ripida finisce sotto
  // le soglie. Non si passa, e al suo posto va il fatto che conta davvero.
  // Il nome non basta: la sonda OSM ha trovato vie attrezzate chiamate
  // "Wanderweg 548" o "Garfagnana Trekking Tappa 3b". Il campo viaFerrata
  // viene dai tag delle way (highway=via_ferrata, via_ferrata_scale) ed e'
  // la fonte piu' affidabile; il nome resta come rete di sicurezza.
  const ferrata = trail.viaFerrata === true || eFerrata(trail.name);
  if (ferrata) {
    // Un itinerario lungo che attraversa un tratto attrezzato non e' "una
    // ferrata": dirlo cosi' sarebbe falso in senso opposto. Ma il grado
    // resta quello del passaggio peggiore, perche' quel tratto non si evita.
    f.push(trail.viaFerrataParziale === true
      ? 'Tratto attrezzato lungo il percorso: SI — comprende almeno un tratto '
        + 'di via ferrata, che richiede imbrago, casco e set da ferrata ed '
        + 'esperienza specifica. Non e\' aggirabile: chi affronta l\'itinerario '
        + 'deve essere attrezzato.'
      : 'Via attrezzata: SI — richiede imbrago, casco e set da ferrata, '
        + 'ed esperienza specifica. Non e\' un sentiero escursionistico.');
  } else if (trail.difficulty && !eeGonfiata) {
    f.push(`Difficoltà: ${trail.difficulty}`);
  }
  if (trail.network) f.push(`Rete: ${trail.network}`);
  if (trail.operator) f.push(`Gestore/sezione: ${trail.operator}`);
  // Se il percorso ne attraversa piu' d'una si dicono tutte; se non e'
  // accertabile (vedi SPAN_MAX_KM) region arriva null e non si nomina nulla.
  if (trail.regioniAttraversate && trail.regioniAttraversate.length > 1) {
    f.push(`Regioni attraversate: ${trail.regioniAttraversate.join(', ')}`);
  } else if (trail.region) {
    f.push(`Regione: ${trail.region}`);
  }
  if (nearbyRifugi.length) f.push(`Rifugi lungo o vicino al percorso (dalla nostra banca dati, max 1,5 km): ${nearbyRifugi.join(', ')}`);

  const system = `Scrivi la descrizione di un sentiero per TrailShare, app outdoor italiana.

REGOLE FERREE:
- Usa SOLO i fatti forniti. NON inventare: niente condizioni del terreno, esposizione, acqua, segnaletica, panorami specifici o tempi se non forniti.
- Italiano, testo originale, tono informativo e invitante ma sobrio.
- 50-90 parole, 1-2 paragrafi. Cita numero sentiero (se c'è), meta, lunghezza, dislivello e, se presenti, i rifugi vicini.
- Se i fatti sono troppo scarni per un testo sensato, "affidabile": false.
- SICUREZZA — se fra i fatti c'è "Via attrezzata: SI": è una via ferrata.
  Dillo chiaramente e cita l'attrezzatura obbligatoria. È VIETATO definirla
  facile, turistica, adatta a tutti, a principianti o a famiglie, e vietato
  scrivere che non presenta difficoltà tecniche: anche se breve e con poco
  dislivello, senza attrezzatura una caduta è fatale. Nel dubbio, meno
  invitante e più chiaro.
- SICUREZZA — se invece c'è "Tratto attrezzato lungo il percorso: SI", NON
  chiamarlo "una via ferrata": è un itinerario escursionistico che ne
  attraversa un tratto. Scrivi che comprende un passaggio attrezzato, che
  serve l'attrezzatura per affrontarlo e che non si può aggirare. Valgono
  gli stessi divieti: niente "adatto a tutti", niente "facile".

Rispondi SOLO con JSON: {"description": "...", "affidabile": true/false}`;

  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: { 'x-api-key': API_KEY, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
    body: JSON.stringify({
      model: MODEL, max_tokens: 400, temperature: 0.4, system,
      messages: [{ role: 'user', content: 'FATTI DEL SENTIERO:\n' + f.join('\n') }],
    }),
  });
  if (!res.ok) throw new Error('anthropic HTTP ' + res.status + ' ' + (await res.text()).slice(0, 160));
  const j = await res.json();
  const text = (j.content?.[0]?.text || '').trim();
  const block = text.match(/\{[\s\S]*\}/);
  return { parsed: JSON.parse(block ? block[0] : text), usage: j.usage };
}

(async () => {
  // Rifugi (per il cross-link sentiero ↔ struttura)
  const bSnap = await db.collection('businesses').where('type', '==', 'rifugio').get();
  const rifugi = [];
  bSnap.forEach(d => {
    const l = d.get('location');
    if (l && typeof l.lat === 'number') rifugi.push({ name: d.get('name'), lat: l.lat, lng: l.lng });
  });
  console.log('Rifugi in banca dati:', rifugi.length);

  // Sentieri candidati
  const tSnap = await db.collection('public_trails').get();
  let cands = [];
  tSnap.forEach(d => {
    const x = d.data();
    const hasDesc = x.description && String(x.description).trim().length >= 30;
    if (hasDesc || x.aiDraft) return;
    if (ONLY_RIFUGIO_ROUTE && x.isRifugioRoute !== true) return;
    // Nome OPPURE tag OSM: dopo la raccolta la seconda e' la fonte buona,
    // e le nuove trovate si chiamano "Wanderweg 548".
    const attrezzata = x.viaFerrata === true || eFerrata(x.name);
    if (ONLY_FERRATE && !attrezzata) return;
    // La soglia dei 300 m tiene fuori i frammenti OSM senza sostanza, ma le
    // vie attrezzate sono corte per natura (una ferrata di 200 m e' normale)
    // ed e' proprio sulla loro scheda che deve stare l'avvertimento
    // sull'attrezzatura obbligatoria. Per loro la soglia non si applica.
    if (!x.distance || (x.distance < 300 && !attrezzata)) return;
    cands.push({ ...x, docRef: d.ref, id: d.id });
  });
  // priorità: rifugioRoute prima, poi i più lunghi (più "raccontabili")
  cands.sort((a, b) => ((b.isRifugioRoute === true ? 1 : 0) - (a.isRifugioRoute === true ? 1 : 0)) || (b.distance - a.distance));
  cands = cands.slice(0, LIMIT);
  console.log('Sentieri da processare:', cands.length);

  let ok = 0, unreliable = 0, errors = 0, regionsSet = 0, vasti = 0;
  let inTok = 0, outTok = 0;
  let nextIdx = 0;
  async function processOne(t, i) {
    const label = `[${i + 1}/${cands.length}] ${String(t.name).slice(0, 50)}`;
    try {
      const pts = trailPoints(t);
      // Regione: attendibile solo se il percorso sta in un'area contenuta.
      // Il campo salvato su Firestore vale quanto il primo punto da cui e'
      // stato dedotto, quindi sui grandi itinerari non ci si fida nemmeno
      // di quello.
      let region = t.region || null;
      const attraversate = regioniLungo(pts);
      const spanKm = estensioneKm(pts);
      const troppoVasto = spanKm > SPAN_MAX_KM || (t.distance / 1000) > DIST_MAX_KM;

      if (attraversate.length > 1) {
        region = null;                       // le elenca il blocco dei fatti
      } else if (troppoVasto) {
        region = null;                       // niente regione: meglio tacere
        vasti++;
      } else if (!region && attraversate.length === 1) {
        region = attraversate[0];
        await t.docRef.update({ region });
        regionsSet++;
      }
      // rifugi entro 1.5 km da uno dei punti del percorso
      const step = Math.max(1, Math.floor(pts.length / 25));
      const near = [];
      for (const r of rifugi) {
        let best = Infinity;
        for (let k = 0; k < pts.length; k += step) {
          const dKm = haversineKm(pts[k][0], pts[k][1], r.lat, r.lng);
          if (dKm < best) best = dKm;
          if (best < 0.3) break;
        }
        if (best <= 1.5) near.push({ name: r.name, d: best });
      }
      near.sort((a, b) => a.d - b.d);
      const nearNames = near.slice(0, 3).map(n => n.name);

      const { parsed, usage } = await generate(
        { ...t, region, regioniAttraversate: attraversate }, nearNames);
      inTok += usage?.input_tokens || 0;
      outTok += usage?.output_tokens || 0;
      if (!parsed.affidabile || !parsed.description || parsed.description.length < 40) {
        unreliable++;
        await t.docRef.update({ aiDraft: { status: 'unreliable', generatedAt: admin.firestore.FieldValue.serverTimestamp() } });
        console.log(label + ' ... fatti troppo scarni, skip');
        return;
      }
      if (AUTOPUBLISH) {
        await t.docRef.update({
          description: String(parsed.description).trim(),
          descriptionSource: 'ai_facts',
          aiNearbyRifugi: nearNames,
          aiGeneratedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } else {
        await t.docRef.update({
          aiDraft: {
            status: 'pending',
            description: String(parsed.description).trim(),
            nearbyRifugi: nearNames,
            model: MODEL,
            generatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        });
      }
      ok++;
      console.log(label + ' ... ' + (AUTOPUBLISH ? 'pubblicata' : 'bozza creata') + (nearNames.length ? ` (rifugi: ${nearNames.join(', ')})` : ''));
    } catch (e) {
      errors++;
      console.log(label + ' ... errore: ' + e.message.slice(0, 120));
    }
    await sleep(120);
  }

  async function worker() {
    while (nextIdx < cands.length) {
      const i = nextIdx++;
      await processOne(cands[i], i);
    }
  }
  await Promise.all(Array.from({ length: Math.min(CONCURRENCY, cands.length) }, () => worker()));
  const cost = (inTok / 1e6) * 1 + (outTok / 1e6) * 5;
  console.log(`\n=== SENTIERI BATCH COMPLETO ===`);
  console.log(`bozze: ${ok} | scarni: ${unreliable} | errori: ${errors} | regioni backfillate: ${regionsSet}`);
  if (vasti) console.log(`percorsi troppo estesi per una regione sola (non nominata): ${vasti}`);
  console.log(`token: ${inTok} in / ${outTok} out ≈ $${cost.toFixed(2)}`);
  process.exit(0);
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
