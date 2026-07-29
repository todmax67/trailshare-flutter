# Note release 2.9.1+110 per gli store

La release che smette di inventare la difficoltà. Fino alla 2.8.2 il grado di
un sentiero era calcolato da lunghezza e dislivello — una formula che misura
la **fatica** e la spacciava per **terreno**. È un errore di categoria: la
scala CAI dice quanto è esposto e tecnico il passaggio, non quanto è lungo.
Confrontando le stime coi rilievi veri di OpenStreetMap, dove entrambi
esistevano, il grado stimato era sbagliato nella maggioranza dei casi, e
sbagliava anche per difetto: 323 vie ferrate risultavano "escursionistiche" e
168 di quelle non lo dichiaravano nemmeno nel nome.

Ora la difficoltà tecnica viene letta dalla cartografia, l'impegno è una
grandezza separata e dichiarata come calcolata, e dove il rilievo manca la
scheda dice "non classificato" invece di riempire il vuoto.

Con la stessa build escono i segmenti cronometrati resi utilizzabili
(classifiche per attività, storico personale, allenamenti a ripetute) e il
fix del login che chiedeva uno username già scelto.

## Play Console / App Store Connect — "Novità in questa versione" (IT)

```
La difficoltà non è più una stima: arriva dal rilievo di chi ha mappato il sentiero, su 7.185 percorsi. Dove manca lo scriviamo, invece di inventare un livello.

Le vie ferrate sono segnalate come tali: 323 percorsi che richiedono imbrago, casco e set. In rosso sulla mappa, escludibili dai filtri.

Tempo di percorrenza stimato su tutto il catalogo e descrizioni su 15.473 sentieri.

Segmenti: classifiche divise per attività, un tempo a testa, lo storico dei tuoi passaggi con le date.
```

## EN

```
Trail difficulty is no longer a guess: it comes from the survey of whoever mapped the path, on 7,185 trails. Where it's missing, we say so instead of inventing a grade.

Via ferrata routes are flagged: 323 need a harness, helmet and ferrata set. Marked red on the map, and you can filter them out.

Estimated walking time across the whole catalogue, plus descriptions on 15,473 trails.

Segments: leaderboards split by activity, one time per person, plus your own attempt history with dates.
```

## Cosa contiene, per chi rilegge fra sei mesi

Tutti i numeri qui sotto sono stati ricontati su Firestore il 29 luglio 2026,
non ripresi dai log degli script. Base: 16.350 sentieri a catalogo.

**Contenuti (già live, nessuna build necessaria)**
- 323 vie ferrate marcate dai tag OSM (`highway=via_ferrata`,
  `via_ferrata_scale`, `climbing=via_ferrata`), 168 delle quali non lo
  dichiaravano nel nome
- difficoltà **rilevata** su 7.185 sentieri (43,9%): 6.862 dalla scala SAC di
  OpenStreetMap, 323 dalle ferrate. Prima erano 158
- descrizioni su 15.473 sentieri (94,6%), generate dai dati del percorso; di
  queste 7.210 sono passate da revisione umana, 8.233 no
- impegno calcolato su 15.290 (93,5%), tempo di percorrenza stimato su 16.295
  (99,7%)

**Codice (serve la build)**
- il badge della card distingue il grado **rilevato** (pallino colorato) dall
  impegno **calcolato** (icona manubrio, scala T1-T5), e dice "Non
  classificato" quando non c'è né l'uno né l'altro
- tempo di percorrenza accanto a distanza e dislivello, coi giorni di cammino
  sugli itinerari che in giornata non si fanno
- vie ferrate in rosso sulla mappa, tracciato e segnaposto, col triangolo di
  attenzione al posto dell'icona dell'attività
- filtri nuovi: "Non classificato", "Solo difficoltà verificata", "Escludi vie
  attrezzate"; e il cursore della lunghezza a fondo scala non taglia più via i
  percorsi oltre i 30 km
- segmenti: classifica per famiglia di attività (niente bici fra i podisti),
  un tempo a testa in graduatoria, storico personale con le date, e tutti i
  passaggi di un'uscita invece del solo primo
- un segmento appena creato nasce con la classifica già popolata dalle tracce
  esistenti, invece di restare vuoto finché qualcuno non lo ripercorre
- fix login: chi entra con email e password non si vede più chiedere uno
  username che aveva già scelto

**Da distribuire a parte, non viaggia nella build**

```
firebase deploy --only functions:onSegmentCreate,firestore:indexes
```

Senza la funzione, un segmento creato dopo l'aggiornamento nasce comunque
vuoto; senza l'indice, la sezione "La tua performance" resta muta. Le regole
Firestore sono già live.

**Quello che NON è in questa release, e perché non è annunciato**

- *Tour dal catalogo.* Il codice sa leggere e mostrare tappe prese dai sentieri
  pubblici, ma manca il selettore per aggiungerle dall'app: la lista da cui si
  sceglie contiene solo le proprie tracce registrate. `searchByName()` in
  `public_trails_repository.dart` è scritto e non chiamato da nessuno — è
  l'impalcatura del selettore che verrà. Le 14 bozze generate dallo script
  restano non pubblicate, in attesa di revisione e descrizioni. Annunciare
  "costruisci un tour dal catalogo" sarebbe falso per chiunque legga la scheda.
- *Numeri per nazione.* 8.437 sentieri su 16.350 non hanno il campo `country`
  (IT 1.475, AT 2.251, CH 2.002, FR 1.148, SI 812, HR 215, HU 9, DE 1).
  Nessun claim del tipo "X sentieri in Francia" è sostenibile finché quelli non
  sono etichettati.
- *"16.350 sentieri completi".* 1.533 (9,4%) non hanno un dislivello
  utilizzabile. "16.350 sentieri a catalogo" è esatto; "completi" no.

**Parole scelte apposta**

- "rilevata" e non "verificata da noi": il rilievo è di chi ha mappato il
  sentiero su OpenStreetMap, non nostro
- "stimato" sul tempo di percorrenza e "calcolato" sull'impegno: sono formule
  su distanza e dislivello, non misure su tracce reali
- "generate dai dati del percorso" sulle descrizioni: metà non ha mai visto un
  revisore umano, e "descritti" da solo farebbe pensare a una redazione
