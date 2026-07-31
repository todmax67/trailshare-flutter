# Note release 2.9.5+114 per gli store

Due correzioni, entrambe emerse da Crashlytics nelle ore successive alla
pubblicazione della 2.9.4.

## 1. I font non si scaricano più

Fino alla 2.9.4 la tipografia arrivava da `fonts.gstatic.com` alla prima
apertura, tramite il pacchetto `google_fonts`. Su un'app da montagna è un
difetto che si vede subito: nei report Crashlytics della 2.9.4, pubblicata
poche ore prima, il fallimento è comparso il giorno stesso.

Chi installa a casa e apre l'app in rifugio senza rete vedeva l'interfaccia
con il font di sistema invece del nostro. Non era un crash — un non-fatal — ma
è esattamente il caso d'uso che l'app pubblicizza.

## Play Console / App Store Connect — "Novità in questa versione" (IT)

```
I caratteri dell'app ora sono inclusi nell'installazione invece di essere scaricati alla prima apertura. Se apri TrailShare senza rete — in rifugio, in quota, in aereo — l'interfaccia si vede come deve.

Corretto un blocco della mappa che poteva capitare aprendo una traccia registrata senza spostarsi, o una tappa di tour senza tracciato.
```

## EN

```
The app's fonts now ship with the install instead of being downloaded on first launch. If you open TrailShare with no connection — in a mountain hut, at altitude, on a plane — the interface looks the way it should.

Fixed a map freeze that could happen when opening a track recorded without moving, or a tour stage with no route.
```

## Cosa contiene, per chi rilegge fra sei mesi

- Outfit impacchettato in `assets/fonts/` come **istanze statiche** a 400, 600
  e 700, estratte dal font variabile con `fonttools varLib.instancer`. Col solo
  variabile Flutter avrebbe simulato il grassetto invece di usare l'asse dei
  pesi, e su un font da display si nota.
- `GoogleFonts.outfit(...)` sostituito da `TextStyle(fontFamily: 'Outfit')` in
  `app_themes.dart` (con l'helper `_outfit`) e `stat_number.dart`.
- **Dipendenza `google_fonts` rimossa.** Non serviva più a nessuno: il
  generatore PDF usa `PdfGoogleFonts` di `printing`, che è un'altra cosa.
- Licenza SIL Open Font impacchettata e registrata in `LicenseRegistry`:
  compare in Impostazioni → Licenze open source.

## L'effetto collaterale che conta

Non è solo un fix estetico. Era **una connessione a Google che nessuna
informativa dichiarava**: senza cache, ogni avvio mandava l'IP dell'utente al
CDN dei font. Non era nell'informativa, non era fra i servizi di terze parti,
non era nei due questionari privacy compilati lo stesso giorno.

Impacchettando i font il buco si chiude alla radice, e non c'è niente da
aggiungere alle dichiarazioni.

È il tipo di cosa che sfugge a un audit perché non la scrive nessuno nel
codice: la porta dentro un pacchetto.

## 2. La mappa non va più in crash su geometrie degeneri

`_TileLayerState._clampToNativeZoom` → *Unsupported operation: Infinity or
NaN*. Un arresto anomalo vero, 19 eventi da un singolo utente, più due
non-fatal con la stessa causa.

flutter_map calcola lo zoom che serve a far entrare il riquadro nello schermo.
Se il riquadro ha **dimensione zero** — tutti i punti alla stessa coordinata, o
un punto solo — quel calcolo tende a infinito e il primo `.round()` a valle
solleva.

I controlli sparsi per l'app (`isNotEmpty`, `length >= 2`) non bastavano: dieci
punti identici li superano entrambi. Non è un caso di laboratorio — una
registrazione avviata e chiusa senza muoversi, un import con un punto ripetuto,
o una geometria di catalogo vuota lo producono.

Perché è comparso ora: il fix sulle tappe dei tour della 2.9.4 ha fatto
**disegnare mappe a tappe che prima mostravano "dati non disponibili"**. Non ha
introdotto matematica sbagliata, ha attivato un percorso di codice che prima
era inerte, e lì il difetto era già in agguato.

Ora tutti gli otto punti dell'app che inquadrano una mappa passano da
`safeBounds` (`lib/core/utils/map_bounds.dart`), che scarta le coordinate non
finite o fuori dai limiti terrestri e **allarga** i riquadri degeneri invece di
rifiutarli: per una traccia di un punto solo la cosa utile è vedere la mappa
centrata lì, non ritrovarsi sull'inquadratura di default. Nove test coprono i
casi che crashavano.

## Verifica

Emulatore Android, installazione pulita, **modalità aereo attiva**: titoli in
Outfit, zero errori di caricamento font nel log del processo. Le uniche
eccezioni sono di Firebase Installations, attese senza rete.
