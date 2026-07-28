// Copertina e galleria dei tour dalle foto dei rifugi di tappa.
//
// I rifugi assegnati alle tappe hanno gia' un'immagine: usarla e' gratis e
// pertinente, perche' e' esattamente il posto dove si dorme in quel tour.
//
// MA LE LICENZE VANNO RISPETTATE. Due terzi di quelle foto vengono da
// Wikimedia Commons con CC BY o CC BY-SA, che obbligano a citare l'autore
// OVUNQUE l'immagine sia mostrata — miniature comprese. `galleryUrls` da
// sola e' una lista di stringhe: copiarci dentro una CC BY-SA significa
// pubblicarla senza credito. Percio' si scrive anche `galleryAttributions`
// (url -> {author, license, source}), che la scheda mostra col
// PhotoCreditChip gia' usato sulla pagina del rifugio.
//
// Le foto senza attribuzione registrata NON si usano: non sapendo da dove
// vengono, non possiamo sapere se abbiamo il diritto di ripubblicarle.
//
// Uso:
//   node scripts/tour_photos_from_rifugi.cjs --dry
//   node scripts/tour_photos_from_rifugi.cjs
const admin = require('../functions/node_modules/firebase-admin');
const sa = require('../functions/serviceAccountKey.json');

admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const DRY = process.argv.includes('--dry');
const REDAZIONE_UID = '1sw845iay7XZnTWzX6IcEYsLIgd2';
const MAX_GALLERIA = 8;

(async () => {
  console.log(DRY ? '=== SIMULAZIONE ===\n' : '=== SCRITTURA ===\n');
  const tSnap = await db.collection('users').doc(REDAZIONE_UID).collection('tours').get();

  let toccati = 0, fotoTot = 0, senzaCredito = 0, gianteCopertina = 0;
  for (const doc of tSnap.docs) {
    const t = doc.data();
    if (t.isPublic) continue;                       // solo le bozze
    if (!t.generatedFromCatalog) continue;          // solo quelle generate
    const bizIds = Object.values(t.stageAccommodations || {});
    if (!bizIds.length) continue;

    const urls = [], crediti = {};
    for (const id of [...new Set(bizIds)]) {
      if (urls.length >= MAX_GALLERIA) break;
      const b = await db.collection('businesses').doc(id).get();
      if (!b.exists) continue;
      const x = b.data();
      const url = x.photoUrl || (x.branding && x.branding.heroPhotoUrl);
      if (!url) continue;
      const a = x.photoAttribution;
      if (!a) { senzaCredito++; continue; }         // origine ignota: si lascia stare
      urls.push(url);
      crediti[url] = a;
    }

    if (!urls.length) { console.log(`· ${t.title}: nessuna foto utilizzabile`); continue; }
    toccati++; fotoTot += urls.length;

    const upd = { galleryUrls: urls, galleryAttributions: crediti };
    // La copertina e' la prima della galleria, salvo che ce ne sia gia' una.
    if (!t.coverPhotoUrl) upd.coverPhotoUrl = urls[0]; else gianteCopertina++;

    const lic = [...new Set(urls.map((u) => crediti[u].license || '?'))].join(', ');
    console.log(`${DRY ? '·' : '✓'} ${String(t.title).slice(0, 40).padEnd(42)} ${urls.length} foto` +
      `${upd.coverPhotoUrl ? ' + copertina' : ''}   [${lic}]`);
    if (!DRY) await doc.ref.update(upd);
  }

  console.log(`\ntour aggiornati:            ${toccati}`);
  console.log(`foto in totale:             ${fotoTot}`);
  console.log(`scartate senza attribuzione: ${senzaCredito}  <- origine ignota, non ripubblicabili`);
  console.log(`copertine gia' presenti:    ${gianteCopertina}  (non sovrascritte)`);
  if (DRY) console.log('\nNessuna scrittura. Per applicare, togliere --dry.');
  process.exit(0);
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
