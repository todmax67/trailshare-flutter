#!/usr/bin/env node
/**
 * Carica un AAB sul canale di test interno della Play Console.
 *
 * A cosa serve. Una build compilata in locale e' firmata con la chiave dello
 * sviluppatore; quella su Play e' rifirmata da Google (Play App Signing). Le
 * due firme non coincidono, quindi Android rifiuta l'aggiornamento e l'unica
 * via e' disinstallare — perdendo i dati locali, mappe offline comprese.
 *
 * Passando dal canale interno la firma la mette Google in entrambi i casi:
 * la build di test arriva come aggiornamento normale, e per giunta si prova
 * esattamente il binario che riceveranno gli utenti.
 *
 * Uso:
 *   node scripts/play_upload_internal.mjs                    # prova a vuoto
 *   node scripts/play_upload_internal.mjs --commit           # carica davvero
 *   node scripts/play_upload_internal.mjs --aab <percorso> --note "testo"
 *
 * E, dopo aver provato la build sul telefono, per mandarla in produzione:
 *   node scripts/play_upload_internal.mjs --promote                    # a vuoto
 *   node scripts/play_upload_internal.mjs --promote --commit
 *   node scripts/play_upload_internal.mjs --promote --commit --rollout 0.2
 *   node scripts/play_upload_internal.mjs --promote --commit --notes-file docs/store_notes_2.11.0.md
 *
 * La promozione sposta in produzione LA STESSA release gia' presente sul canale
 * interno: stesso versionCode, stessi byte. Ricompilare per la produzione
 * significherebbe spedire un artefatto che nessuno ha provato.
 *
 * Senza --commit non viene pubblicato niente: la edit creata per l'ispezione
 * viene eliminata prima di uscire.
 */
import { readFileSync, statSync } from 'node:fs';
import { basename } from 'node:path';
import { JWT } from '/Volumes/Lexar/Sviluppo/trailshare-ai-manager/functions/node_modules/google-auth-library/build/src/index.js';

const PKG = 'com.trailshare.app';
const TRACK = 'internal';
const PROD = 'production';
const KEY = '/Volumes/Lexar/secrets/trailshare-5334b-b0139919e3d1.json';
const BASE = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications';
const UPLOAD = 'https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications';

const args = process.argv.slice(2);
const flag = (name) => args.includes(name);
const value = (name, fallback) => {
  const i = args.indexOf(name);
  return i >= 0 && args[i + 1] ? args[i + 1] : fallback;
};

const commit = flag('--commit');
const promote = flag('--promote');
const aabPath = value('--aab', 'build/app/outputs/bundle/release/app-release.aab');
const note = value('--note', 'Build di test interna.');
const notesFile = value('--notes-file', null);
// Rollout progressivo: 0.2 = al 20% degli utenti. Assente = a tutti.
const rollout = value('--rollout', null);

// --- autenticazione ------------------------------------------------------

const sa = JSON.parse(readFileSync(KEY, 'utf8'));
const jwt = new JWT({
  email: sa.client_email,
  key: sa.private_key,
  scopes: ['https://www.googleapis.com/auth/androidpublisher'],
});
const { token } = await jwt.getAccessToken();

const api = async (method, path, body) => {
  const r = await fetch(`${BASE}/${PKG}${path}`, {
    method,
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await r.text();
  const parsed = text ? JSON.parse(text) : null;
  if (!r.ok) {
    throw new Error(`${method} ${path} → HTTP ${r.status}: ${parsed?.error?.message ?? text}`);
  }
  return parsed;
};

// --- controlli prima di toccare la console -------------------------------

if (rollout !== null && !promote) {
  console.error('--rollout vale solo con --promote: il canale interno va sempre a tutti i tester.');
  process.exit(1);
}
const fraction = rollout === null ? null : Number(rollout);
if (fraction !== null && (!Number.isFinite(fraction) || fraction <= 0 || fraction >= 1)) {
  console.error(`--rollout dev'essere fra 0 e 1 escusi (es. 0.2 per il 20%). Ricevuto: ${rollout}`);
  process.exit(1);
}

// In promozione non serve nessun file: si sposta una release gia' caricata.
let aab = null;
if (!promote) {
  try {
    aab = readFileSync(aabPath);
  } catch {
    console.error(`AAB non trovato: ${aabPath}`);
    console.error('Compilalo con: flutter build appbundle --release');
    process.exit(1);
  }
  const sizeMb = (statSync(aabPath).size / 1024 / 1024).toFixed(1);
  console.log(`file    ${basename(aabPath)} (${sizeMb} MB)`);
}

console.log(`azione  ${promote ? `promozione ${TRACK} → ${PROD}` : `caricamento su ${TRACK}`}`);
if (fraction !== null) console.log(`rollout ${(fraction * 100).toFixed(0)}% degli utenti`);
console.log(`modo    ${commit ? 'ESECUZIONE REALE' : 'prova a vuoto (niente verra\' pubblicato)'}\n`);

const edit = await api('POST', '/edits', {});
const editId = edit.id;

try {
  // Le release gia' presenti: serve a vedere subito se il versionCode e' bruciato.
  const tracks = await api('GET', `/edits/${editId}/tracks`);
  console.log('canali attuali:');
  for (const t of tracks.tracks ?? []) {
    const rel = (t.releases ?? [])
      .map((r) => `${r.status} ${(r.versionCodes ?? []).join(',')}`)
      .join(' | ');
    console.log(`   ${t.track.padEnd(18)} ${rel || '(nessuna release)'}`);
  }
  console.log();

  // --- promozione: canale interno → produzione ---------------------------

  if (promote) {
    const internal = (tracks.tracks ?? []).find((t) => t.track === TRACK);
    const source = (internal?.releases ?? []).find((r) => (r.versionCodes ?? []).length);
    if (!source) {
      throw new Error(`nessuna release sul canale ${TRACK}: prima carica una build.`);
    }

    const prod = (tracks.tracks ?? []).find((t) => t.track === PROD);
    const live = (prod?.releases ?? []).flatMap((r) => r.versionCodes ?? []);
    if (live.includes(source.versionCodes[0])) {
      throw new Error(
        `la versionCode ${source.versionCodes[0]} e' gia' in produzione: niente da promuovere.`,
      );
    }

    // Guardia contro la retrocessione. Il canale interno puo' benissimo essere
    // fermo a una build vecchia — lo era, alla 95 contro la 122 in produzione —
    // e promuoverla significherebbe rimandare agli utenti una versione
    // superata. Play accetterebbe la richiesta senza obiettare.
    const newest = Math.max(0, ...live.map(Number));
    const candidate = Math.max(...source.versionCodes.map(Number));
    if (candidate < newest) {
      throw new Error(
        `RETROCESSIONE: il canale ${TRACK} ha la ${candidate}, la produzione ha la ${newest}. ` +
          `Carica prima una build nuova sul canale interno.`,
      );
    }

    // Le note di rilascio non viaggiano da sole: se non si ripassano, la
    // scheda "Novita'" in produzione resta vuota.
    let notes = source.releaseNotes;
    if (notesFile) {
      notes = [{ language: 'it-IT', text: readFileSync(notesFile, 'utf8').trim() }];
    }
    if (!notes?.length) {
      console.log('ATTENZIONE: nessuna nota di rilascio. Usa --notes-file per non');
      console.log('            lasciare vuota la sezione "Novita\'" in produzione.\n');
    }

    const release = {
      versionCodes: source.versionCodes,
      releaseNotes: notes,
      ...(fraction === null
        ? { status: 'completed' }
        : { status: 'inProgress', userFraction: fraction }),
    };

    console.log(`promuovo la versionCode ${source.versionCodes.join(',')} in produzione`);
    console.log(`   sostituisce: ${live.join(',') || '(niente)'}`);

    if (!commit) {
      console.log('\nProva a vuoto conclusa. Rilancia con --commit per promuovere davvero.');
      await api('DELETE', `/edits/${editId}`);
      process.exit(0);
    }

    await api('PUT', `/edits/${editId}/tracks/${PROD}`, { track: PROD, releases: [release] });
    await api('POST', `/edits/${editId}:commit`);
    console.log(
      `\nFatto. In produzione${fraction === null ? '' : ` al ${(fraction * 100).toFixed(0)}%`}.`,
    );
    process.exit(0);
  }

  if (!commit) {
    console.log('Prova a vuoto conclusa. Rilancia con --commit per caricare davvero.');
    await api('DELETE', `/edits/${editId}`);
    process.exit(0);
  }

  // --- caricamento -------------------------------------------------------

  console.log('carico l\'AAB…');
  const up = await fetch(`${UPLOAD}/${PKG}/edits/${editId}/bundles?uploadType=media`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/octet-stream' },
    body: aab,
  });
  const upText = await up.text();
  if (!up.ok) {
    throw new Error(`caricamento fallito → HTTP ${up.status}: ${upText}`);
  }
  const versionCode = JSON.parse(upText).versionCode;
  console.log(`   caricato, versionCode ${versionCode}`);

  await api('PUT', `/edits/${editId}/tracks/${TRACK}`, {
    track: TRACK,
    releases: [
      {
        versionCodes: [String(versionCode)],
        status: 'completed',
        releaseNotes: [{ language: 'it-IT', text: note }],
      },
    ],
  });
  console.log(`   assegnato al canale ${TRACK}`);

  await api('POST', `/edits/${editId}:commit`);
  console.log(`\nFatto. La build arriva ai tester interni fra qualche minuto,`);
  console.log('e si installa come aggiornamento normale: niente disinstallazione.');
} catch (err) {
  // Una edit non committata non ha effetti, ma lasciarla in giro confonde
  // la console: si prova a ripulire prima di propagare l'errore.
  await api('DELETE', `/edits/${editId}`).catch(() => {});
  console.error(`\nERRORE: ${err.message}`);
  process.exit(1);
}
