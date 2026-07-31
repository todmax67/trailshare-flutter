# Note release 2.9.4+113 per gli store

Due cose per chi usa l'app — le tappe dei tour complete e le durate lunghe
leggibili — e una che si vede al primo avvio: la richiesta di consenso alle
statistiche d'uso.

Il grosso del lavoro di questa versione è invisibile: la strumentazione che
misura da dove arrivano gli utenti e quanti riescono a usare l'app. Non cambia
niente per chi la usa, ma è la prima volta che si può rispondere alla domanda
"questo canale porta persone vere?" con un numero invece che a intuito. Vedi
[growth_engine.md](growth_engine.md).

## Play Console / App Store Connect — "Novità in questa versione" (IT)

```
Tour multi-giorno: le tappe prese dal catalogo ora arrivano complete di quote, durata stimata e grafico altimetrico, come quelle disegnate a mano.

Le durate oltre le otto ore si leggono in giorni e ore invece che in ore secche: "1 g 4 h" invece di "28 h".

Quando la quota di un punto non è nota, ora resta non nota: prima diventava zero e falsava il dislivello del percorso.

Al primo avvio ti chiediamo se possiamo raccogliere statistiche anonime su quali funzioni vengono usate. Puoi dire di no — l'app funziona identica — e cambiare idea quando vuoi da Impostazioni → Privacy. L'informativa è stata aggiornata di conseguenza.
```

## EN

```
Multi-day tours: stages taken from the catalogue now come with elevation, estimated duration and an elevation profile, just like hand-drawn ones.

Durations over eight hours now read in days and hours instead of raw hours: "1 d 4 h" instead of "28 h".

When a point's elevation is unknown it now stays unknown: it used to become zero, which distorted the route's total elevation gain.

On first launch we ask whether we may collect anonymous statistics about which features get used. You can say no — the app works exactly the same — and change your mind any time in Settings → Privacy. The privacy policy has been updated accordingly.
```

## Prima di caricare

Questa versione introduce raccolta dati che prima non c'era. **Le dichiarazioni
privacy nelle due console vanno aggiornate prima della pubblicazione**, non
dopo: le tabelle da compilare sono in [store_privacy.md](store_privacy.md).

Va anche pubblicata la privacy policy aggiornata sul sito — il deploy web è
separato da quello mobile.

Nessun prompt ATT su iOS: l'ID pubblicitario è stato rimosso dal manifest, e
alla domanda sul tracking si risponde "No" in entrambi i questionari.

## Cosa contiene, per chi rilegge fra sei mesi

**Visibile agli utenti**
- Schermata di consenso alle statistiche, dopo l'onboarding. Compare anche agli
  utenti già esistenti, che non erano mai stati interpellati
- Due interruttori nuovi in Impostazioni → Privacy: statistiche d'uso e misura
  del percorso utente
- Nuova sezione nell'informativa privacy, in app e sul sito
- Tour: tappe dal catalogo con quote, durata e altimetria (`c93a318`)
- Durate lunghe in giorni (`cbf5c0f`)
- Quota mancante non più forzata a zero (`934f20e`)

**Invisibile ma è il grosso**
- `GrowthAnalyticsService`: funnel a dieci tappe, doppio sink Analytics +
  `growth_users`, attribuzione first-touch da deep link e install referrer
- Cloud Function `growthDaily` nel repo del manager, che aggrega e riporta su
  Telegram alle 7:30
- Rimozione dell'ID pubblicitario che Firebase Analytics si portava dietro

**Contenuti, senza impatto sulla build**
- Tracciati e materiali dei tour Tour du Mont Blanc e Garda Brenta
- Script di manutenzione del catalogo (quote da DEM locale, verso, difficoltà)
- Attribuzione foto che rimanda al file originale su Wikimedia Commons
