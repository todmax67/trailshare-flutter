// Approvazione in blocco delle bozze in attesa, con filtro di sicurezza.
//
// Approvare a mano quasi quattromila schede non e' praticabile, e leggerne
// un campione non basta: quello che sfugge al campione e' proprio il caso
// raro. Questo script pubblica tutto TRANNE le bozze che inciampano in un
// controllo automatico, e quelle le rimette in coda.
//
// Il controllo: una descrizione non puo' dire "facile", "accessibile",
// "passeggiata" o "adatta a tutti" su un sentiero classificato EE o EEA.
// La scala CAI classifica il TERRENO, non la fatica — un traverso esposto
// puo' essere pianeggiante e restare da escursionisti esperti — e il
// modello, vedendo poco dislivello, a volte lo definiva facile
// contraddicendo il grado che gli avevamo appena dato ("Percorso di facile
// escursionismo (EE)").
//
// Le negazioni non contano: "NON adatta a principianti" e' corretto.
//
// Le bozze rimesse in coda si rigenerano con la regola aggiunta a
// trail_ai_descriptions.cjs, che ora vieta esplicitamente quella deduzione.
//
// Uso:
//   node scripts/trail_drafts_bulk_approve.cjs --dry
//   node scripts/trail_drafts_bulk_approve.cjs
const admin = require('../functions/node_modules/firebase-admin');
const sa = require('../functions/serviceAccountKey.json');

admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const DRY = process.argv.includes('--dry');

const IMPEGNATIVI = new Set(['ee', 'eea', 'difficile', 'EE', 'EEA']);
const RASSICURA = /\b(facile|facili|accessibile|tranquill[oa]|passeggiata|adatt[oaie] a tutti|ogni livello|per principianti|per famigli|turistic|senza difficolt|alla portata di tutti)/i;
const NEGAZIONE = /\b(non|mai|né|ne'|nessun)\b/i;

/// Vero se la parola rassicurante e' negata poco prima ("non e' una facile
/// passeggiata"): in quel caso il testo dice la cosa giusta.
function negata(testo, indice) {
  return NEGAZIONE.test(testo.slice(Math.max(0, indice - 45), indice));
}

(async () => {
  console.log(DRY ? '=== SIMULAZIONE ===\n' : '=== APPROVAZIONE ===\n');
  const snap = await db.collection('public_trails').where('aiDraft.status', '==', 'pending').get();
  console.log(`bozze in attesa: ${snap.size}\n`);

  const daPubblicare = [], daRifare = [];
  for (const d of snap.docs) {
    const x = d.data();
    const testo = String((x.aiDraft && x.aiDraft.description) || '').trim();
    if (testo.length < 40) { daRifare.push({ d, x, motivo: 'testo troppo corto' }); continue; }

    const grado = String(x.difficulty || '');
    if (IMPEGNATIVI.has(grado) || IMPEGNATIVI.has(grado.toLowerCase())) {
      const m = testo.match(RASSICURA);
      if (m && !negata(testo, testo.indexOf(m[0]))) {
        daRifare.push({ d, x, motivo: `dice "${m[0]}" su un ${grado.toUpperCase()}` });
        continue;
      }
    }
    daPubblicare.push({ d, x, testo });
  }

  console.log(`da pubblicare: ${daPubblicare.length}`);
  console.log(`da rifare:     ${daRifare.length}`);
  if (daRifare.length) {
    console.log('\nrimesse in coda:');
    daRifare.slice(0, 20).forEach((r) => console.log(
      `  ${String(r.x.name).slice(0, 44).padEnd(46)} ${r.motivo}`));
    if (daRifare.length > 20) console.log(`  ... e altre ${daRifare.length - 20}`);
  }

  if (DRY) { console.log('\nNessuna scrittura. Per applicare, togliere --dry.'); process.exit(0); }

  let n = 0;
  for (let i = 0; i < daPubblicare.length; i += 400) {
    const batch = db.batch();
    for (const p of daPubblicare.slice(i, i + 400)) {
      batch.update(p.d.ref, {
        description: p.testo,
        descriptionSource: 'ai_facts_reviewed',
        aiDraft: admin.firestore.FieldValue.delete(),
      });
    }
    await batch.commit();
    n += Math.min(400, daPubblicare.length - i);
    if (n % 1000 === 0 || n === daPubblicare.length) console.log(`  pubblicate ${n}/${daPubblicare.length}`);
  }
  for (let i = 0; i < daRifare.length; i += 400) {
    const batch = db.batch();
    for (const r of daRifare.slice(i, i + 400)) {
      batch.update(r.d.ref, { aiDraft: admin.firestore.FieldValue.delete() });
    }
    await batch.commit();
  }
  console.log(`\nFatto: ${daPubblicare.length} pubblicate, ${daRifare.length} rimesse in coda.`);
  if (daRifare.length) {
    console.log(`Per rigenerarle:  node scripts/trail_ai_descriptions.cjs --rilevati --limit ${daRifare.length + 20}`);
  }
  process.exit(0);
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
