---
canale: instagram
formato: reel
tema: Sicurezza / Lifeline
settimana: 2026-W18
stato: draft
voce: founder
aspect_ratio: 9:16
asset_paths:
  - social_lab/assets/video_demo/la-sicurezza.mov
note_bridge: |
  Video composto in claude.ai/design (Animated video skill) basato sul TikTok
  storytelling_incidente.md della stessa settimana. Stesso file usato per:
  - IG Reel (questo draft, via bridge)
  - TikTok (caricato a mano via app TikTok dal founder)
companion_draft: social_lab/drafts/2026-W18/tiktok_storytelling_incidente.md
---

## Caption

Un anno fa nessuno sapeva dov'ero.

Ero andato in montagna da solo. Mi sono fatto male a un ginocchio a tre ore di cammino dall'auto. Niente campo per chiamare, niente forze per tornare indietro. L'unica cosa che continuava era la traccia che stavo registrando sul telefono.

Da li e' nata Lifeline. L'idea e' semplice: mentre registri un'attivita', l'app controlla se ti stai muovendo. Se ti fermi troppo a lungo, parte un alert sonoro che ti chiede "tutto bene?". Se non rispondi, manda un SMS automatico ai tuoi contatti emergenza con il link della tua traccia live.

Non sostituisce il soccorso alpino. Lo affianca. Ti da una rete in piu' quando sei solo dove non c'e nessuno a controllare.

La configurazione e' tre contatti, tre numeri, due minuti dalle impostazioni dell'app. Fine.

TrailShare e' gratis su iOS e Android. Lifeline e' una delle ragioni per cui l'abbiamo costruita. Link store in bio.

## Hashtag

```
#trailshare #trailshareapp
#sicurezzainmontagna #lifeline #sosmontagna
#montagnasicura #soccorsoalpino
#escursionismo #trailrunning
#hiking #trekking
#alpi #appennini #montagnaitaliana
#cai #outdooritalia
```

## Visual direction

Video gia' prodotto in claude.ai/design (Animated video skill), 9:16, ~35-45s, voice-over founder anonimo. File: `social_lab/assets/video_demo/la-sicurezza.mov`. Niente da girare: caricalo cosi com'e' tramite il bridge.

## CTA

Chiusura caption (gia' integrata sopra): "TrailShare e' gratis su iOS e Android. Link store in bio." Nel primo commento aggiungi il link diretto store + invito breve alla configurazione Lifeline (3 contatti, 2 minuti). Rispondi ai commenti "come funziona?" con un rimando al reel tutorial brand in arrivo (W22).

## Note per il founder

- **Pubblicazione via bridge**: cambia `stato: draft` → `stato: ready` in questo file. Il watcher pusha il post a Firestore entro 1.5s con asset upload automatico del .mov. Verifica che il link in bio punti alla landing store aggiornata.
- **Cross-post TikTok (manuale, non bridge)**: carica lo stesso file `la-sicurezza.mov` via app TikTok. Usa la caption breve del draft TikTok (`tiktok_storytelling_incidente.md`) — 3 righe asciutte, niente la versione lunga IG. Hashtag dal draft TikTok (14 hashtag). NON pubblicarlo via bridge per evitare doppioni.
- **Facebook — NON oggi**: oggi 12:10 c'e' gia' schedulato il post testo lungo Lifeline su FB. Pubblicare anche il video oggi cannibalizza. Suggerimento: ripubblica come video FB **giovedi 14 maggio** (intorno alle 18:30-19:00), come rinforzo visuale del post testo. Caption FB piu' breve della IG, 80-120 parole, niente hashtag pesanti (3-4 max).
- **Window di pubblicazione IG ottimale**: lunedi sera 19-21 o martedi mattina 8-10. Storytelling lungo su IG funziona se la prima riga e' un hook — qui ce l'hai ("Un anno fa nessuno sapeva dov'ero.").
- **Monitoraggio**: a 24h e a 72h annota reach / saves / shares / commenti per il file di archiviazione in `published/`. I "saves" sono la metrica che conta per contenuti tipo Lifeline (utenti che vogliono tornare a configurare).
