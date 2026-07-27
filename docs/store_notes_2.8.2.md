# Note release 2.8.2+108 per gli store

L'espansione all'arco alpino: fino alla 2.8.1 il catalogo era italiano, ora
copre Francia, Svizzera, Austria, Slovenia e Croazia — 16.350 sentieri e
4.318 rifugi.

Buona parte del lavoro è nei dati e gli utenti la vedono già senza
aggiornare. Quello che serve la build è la **navigazione** di quei dati: il
filtro per regione vive nel binario, e nella 2.8.1 conosceva solo le venti
regioni italiane. Peggio: filtrava chiedendo "il punto di partenza sta dentro
il rettangolo della regione?", e i rettangoli si accavallano oltre confine —
1.281 sentieri stranieri finivano nei filtri italiani, 803 solo sotto
Piemonte. Questa release lo corregge risolvendo la regione più specifica che
contiene il punto.

Con la stessa build esce il fix del salvataggio offline, nato dal ticket
dell'utente che aveva perso delle tracce.

## Play Console / App Store Connect — "Novità in questa versione" (IT)

```
TrailShare esce dall'Italia: sentieri e rifugi di Francia, Svizzera, Austria, Slovenia e Croazia, con i filtri per regione che ora conoscono il Vallese, il Tirolo e l'Alta Savoia.

I rifugi senza foto non mostrano più un riquadro vuoto: al suo posto c'è il profilo reale del terreno che li circonda. E 460 rifugi hanno una foto nuova.

La traccia registrata resta al sicuro finché il server non conferma di averla salvata.
```

## EN

```
TrailShare goes beyond Italy: trails and mountain huts across France, Switzerland, Austria, Slovenia and Croatia, with region filters that now know Valais, Tyrol and Haute-Savoie.

Huts without a photo no longer show an empty box — you get the real terrain profile around them instead. And 460 huts gained a photo.

Your recorded track stays safe until the server confirms it has been saved.
```

## Cosa contiene, per chi rilegge fra sei mesi

**Contenuti (già live, nessuna build necessaria)**
- 16.350 sentieri e 4.318 rifugi su sei paesi, con paese e regione corretti
- 460 copertine ai rifugi da Wikimedia Commons, passate una per una da
  revisione umana — copertura dal 30% al 40,3%
- quota per il 100% dei rifugi, 1.396 ricavate dal DEM europeo a 25 m
- 29 schede duplicate fuse

**Codice (serve la build)**
- modello regioni con paese: 43 regioni su IT, FR, CH, AT, SI, HR, HU
- filtro Scopri che risolve la regione più specifica invece del contenimento
  nel rettangolo
- copertina col profilo del terreno per le schede senza foto
- backup della registrazione non cancellato finché il server non conferma
- telemetria del salvataggio + Crashlytics

**Non ancora completo alla data della build**
I profili del terreno sono in campionamento: opentopodata dà mille chiamate
al giorno e ne servono ~1.550. Le schede ancora senza profilo mostrano il
ripiego di prima e si accendono da sole man mano che il dato arriva, senza
bisogno di un'altra build.
