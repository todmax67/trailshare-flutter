# social_lab

Workspace del social media manager di TrailShare. Contiene briefing del brand, editorial calendar, asset e draft dei post.

## Come funziona

1. Riempi `assets/` con le tue foto/video grezzi, organizzati per tema
2. Invoca il sub-agente **social-manager** con un comando tipo:
   - *"prepara post settimana 17"*
   - *"genera 3 varianti reel sul tema Lifeline usando gli asset in video_demo/lifeline"*
   - *"analizza gli asset in paesaggi/dolomiti e suggerisci come usarli"*
3. L'agente produce draft in `drafts/YYYY-WW/<slug>.md`
4. Rivedi i draft, copia-incolla su IG/TikTok/FB (o usa un tool di scheduling)
5. Quando pubblichi, chiedi all'agente *"archivia draft <nome> come pubblicato"*
6. Dopo qualche giorno, aggiungi le metriche reali nel file pubblicato
7. Fine mese: *"analizza performance ultimo mese"* → retrospettiva

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
