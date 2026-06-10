// FASE B — Bozze descrizione AI per schede business con sito web e
// descrizione mancante. NON pubblica nulla: salva `aiDraft` (status
// 'pending') che il founder approva/modifica/scarta dalla web admin
// (pagina "Bozze AI"). Regole: solo FATTI dal sito, testo originale
// (mai copiato), niente invenzioni.
//
// Uso:
//   ANTHROPIC_API_KEY=$(firebase functions:secrets:access ANTHROPIC_API_KEY) \
//   node scripts/business_ai_drafts.cjs --limit 20 [--type rifugio] [--region Lombardia]
const admin = require('../functions/node_modules/firebase-admin');
const sa = require('../functions/serviceAccountKey.json');
admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const API_KEY = process.env.ANTHROPIC_API_KEY;
if (!API_KEY) { console.error('ANTHROPIC_API_KEY mancante'); process.exit(1); }
const MODEL = 'claude-haiku-4-5-20251001';
const UA = 'TrailShare-enrichment/1.0 (info@trailshare.app)';
const sleep = ms => new Promise(r => setTimeout(r, ms));

const args = process.argv.slice(2);
const opt = (name, dflt) => {
  const i = args.indexOf('--' + name);
  return i >= 0 ? args[i + 1] : dflt;
};
const LIMIT = Number(opt('limit', 20));
const TYPE = opt('type', null);
const REGION = opt('region', null);


// I siti con anti-spam (es. Cloudflare) producono artefatti tipo
// "[email protected]": validiamo prima di proporre i contatti estratti.
function isValidEmail(v) {
  if (!v) return false;
  const s = String(v).trim();
  if (/protected|example\./i.test(s)) return false;
  return /^[^\s@]+@[^\s@]+\.[a-z]{2,}$/i.test(s);
}
function isValidPhone(v) {
  if (!v) return false;
  const digits = String(v).replace(/[^0-9]/g, '');
  return digits.length >= 8 && digits.length <= 15;
}

async function fetchSiteText(url) {
  try {
    const ctrl = new AbortController();
    const to = setTimeout(() => ctrl.abort(), 15000);
    const res = await fetch(url, { headers: { 'User-Agent': UA }, signal: ctrl.signal, redirect: 'follow' });
    clearTimeout(to);
    if (!res.ok) return null;
    const ct = res.headers.get('content-type') || '';
    if (!ct.includes('html')) return null;
    let html = await res.text();
    html = html.replace(/<script[\s\S]*?<\/script>/gi, ' ')
               .replace(/<style[\s\S]*?<\/style>/gi, ' ')
               .replace(/<!--[\s\S]*?-->/g, ' ');
    // meta description in testa (spesso il riassunto migliore)
    const meta = (html.match(/<meta[^>]+name=["']description["'][^>]+content=["']([^"']+)["']/i) || [])[1] || '';
    const text = html.replace(/<[^>]+>/g, ' ').replace(/&[a-z#0-9]+;/gi, ' ').replace(/\s+/g, ' ').trim();
    return (meta ? meta + '\n\n' : '') + text.slice(0, 9000);
  } catch (e) {
    return null;
  }
}

async function generateDraft(b, siteText) {
  const system = `Sei l'editor delle schede di TrailShare, app outdoor italiana (escursionismo, rifugi, bici).
Dato il testo del sito ufficiale di una struttura, scrivi la descrizione della sua scheda.

REGOLE FERREE:
- Usa SOLO fatti presenti nel testo fornito. Se un'informazione non c'è, non inventarla.
- Scrivi in italiano, testo ORIGINALE (mai copiare frasi dal sito).
- Tono: informativo e caldo, utile a un escursionista/ciclista. Niente superlativi vuoti, niente marketing gridato.
- 2 paragrafi brevi (60-110 parole totali): cosa è / dove / cosa offre; poi info pratiche utili.
- Se il testo del sito è inutilizzabile (parcheggiato, errore, lingua incomprensibile, contenuti non pertinenti) metti "affidabile": false.

Rispondi SOLO con JSON valido:
{"description": "...", "periodo_apertura": "... o null", "telefono": "... o null", "email": "... o null", "servizi": ["max 6 voci brevi"], "affidabile": true/false, "note": "eventuali dubbi per il revisore, o null"}`;

  const user = `STRUTTURA: ${b.name}
TIPO: ${b.type}
LUOGO: ${[b.city, b.region].filter(Boolean).join(', ') || 'n/d'}${b.elevation ? ` (${Math.round(b.elevation)} m)` : ''}
SITO: ${b.website}

TESTO DEL SITO:
${siteText}`;

  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key': API_KEY,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 700,
      temperature: 0.4,
      system,
      messages: [{ role: 'user', content: user }],
    }),
  });
  if (!res.ok) throw new Error('anthropic HTTP ' + res.status + ' ' + (await res.text()).slice(0, 200));
  const j = await res.json();
  const text = (j.content && j.content[0] && j.content[0].text || '').trim();
  const jsonStr = text.replace(/^```json?\s*/i, '').replace(/```\s*$/, '');
  return { parsed: JSON.parse(jsonStr), usage: j.usage };
}

(async () => {
  const all = await db.collection('businesses').get();
  let candidates = [];
  all.forEach(d => {
    const x = d.data();
    const hasDesc = x.description && String(x.description).trim().length >= 20;
    const website = x.contacts && x.contacts.website;
    if (hasDesc || !website) return;
    if (x.aiDraft) return; // già processato (pending o rigettato in passato)
    if (TYPE && x.type !== TYPE) return;
    if (REGION && (!x.location || x.location.region !== REGION)) return;
    candidates.push({
      ref: d.ref, id: d.id, name: x.name, type: x.type, website,
      city: x.location && x.location.city, region: x.location && x.location.region,
      elevation: x.location && x.location.elevation,
      hasPhone: !!(x.contacts && x.contacts.phone),
      hasEmail: !!(x.contacts && x.contacts.email),
    });
  });
  // rifugi prima (priorità founder), poi noleggi
  candidates.sort((a, b) => (a.type === 'rifugio' ? 0 : 1) - (b.type === 'rifugio' ? 0 : 1));
  candidates = candidates.slice(0, LIMIT);
  console.log('Candidate da processare:', candidates.length, TYPE ? `(type=${TYPE})` : '', REGION ? `(region=${REGION})` : '');

  let ok = 0, siteFail = 0, aiFail = 0, unreliable = 0;
  let inTok = 0, outTok = 0;
  for (const [i, b] of candidates.entries()) {
    process.stdout.write(`[${i + 1}/${candidates.length}] ${b.name} ... `);
    const siteText = await fetchSiteText(b.website);
    if (!siteText || siteText.length < 200) {
      siteFail++;
      console.log('sito non leggibile, skip');
      await b.ref.update({ aiDraft: { status: 'site_unreachable', generatedAt: admin.firestore.FieldValue.serverTimestamp() } });
      continue;
    }
    try {
      const { parsed, usage } = await generateDraft(b, siteText);
      inTok += (usage && usage.input_tokens) || 0;
      outTok += (usage && usage.output_tokens) || 0;
      if (!parsed.affidabile || !parsed.description || parsed.description.length < 40) {
        unreliable++;
        console.log('AI giudica il sito inaffidabile, skip');
        await b.ref.update({ aiDraft: { status: 'unreliable', note: parsed.note || null, generatedAt: admin.firestore.FieldValue.serverTimestamp() } });
        continue;
      }
      await b.ref.update({
        aiDraft: {
          status: 'pending',
          description: String(parsed.description).trim(),
          facts: {
            periodoApertura: parsed.periodo_apertura || null,
            telefono: (!b.hasPhone && isValidPhone(parsed.telefono)) ? String(parsed.telefono).trim() : null,
            email: (!b.hasEmail && isValidEmail(parsed.email)) ? String(parsed.email).trim() : null,
            servizi: Array.isArray(parsed.servizi) ? parsed.servizi.slice(0, 6) : [],
          },
          note: parsed.note || null,
          sourceUrl: b.website,
          model: MODEL,
          generatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
      });
      ok++;
      console.log('bozza creata');
    } catch (e) {
      aiFail++;
      console.log('errore AI:', e.message.slice(0, 120));
    }
    await sleep(400);
  }
  const cost = (inTok / 1e6) * 1 + (outTok / 1e6) * 5; // pricing haiku 4.5
  console.log(`\n=== FASE B BATCH COMPLETO ===`);
  console.log(`bozze create: ${ok} | siti irraggiungibili: ${siteFail} | inaffidabili: ${unreliable} | errori: ${aiFail}`);
  console.log(`token: ${inTok} in / ${outTok} out ≈ $${cost.toFixed(2)}`);
  process.exit(0);
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
