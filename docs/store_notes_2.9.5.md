# Note release 2.9.5+114 per gli store

Sette interventi. **Nessuno scelto a tavolino**: sei arrivano da segnali reali —
Crashlytics, una segnalazione utente, il primo resoconto di crescita — e uno dal
confronto coi competitor.

È la prima release costruita a partire da quello che l'app dice di sé, invece
che da una lista di cose da fare.

## Play Console / App Store Connect — "Novità in questa versione" (IT)

```
I caratteri dell'app ora sono inclusi nell'installazione invece di essere scaricati alla prima apertura: se apri TrailShare senza rete — in rifugio, in quota, in aereo — l'interfaccia si vede come deve.

Un rifugio che ha una scheda TrailShare non compare più due volte sulla mappa.

Corretti tre blocchi: aprendo una traccia registrata senza spostarsi, aggiornando una lista mentre si esce dalla pagina, e con una foto danneggiata.

Dopo qualche uscita ti chiediamo una volta se ti va di lasciare una recensione. Puoi ignorarla: non torna più per mesi.
```

## EN

```
The app's fonts now ship with the install instead of being downloaded on first launch: if you open TrailShare with no connection — in a mountain hut, at altitude, on a plane — the interface looks the way it should.

A mountain hut with a TrailShare listing no longer shows up twice on the map.

Fixed three freezes: opening a track recorded without moving, refreshing a list while leaving the page, and loading a damaged photo.

After a few outings we'll ask once whether you'd like to leave a review. Feel free to ignore it — it won't come back for months.
```

---

## 1. I font non si scaricano più

Fino alla 2.9.4 la tipografia arrivava da `fonts.gstatic.com` alla prima
apertura, via `google_fonts`. Su un'app da montagna il difetto si vede subito:
chi installa a casa e apre in rifugio senza rete vedeva il font di sistema.

Outfit è ora in `assets/fonts/` come **istanze statiche** a 400, 600 e 700,
estratte dal variabile con `fonttools varLib.instancer` — col solo variabile
Flutter avrebbe simulato il grassetto invece di usare l'asse dei pesi.
Dipendenza `google_fonts` rimossa, licenza SIL impacchettata e registrata in
`LicenseRegistry`.

**L'effetto che conta più del fix**: era una connessione a Google che nessuna
informativa dichiarava — senza cache, ogni avvio mandava l'IP dell'utente al CDN
dei font. Impacchettando, il buco si chiude alla radice.

## 2. Un rifugio, un marker

Da una segnalazione utente sul Rifugio Jean-Antoine Carrel, marcata
"Duplicato". Non lo era fra schede: lo era **fra sorgenti**. Lo stesso rifugio
esiste sia in `businesses` sia nel dataset OSM bundlato, perché entrambi
derivano da OpenStreetMap.

Misurato: **2.949 schede su 6.496 (45,4%)** hanno un POI con nome identico a
meno di 60 metri. Le due sorgenti convivono in un punto solo — la mappa traccia
a schermo intero — e lì ora vince la scheda, che ha foto, orari e listino.

Confronto sul nome **esatto**: i 93 POI vicini con nome diverso sono cose
diverse che stanno vicine, e nasconderli sarebbe l'errore più costoso.

## 3. Niente zoom infinito sulle geometrie degeneri

`_TileLayerState._clampToNativeZoom` → *Unsupported operation: Infinity or NaN*.
Con un riquadro di dimensione zero — tutti i punti alla stessa coordinata — il
calcolo dello zoom tende a infinito. I controlli esistenti (`isNotEmpty`,
`length >= 2`) non bastavano: dieci punti identici li superano entrambi.

Tutti gli otto punti che inquadrano una mappa passano da `safeBounds`, che
**allarga** i riquadri degeneri invece di rifiutarli.

## 4. Il pull-to-refresh non crasha a pagina chiusa

Lo stack completo diceva tutto: `State.setState` → `_element!` null perché lo
State era già smontato. Si tira per aggiornare, si esce, la callback arriva a
widget morto. Guardati i 29 metodi raggiungibili da un `onRefresh` — non tutti
gli 84 con quello schema: una `setState` chiamata da `initState` è al sicuro
per costruzione.

## 5. Le immagini corrotte mostrano un ripiego

`dart:ui .instantiateImageCodecWithSize` → *Invalid image data*. Cinque punti su
ventidue erano scoperti; il più sospetto è l'`Image.memory` dell'AR, che compone
byte in memoria.

## 6. La recensione, chiesta quando ha senso

TrailShare ha 1 recensione. Komoot 30.748, Wikiloc 21.202, PeakVisor 15.497. È
il divario più largo coi competitor e l'unico che si chiude senza budget.

Il prompt c'era ma solo in Impostazioni, dove nessuno va. Ora arriva dopo il
dialog di fine registrazione — traccia salva, punti guadagnati — e mai prima
della terza traccia, mai nei primi sette giorni, mai più di tre volte, e **mai
se il salvataggio non è confermato dal server**.

## 7. Quanto viene usata, non solo se è stata provata

Il funnel registrava la prima volta di ogni cosa e poi taceva. Ora ogni
salvataggio incrementa un contatore e aggiorna `lastTrackSavedAt`, che per
un'app di registrazione è il segnale di vita vero: aprire l'app per guardare una
mappa non è come uscire a camminare.

Le tracce private contano quanto le pubbliche.

## Prima di caricare

- [ ] Play Console: eliminazione dati da "non supportata" a **supportata**
      (`deleteMyAccount` cancella tutto), più i passaggi per tipo — vedi
      [store_privacy.md](store_privacy.md)
- [ ] App Store Connect: aggiungere `Informazioni di contatto → Nome`, che su
      Play è già dichiarato

## Verifica

`flutter analyze` pulito. Test: 9 su `safeBounds`, 8 su `dedupOsmPois`. Font
provati su emulatore con installazione pulita e **modalità aereo attiva**: zero
errori di caricamento nel log del processo.
