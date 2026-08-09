# Aperture e chiusure dei rifugi

Misurato il 2026-08-09 su `italy-latest.osm.pbf` (2,1 GB, Geofabrik) con
`osmium tags-filter` su `tourism=alpine_hut,wilderness_hut`. Numeri veri,
rifacibili.

## La misura

```
rifugi + bivacchi in OSM Italia        6.468
   alpine_hut  (gestiti)               3.492
   wilderness_hut (bivacchi)           2.662
   altro/edifici senza tag               314
```

| Campo | Copertura |
|---|---|
| **opening_hours** | **517 (8,0%)** |
| seasonal | 12 (0,2%) |
| gestore (`operator`) | 1.986 (30,7%) |
| posti letto (`capacity`) | 1.363 (21,1%) |
| sito | 1.501 (23,2%) |
| telefono | 1.657 (25,6%) |
| email | 977 (15,1%) |
| **almeno un recapito** | **2.216 (34,3%)** |

E dei 517 che hanno l'orario:

| | |
|---|---|
| con una finestra stagionale usabile | 309 (59,8%) |
| sempre aperto `24/7` | 47 (9,1%) |
| dichiarati `closed` | 12 (2,3%) |
| **con un anno esplicito, gia' scaduto** | **12 (2,3%)** |

## Cosa smentisce

L'idea di partire dalle aperture *perche' si possono raccogliere senza
aspettare i gestori paganti* **non regge alla misura**. Tolti i bivacchi,
restano circa 470 rifugi gestiti su 3.492 con un dato di apertura: il **13%**.
Non e' una funzione, e' una dimostrazione.

E la fonte mostra da sola il modo in cui fallisce:

```
Schutzhütte Hochalm            → 2024 Jun-Oct
Schutzhaus Bockerhütte         → 2024 Apr 23-Nov 06
Stettiner Hütte                → 2024 Jul-Sep
```

Qualcuno ha inserito le date di una stagione precisa e non e' piu' tornato.
Due stagioni dopo quel dato non e' impreciso: e' **falso**, e mostrato senza
contesto manderebbe qualcuno a duemila metri davanti a una porta chiusa.

## Cosa invece regge, e non me l'aspettavo

**I bivacchi non hanno la domanda.** Un `wilderness_hut` e' per definizione non
gestito e sempre accessibile: solo l'1,8% ha `opening_hours`, e non perche' il
dato manchi ma perche' non si applica. Sono **2.662 punti su 6.468, il 41% del
totale, risolti dalla categoria invece che dalla raccolta.**

Per quei punti la risposta giusta non e' un orario ma una frase: sempre
accessibile, nessun servizio, nessuna prenotazione, portati tutto.

**E OSM da' la lista di outreach, non i dati.** 2.216 rifugi con almeno un
recapito e 1.986 con il nome del gestore: e' esattamente la rubrica che serve
al lato B2B. Il valore di questa passata non sono le aperture — sono i contatti.

## Il piano che ne segue

L'ordine si inverte. Non "raccolgo le aperture e poi vendo ai gestori", ma
**"i gestori sono l'unica fonte possibile delle aperture"**.

1. **Modello dati che non puo' mentire.** Un'apertura e' un intervallo di date
   con dentro: la **stagione** a cui si riferisce, la **fonte** (gestore, OSM,
   community, redazione) e **quando e' stata toccata l'ultima volta**. Un
   intervallo della stagione scorsa non si mostra mai come "aperto": si mostra
   come "l'anno scorso apriva il...".
2. **Seed gratuito.** I 2.662 bivacchi per categoria, i ~470 rifugi da OSM.
   Serve a costruire e provare la UI su dati veri, non a dire di avere la
   funzione.
3. **La UI dichiara sempre l'eta' del dato.** Accanto all'apertura, la data
   dell'ultimo aggiornamento e chi l'ha messa. Dove non si sa, si scrive che
   non si sa: e' informazione anche quella, ed e' l'unica onesta.
4. **Il gestore aggiorna la sua scheda.** E' il pezzo che chiude il giro con il
   B2B: il rifugio paga per farsi trovare, l'aggiornamento e' cio' che rende
   PRO desiderabile, PRO porta escursionisti che guardano la scheda.

## Da rifare

La passata `osmium` quando esce un estratto Geofabrik nuovo. Se la copertura di
`opening_hours` sale sensibilmente sopra l'8% e' cambiato qualcosa a monte e
vale la pena riguardare il piano.
