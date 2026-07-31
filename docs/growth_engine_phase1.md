# Motore di crescita — Fase 1: l'analista

**Proposta**, non ancora implementata. Scritta il 2026-07-31 dopo aver
verificato che ogni fonte citata esista e risponda davvero.

## Il rischio da evitare, prima di tutto

Un "analista AI" che genera brief di mercato dalle proprie convinzioni è
peggio di niente: produce affermazioni plausibili e sicure di sé che
indirizzano decisioni vere. "Il mercato outdoor si sta spostando verso X" è
una frase che un modello sa scrivere benissimo senza sapere nulla.

Quindi il vincolo di progetto è uno solo, e viene prima dell'architettura:

> **Ogni riga del brief deve risalire a un dato che è stato effettivamente
> scaricato o misurato.** Se una fonte non risponde, il brief lo dice e non
> riempie il buco.

Corollario: **"non è cambiato niente" è un brief valido.** Un analista che
trova sempre qualcosa di interessante è un analista che se lo inventa.

Il ruolo di Claude qui non è sapere cose. È leggere i numeri raccolti,
confrontarli con la settimana prima, e dire cosa merita attenzione.

## Cosa produce

Un documento settimanale, il lunedì mattina, fatto di quattro parti:

1. **Posizionamento negli store** — dove compare TrailShare cercando le
   keyword che contano, e come si è mosso rispetto a sette giorni fa
2. **Mosse dei competitor** — chi ha rilasciato cosa, con le note di rilascio
   vere, e come si muovono i loro voti
3. **Voce degli utenti** — le recensioni nuove, di TrailShare e dei competitor
4. **I nostri numeri** — il funnel da `growth_daily`, quando ci saranno

E si chiude con **1-3 esperimenti candidati**, non con "insight". Un brief su
cui nessuno agisce è lavoro sprecato: la Fase 2 li prende da lì.

## Le fonti, verificate il 2026-07-31

| Fonte | Cosa dà | Stato |
|---|---|---|
| iTunes Search API | Risultati di ricerca ordinati per keyword, storefront IT | ✅ verificata |
| iTunes Lookup API | Versione, data di rilascio, note, voti — nostri e dei competitor | ✅ verificata |
| RSS recensioni Apple | Testo delle recensioni per app id | da verificare |
| `growth_daily` | Il nostro funnel per canale | ✅ esiste (dati dal rilascio 2.9.4) |
| Reddit JSON | Menzioni nelle community | da verificare, segnale probabilmente sottile in IT |

Gratis, senza chiavi, senza scraping.

### Il baseline, già misurato

Non un esempio ipotetico: la posizione reale di TrailShare nell'App Store
italiano, il 2026-07-31.

| Keyword | Posizione |
|---|---|
| **rifugi** | **11** |
| **wikiloc** | **8** |
| sentieri | 47 |
| trekking | fuori dai 100 |
| escursionismo | fuori dai 100 |
| mappe offline | fuori dai 100 |
| trail running | fuori dai 100 |
| mtb | fuori dai 100 |
| gps outdoor | fuori dai 100 |
| komoot | fuori dai 100 |

Tre cose che questo dice già oggi, e che nessuno aveva guardato:

- **`rifugi` alla 11 è l'asset più vicino alla superficie.** È anche il
  verticale dove il prodotto ha contenuto vero (18.500 POI) e dove passa il
  ground game. È la nicchia da presidiare, non `trekking`.
- **Il trucco delle keyword competitor funziona solo a metà**: `wikiloc`
  porta all'ottava posizione, `komoot` da nessuna parte.
- **Il nome non compra il posizionamento.** L'app si chiama "TrailShare —
  Sentieri GPS" e su `sentieri` è 47ª.

## Architettura

Nel repo `trailshare-ai-manager`, accanto a `growthDaily`:

```
functions/src/services/market/
  ├── appStore.ts      collettore: ranking, versioni, voti, recensioni
  ├── community.ts     collettore: menzioni Reddit
  └── brief.ts         confronto con la settimana prima + stesura via Claude

functions/src/scheduled/
  └── weeklyMarketBrief.ts    lunedì 7:00
```

Ogni collettore restituisce dati strutturati **oppure fallisce
esplicitamente**: nessun valore inventato per riempire un campo.

Le osservazioni grezze finiscono in `market_observations/{data}`, il brief in
`market_briefs/{data}`. La separazione serve a una cosa sola ma importante:
**il brief è un diff, non una fotografia**, e senza lo storico grezzo non si
può ricalcolare né correggere a posteriori.

Consegna su Telegram, come gli altri due report.

La prima settimana il brief sarà povero: non c'è un "prima" con cui
confrontare. È previsto, e va detto nel brief stesso invece di mascherarlo.

## Cosa NON entra in v1, e perché

- **Google Play**: nessuna API pubblica per ranking e recensioni. Servirebbe
  scraping, fragile e contro i termini. Metà del quadro manca, e va detto.
- **Google Trends**: nessuna API ufficiale. Le librerie non ufficiali si
  rompono senza preavviso e restituiscono silenziosamente dati vuoti — il
  modo peggiore di sbagliare.
- **Gruppi Facebook**: non accessibili senza login. Fuori portata.
- **Stime di volume di ricerca**: i dati affidabili sono a pagamento. Senza,
  qualunque numero sarebbe inventato.

## Costo

Una chiamata a Claude a settimana su poche migliaia di token: pochi centesimi
al mese. Le API Apple sono gratuite. Firebase, rumore di fondo.

Il costo vero sono i minuti che passi a leggere il brief. Se non lo leggi,
va spento.

## Le decisioni che chiedo

1. **La lista delle keyword.** Quelle qui sopra sono le mie, dedotte da
   `docs/store_notes` e dalla strategia di maggio. Vanno riviste da te: sono
   la cosa che il brief misura ogni settimana, e cambiarle spesso rende la
   serie storica inconfrontabile.
2. **I competitor da seguire.** Proporrei Komoot, Wikiloc, AllTrails,
   Outdooractive, PeakVisor e Terra Map — i primi cinque escono davanti a noi
   su `sentieri`, e PeakVisor presidia il riconoscimento cime.
3. **Reddit sì o no.** In Italia l'outdoor su Reddit è sottile: il rischio è
   un collettore che ogni settimana restituisce zero risultati e occupa
   spazio nel brief. Si può aggiungere dopo.
4. **Il giorno.** Lunedì 7:00 mette il brief prima della pianificazione della
   settimana. Se preferisci il venerdì per decidere con calma nel weekend, si
   sposta.
