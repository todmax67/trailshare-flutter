# Note release 2.9.3+112 per gli store

I giri dell'orologio arrivano fino alla scheda della traccia.

Fino alla 2.9.2 la scheda mostrava dei giri, ma se li calcolava da sola ogni
1000 metri: erano chilometri, non giri. Chi registra con un Garmin e usa
l'auto-giro o il tasto del giro ora ritrova i **suoi** giri — in un allenamento
a ripetute sono gli intervalli veri, non tratti tagliati a caso.

Le tracce senza giri non cambiano: la scheda continua a calcolarli al
chilometro come ha sempre fatto.

## Play Console / App Store Connect — "Novità in questa versione" (IT)

```
Se registri con un orologio Garmin e usi i giri, nella scheda della traccia ora trovi i tuoi giri veri invece dei chilometri: tempo, passo, dislivello e battito medio di ciascuno.

In un allenamento a ripetute sono i tuoi intervalli, non tratti tagliati a caso.

Sulle tracce senza giri la scheda continua a calcolarli ogni chilometro, come prima.
```

## EN

```
If you record with a Garmin watch and use laps, the track page now shows your real laps instead of kilometre splits: time, pace, elevation gain and average heart rate for each.

On an interval workout those are your actual intervals, not arbitrary slices.

Tracks without laps keep the per-kilometre splits, exactly as before.
```

## Cosa contiene, per chi rilegge fra sei mesi

**App (serve la build)**
- `TrackLap` nel modello traccia, letto da Firestore, additivo: le tracce
  esistenti restano con lista vuota
- `LapSplitsWidget` accetta `deviceLaps` e, se ci sono, salta il calcolo al
  chilometro. La tabella, il passo, la riga TOT e il tap-per-evidenziare erano
  gia' tutti li': mancava solo la sorgente
- il ponte nativo Garmin non parte piu' su iOS (era `!kIsWeb`, doveva essere
  "solo Android"): niente piu' MissingPluginException a ogni avvio su iPhone

**Server (deploy separato)**

```
firebase deploy --only functions:syncGarminTrack
```

`syncGarminTrack` leggeva solo points/name/sport/duration/clientId e buttava
via il resto in silenzio: senza questo deploy i giri partono dall'orologio e
si perdono. Normalizza in metri e SECONDI (l'orologio manda millisecondi) e
scrive il campo solo se ci sono giri, cosi' l'assenza resta il segnale per
tornare al calcolo al chilometro.

**Orologio (Connect IQ store, pacchetto a parte)**
`bin/TrailShareApp.iq`, 122/122 varianti. Auto-giro configurabile 1/2/5/10 km
o solo manuale, giro manuale col gesto MENU e dal menu di pausa, pagina Giri
col confronto col giro precedente, pagina Orologio con ora e batteria.

**La decisione che vale la pena ricordare**
Fra orologio e server NON viaggia nessun indice di punto. Il buffer
dell'orologio si dimezza ogni 400 punti, quindi un indice registrato prima di
un dimezzamento indicherebbe un altro punto. Viaggiano distanza e durata di
ogni giro; gli indici per evidenziare il tratto sulla mappa li ricava l'app
camminando sui punti, e restano giusti anche se la traccia viene risalvata e
decimata. E' la stessa lezione dei passaggi sui segmenti, dove `trackStartIdx`
non combaciava fra le due sponde e si e' passati a `passIndex`.

**Perche' 2.9.3 e non un aggiornamento della 2.9.2**
La 2.9.2+111 e' gia' pubblica su Play e conteneva solo il fix del crash
Garmin (regole ProGuard). L'integrazione dei giri e' arrivata dopo. Su App
Store l'ultima pubblicata era la 2.9.1+110: la 2.9.2 era Android-only.
