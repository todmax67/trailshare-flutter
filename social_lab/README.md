# social_lab

Workspace del social media manager di TrailShare. Contiene briefing del brand, editorial calendar, asset e draft dei post.

## Come funziona

1. Riempi `assets/` con le tue foto/video grezzi, organizzati per tema
2. Invoca il sub-agente **social-manager** con un comando tipo:
   - *"prepara post settimana 17"*
   - *"genera 3 varianti reel sul tema Lifeline usando gli asset in video_demo/lifeline"*
   - *"prepara un IG carousel sulla feature classifiche regionali"*
3. L'agente produce draft in `drafts/YYYY-WW/<slug>.md` con `stato: draft`
4. **Rivedi i draft**: ritocca caption, verifica asset, eventualmente ritaglia immagini per IG (1:1, 4:5, 1.91:1)
5. **Quando il draft è pronto** cambia il frontmatter a `stato: ready`
6. **Lancia il bridge** per pushare il draft come post nel manager Firestore:
   ```
   cd social_lab/scripts
   node bridge.mjs ../drafts/2026-W18/foo.md
   ```
7. Apri la dashboard del manager → revisione finale → ✅ Pubblica
8. Quando pubblicato, archivia il draft: `mv drafts/.../foo.md published/.../foo.md` e aggiorna `stato: published` + `data_pubblicazione`
9. Dopo qualche giorno, aggiungi le metriche reali (reach, likes, commenti) nel file archiviato
10. Fine mese: *"analizza performance ultimo mese"* → retrospettiva via sub-agent

## Bridge social_lab → ai-manager

Lo script `scripts/bridge.mjs` collega questo workspace al runtime di pubblicazione [trailshare-ai-manager](../../trailshare-ai-manager/) (Firebase live).

Cosa fa quando lo lanci su un draft:

1. Parsa il frontmatter YAML del draft
2. Valida (`stato: ready`, `asset_paths` reali senza `[SERVE]`, caption presente)
3. Carica gli asset dal repo locale → Storage del manager (`content/social_lab/<settimana>/<slug>/`)
4. Crea documento Firestore in `posts/` del manager con `status: ready`
5. Stampa l'URL della dashboard per la revisione finale

Da quel momento il post è nella coda della dashboard / `/lista` del bot Telegram, pronto da approvare e pubblicare.

### Setup bridge (una sola volta)

Servono 2 cose: dipendenze Node + service account.

**1. Dipendenze**:
```bash
cd social_lab/scripts
npm install
```

**2. Service account writer per il manager**:

Apri https://console.cloud.google.com/iam-admin/serviceaccounts?project=trailshare-ai-manager (logga come `toddemassimiliano67@gmail.com`).

- Click **"+ Create service account"**
  - Name: `social-lab-bridge-writer`
  - Description: `Bridge da social_lab al manager: writes Firestore posts/ + Storage content/`
- Step 2 "Grant access":
  - Aggiungi ruolo **Cloud Datastore User** (Firestore read+write)
  - Aggiungi ruolo **Storage Object Admin** (Storage read+write)
  - Click Continue → Done
- Click sul SA appena creato → tab **Keys** → Add key → Create new key → JSON → Create
- Salva il file scaricato come `social_lab/scripts/sa-bridge-writer.json`

```bash
mv ~/Downloads/trailshare-ai-manager-*.json social_lab/scripts/sa-bridge-writer.json
```

⚠️ **Mai committare** `sa-bridge-writer.json`: è già in `social_lab/scripts/.gitignore`.

### Workflow tipico

```bash
# 1. social-manager produce i draft
# (chat con Claude: "prepara i post di questa settimana")

# 2. Rivedi i draft, ritocca, marca stato: ready
# (apri il file .md, modifica)

# 3. Bridge il draft pronto
cd social_lab/scripts
node bridge.mjs ../drafts/2026-W18/fb_post_lungo_storia_lifeline.md

# 4. Apri dashboard, revisiona, pubblica
open https://trailshare-ai-manager.web.app

# 5. Archivia il draft come pubblicato
mkdir -p ../published/2026-W18
mv ../drafts/2026-W18/fb_post_lungo_storia_lifeline.md ../published/2026-W18/
# poi modifica il frontmatter: stato: published + data_pubblicazione: 2026-05-04
```

### Limiti attuali del bridge

- **No auto-resize aspect ratio**: per IG devi pre-cropare le immagini a 1:1 / 4:5 / 1.91:1 prima del bridge (o usa Claude Design per la composizione, vedi sotto). Auto-crop con `sharp` è in TODO post-launch.
- **Solo IG e FB**: TikTok skippato (manca OAuth setup; vedi TODO).
- **No rollback automatico**: se il push Firestore fallisce dopo upload Storage, restano file orfani in Storage. Cleanup manuale se serve.

### Idempotency (anti-duplicati)

Dopo un bridge riuscito, lo script scrive nel frontmatter del draft:
```yaml
bridged_post_id: <firestore-doc-id>
bridged_at: '2026-05-07T...'
```

Se rilanci `node bridge.mjs` sullo stesso draft, il bridge **rifiuta** (exit 6) per evitare duplicati. Per ri-bridgiare comunque (es. dopo aver cancellato il post in dashboard):
1. Cancella prima il post in dashboard
2. Rimuovi `bridged_post_id` e `bridged_at` dal frontmatter del draft
3. Rilancia `node bridge.mjs ...`

Oppure, se sai cosa stai facendo, usa `--force` per saltare il check (rischia duplicati).

### Watcher auto-bridge (opzionale)

Per evitare di lanciare `bridge.mjs` a mano ogni volta, c'è un watcher che monitora `drafts/**/*.md` e auto-bridgia quando un draft passa a `stato: ready` (e non è già stato bridgiato).

**Avvio manuale (in foreground)**:
```bash
cd social_lab/scripts
npm run watch
```
Tieni il terminale aperto. Modifica un draft → salva con `stato: ready` → entro 1.5s parte il bridge automatico.

**Auto-start al login (consigliato, macOS)**:
```bash
# 1. Verifica path di node sul tuo Mac
which node
# se non è /usr/local/bin/node, modifica il plist al passo 2

# 2. Copia plist in LaunchAgents
cp social_lab/scripts/com.trailshare.social-lab-watch.plist ~/Library/LaunchAgents/

# 3. Carica il LaunchAgent
launchctl load ~/Library/LaunchAgents/com.trailshare.social-lab-watch.plist

# 4. Verifica che gira
launchctl list | grep trailshare
tail -f ~/Library/Logs/trailshare-social-lab-watch.log
```

Da quel momento, ogni volta che fai login il watcher parte automaticamente. Modifichi un draft a `stato: ready` → entro 1.5s ricevi notifica Telegram (se hai .env configurato) col link al post in dashboard.

**Disinstallazione**:
```bash
launchctl unload ~/Library/LaunchAgents/com.trailshare.social-lab-watch.plist
rm ~/Library/LaunchAgents/com.trailshare.social-lab-watch.plist
```

### Notifica Telegram bridge (opzionale)

Per ricevere notifica Telegram dopo ogni bridge riuscito (con link diretto al post in dashboard):

```bash
cd social_lab/scripts
cp .env.example .env
# Apri .env e popola TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID
# (gli stessi valori che hai impostato come Firebase secrets per il manager)
```

`.env` è gitignored. Sia `bridge.mjs` che `watch-drafts.mjs` la leggono se presente. Se manca, il bridge funziona uguale ma senza notifica.

### Workflow consolidato (con watcher attivo)

```
1. social-manager agent (chat con Claude Code)
   "prepara post W19 sul tema classifiche regionali"
   ↓
2. Agent produce drafts in social_lab/drafts/2026-W19/ (stato: draft)
   ↓
3. Tu rivedi i .md, eventualmente generi visual carousel via claude.ai/design
   ↓
4. Quando un draft è pronto: cambi stato: draft → ready
   ↓
5. ⚙ Watcher detect → auto-bridge → Firestore + Telegram notification
   ↓
6. 🔔 Telegram: "Bridge OK — post pronto in dashboard"
   ↓
7. Apri dashboard → review finale → ✅ Pubblica
   ↓
8. Manager pubblica su IG/FB
   ↓
9. Archivia: mv drafts/.../foo.md published/.../foo.md + stato: published
```

Tempo umano per settimana: ~30-45 min totali (gen drafts + review + publish).

## Struttura

```
social_lab/
├── README.md              questo file
├── calendar.md            editorial calendar 3 mesi, tema per settimana
├── brand/
│   ├── positioning.md     chi siamo, audience, differenziatori
│   ├── voice_and_tone.md  tono di voce, regole anonimato, do/don't
│   ├── hashtag_bank.md    hashtag per tema/regione/stagione
│   └── feature_map.md     mappa feature app (fonte di verita)
├── assets/                (gitignored - materiali pesanti)
│   ├── screenshots_app/
│   ├── paesaggi/
│   ├── video_demo/
│   ├── ambassador/
│   └── generated/         (asset generati, es. template grafici)
├── drafts/                post in preparazione
│   └── YYYY-WW/
└── published/             archivio storico con metriche reali
    └── YYYY-WW/
```

## Account social

- **Instagram**: [@trailshareapp](https://www.instagram.com/trailshareapp)
- **TikTok**: [@trailshareapp](https://www.tiktok.com/@trailshareapp)
- **Facebook**: [@trailshareapp](https://www.facebook.com/trailshareapp) *(URL da personalizzare, vedi task account setup)*

## Founder

Massimiliano (Max). **Anonimo in camera di default**. Voice-over OK. Nome usabile solo se esplicitamente richiesto dal founder per un singolo contenuto.

## Editorial calendar corrente

Vedi [calendar.md](calendar.md). Mese corrente determina il tema settimanale.
