# Note release 2.11.4+133 per gli store

> **Si compila la 133.** La 132 e' stata costruita e verificata, poi la
> revisione post-commit ha trovato che un solo buco poteva coprire due archi:
> i chilometri ricostruiti si sommavano due volte e il disegnatore riceveva
> gli estremi sbagliati. La 132 non va promossa.

La 2.11.3 diceva «non sappiamo cosa c'è in mezzo». Questa aggiunge l'unica
persona che lo sa: **chi è passato di lì**.

## La cosa da comunicare bene

È facile raccontarla male, e il modo sbagliato è «TrailShare ricostruisce le
tracce interrotte». Non le ricostruisce nessun algoritmo: le ridisegna il
proprietario, e il risultato **resta tratteggiato** proprio perché non è una
misura.

Il valore sta tutto lì. Un'app che indovina il percorso mancante e lo disegna
come tutto il resto sta mentendo con più eleganza di prima. Un'app che ti fa
dichiarare dove sei passato, e poi tiene il tuo disegno visibilmente distinto
da ciò che il GPS ha registrato, dice due verità insieme: *questa è la strada
che hai fatto* e *questa non l'abbiamo misurata noi*.

Tre livelli di certezza, tre disegni diversi:

| disegno | significa |
|---|---|
| linea piena colorata | misurato dal GPS |
| tratteggiato lungo un sentiero | dichiarato da chi c'era |
| tratteggiato dritto | non lo sappiamo |

## "Novità in questa versione"

### IT — Play Console (max 500)

```
Dove la registrazione si era fermata, ora puoi disegnare tu la strada che hai fatto: ti proponiamo il percorso lungo i sentieri fra i due punti, e lo correggi toccando la mappa.

Resta tratteggiato anche dopo: non è una misura, è la tua dichiarazione.

Quei chilometri non si sommano a niente — né alla distanza, né alle classifiche, né ai segmenti.

Puoi cancellarla quando vuoi, e può farla solo chi ha registrato la traccia.
```

### IT — App Store Connect (max 4000)

```
IL TRATTO MANCANTE LO RIDISEGNI TU
Quando il telefono sospende la registrazione, la traccia si ricongiunge con una linea dritta. Dalla 2.11.3 quella linea è tratteggiata e dichiarata. Ora puoi fare un passo in più: disegnare la strada che hai fatto davvero.

Ti proponiamo il percorso lungo i sentieri fra il punto dove ci siamo fermati e quello dove abbiamo ripreso. Se ha preso la via sbagliata, tocchi la mappa e lo correggi.

RESTA TRATTEGGIATO ANCHE DOPO
Non è una svista: è il punto. Quello che disegni non l'ha misurato il GPS, e continuerà a vedersi diverso dal resto della traccia. Chi guarda deve poter distinguere ciò che è stato registrato da ciò che è stato dichiarato — anche quando a dichiararlo sei tu, e anche quando hai ragione.

QUEI CHILOMETRI NON SI SOMMANO A NIENTE
Non alla distanza della traccia, non alle classifiche, non ai tempi sui segmenti, non ai dati che mandiamo a Salute. La traccia continua a contare quel tratto solo in linea retta, come prima.

Poteva essere l'occasione per far salire i numeri di qualche chilometro. Sarebbe stata la scelta sbagliata: un totale che cresce perché hai disegnato una linea non è un totale.

SOLO CHI C'ERA
La ricostruzione può farla soltanto chi ha registrato la traccia, e può cancellarla quando vuole. Il valore di questo dato sta tutto nel fatto che lo dice chi è passato di lì.
```

### EN — App Store Connect

```
YOU REDRAW THE MISSING STRETCH
When the phone suspends the recording, the track closes the hole with a straight line. Since 2.11.3 that line is dashed and declared. Now you can go one step further: draw the way you actually went.

We suggest a route along the trails between where we stopped and where we picked up again. If it took the wrong path, tap the map and correct it.

IT STAYS DASHED AFTERWARDS
That is not an oversight, it is the point. What you draw was not measured by the GPS, and it keeps looking different from the rest of the track. Anyone looking must be able to tell recorded from declared — even when you are the one declaring, and even when you are right.

THOSE KILOMETRES ARE ADDED TO NOTHING
Not to the track distance, not to the leaderboards, not to segment times, not to what we send to Health. The track still counts that stretch as a straight line, exactly as before.

This could have been an occasion to make the numbers grow. It would have been the wrong call: a total that grows because you drew a line is not a total.

ONLY WHOEVER WAS THERE
Only the person who recorded the track can reconstruct it, and they can delete it whenever they want. The whole value of this data is that it comes from whoever walked it.
```

## Cosa NON promettere

- **Non è un recupero del segnale.** Niente è stato recuperato: il dato non
  esiste e non esisterà. È una dichiarazione umana messa accanto a una misura,
  tenuta distinta da essa.
- **Non c'è un passo né una velocità su quel tratto**, e non ci saranno: la
  ricostruzione non ha orari. Inventarli sarebbe esattamente il difetto che
  questa funzione ripara.
- **Non si applica alle tracce di altri.** Nessuna correzione collaborativa,
  nessun suggerimento automatico.

## Verifiche prima di pubblicare

- Ricostruire un buco e riaprire la scheda: il tratteggio deve seguire il
  percorso disegnato **e partire dall'ultimo punto registrato**, non dal punto
  dove il routing si è agganciato al sentiero.
- Controllare che la distanza della traccia **non cambi** dopo la
  ricostruzione.
- Esportare il GPX di una traccia ricostruita e **reimportarlo**: deve tornare
  con lo stesso numero di punti di prima, e i punti disegnati non devono
  esserci. È il difetto grave trovato in revisione, ed è quello che si rompe
  per primo se qualcuno tocca `gpx_service.dart`.
- Cambiare l'attività dalla scheda di una traccia ricostruita: tratteggio e
  ricostruzione devono restare.

## Restano da fare, invariate dalla 2.11.3

- **Apple, categoria secondaria** Sport → Navigazione: va fatta *insieme a
  questa submission*, o aspetta la prossima. Vedi `docs/aso_keywords.md` § 1.
- **Play, i tag** (non richiedono build) — § 1b dello stesso documento. La
  categoria su Play **non si tocca**.
- **Screenshot dello store**: ancora quelli del Peak Finder a linea piatta.
