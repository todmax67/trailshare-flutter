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

// ── Regioni (point-in-polygon, riuso pipeline schede) ─────────────────────
const gj = JSON.parse(fs.readFileSync('/tmp/it_regions.geojson', 'utf8'));
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
  if (trail.maxAltitude != null) f.push(`Quota massima: ${Math.round(trail.maxAltitude)} m`);
  if (trail.minAltitude != null) f.push(`Quota minima: ${Math.round(trail.minAltitude)} m`);
  if (trail.isCircular != null) f.push(`Anello: ${trail.isCircular ? 'sì' : 'no'}`);
  if (trail.difficulty) f.push(`Difficoltà: ${trail.difficulty}`);
  if (trail.network) f.push(`Rete: ${trail.network}`);
  if (trail.operator) f.push(`Gestore/sezione: ${trail.operator}`);
  if (trail.region) f.push(`Regione: ${trail.region}`);
  if (nearbyRifugi.length) f.push(`Rifugi lungo o vicino al percorso (dalla nostra banca dati, max 1,5 km): ${nearbyRifugi.join(', ')}`);

  const system = `Scrivi la descrizione di un sentiero per TrailShare, app outdoor italiana.

REGOLE FERREE:
- Usa SOLO i fatti forniti. NON inventare: niente condizioni del terreno, esposizione, acqua, segnaletica, panorami specifici o tempi se non forniti.
- Italiano, testo originale, tono informativo e invitante ma sobrio.
- 50-90 parole, 1-2 paragrafi. Cita numero sentiero (se c'è), meta, lunghezza, dislivello e, se presenti, i rifugi vicini.
- Se i fatti sono troppo scarni per un testo sensato, "affidabile": false.

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
  const text = (j.content?.[0]?.text || '').trim().replace(/^```json?\s*/i, '').replace(/```\s*$/, '');
  return { parsed: JSON.parse(text), usage: j.usage };
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
    if (!x.distance || x.distance < 300) return;
    cands.push({ ref: d.ref, id: d.id, ...x });
  });
  // priorità: rifugioRoute prima, poi i più lunghi (più "raccontabili")
  cands.sort((a, b) => ((b.isRifugioRoute === true ? 1 : 0) - (a.isRifugioRoute === true ? 1 : 0)) || (b.distance - a.distance));
  cands = cands.slice(0, LIMIT);
  console.log('Sentieri da processare:', cands.length);

  let ok = 0, unreliable = 0, errors = 0, regionsSet = 0;
  let inTok = 0, outTok = 0;
  for (const [i, t] of cands.entries()) {
    process.stdout.write(`[${i + 1}/${cands.length}] ${String(t.name).slice(0, 50)} ... `);
    try {
      const pts = trailPoints(t);
      // regione (backfill se mancante)
      let region = t.region || null;
      if (!region && pts.length) {
        region = regionOf(pts[0][1], pts[0][0]);
        if (region) { await t.ref.update({ region }); regionsSet++; }
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

      const { parsed, usage } = await generate({ ...t, region }, nearNames);
      inTok += usage?.input_tokens || 0;
      outTok += usage?.output_tokens || 0;
      if (!parsed.affidabile || !parsed.description || parsed.description.length < 40) {
        unreliable++;
        await t.ref.update({ aiDraft: { status: 'unreliable', generatedAt: admin.firestore.FieldValue.serverTimestamp() } });
        console.log('fatti troppo scarni, skip');
        continue;
      }
      await t.ref.update({
        aiDraft: {
          status: 'pending',
          description: String(parsed.description).trim(),
          nearbyRifugi: nearNames,
          model: MODEL,
          generatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
      });
      ok++;
      console.log('bozza creata' + (nearNames.length ? ` (rifugi: ${nearNames.join(', ')})` : ''));
    } catch (e) {
      errors++;
      console.log('errore:', e.message.slice(0, 120));
    }
    await sleep(300);
  }
  const cost = (inTok / 1e6) * 1 + (outTok / 1e6) * 5;
  console.log(`\n=== SENTIERI BATCH COMPLETO ===`);
  console.log(`bozze: ${ok} | scarni: ${unreliable} | errori: ${errors} | regioni backfillate: ${regionsSet}`);
  console.log(`token: ${inTok} in / ${outTok} out ≈ $${cost.toFixed(2)}`);
  process.exit(0);
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
