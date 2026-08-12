# Note release 2.11.0+125 per gli store

Una funzione sola, rifatta da capo: il riconoscimento delle cime.

Da qui il minore invece della patch. Non si corregge il Peak Finder, cambia di
categoria — e per chi l'aveva provato prima e l'aveva trovato inutilizzabile,
è letteralmente un'altra cosa.

## La cosa da comunicare bene

Non è «abbiamo aggiunto delle funzioni». È che **prima non funzionava, e chi ha
pagato Pro lo sa**.

Il puntamento sbagliava di gradi, i nomi inseguivano le montagne con un quinto di
schermo di ritardo, e il panorama era una macchia verde piatta. Tre difetti
misurati e chiusi, non impressioni.

Chi l'ha provato una volta e ha smesso non riaprirà la schermata perché
promettiamo «migliorie»: va detto che è **rifatto**.

## "Novità in questa versione"

### IT — Play Console (max 500)

```
Il riconoscimento delle cime è rifatto da capo.

Cerca una cima per nome e l'app ti dice quanti gradi girarti per averla davanti.

Il panorama non è più una linea: montagne su più piani di profondità, ombreggiate dal sole all'ora che scegli.

Ti dice dietro quale cima tramonta il sole, e a che ora: in valle può essere mezz'ora prima dell'orario ufficiale.

I nomi restano incollati alle montagne mentre muovi il telefono, e smettono di lampeggiare quando lo tieni fermo.

Nuovo elenco delle cime visibili, tutto il giro d'orizzonte.
```

### IT — App Store Connect (max 4000)

```
Il riconoscimento delle cime è rifatto da capo.

CERCA UNA CIMA PER NOME
Scrivi "Monte Rosa", o anche solo "coca": l'app ti dice quanti gradi a destra o a sinistra girarti, e quanto è lontana. Quando entra nell'inquadratura te la cerchia.

IL PANORAMA È UN PAESAGGIO
Le montagne sono disegnate su più piani di profondità, che sbiadiscono con la distanza come fa la foschia vera. E sono ombreggiate dal sole all'ora che scegli: sposta il cursore e vedi quale versante avrà luce alle sette.

IL TRAMONTO VERO
Non quello da almanacco: l'app ti dice dietro quale cima sparisce il sole, e a che ora. In una valle stretta può essere mezz'ora prima dell'orario ufficiale, ed è l'unico che conta se stai aspettando la luce.

PUNTARE È DIVENTATO FACILE
I nomi restano incollati alle montagne mentre muovi il telefono, invece di inseguirle. E tenendolo fermo smettono di lampeggiare: prima le cime ai bordi entravano e uscivano di continuo.

L'ELENCO DELLE CIME VISIBILI
Tutto il giro d'orizzonte, in ordine di direzione: sai cosa c'è alle tue spalle senza girarti, e leggi i nomi senza tenere il telefono alzato.

E QUANDO NON SAPPIAMO, LO DICIAMO
Dove il terreno non è stato scaricato l'app tace, invece di disegnare un orizzonte che non conosce.
```

### EN — App Store Connect

```
Peak recognition has been rebuilt from scratch.

SEARCH A PEAK BY NAME
Type "Monte Rosa", or just "coca": the app tells you how many degrees to turn left or right, and how far it is. When it enters the frame, it circles it for you.

THE PANORAMA IS A LANDSCAPE
Mountains are drawn on several depth planes that fade with distance, the way real haze does. And they are shaded by the sun at the hour you pick: move the slider and see which slope will have light at seven.

THE REAL SUNSET
Not the almanac one: the app tells you behind which peak the sun disappears, and when. In a narrow valley that can be half an hour earlier than the official time, and it is the only one that matters if you are waiting for the light.

AIMING IS EASY NOW
Names stay stuck to the mountains as you move the phone instead of chasing them. And they stop flickering when you hold still.

THE LIST OF VISIBLE PEAKS
All the way around the horizon, in bearing order: know what is behind you without turning, and read the names without holding the phone up.

AND WHEN WE DO NOT KNOW, WE SAY SO
Where the terrain has not been downloaded the app stays silent, instead of drawing a horizon it does not know.
```

## Cosa NON promettere

- **Non è offline ovunque.** Funziona senza rete solo dove la zona è già stata
  scaricata da Mappe Offline. Verificato in modalità aereo, ma la zona va
  scaricata prima.
- **Solo Italia.** Il catalogo è di 37.209 cime italiane. Fuori dai confini non
  c'è niente, e su questo il concorrente resta avanti di parecchio.
- **Niente ombre portate.** Il rilievo dice quale versante guarda il sole, non se
  una cresta ne proietta l'ombra sulla valle dietro.

## Verifiche prima di pubblicare

- [x] AAB firmato con la chiave di rilascio (impronta SHA1 confrontata col
      keystore, non dedotta dal fatto che il build sia riuscito)
- [x] Provato sul campo su Motorola edge 60 pro, in release
- [x] Changelog in-app aggiornato in `settings_page.dart`
- [ ] Screenshot store aggiornati: il panorama ombreggiato e la ricerca sono le
      due cose nuove che si vedono, e gli screenshot attuali mostrano ancora la
      linea piatta
