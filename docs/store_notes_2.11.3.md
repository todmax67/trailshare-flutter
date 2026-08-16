# Note release 2.11.3+128 per gli store

Una cosa sola da comunicare, e non è una funzione nuova: **quando la
registrazione si ferma, ora la traccia lo dice.**

## La cosa da comunicare bene

Il difetto non era la retta — quella è la conseguenza. Era che la retta veniva
disegnata **identica al sentiero percorso**, quindi chi guardava non aveva modo
di distinguere un tratto camminato da un tratto in cui l'app era congelata.

Un utente l'ha segnalato il 2026-08-16 con le parole giuste: *"ha perso il GPS,
c'è una linea retta"*. Non aveva perso il GPS — il sistema aveva sospeso l'app —
ma il punto è che nessuno gliel'aveva detto, né durante né dopo.

Non si può impedire del tutto: quando il sistema congela il processo non gira
una riga di codice nostro, e infatti non ci riesce nemmeno la concorrenza. Nel
gruppo Komoot Italia il rimedio che gira è **portarsi un power bank e tenere lo
schermo acceso**. Si può però smettere di fingere che non sia successo.

## "Novità in questa versione"

### IT — Play Console (498 / 500)

```
Se il telefono sospende la registrazione, la traccia si ricongiunge con una linea dritta. Ora è tratteggiata, e la scheda dice quante volte è successo e per quanto: nel totale conta solo la retta, quasi certamente meno della strada vera.

Un tratto dritto sospetto su una traccia vecchia lo dichiari tu: solo tu sai dove sei passato.

Il GPX si spezza dove la registrazione si è interrotta: niente rette spacciate per percorso.

La Dashboard salute dice quando le manca il permesso, invece di zeri.
```

### IT — App Store Connect (max 4000)

```
QUANDO LA REGISTRAZIONE SI FERMA, TE LO DICIAMO
Se il telefono sospende l'app — succede, e non solo alla nostra — la traccia si ricongiunge con una linea dritta fra il punto dove ci siamo fermati e quello dove abbiamo ripreso.

Quella linea ora è tratteggiata e più chiara, così non si confonde con il sentiero percorso. E sopra le statistiche compare una riga che dice quante volte è successo e per quanti minuti in tutto.

NEL TOTALE QUEL TRATTO CONTA SOLO IN LINEA RETTA
La strada vera di quei minuti era quasi certamente più lunga della linea che la sostituisce. Preferiamo dirtelo noi piuttosto che fartelo scoprire guardando la mappa a casa.

I TRATTI DRITTI DELLE TRACCE VECCHIE LI DICHIARI TU
Se una traccia salvata prima di questa versione ha un tratto dritto sospetto — tanti minuti e tanti chilometri fra due punti — te lo segnaliamo e puoi dichiararlo: diventa tratteggiato, la scheda lo dice, il GPX si spezza lì. Puoi sempre tornare indietro, e può farlo solo chi la traccia l'ha registrata.

IL GPX SI SPEZZA DOVE SI È INTERROTTO
Esportando la traccia, l'interruzione diventa uno stacco fra due segmenti: Garmin, Strava e chiunque altro la legga vedranno un buco invece di una linea retta percorsa. È il modo che il formato GPX prevede da sempre per dirlo.

LA DASHBOARD SALUTE NON MENTE PIÙ
Quando le manca il permesso lo dice, invece di mostrare zeri che sembrano storico perso.

E NON DOVRAI PIÙ RIFARE L'ACCESSO
Corretto un difetto per cui alcuni si ritrovavano scollegati a ogni apertura. Chi ci era dentro viene riparato al primo avvio.
```

### EN — App Store Connect

```
WHEN THE RECORDING STOPS, WE TELL YOU
If the phone suspends the app — it happens, and not only to ours — the track closes the hole with a straight line between where we stopped and where we picked up again.

That line is now dashed and lighter, so it cannot be mistaken for the trail you walked. And above the stats there is a line saying how many times it happened, and for how many minutes in total.

THAT STRETCH COUNTS ONLY AS A STRAIGHT LINE
The real path of those minutes was almost certainly longer than the line standing in for it. We would rather tell you than let you work it out from the map once you are home.

STRAIGHT STRETCHES ON OLDER TRACKS ARE YOURS TO DECLARE
If a track saved before this version has a suspicious straight stretch — many minutes and many kilometres between two points — we point it out and you can declare it: it turns dashed, the page says so, the GPX breaks there. You can always undo it, and only whoever recorded the track can do it.

THE GPX BREAKS WHERE THE RECORDING DID
Export the track and the interruption becomes a break between two segments: Garmin, Strava and anything else reading it will see a gap instead of a straight line you never rode. It is how the GPX format has always said this.

THE HEALTH DASHBOARD NO LONGER LIES
When it is missing the permission it says so, instead of showing zeros that look like lost history.

AND NO MORE SIGNING IN AGAIN
Fixed a fault that left some people signed out every time they opened the app. Anyone affected is repaired on the next launch.
```

## Cosa NON promettere

- **Non abbiamo risolto le interruzioni.** Quando il sistema sospende il
  processo non c'è niente da fare: si può solo accorgersene e dirlo. Promettere
  registrazioni senza buchi sarebbe una bugia verificabile alla prima uscita.
- **Le tracce già salvate non mostreranno la riga.** Il campo non esisteva
  quando sono state scritte, e per quelle un elenco vuoto vuol dire "non lo
  sappiamo", non "nessuna interruzione".
- Niente percorso ricostruito: la linea tratteggiata **non è un'ipotesi di dove
  sei passato**, è la dichiarazione che non lo sappiamo.

## Verifiche prima di pubblicare

- Registrare una traccia e controllare che senza interruzioni **non compaia
  niente**: la riga deve apparire solo quando serve.
- Esportare un GPX di una traccia senza buchi e verificare che sia identico a
  prima (un solo `<trkseg>`).
- iOS: e' la prima build che porta il banner dei permessi salute, che su
  Android c'e' dalla 2.11.2. La correzione del logout e' Android-only.

## Dopo la pubblicazione

- Gli **screenshot dello store sono ancora quelli del Peak Finder vecchio**, a
  linea piatta. Restano il primo lavoro da fare: le parole fanno trovare
  l'app, gli screenshot decidono se la installano.
