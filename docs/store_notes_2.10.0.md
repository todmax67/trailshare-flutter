# Note release 2.10.0+122 per gli store

Sette versioni di sviluppo condensate in una pubblicazione. Il filo che le lega
non è una lista di funzioni nuove: è che **diversi numeri che l'app mostrava non
misuravano quello che dicevano di misurare**, e ora lo misurano.

Da qui la scelta del minore invece dell'ennesima patch: per chi usa l'app da
prima, alcune cifre cambieranno — e la più visibile calerà parecchio.

## La cosa da comunicare bene

"In movimento" fino alla 2.9.5 conteneva **la durata totale**, soste comprese:
non era una stima imprecisa, era un campo copiato. Ora conta il tempo in cui ci
si stava davvero muovendo.

Su un'escursione con soste può essere **ore in meno**. Chi non lo sa lo legge
come un regresso, quindi va detto per primo e senza girarci intorno.

Riferimento misurato: giro del 2026-08-06, 6h14 di durata. Prima l'app diceva
6h14 di movimento, l'orologio 4h18. Ora l'app dice 4h00.

## "Novità in questa versione"

### IT — Play Console (494)

```
"In movimento" ora è una misura vera: prima riportava la durata totale, soste comprese. Sarà più basso di prima e non è un errore.

Le tracce seguono i tornanti invece di tagliarli: percorso più fedele, distanza più vicina al vero.

Se il telefono sospende la registrazione ora te lo dice, invece di lasciartelo scoprire a casa.

Orologi Garmin: tracce quattro volte più dettagliate, con gli orari veri. Aggiorna anche l'app sull'orologio.

Corretta una chiusura improvvisa del mountain finder.
```

### IT — App Store Connect (842)

```
"In movimento" ora è una misura vera. Fino alla scorsa versione quel campo riportava la durata totale, soste comprese: sarà più basso di prima, e non è un errore — è il numero che prima non c'era.

Le tracce seguono i tornanti invece di tagliarli. La riduzione dei punti ora conserva quelli dove il sentiero curva: il percorso che vedi, esporti e condividi è molto più fedele, e la distanza più vicina al vero.

Se il telefono sospende la registrazione ora te lo dice mentre cammini, invece di lasciartelo scoprire a casa davanti a un buco nella mappa.

Orologi Garmin: tracce quattro volte più dettagliate, con gli orari veri dell'attività e il tempo in movimento calcolato davvero. Richiede l'aggiornamento anche dell'app sull'orologio, dallo store Connect IQ.

Corretta una chiusura improvvisa del mountain finder, e migliorato il volo 3D.
```

### EN — Play Console (475)

```
"Moving time" is now a real measurement: it used to show total duration, breaks included. It will be lower than before, and that is not a bug.

Tracks follow switchbacks instead of cutting them: truer shape, distance closer to reality.

If your phone suspends the recording, the app now tells you, instead of letting you find out at home.

Garmin watches: four times more detailed tracks, with real timestamps. Update the watch app too.

Fixed a crash in the mountain finder.
```

### EN — App Store Connect (805)

```
"Moving time" is now a real measurement. Until the last version that field showed total duration, breaks included: it will be lower than before, and that is not a bug — it is the number that was missing.

Tracks follow switchbacks instead of cutting them. Point reduction now keeps the points where the trail turns: the route you see, export and share is far truer, and the distance closer to reality.

If your phone suspends the recording, the app now tells you while you walk, instead of letting you find out at home in front of a gap in the map.

Garmin watches: four times more detailed tracks, with the activity's real timestamps and moving time actually computed. Requires updating the watch app too, from the Connect IQ store.

Fixed a crash in the mountain finder, and improved the 3D fly-through.
```

## 1. "In movimento" misura il movimento

Era `movingTime = duration`, con accanto un commento che prometteva di
migliorarlo. Ora la velocità si giudica su una finestra di 15 secondi e non sul
singolo campione: fra due punti a pochi metri l'errore GPS è più grande dello
spostamento, e la decisione diventerebbe casuale — era così che metà della
camminata vera finiva archiviata come sosta.

## 2. Le tracce non tagliano più gli angoli

La riduzione dei punti prendeva un punto ogni N, trattando un tornante e un
rettilineo allo stesso modo. Ora è per forma (Douglas-Peucker): misurato su una
traccia reale, a parità di punti conservati lo scarto di lunghezza passa da
-5,4% a -0,3%. Il tetto per traccia sale da 1000 a 3000 punti.

## 3. La registrazione avvisa quando si interrompe

Il 3 agosto, su un giro di 6h15, il sistema ha sospeso l'app per 37 minuti senza
che l'utente lo sapesse. Non era il GPS: l'accuratezza era 3 metri prima e 3
metri dopo. Ora un tick periodico che si risveglia con troppi minuti di orologio
alle spalle riconosce il congelamento e lo dichiara.

## 4. Orologi Garmin: orari veri e quattro volte i punti

L'orologio non mandava i tempi dei punti, e il server li ricostruiva
distribuendoli a intervalli uguali — cancellando ogni sosta e rendendo il tempo
in movimento incalcolabile. Ora li manda, in un formato compatto che a parità di
byte trasporta il doppio dei punti.

**Richiede l'aggiornamento dell'app sull'orologio**, che si scarica da Connect
IQ. Il server accetta comunque il formato vecchio.

## 5. Mountain finder: niente più chiusure

Uscire dall'inquadratura delle cime mentre la fotocamera si stava ancora
accendendo chiudeva l'app. Un crash fatale, arrivato dai rapporti di Crashlytics.

## 6. Volo 3D

Il segnaposto restava in quadro fino a circa 1000 metri di dislivello, poi
usciva dallo schermo. E il volo partiva prima che il rilievo fosse caricato, coi
primi secondi di montagne appiattite. Entrambi corretti.

## Dopo la pubblicazione

- ~~Caricare i **dSYM iOS** su Crashlytics~~ — fatto il 2026-08-09 per la
  2.10.0+122 (UUID `153C9223-…-C092B30945C7`), **e automatizzato**: da ora una
  build phase del target Runner li carica a fine compilazione, quindi dalla
  prossima release il passaggio non esiste più.

  Il percorso di `upload-symbols` non è quello delle guide: qui Crashlytics
  arriva da Swift Package Manager, non da CocoaPods, e sta sotto
  `build/ios/SourcePackages/checkouts/`.
- L'app da polso su Connect IQ va aggiornata **prima o insieme**, altrimenti le
  tracce continuano ad arrivare nel formato vecchio (che resta accettato, ma
  senza i tempi veri).
