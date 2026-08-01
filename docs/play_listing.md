# Scheda Play Store

Riscritta il 2026-08-01. Ogni affermazione qui sotto è stata verificata nel
codice o nei dati prima di scriverla — le fonti sono annotate in fondo.

## Cosa non andava nella scheda precedente

**La parola `rifugi` non compariva nemmeno una volta.** È la nicchia dove l'app
è dodicesima su App Store mentre su tutto il resto è fuori dai cento (vedi
[aso_keywords.md](aso_keywords.md)), è ciò su cui gira il ground game dei QR,
l'outreach via email e le 6.496 schede. La scheda Play non la nominava.

Su Play non esiste un campo keyword: Google indicizza **titolo, descrizione
breve e descrizione lunga**. Una parola assente dal testo è una parola su cui
non si viene trovati, punto.

Il resto era una scheda ferma a qualche versione fa:

- `Kudos` non esiste più nell'app, si chiamano **Cheer** da mesi
- niente mappe offline, che è il vero motivo per cui un'app da montagna si
  scarica invece di usare Google Maps
- niente rifugi, bivacchi, sorgenti: i 21.556 punti già dentro l'installazione
- quattro attività citate su **quattordici** che l'app registra — mancano
  scialpinismo, ciaspole, sci nordico, gravel, e-MTB
- niente orologi né fasce cardio, niente segmenti, niente 3D, niente condivisione
  posizione in tempo reale
- `L' avventura` con lo spazio dopo l'apostrofo

## Descrizione breve (79/80)

```
Sentieri, rifugi e bivacchi sulla mappa. GPS e mappe offline, anche senza rete.
```

Ottanta caratteri sono la parte più pesata dell'indicizzazione Play. Questi ne
usano 79 per dire le tre cose che ci distinguono e che nessun concorrente
generalista dice: **rifugi**, **bivacchi**, **offline**.

## Descrizione lunga

```
TrailShare è l'app per chi va in montagna: registra le escursioni con il GPS, trova rifugi e bivacchi sulla mappa e continua a funzionare dove il telefono non prende.

QUANDO NON C'È CAMPO

Scarica in anticipo l'area che ti serve: la mappa resta disponibile mentre registri e mentre segui un sentiero, anche in modalità aereo.

Insieme all'app trovi già installati oltre 21.000 punti della montagna italiana: 3.100 rifugi, 1.600 bivacchi, 2.000 ricoveri, 4.800 sorgenti, 3.500 fontane, 3.200 punti panoramici e 1.100 colonnine di ricarica per e-bike. Sono nel telefono, non su un server: li vedi senza rete.

REGISTRA LE TUE USCITE

Tracciamento GPS con distanza, dislivello, tempo in movimento e velocità. Funziona in background senza perdere dati.

Quattordici attività: trekking, camminata, trail running, corsa, ciclismo, mountain bike, gravel, e-bike, e-MTB, sci alpino, scialpinismo, sci nordico, ciaspole e snowboard.

Scatta foto geolocalizzate lungo il percorso e rivedi il tracciato in 3D quando torni a casa.

SCOPRI DOVE ANDARE

Esplora la mappa e il feed della community per trovare la prossima uscita. Migliaia di sentieri descritti, con difficoltà e dislivello. Rifugi e bivacchi con foto, quota e contatti, e le sorgenti dove riempire la borraccia.

SEGUI UNA TRACCIA, O DISEGNALA

Importa i tuoi file GPX, TCX e FIT, oppure segui sulla mappa una traccia condivisa da un altro escursionista. Con il planner scegli i punti di passaggio e il percorso si disegna da solo: lo salvi e parti quando sei pronto.

OROLOGI E FASCE CARDIO

Collega Polar e Suunto: le uscite registrate al polso arrivano nell'app con traccia e frequenza cardiaca. Compatibile con le fasce cardio Bluetooth, con Salute di Apple e con Health Connect.

COMMUNITY

Segui altri escursionisti, lascia un Cheer, commenta. Gruppi, classifiche, badge e sfide per chi si diverte a tenere il conto, e segmenti cronometrati sui tratti che rifai spesso.

QUANDO ESCI DA SOLO

Condividi la posizione in tempo reale con chi resta a casa e imposta i contatti da avvisare.

PER CHI È TrailShare

Escursionisti, appassionati di trekking e alpinismo, trail runner, ciclisti in mountain bike ed e-bike, e chiunque vada per rifugi, bivacchi e vie ferrate.

Fatto in Italia, per la montagna italiana.

Alcune funzioni avanzate fanno parte di TrailShare Pro. Tutto il resto è gratuito.
```

### Frasi da aggiungere solo se sono davvero aperte

Tenute fuori apposta, non dimenticate. Vedi i dubbi in fondo.

- **Strava** — da inserire in "OROLOGI E FASCE CARDIO":
  `Le attività registrate col telefono possono salire su Strava da sole, a fine uscita.`
- **Garmin** — stessa sezione:
  `Con l'app per orologi Garmin registri dal polso e la traccia arriva qui.`

## Perché è scritto così

Le parole misurate su App Store — `rifugi`, `bivacchi`, `ciaspole`, `ferrate`,
`alpinismo` — compaiono tutte, ma **dentro frasi vere**. Su Play il keyword
stuffing è penalizzato, mentre su Apple il campo è nascosto e non lo è: la
stessa lista non si copia da un negozio all'altro.

I numeri non sono decorazione. "Oltre 21.000 punti" è verificabile, "3.100
rifugi" pure, e sono la cosa che distingue davvero questa app da komoot e
Wikiloc su un telefono senza campo in Val Seriana.

## Dubbi da sciogliere prima di pubblicare

1. **Strava è ancora limitata a un atleta?** La richiesta di aumento 1→100 è
   partita il 2026-05-12 e non risulta una risposta. Se il limite è ancora
   attivo, nominare Strava nella scheda manda le persone contro un errore.
2. **L'app Garmin Connect IQ è pubblicata sullo store Garmin?** Risultava
   ancora da pubblicare: senza, chi legge "Garmin" non trova niente da
   installare.
3. **Titolo (30 caratteri).** Oggi su App Store è `TrailShare — Sentieri GPS`.
   Su Play conviene allinearlo, perché il titolo è la parte più pesata
   dell'indicizzazione — ma andrebbe verificato cosa c'è adesso.

## Verificato dove

| Affermazione | Fonte |
|---|---|
| 21.556 POI, di cui 3.102 `alpine_hut`, 1.597 `wilderness_hut`, 2.058 `shelter`, 4.840 `spring`, 3.599 `drinking_water`, 3.218 `viewpoint`, 1.124 `ebike_charging` | conteggio su `assets/data/pois_italy_clean.json` |
| I POI funzionano senza rete | `osm_pois_repository.dart` legge da `rootBundle`, non da rete |
| Mappe offline vere | `offline_maps_service.downloadArea` + `OfflineFallbackTileProvider` usato in registrazione, scoperta, navigazione e planner |
| 14 attività | `enum ActivityType` in `lib/data/models/track.dart` |
| Cheer, non Kudos | zero occorrenze di "Kudos" in `lib/`, sei file con "Cheer" |
| Polar e Suunto | `polar_service.dart`, `suunto_service.dart`, validati end-to-end |
| 3D, segmenti, posizione in tempo reale | `pages/track_3d`, `pages/segments`, `pages/livetrack` |
| Pro non copre il nucleo | `isPro` compare in training HR, statistiche gruppo, mountain finder e dettaglio traccia — non in registrazione, mappe offline o POI |
