#!/usr/bin/env node
/**
 * social_lab → trailshare-ai-manager bridge
 *
 * Trasforma un draft markdown di social_lab in un post Firestore pronto
 * per la pubblicazione dalla dashboard del manager.
 *
 * Usage:
 *   node bridge.mjs <draft-path> [--force]
 *
 * Esempi:
 *   node bridge.mjs ../drafts/2026-W18/fb_post_lungo_storia_lifeline.md
 *   node bridge.mjs --force ../drafts/2026-W19/foo.md   # ri-bridge anche se già bridgiato
 *
 * Service account:
 *   Default: social_lab/scripts/sa-bridge-writer.json
 *   Override: BRIDGE_SA_JSON=/path/to/sa.json node bridge.mjs ...
 *
 * Telegram notification (opzionale):
 *   Se TELEGRAM_BOT_TOKEN e TELEGRAM_CHAT_ID sono in .env, dopo il push
 *   manda una notifica al founder col link alla dashboard.
 *
 * Idempotency:
 *   Dopo un bridge riuscito, scrive `bridged_post_id` e `bridged_at` nel
 *   frontmatter del draft. Re-run sullo stesso draft viene bloccato (skip)
 *   a meno di --force, per evitare duplicati in dashboard.
 *
 * Cosa fa:
 *   1. Parsa frontmatter YAML del draft
 *   2. Valida (stato: ready, asset paths reali, caption presente, non già bridgiato)
 *   3. Carica gli asset su Storage del manager (cartella content/social_lab/...)
 *   4. Crea documento Firestore in posts/ con status="ready"
 *   5. Aggiorna il frontmatter del draft con bridged_post_id + bridged_at
 *   6. Invia notifica Telegram (se configurata)
 *   7. Stampa l'URL dashboard per revisione finale
 */

import { fileURLToPath } from "node:url";
import path from "node:path";
import fs from "node:fs/promises";
import { existsSync } from "node:fs";
import process from "node:process";
import { initializeApp, cert } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import matter from "gray-matter";
import dotenv from "dotenv";

// ============================================
// CONSTANTS
// ============================================

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SOCIAL_LAB_ROOT = path.resolve(__dirname, "..");          // social_lab/
const REPO_ROOT = path.resolve(SOCIAL_LAB_ROOT, "..");          // trailshare_flutter/
const DEFAULT_SA = path.resolve(__dirname, "sa-bridge-writer.json");
const ENV_FILE = path.resolve(__dirname, ".env");

// Carica .env se presente (TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, ecc.)
dotenv.config({ path: ENV_FILE });

const MIME_BY_EXT = {
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  png: "image/png",
  webp: "image/webp",
  gif: "image/gif",
  mp4: "video/mp4",
  mov: "video/quicktime",
  webm: "video/webm",
};

// ============================================
// CLI
// ============================================

const argv = process.argv.slice(2);
const force = argv.includes("--force");
const positional = argv.filter((a) => !a.startsWith("--"));

if (positional.length === 0 || argv.includes("--help") || argv.includes("-h")) {
  console.error("Usage: node bridge.mjs <draft-path> [--force]");
  console.error("");
  console.error("Esempi:");
  console.error("  node bridge.mjs ../drafts/2026-W18/fb_post_lungo_storia_lifeline.md");
  console.error("  node bridge.mjs --force ../drafts/2026-W19/foo.md");
  process.exit(1);
}

const draftArg = positional[0];

let draftAbs;
if (path.isAbsolute(draftArg)) {
  draftAbs = draftArg;
} else if (existsSync(path.resolve(process.cwd(), draftArg))) {
  draftAbs = path.resolve(process.cwd(), draftArg);
} else {
  draftAbs = path.resolve(REPO_ROOT, draftArg);
}

if (!existsSync(draftAbs)) {
  console.error(`✗ Draft non trovato: ${draftAbs}`);
  process.exit(3);
}

// ============================================
// SERVICE ACCOUNT
// ============================================

const saPath = process.env.BRIDGE_SA_JSON || DEFAULT_SA;
let sa;
try {
  sa = JSON.parse(await fs.readFile(saPath, "utf8"));
} catch {
  console.error(`✗ Service account non trovato: ${saPath}`);
  console.error(`  Genera la SA per "trailshare-ai-manager" (vedi social_lab/README.md → Setup bridge)`);
  console.error(`  oppure usa: BRIDGE_SA_JSON=/path/to/sa.json node bridge.mjs ...`);
  process.exit(2);
}

// ============================================
// PARSE DRAFT
// ============================================

console.log(`→ Leggo ${path.relative(process.cwd(), draftAbs)}`);

const raw = await fs.readFile(draftAbs, "utf8");
const parsed = matter(raw);
const meta = parsed.data;
const content = parsed.content;

// ============================================
// IDEMPOTENCY CHECK
// ============================================

if (meta.bridged_post_id && !force) {
  console.error(`\n⚠ Draft già bridgiato:`);
  console.error(`  bridged_post_id: ${meta.bridged_post_id}`);
  console.error(`  bridged_at: ${meta.bridged_at || "(non registrato)"}`);
  console.error(`\nSe vuoi ri-bridgiare comunque (creerà un duplicato), usa --force.`);
  console.error(`Per re-bridge pulito: cancella prima il post in dashboard, rimuovi bridged_post_id dal frontmatter, rilancia.`);
  process.exit(6);
}

// ============================================
// VALIDATE
// ============================================

const errors = [];

if (meta.stato !== "ready") {
  errors.push(`stato è "${meta.stato || "(mancante)"}", deve essere "ready" — il founder lo cambia quando il draft è approvato`);
}
if (!meta.canale) {
  errors.push("canale mancante");
} else if (!["instagram", "facebook"].includes(meta.canale)) {
  errors.push(`canale "${meta.canale}" non supportato dal bridge (per ora solo instagram/facebook; tiktok sarà aggiunto)`);
}
if (!Array.isArray(meta.asset_paths) || meta.asset_paths.length === 0) {
  errors.push("asset_paths vuoto o mancante");
}
for (const p of meta.asset_paths || []) {
  if (typeof p !== "string") {
    errors.push(`asset_paths contiene un valore non-stringa: ${JSON.stringify(p)}`);
    continue;
  }
  if (p.includes("[SERVE")) {
    errors.push(`asset_paths contiene placeholder non risolto: ${p}`);
  }
}

const captionMatch = content.match(/##\s+Caption\s*\n+([\s\S]+?)(?=\n##\s|\n*$)/);
if (!captionMatch) {
  errors.push("sezione `## Caption` mancante");
}

const hashtagSection = content.match(/##\s+Hashtag\s*\n+([\s\S]+?)(?=\n##\s|\n*$)/);

if (errors.length > 0) {
  console.error("\n✗ Validazione fallita:");
  for (const e of errors) console.error(`  - ${e}`);
  console.error("\nSistema il draft e rilancia.");
  process.exit(4);
}

const caption = captionMatch[1].trim();
const hashtags = hashtagSection ? extractHashtags(hashtagSection[1]) : [];

console.log(`✓ Frontmatter OK`);
console.log(`  Canale: ${meta.canale}`);
console.log(`  Voce: ${meta.voce}`);
console.log(`  Tema: ${meta.tema}`);
console.log(`  Asset: ${meta.asset_paths.length}`);
console.log(`  Caption: ${caption.length} char`);
console.log(`  Hashtag: ${hashtags.length}`);

// ============================================
// FIREBASE INIT
// ============================================

const projectId = sa.project_id;
const bucketName = `${projectId}.firebasestorage.app`;

const app = initializeApp({
  credential: cert(sa),
  projectId,
  storageBucket: bucketName,
});

const db = getFirestore(app);
const bucket = getStorage(app).bucket();

// ============================================
// UPLOAD ASSETS
// ============================================

const slug = path.basename(draftAbs, ".md");
const week = meta.settimana || "unknown";

console.log(`\n→ Upload ${meta.asset_paths.length} asset su gs://${bucketName}/content/social_lab/${week}/${slug}/`);

const mediaUrls = [];
for (let i = 0; i < meta.asset_paths.length; i++) {
  const relPath = meta.asset_paths[i];
  const localAbs = path.isAbsolute(relPath) ? relPath : path.resolve(REPO_ROOT, relPath);

  let stat;
  try {
    stat = await fs.stat(localAbs);
  } catch {
    console.error(`  ✗ asset[${i}] non trovato: ${localAbs}`);
    process.exit(5);
  }

  const ext = path.extname(localAbs).toLowerCase().slice(1) || "jpg";
  const contentType = MIME_BY_EXT[ext] || "application/octet-stream";
  const remotePath = `content/social_lab/${week}/${slug}/${String(i).padStart(2, "0")}.${ext}`;

  const buffer = await fs.readFile(localAbs);
  const file = bucket.file(remotePath);
  await file.save(buffer, {
    metadata: { contentType, cacheControl: "public, max-age=86400" },
  });
  await file.makePublic();

  const url = `https://storage.googleapis.com/${bucket.name}/${remotePath}`;
  mediaUrls.push(url);
  console.log(`  ✓ ${i + 1}/${meta.asset_paths.length}: ${path.basename(relPath)} (${(stat.size / 1024).toFixed(0)} KB)`);
}

// ============================================
// CREATE FIRESTORE POST
// ============================================

const platforms = [meta.canale];
const firstExt = path.extname(meta.asset_paths[0]).toLowerCase();
const isVideo = [".mp4", ".mov", ".webm"].includes(firstExt);
const mediaType = isVideo ? "video" : meta.asset_paths.length > 1 ? "carousel" : "image";

const postRef = db.collection("posts").doc();
const postData = {
  id: postRef.id,
  createdAt: Timestamp.now(),
  updatedAt: Timestamp.now(),
  mediaUrls,
  mediaType,
  captionDraft: `[social_lab] ${meta.tema || slug}`,
  captionFinal: caption,
  hashtags: hashtags.map((h) => (h.startsWith("#") ? h : `#${h}`)),
  status: "ready",
  platforms,
  source: {
    type: "social_lab",
    postId: slug,
    postUrl: path.relative(REPO_ROOT, draftAbs),
    title: meta.tema || slug,
  },
};

await postRef.set(postData);

console.log(`\n✓ Post creato in Firestore: posts/${postRef.id}`);
console.log(`  Status: ready`);
console.log(`  Canale: ${meta.canale}`);
console.log(`  MediaType: ${mediaType}`);

// ============================================
// WRITE-BACK FRONTMATTER (idempotency marker)
// ============================================

const updatedMeta = {
  ...meta,
  bridged_post_id: postRef.id,
  bridged_at: new Date().toISOString(),
};
const updatedRaw = matter.stringify(content, updatedMeta);
await fs.writeFile(draftAbs, updatedRaw, "utf8");
console.log(`✓ Frontmatter aggiornato con bridged_post_id`);

// ============================================
// TELEGRAM NOTIFICATION (opzionale)
// ============================================

await notifyTelegram({
  tema: meta.tema || slug,
  canale: meta.canale,
  voce: meta.voce,
  asset: meta.asset_paths.length,
  postId: postRef.id,
  projectId,
});

console.log(`\n→ Apri la dashboard per revisione finale + pubblicazione:`);
console.log(`  https://${projectId}.web.app`);
console.log("");
console.log(`Dopo la pubblicazione, archivia il draft con:`);
const archivedPath = draftAbs.replace("/drafts/", "/published/");
console.log(`  mkdir -p ${path.dirname(path.relative(process.cwd(), archivedPath))}`);
console.log(`  mv ${path.relative(process.cwd(), draftAbs)} ${path.relative(process.cwd(), archivedPath)}`);
console.log(`  Poi aggiorna il frontmatter: stato → published, data_pubblicazione: YYYY-MM-DD`);

process.exit(0);

// ============================================
// HELPERS
// ============================================

function extractHashtags(text) {
  const cleaned = text
    .replace(/```[a-z]*\n/g, "")
    .replace(/```/g, "")
    .replace(/\n/g, " ");
  const matches = cleaned.match(/#[\w]+/g) || [];
  return matches.map((h) => h.toLowerCase());
}

async function notifyTelegram({ tema, canale, voce, asset, postId, projectId }) {
  const token = process.env.TELEGRAM_BOT_TOKEN;
  const chatId = process.env.TELEGRAM_CHAT_ID;
  if (!token || !chatId) {
    // Notifiche opzionali: silently skip se non configurate
    return;
  }
  const platformIcon = canale === "instagram" ? "📸" : "📘";
  const text =
    `🌉 <b>Bridge OK</b>\n\n` +
    `${platformIcon} <b>${escapeHtml(tema)}</b>\n` +
    `Canale: ${canale} · Voce: ${voce}\n` +
    `Asset: ${asset} · Post ID: <code>${postId}</code>\n\n` +
    `Pronto in dashboard per revisione e pubblicazione:\n` +
    `https://${projectId}.web.app`;

  try {
    const res = await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: chatId,
        text,
        parse_mode: "HTML",
        disable_web_page_preview: true,
      }),
    });
    if (!res.ok) {
      const body = await res.text();
      console.warn(`⚠ Telegram notify fallita (${res.status}): ${body.slice(0, 200)}`);
    } else {
      console.log(`✓ Notifica Telegram inviata`);
    }
  } catch (err) {
    console.warn(`⚠ Telegram notify errore: ${err.message}`);
  }
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}
