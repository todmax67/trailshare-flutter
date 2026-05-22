#!/usr/bin/env node
/**
 * watch-drafts — auto-bridge dei draft social_lab quando passano a `stato: ready`
 *
 * Sorveglia `social_lab/drafts/**\/*.md` con chokidar. Quando un .md cambia:
 *   - Se `stato: ready` AND no `bridged_post_id` → invoca bridge.mjs
 *   - Altrimenti ignora
 *
 * Usage diretto:
 *   node watch-drafts.mjs
 *
 * Auto-start al login (consigliato): vedi launchd plist in
 * social_lab/scripts/com.trailshare.social-lab-watch.plist (carica con launchctl).
 *
 * Log: stdout/stderr. Quando avviato via launchd, viene rediretto in
 *   ~/Library/Logs/trailshare-social-lab-watch.log
 */

import { fileURLToPath } from "node:url";
import path from "node:path";
import fs from "node:fs/promises";
import { spawn } from "node:child_process";
import process from "node:process";
import chokidar from "chokidar";
import matter from "gray-matter";
import dotenv from "dotenv";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SOCIAL_LAB_ROOT = path.resolve(__dirname, "..");
const DRAFTS_GLOB = path.join(SOCIAL_LAB_ROOT, "drafts", "**", "*.md");
const BRIDGE_SCRIPT = path.resolve(__dirname, "bridge.mjs");

dotenv.config({ path: path.resolve(__dirname, ".env") });

// ============================================
// LOGGING
// ============================================

function log(...args) {
  const ts = new Date().toISOString();
  console.log(`[${ts}]`, ...args);
}

function logError(...args) {
  const ts = new Date().toISOString();
  console.error(`[${ts}]`, ...args);
}

// ============================================
// DEBOUNCE — evita doppi trigger su salvataggi rapidi
// ============================================

const pending = new Map(); // path → timeout id
const DEBOUNCE_MS = 1500;

function scheduleProcess(filePath) {
  const existing = pending.get(filePath);
  if (existing) clearTimeout(existing);

  const tid = setTimeout(() => {
    pending.delete(filePath);
    processDraft(filePath).catch((err) => {
      logError(`Errore processando ${filePath}:`, err.message);
    });
  }, DEBOUNCE_MS);
  pending.set(filePath, tid);
}

// ============================================
// PROCESS DRAFT
// ============================================

async function processDraft(filePath) {
  let raw;
  try {
    raw = await fs.readFile(filePath, "utf8");
  } catch (err) {
    if (err.code === "ENOENT") return; // file cancellato dopo il trigger
    throw err;
  }

  const rel = path.relative(SOCIAL_LAB_ROOT, filePath);

  // Parsing YAML può fallire su frontmatter malformati (es. drafts vecchi
  // con [SERVE] non quotato in array). In quel caso silently skip — quei
  // draft non sono comunque "ready" e non possono essere bridgiati.
  let parsed;
  try {
    parsed = matter(raw);
  } catch (err) {
    log(`skip ${rel} — YAML invalido (${err.message.split("\n")[0]})`);
    return;
  }
  const meta = parsed.data;

  if (meta.stato !== "ready") {
    log(`skip ${rel} — stato: ${meta.stato || "(none)"}`);
    return;
  }
  if (meta.bridged_post_id) {
    log(`skip ${rel} — già bridgiato (${meta.bridged_post_id})`);
    return;
  }
  if (!Array.isArray(meta.asset_paths) || meta.asset_paths.length === 0) {
    log(`skip ${rel} — asset_paths vuoto`);
    return;
  }
  if (meta.asset_paths.some((p) => typeof p === "string" && p.includes("[SERVE"))) {
    log(`skip ${rel} — contiene [SERVE]`);
    return;
  }

  log(`▶ bridge ${rel}`);
  await runBridge(filePath, rel);
}

function runBridge(filePath, rel) {
  return new Promise((resolve) => {
    const child = spawn("node", [BRIDGE_SCRIPT, filePath], {
      cwd: __dirname,
      env: process.env,
      stdio: ["ignore", "pipe", "pipe"],
    });

    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d) => (stdout += d.toString()));
    child.stderr.on("data", (d) => (stderr += d.toString()));

    child.on("exit", (code) => {
      if (code === 0) {
        log(`✓ bridge ${rel} OK`);
      } else {
        logError(`✗ bridge ${rel} exit ${code}`);
        if (stderr.trim()) logError(`stderr: ${stderr.trim()}`);
        if (stdout.trim()) logError(`stdout: ${stdout.trim()}`);
      }
      resolve();
    });

    child.on("error", (err) => {
      logError(`✗ bridge ${rel} spawn error:`, err.message);
      resolve();
    });
  });
}

// ============================================
// MAIN
// ============================================

log(`🔭 Watching ${DRAFTS_GLOB}`);
log(`   Auto-bridge: stato:ready + asset_paths reali + non già bridgiato`);
log(`   Debounce: ${DEBOUNCE_MS}ms`);

const watcher = chokidar.watch(DRAFTS_GLOB, {
  persistent: true,
  ignoreInitial: false, // alla startup processa anche i draft esistenti già pronti
  awaitWriteFinish: {
    stabilityThreshold: 800,
    pollInterval: 100,
  },
});

watcher.on("ready", () => {
  log(`✓ Watcher pronto`);
});

watcher.on("add", (filePath) => scheduleProcess(filePath));
watcher.on("change", (filePath) => scheduleProcess(filePath));

watcher.on("error", (err) => {
  logError("Watcher error:", err.message);
});

// Graceful shutdown
process.on("SIGINT", async () => {
  log("⏹ Shutting down (SIGINT)");
  await watcher.close();
  process.exit(0);
});
process.on("SIGTERM", async () => {
  log("⏹ Shutting down (SIGTERM)");
  await watcher.close();
  process.exit(0);
});
