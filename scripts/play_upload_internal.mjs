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
 * Senza --commit non viene pubblicato niente: la edit creata per l'ispezione
 * viene eliminata prima di uscire.
 */
import { readFileSync, statSync } from 'node:fs';
import { basename } from 'node:path';
import { JWT } from '/Volumes/Lexar/Sviluppo/trailshare-ai-manager/functions/node_modules/google-auth-library/build/src/index.js';

const PKG = 'com.trailshare.app';
const TRACK = 'internal';
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
const aabPath = value('--aab', 'build/app/outputs/bundle/release/app-release.aab');
const note = value('--note', 'Build di test interna.');

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

let aab;
try {
  aab = readFileSync(aabPath);
} catch {
  console.error(`AAB non trovato: ${aabPath}`);
  console.error('Compilalo con: flutter build appbundle --release');
  process.exit(1);
}
const sizeMb = (statSync(aabPath).size / 1024 / 1024).toFixed(1);

console.log(`file    ${basename(aabPath)} (${sizeMb} MB)`);
console.log(`canale  ${TRACK}`);
console.log(`modo    ${commit ? 'CARICAMENTO REALE' : 'prova a vuoto (niente verra\' pubblicato)'}\n`);

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
